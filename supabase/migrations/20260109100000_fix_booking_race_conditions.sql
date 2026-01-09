-- ============================================================================
-- Fix Race Conditions e Booking Duplicati
-- Migration: 20260109100000_fix_booking_race_conditions.sql
-- ============================================================================
-- Problemi risolti:
-- 1. Race condition: due utenti possono prenotare l'ultimo posto simultaneamente
-- 2. Booking duplicati: nessun vincolo DB previene duplicati per stesso client/lezione
--
-- Soluzione:
-- - Unique partial index su bookings(lesson_id, client_id) WHERE status = 'booked'
-- - ON CONFLICT DO NOTHING nelle INSERT per gestire race conditions
-- ============================================================================

-- 1. Unique partial index per prevenire booking duplicati
-- Questo previene che lo stesso client prenoti la stessa lezione più volte
-- Nota: usiamo WHERE status = 'booked' per permettere cancellazioni e ri-prenotazioni
CREATE UNIQUE INDEX IF NOT EXISTS idx_booking_lesson_client_active
ON public.bookings(lesson_id, client_id)
WHERE status = 'booked' AND client_id IS NOT NULL;

-- 2. Aggiornare book_lesson per usare ON CONFLICT
CREATE OR REPLACE FUNCTION public.book_lesson(p_lesson_id uuid, p_subscription_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_my_client_id uuid;
  v_booking_id uuid;
  v_lesson lessons%ROWTYPE;
  v_sub subscriptions%ROWTYPE;
  v_plan plans%ROWTYPE;
  v_activity_id uuid;
  v_starts_at timestamptz;
  v_capacity integer;
  v_is_individual boolean;
  v_assigned_client_id uuid;
  v_total_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_booked_count integer;
  v_has_plan_activities boolean;
BEGIN
  -- Auth check
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Lock the lesson row to prevent race conditions on capacity check
  SELECT * INTO v_lesson
  FROM public.lessons
  WHERE id = p_lesson_id
  FOR UPDATE;

  IF NOT FOUND OR v_lesson.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  v_activity_id := v_lesson.activity_id;
  v_starts_at := v_lesson.starts_at;
  v_capacity := v_lesson.capacity;
  v_is_individual := v_lesson.is_individual;
  v_assigned_client_id := v_lesson.assigned_client_id;

  -- Verify activity not deleted
  IF v_activity_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.activities WHERE id = v_activity_id AND deleted_at IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  -- Validate subscription if provided
  IF p_subscription_id IS NOT NULL THEN
    SELECT * INTO v_sub
    FROM public.subscriptions
    WHERE id = p_subscription_id
      AND client_id = v_my_client_id
      AND status = 'active'
      AND v_starts_at::date BETWEEN started_at::date AND expires_at::date;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_NOT_FOUND_OR_INACTIVE');
    END IF;

    SELECT * INTO v_plan FROM public.plans WHERE id = v_sub.plan_id;
    IF v_plan.deleted_at IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'PLAN_NOT_FOUND');
    END IF;

    -- Validate discipline coverage
    SELECT EXISTS(
      SELECT 1 FROM public.plan_activities pa WHERE pa.plan_id = v_sub.plan_id
    ) INTO v_has_plan_activities;

    IF v_has_plan_activities THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.plan_activities pa
        WHERE pa.plan_id = v_sub.plan_id AND pa.activity_id = v_activity_id
      ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_DISCIPLINE_MISMATCH');
      END IF;
    END IF;

    -- Remaining entries check
    v_total_entries := COALESCE(v_sub.custom_entries, v_plan.entries);
    IF v_total_entries IS NOT NULL THEN
      SELECT COALESCE(SUM(delta), 0) INTO v_used_entries
      FROM public.subscription_usages WHERE subscription_id = v_sub.id;
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

    -- Check existing booking first
    IF EXISTS (
      SELECT 1 FROM public.bookings
      WHERE lesson_id = p_lesson_id AND client_id = v_my_client_id AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    -- Insert with ON CONFLICT for race condition safety
    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
    VALUES (p_lesson_id, v_my_client_id, p_subscription_id, 'booked')
    ON CONFLICT (lesson_id, client_id) WHERE status = 'booked' AND client_id IS NOT NULL
    DO NOTHING
    RETURNING id INTO v_booking_id;

    IF v_booking_id IS NULL THEN
      -- Race condition: another request inserted just before us
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

  ELSE
    -- Public lesson: check deadline
    IF now() > v_starts_at - make_interval(mins => COALESCE(v_lesson.booking_deadline_minutes, 30)) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
    END IF;

    -- Check already booked first
    IF EXISTS (
      SELECT 1 FROM public.bookings
      WHERE lesson_id = p_lesson_id AND client_id = v_my_client_id AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    -- Capacity check (lesson is locked with FOR UPDATE, so this is atomic)
    SELECT count(*) INTO v_booked_count
    FROM public.bookings
    WHERE lesson_id = p_lesson_id AND status = 'booked';

    IF v_booked_count >= v_capacity THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;

    -- Insert with ON CONFLICT for race condition safety (double booking prevention)
    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
    VALUES (p_lesson_id, v_my_client_id, p_subscription_id, 'booked')
    ON CONFLICT (lesson_id, client_id) WHERE status = 'booked' AND client_id IS NOT NULL
    DO NOTHING
    RETURNING id INTO v_booking_id;

    IF v_booking_id IS NULL THEN
      -- Race condition: user already has a booking
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  END IF;

  -- Usage accounting: track ALL subscriptions (including unlimited)
  IF p_subscription_id IS NOT NULL THEN
    INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
    VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');
  END IF;

  RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED', 'booking_id', v_booking_id);
END;
$$;

COMMENT ON FUNCTION public.book_lesson(uuid, uuid) IS
'Book a lesson. Uses FOR UPDATE on lesson and ON CONFLICT on booking to prevent race conditions and double bookings.';

-- 3. Aggiornare staff_book_lesson con stessa logica ON CONFLICT
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
  v_activity_id uuid;
  v_has_plan_activities boolean;
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

  -- Lock lesson and get activity_id
  SELECT l.capacity, l.starts_at, l.booking_deadline_minutes, l.is_individual, l.assigned_client_id, l.activity_id
  INTO v_capacity, v_starts_at, v_booking_deadline_minutes, v_is_individual, v_assigned_client_id, v_activity_id
  FROM public.lessons l
  WHERE l.id = p_lesson_id
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

  -- Check if already booked
  IF EXISTS (
    SELECT 1 FROM public.bookings
    WHERE lesson_id = p_lesson_id AND client_id = p_client_id AND status = 'booked'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
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

    -- Validate discipline coverage
    SELECT EXISTS(
      SELECT 1 FROM public.plan_activities pa WHERE pa.plan_id = v_sub.plan_id
    ) INTO v_has_plan_activities;

    IF v_has_plan_activities THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.plan_activities pa
        WHERE pa.plan_id = v_sub.plan_id
          AND pa.activity_id = v_activity_id
      ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_DISCIPLINE_MISMATCH');
      END IF;
    END IF;

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

  -- Initialize usage tracking variables for reactivation
  IF v_reactivate_booking IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.subscription_usages
      WHERE booking_id = v_reactivate_booking AND delta = -1
    ) INTO v_has_existing_usage;

    SELECT EXISTS(
      SELECT 1 FROM public.subscription_usages
      WHERE booking_id = v_reactivate_booking AND delta = +1
    ) INTO v_cancel_restore_exists;
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
    -- Insert with ON CONFLICT for race condition safety
    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
    VALUES (p_lesson_id, p_client_id, p_subscription_id, 'booked')
    ON CONFLICT (lesson_id, client_id) WHERE status = 'booked' AND client_id IS NOT NULL
    DO NOTHING
    RETURNING id INTO v_booking_id;

    IF v_booking_id IS NULL THEN
      -- Race condition: another request inserted just before us
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  END IF;

  -- Usage accounting: track ALL subscriptions (including unlimited)
  IF p_subscription_id IS NOT NULL THEN
    IF v_reactivate_booking IS NOT NULL AND v_has_existing_usage AND v_cancel_restore_exists THEN
      -- Reactivation: remove the cancel restore instead of creating new usage
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
'Staff booking with race condition protection via ON CONFLICT and FOR UPDATE lock on lesson.';
