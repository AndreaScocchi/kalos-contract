-- Migration 20260107150000: Fix duplicate bookings in staff_book_lesson for individual lessons
--
-- Problem: staff_book_lesson was creating duplicate bookings for individual lessons
-- when a booking was already auto-created by the trigger. This caused duplicate
-- subscription_usages entries, leading to double usage of subscription entries.
--
-- Solution: Add check for existing active booking before creating a new one,
-- similar to how book_lesson handles individual lessons.

-- ============================================================================
-- staff_book_lesson
-- (Fix: Check for existing active booking before creating new one)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.staff_book_lesson(
  p_lesson_id uuid,
  p_client_id uuid,
  p_subscription_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_staff_id uuid := auth.uid();
  v_client clients%rowtype;
  v_capacity integer;
  v_starts_at timestamptz;
  v_booking_deadline_minutes integer;
  v_is_individual boolean;
  v_assigned_client_id uuid;
  v_booked_count integer;
  v_booking_id uuid;
  v_total_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_reactivate_booking uuid;
  v_has_existing_usage boolean := false;
  v_cancel_restore_exists boolean := false;
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
BEGIN
  -- Staff check
  IF NOT public.is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
  END IF;

  -- Validate client
  SELECT * INTO v_client
  FROM public.clients
  WHERE id = p_client_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Lock lesson
  SELECT capacity, starts_at, booking_deadline_minutes, is_individual, assigned_client_id
  INTO v_capacity, v_starts_at, v_booking_deadline_minutes, v_is_individual, v_assigned_client_id
  FROM public.lessons
  WHERE id = p_lesson_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  -- Individual lesson checks
  IF v_is_individual THEN
    IF v_assigned_client_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_ASSIGNED');
    END IF;
    IF v_assigned_client_id != p_client_id THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_ASSIGNED');
    END IF;
    
    -- FIX: Check if booking already exists (to avoid duplicates from auto-booking trigger)
    SELECT id INTO v_booking_id
    FROM public.bookings
    WHERE lesson_id = p_lesson_id
      AND client_id = p_client_id
      AND status IN ('booked', 'attended', 'no_show')
    LIMIT 1;
    
    IF v_booking_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'ok', true,
        'reason', 'ALREADY_BOOKED',
        'booking_id', v_booking_id
      );
    END IF;
  END IF;

  -- Existing canceled booking to reactivate
  SELECT id INTO v_reactivate_booking
  FROM public.bookings
  WHERE lesson_id = p_lesson_id
    AND client_id = p_client_id
    AND status = 'canceled'
  LIMIT 1;

  -- Capacity for public lessons
  IF NOT v_is_individual THEN
    SELECT COUNT(*) INTO v_booked_count
    FROM public.bookings
    WHERE lesson_id = p_lesson_id
      AND status = 'booked';
    IF v_booked_count >= v_capacity THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;
  END IF;

  -- Validate subscription if provided: valid on lesson date
  IF p_subscription_id IS NOT NULL THEN
    SELECT * INTO v_sub
    FROM public.subscriptions
    WHERE id = p_subscription_id
      AND client_id = p_client_id
      AND status = 'active'
      AND v_starts_at::date BETWEEN started_at::date AND expires_at::date;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_NOT_FOUND_OR_INACTIVE');
    END IF;

    SELECT * INTO v_plan FROM public.plans WHERE id = v_sub.plan_id;
    v_total_entries := COALESCE(v_sub.custom_entries, v_plan.entries);
    IF v_total_entries IS NOT NULL THEN
      SELECT COALESCE(SUM(delta), 0) INTO v_used_entries
      FROM public.subscription_usages
      WHERE subscription_id = v_sub.id;
      v_remaining_entries := v_total_entries + v_used_entries;
      IF v_remaining_entries <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NO_ENTRIES_LEFT');
      END IF;
    END IF;
  END IF;

  -- Create or reactivate booking
  IF v_reactivate_booking IS NOT NULL THEN
    UPDATE public.bookings
    SET status = 'booked',
        created_at = now(),
        subscription_id = p_subscription_id
    WHERE id = v_reactivate_booking;
    v_booking_id := v_reactivate_booking;
  ELSE
    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
    VALUES (p_lesson_id, p_client_id, p_subscription_id, 'booked')
    RETURNING id INTO v_booking_id;
  END IF;

  -- Usage accounting (entries-limited only)
  IF p_subscription_id IS NOT NULL AND v_total_entries IS NOT NULL THEN
    IF v_reactivate_booking IS NOT NULL AND v_has_existing_usage AND v_cancel_restore_exists THEN
      DELETE FROM public.subscription_usages
      WHERE id = (
        SELECT su.id
        FROM public.subscription_usages su
        WHERE su.booking_id = v_reactivate_booking
          AND su.delta = +1
        ORDER BY su.created_at DESC
        LIMIT 1
      );
    ELSE
      INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
      VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED', 'booking_id', v_booking_id);
END;
$$;

COMMENT ON FUNCTION public.staff_book_lesson(uuid, uuid, uuid) IS 
'Staff booking: validates subscription on the lesson date (starts_at). Prevents duplicate bookings for individual lessons.';

