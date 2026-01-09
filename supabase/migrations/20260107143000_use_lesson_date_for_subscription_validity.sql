-- Migration 20260107143000: Use lesson date for subscription validity checks
--
-- Goal: Assign subscriptions even if validity starts in the future, as long as
-- the subscription is valid on the lesson date. Replace current_date checks
-- with the lesson's starts_at date in all relevant functions/triggers.
--
-- Affected:
-- - auto_create_booking_for_individual_lesson (trigger on lessons)
-- - handle_individual_lesson_update (trigger function)
-- - book_lesson (RPC)
-- - staff_book_lesson (RPC)

-- ============================================================================
-- auto_create_booking_for_individual_lesson
-- (Base: latest simplified version using client_id)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.auto_create_booking_for_individual_lesson() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
AS $$
DECLARE
  v_subscription_id uuid;
  v_booking_id uuid;
BEGIN
  -- Only process if this is an individual lesson with assigned client
  IF NEW.is_individual = true AND NEW.assigned_client_id IS NOT NULL THEN
    -- Try to find an active subscription for this client, valid on lesson date
    SELECT id INTO v_subscription_id
    FROM public.subscriptions_with_remaining
    WHERE client_id = NEW.assigned_client_id
      AND status = 'active'
      AND NEW.starts_at::date BETWEEN started_at::date AND expires_at::date
      AND (remaining_entries IS NULL OR remaining_entries > 0)
    ORDER BY expires_at DESC NULLS LAST
    LIMIT 1;
    
    -- Check if booking already exists (to avoid duplicates on UPDATE)
    SELECT id INTO v_booking_id
    FROM public.bookings
    WHERE lesson_id = NEW.id
      AND client_id = NEW.assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
    LIMIT 1;
    
    IF v_booking_id IS NULL THEN
      -- Create booking
      INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
      VALUES (NEW.id, NEW.assigned_client_id, v_subscription_id, 'booked')
      RETURNING id INTO v_booking_id;
      
      -- Create subscription usage if subscription exists (entries-limited only)
      IF v_subscription_id IS NOT NULL THEN
        INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
        VALUES (v_subscription_id, v_booking_id, -1, 'BOOK');
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.auto_create_booking_for_individual_lesson() IS 
'Auto-creates a booking for individual lessons. Picks subscriptions valid on the lesson date (starts_at).';

-- ============================================================================
-- handle_individual_lesson_update
-- (Base: version that respects NEW.assigned_subscription_id with fallback)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_individual_lesson_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
AS $$
DECLARE
  v_client_profile_id uuid;
  v_subscription_id uuid;
  v_booking_id uuid;
  v_old_booking_id uuid;
  v_subscription_changed boolean;
  v_old_subscription_id uuid;
  v_total_entries integer;
BEGIN
  -- If lesson is being changed from individual to non-individual, clean up
  IF OLD.is_individual = true AND NEW.is_individual = false THEN
    NEW.assigned_client_id := NULL;
    RETURN NEW;
  END IF;
  
  -- Track subscription change via assigned_subscription_id
  v_subscription_changed := OLD.assigned_subscription_id IS DISTINCT FROM NEW.assigned_subscription_id;
  
  -- If assigned_client_id is changing on an individual lesson
  IF NEW.is_individual = true AND NEW.assigned_client_id IS NOT NULL THEN
    -- If client changed, cancel old booking and restore usage
    IF OLD.assigned_client_id IS DISTINCT FROM NEW.assigned_client_id AND OLD.assigned_client_id IS NOT NULL THEN
      SELECT id INTO v_old_booking_id
      FROM public.bookings
      WHERE lesson_id = NEW.id
        AND client_id = OLD.assigned_client_id
        AND status IN ('booked', 'attended', 'no_show')
      LIMIT 1;
      
      IF v_old_booking_id IS NOT NULL THEN
        UPDATE public.bookings
        SET status = 'canceled'
        WHERE id = v_old_booking_id;
        
        UPDATE public.subscription_usages
        SET delta = +1, reason = 'individual_lesson_client_changed'
        WHERE booking_id = v_old_booking_id
          AND delta = -1
          AND NOT EXISTS (
            SELECT 1 FROM public.subscription_usages
            WHERE booking_id = v_old_booking_id
              AND delta = +1
              AND reason = 'individual_lesson_client_changed'
          );
      END IF;
    END IF;
    
    -- Create/update booking for assigned client
    SELECT profile_id INTO v_client_profile_id
    FROM public.clients
    WHERE id = NEW.assigned_client_id AND deleted_at IS NULL;
    
    -- Check if booking already exists for client
    IF v_client_profile_id IS NOT NULL THEN
      SELECT id INTO v_booking_id
      FROM public.bookings
      WHERE lesson_id = NEW.id
        AND (
          (client_id = NEW.assigned_client_id) OR (user_id = v_client_profile_id)
        )
        AND status IN ('booked', 'attended', 'no_show')
      LIMIT 1;
    ELSE
      SELECT id INTO v_booking_id
      FROM public.bookings
      WHERE lesson_id = NEW.id
        AND client_id = NEW.assigned_client_id
        AND status IN ('booked', 'attended', 'no_show')
      LIMIT 1;
    END IF;
    
    -- If booking exists and assigned_subscription_id changed, update it
    IF v_booking_id IS NOT NULL AND v_subscription_changed THEN
      SELECT subscription_id INTO v_old_subscription_id
      FROM public.bookings
      WHERE id = v_booking_id;
      
      IF v_old_subscription_id IS NOT NULL THEN
        SELECT COALESCE(s.custom_entries, p.entries) INTO v_total_entries
        FROM public.subscriptions s
        LEFT JOIN public.plans p ON p.id = s.plan_id
        WHERE s.id = v_old_subscription_id;
        
        IF v_total_entries IS NOT NULL THEN
          UPDATE public.subscription_usages
          SET delta = +1, reason = 'individual_lesson_subscription_changed'
          WHERE booking_id = v_booking_id
            AND subscription_id = v_old_subscription_id
            AND delta = -1
            AND NOT EXISTS (
              SELECT 1 FROM public.subscription_usages
              WHERE booking_id = v_booking_id
                AND subscription_id = v_old_subscription_id
                AND delta = +1
                AND reason = 'individual_lesson_subscription_changed'
            );
        END IF;
      END IF;
      
      -- Priority: use assigned_subscription_id if present; else pick valid on lesson date
      IF NEW.assigned_subscription_id IS NOT NULL THEN
        v_subscription_id := NEW.assigned_subscription_id;
      ELSE
        IF v_client_profile_id IS NOT NULL THEN
          SELECT id INTO v_subscription_id
          FROM public.subscriptions_with_remaining
          WHERE (
            (client_id = NEW.assigned_client_id) OR (user_id = v_client_profile_id)
          )
            AND status = 'active'
            AND NEW.starts_at::date BETWEEN started_at::date AND expires_at::date
            AND (remaining_entries IS NULL OR remaining_entries > 0)
          ORDER BY expires_at DESC NULLS LAST
          LIMIT 1;
        ELSE
          SELECT id INTO v_subscription_id
          FROM public.subscriptions_with_remaining
          WHERE client_id = NEW.assigned_client_id
            AND status = 'active'
            AND NEW.starts_at::date BETWEEN started_at::date AND expires_at::date
            AND (remaining_entries IS NULL OR remaining_entries > 0)
          ORDER BY expires_at DESC NULLS LAST
          LIMIT 1;
        END IF;
      END IF;
      
      UPDATE public.bookings
      SET subscription_id = v_subscription_id
      WHERE id = v_booking_id;
      
      -- Handle usage for new subscription (entries-limited only)
      IF v_subscription_id IS NOT NULL THEN
        SELECT COALESCE(s.custom_entries, p.entries) INTO v_total_entries
        FROM public.subscriptions s
        LEFT JOIN public.plans p ON p.id = s.plan_id
        WHERE s.id = v_subscription_id;
        
        IF v_total_entries IS NOT NULL THEN
          INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
          VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_subscription_changed')
          ON CONFLICT DO NOTHING;
        END IF;
      END IF;
    ELSIF v_booking_id IS NULL THEN
      -- Create booking if it doesn't exist
      IF NEW.assigned_subscription_id IS NOT NULL THEN
        v_subscription_id := NEW.assigned_subscription_id;
      ELSE
        IF v_client_profile_id IS NOT NULL THEN
          SELECT id INTO v_subscription_id
          FROM public.subscriptions_with_remaining
          WHERE (
            (client_id = NEW.assigned_client_id) OR (user_id = v_client_profile_id)
          )
            AND status = 'active'
            AND NEW.starts_at::date BETWEEN started_at::date AND expires_at::date
            AND (remaining_entries IS NULL OR remaining_entries > 0)
          ORDER BY expires_at DESC NULLS LAST
          LIMIT 1;
        ELSE
          SELECT id INTO v_subscription_id
          FROM public.subscriptions_with_remaining
          WHERE client_id = NEW.assigned_client_id
            AND status = 'active'
            AND NEW.starts_at::date BETWEEN started_at::date AND expires_at::date
            AND (remaining_entries IS NULL OR remaining_entries > 0)
          ORDER BY expires_at DESC NULLS LAST
          LIMIT 1;
        END IF;
      END IF;
      
      INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
      VALUES (NEW.id, NEW.assigned_client_id, v_subscription_id, 'booked')
      RETURNING id INTO v_booking_id;
      
      IF v_subscription_id IS NOT NULL THEN
        SELECT COALESCE(s.custom_entries, p.entries) INTO v_total_entries
        FROM public.subscriptions s
        LEFT JOIN public.plans p ON p.id = s.plan_id
        WHERE s.id = v_subscription_id;
        
        IF v_total_entries IS NOT NULL THEN
          INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
          VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_auto_booking');
        END IF;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_individual_lesson_update() IS 
'Keeps bookings in sync for individual lessons. Picks subscriptions valid on the lesson date (starts_at).';

-- ============================================================================
-- book_lesson
-- (Base: migration 0037 with usage accounting)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.book_lesson(
  p_lesson_id uuid,
  p_subscription_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_my_client_id uuid;
  v_capacity integer;
  v_starts_at timestamptz;
  v_booking_deadline_minutes integer;
  v_now timestamptz := now();
  v_is_individual boolean;
  v_assigned_client_id uuid;
  v_booked_count integer;
  v_booking_id uuid;
  v_lesson_deleted_at timestamptz;
  v_activity_deleted_at timestamptz;
  -- Subscription vars
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_total_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Lock lesson
  SELECT 
    capacity, 
    starts_at, 
    booking_deadline_minutes, 
    is_individual, 
    assigned_client_id,
    deleted_at
  INTO 
    v_capacity, 
    v_starts_at, 
    v_booking_deadline_minutes, 
    v_is_individual, 
    v_assigned_client_id,
    v_lesson_deleted_at
  FROM public.lessons
  WHERE id = p_lesson_id
  FOR UPDATE;

  IF NOT FOUND OR v_lesson_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  -- Ensure activity not deleted
  SELECT a.deleted_at INTO v_activity_deleted_at
  FROM public.lessons l
  INNER JOIN public.activities a ON a.id = l.activity_id
  WHERE l.id = p_lesson_id;
  IF v_activity_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  -- Validate subscription if provided: valid on lesson date
  IF p_subscription_id IS NOT NULL THEN
    SELECT *
    INTO v_sub
    FROM public.subscriptions
    WHERE id = p_subscription_id
      AND client_id = v_my_client_id
      AND status = 'active'
      AND v_starts_at::date BETWEEN started_at::date AND expires_at::date;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_NOT_FOUND_OR_INACTIVE');
    END IF;

    -- Plan info and remaining entries
    SELECT * INTO v_plan FROM public.plans WHERE id = v_sub.plan_id;
    IF v_plan.deleted_at IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'PLAN_NOT_FOUND');
    END IF;

    v_total_entries := COALESCE(v_sub.custom_entries, v_plan.entries);
    IF v_total_entries IS NOT NULL THEN
      SELECT COALESCE(SUM(delta), 0)
      INTO v_used_entries
      FROM public.subscription_usages
      WHERE subscription_id = v_sub.id;
      v_remaining_entries := v_total_entries + v_used_entries;
      IF v_remaining_entries <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NO_ENTRIES_LEFT');
      END IF;
    END IF;
  END IF;

  -- Individual lesson: honor assigned client
  IF v_is_individual = true THEN
    IF v_assigned_client_id IS NULL OR v_my_client_id IS DISTINCT FROM v_assigned_client_id THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    -- Already booked?
    SELECT id INTO v_booking_id
    FROM public.bookings
    WHERE lesson_id = p_lesson_id
      AND client_id = v_assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
    LIMIT 1;
    IF v_booking_id IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'reason', 'ALREADY_BOOKED', 'booking_id', v_booking_id);
    END IF;

    -- Create booking
    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
    VALUES (p_lesson_id, v_assigned_client_id, p_subscription_id, 'booked')
    RETURNING id INTO v_booking_id;

    -- Usage accounting (entries-limited only)
    IF p_subscription_id IS NOT NULL AND v_total_entries IS NOT NULL THEN
      INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
      VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED', 'booking_id', v_booking_id);
  END IF;

  -- Public lesson
  IF v_booking_deadline_minutes IS NOT NULL
     AND v_booking_deadline_minutes > 0
     AND v_now > (v_starts_at - (v_booking_deadline_minutes || ' minutes')::interval) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.bookings
    WHERE lesson_id = p_lesson_id
      AND client_id = v_my_client_id
      AND status = 'booked'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
  END IF;

  -- Capacity
  SELECT count(*) INTO v_booked_count
  FROM public.bookings
  WHERE lesson_id = p_lesson_id
    AND status = 'booked';
  IF v_booked_count >= v_capacity THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
  END IF;

  INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
  VALUES (p_lesson_id, v_my_client_id, p_subscription_id, 'booked')
  RETURNING id INTO v_booking_id;

  IF p_subscription_id IS NOT NULL AND v_total_entries IS NOT NULL THEN
    INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
    VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');
  END IF;

  RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED', 'booking_id', v_booking_id);
END;
$$;

COMMENT ON FUNCTION public.book_lesson(uuid, uuid) IS 
'Books a lesson using client_id. Validates subscription on the lesson date (starts_at).';

-- ============================================================================
-- staff_book_lesson
-- (Base: standardized client_id version; validate on lesson date)
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
'Staff booking: validates subscription on the lesson date (starts_at).';


