-- Migration 20260109000000: Improve Booking Validation
--
-- Changes:
-- 1. Add discipline validation to book_lesson and staff_book_lesson
-- 2. Track subscription_usages for unlimited subscriptions too
-- 3. Fix staff_book_lesson bug: v_has_existing_usage and v_cancel_restore_exists never initialized
-- 4. Remove dangerous Strategy 3 from cancel_booking (prevents gifting entries to wrong subscription)
-- 5. Track subscription_usages for all subscriptions in cancel_booking restore logic
--
-- This migration fixes several critical bugs in the booking system:
-- - CRITICAL: book_lesson/staff_book_lesson don't validate that subscription covers lesson discipline
-- - HIGH: staff_book_lesson has dead code due to uninitialized variables
-- - HIGH: cancel_booking Strategy 3 can gift entries to wrong subscription
-- - MEDIUM: Unlimited subscriptions don't track usage history

-- ============================================================================
-- book_lesson: Add discipline validation + track unlimited usage
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
  v_activity_id uuid;
  v_activity_deleted_at timestamptz;
  -- Subscription vars
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_total_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_has_plan_activities boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Lock lesson and get activity_id
  SELECT
    l.capacity,
    l.starts_at,
    l.booking_deadline_minutes,
    l.is_individual,
    l.assigned_client_id,
    l.deleted_at,
    l.activity_id
  INTO
    v_capacity,
    v_starts_at,
    v_booking_deadline_minutes,
    v_is_individual,
    v_assigned_client_id,
    v_lesson_deleted_at,
    v_activity_id
  FROM public.lessons l
  WHERE l.id = p_lesson_id
  FOR UPDATE;

  IF NOT FOUND OR v_lesson_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  -- Ensure activity not deleted
  SELECT a.deleted_at INTO v_activity_deleted_at
  FROM public.activities a
  WHERE a.id = v_activity_id;
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

    -- Plan info
    SELECT * INTO v_plan FROM public.plans WHERE id = v_sub.plan_id;
    IF v_plan.deleted_at IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'PLAN_NOT_FOUND');
    END IF;

    -- NEW: Validate discipline coverage
    -- Check if plan has any plan_activities (if not, it's an "Open" plan covering all disciplines)
    SELECT EXISTS(
      SELECT 1 FROM public.plan_activities pa WHERE pa.plan_id = v_sub.plan_id
    ) INTO v_has_plan_activities;

    IF v_has_plan_activities THEN
      -- Plan is discipline-specific, must cover the lesson's activity
      IF NOT EXISTS (
        SELECT 1 FROM public.plan_activities pa
        WHERE pa.plan_id = v_sub.plan_id
          AND pa.activity_id = v_activity_id
      ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_DISCIPLINE_MISMATCH');
      END IF;
    END IF;

    -- Remaining entries check
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

    -- Usage accounting: track ALL subscriptions (including unlimited)
    IF p_subscription_id IS NOT NULL THEN
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

  -- Usage accounting: track ALL subscriptions (including unlimited)
  IF p_subscription_id IS NOT NULL THEN
    INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
    VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');
  END IF;

  RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED', 'booking_id', v_booking_id);
END;
$$;

COMMENT ON FUNCTION public.book_lesson(uuid, uuid) IS
'Books a lesson using client_id. Validates subscription on the lesson date and discipline coverage. Tracks usage for all subscriptions including unlimited.';

-- ============================================================================
-- staff_book_lesson: Add discipline validation + fix v_has_existing_usage bug
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

    -- NEW: Validate discipline coverage
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

  -- FIX: Initialize v_has_existing_usage and v_cancel_restore_exists BEFORE using them
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
    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
    VALUES (p_lesson_id, p_client_id, p_subscription_id, 'booked')
    RETURNING id INTO v_booking_id;
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
'Staff booking: validates subscription on the lesson date and discipline coverage. Fixed bug with v_has_existing_usage initialization.';

-- ============================================================================
-- cancel_booking: Remove Strategy 3 + track unlimited usage
-- ============================================================================
CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id uuid) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
declare
  v_booking bookings%rowtype;
  v_lesson lessons%rowtype;
  v_now timestamptz := now();
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_total_entries integer;
  v_cancel_restore_exists boolean := false;
  v_my_client_id uuid;
begin
  v_my_client_id := public.get_my_client_id();

  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  select *
  into v_booking
  from bookings
  where id = p_booking_id
    and client_id = v_my_client_id;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  end if;

  if v_booking.status <> 'booked' then
    return jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_BOOKED');
  end if;

  select *
  into v_lesson
  from lessons
  where id = v_booking.lesson_id;

  -- Allow cancellation even if lesson is soft-deleted

  if v_now > v_lesson.starts_at - make_interval(mins => coalesce(v_lesson.cancel_deadline_minutes, 120)) then
    return jsonb_build_object('ok', false, 'reason', 'CANCEL_DEADLINE_PASSED');
  end if;

  update bookings
  set status = 'canceled'
  where id = p_booking_id;

  -- Strategy 1: Find subscription via subscription_usages (most reliable)
  select s.*
  into v_sub
  from subscription_usages su
  join subscriptions s on s.id = su.subscription_id
  where su.booking_id = p_booking_id
    and su.delta = -1
    and s.client_id = v_my_client_id
    and s.deleted_at IS NULL
  order by su.created_at desc
  limit 1;

  -- Strategy 2: If not found via subscription_usages, try using subscription_id from booking
  if not found and v_booking.subscription_id is not null then
    select *
    into v_sub
    from subscriptions
    where id = v_booking.subscription_id
      and client_id = v_my_client_id
      and deleted_at IS NULL;
  end if;

  -- REMOVED: Strategy 3 was dangerous - it could find a random subscription
  -- and gift entries to the wrong subscription. If we can't find the subscription,
  -- just cancel without restoring entries.
  if not found then
    return jsonb_build_object('ok', true, 'reason', 'CANCELED_NO_SUBSCRIPTION');
  end if;

  select *
  into v_plan
  from plans
  where id = v_sub.plan_id;

  -- Verifica soft delete del piano
  if v_plan.deleted_at IS NOT NULL then
    return jsonb_build_object('ok', true, 'reason', 'CANCELED_PLAN_DELETED');
  end if;

  -- CHANGED: Track restore for ALL subscriptions, not just limited ones
  -- This keeps a complete history of bookings even for unlimited subscriptions

  -- Check if CANCEL_RESTORE already exists for this booking
  select exists(
    select 1
    from subscription_usages
    where booking_id = p_booking_id
      and delta = +1
      and reason = 'CANCEL_RESTORE'
  ) into v_cancel_restore_exists;

  -- Only insert CANCEL_RESTORE if it doesn't already exist
  if not v_cancel_restore_exists then
    insert into subscription_usages (subscription_id, booking_id, delta, reason)
    values (v_sub.id, p_booking_id, +1, 'CANCEL_RESTORE');
  end if;

  return jsonb_build_object('ok', true, 'reason', 'CANCELED');
end;
$$;

COMMENT ON FUNCTION public.cancel_booking(uuid) IS
'Cancels a booking. Removed dangerous Strategy 3 (random subscription lookup). Tracks restore for all subscriptions including unlimited.';

-- ============================================================================
-- staff_cancel_booking: Track unlimited usage
-- ============================================================================
CREATE OR REPLACE FUNCTION public.staff_cancel_booking(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_sub subscriptions%ROWTYPE;
  v_plan plans%ROWTYPE;
  v_total_entries integer;
  v_cancel_restore_exists boolean := false;
BEGIN
  -- Verifica che l'utente sia staff
  IF NOT is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
  END IF;

  -- Recupera la booking
  SELECT *
  INTO v_booking
  FROM bookings
  WHERE id = p_booking_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  END IF;

  -- Verifica che la booking sia in stato "booked"
  IF v_booking.status <> 'booked' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_BOOKED');
  END IF;

  -- Aggiorna lo stato a canceled
  UPDATE bookings
  SET status = 'canceled'
  WHERE id = p_booking_id;

  -- Strategy 1: Find subscription via subscription_usages (most reliable)
  SELECT s.*
  INTO v_sub
  FROM subscription_usages su
  JOIN subscriptions s ON s.id = su.subscription_id
  WHERE su.booking_id = p_booking_id
    AND su.delta = -1
    AND s.deleted_at IS NULL
  ORDER BY su.created_at DESC
  LIMIT 1;

  -- Strategy 2: If not found via subscription_usages, try using subscription_id from booking
  IF NOT FOUND AND v_booking.subscription_id IS NOT NULL THEN
    SELECT *
    INTO v_sub
    FROM subscriptions
    WHERE id = v_booking.subscription_id
      AND deleted_at IS NULL;
  END IF;

  -- Se abbiamo trovato una subscription, track the restore
  IF FOUND THEN
    -- Get plan info
    SELECT *
    INTO v_plan
    FROM plans
    WHERE id = v_sub.plan_id;

    -- Verifica soft delete del piano
    IF v_plan.deleted_at IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED_PLAN_DELETED');
    END IF;

    -- CHANGED: Track restore for ALL subscriptions, not just limited ones
    -- Verifica che non esista già un record di ripristino
    SELECT EXISTS(
      SELECT 1
      FROM subscription_usages
      WHERE booking_id = p_booking_id
        AND delta = +1
        AND reason IN ('CANCEL_RESTORE', 'CANCEL')
    ) INTO v_cancel_restore_exists;

    -- Solo se non esiste già un record di ripristino
    IF NOT v_cancel_restore_exists THEN
      INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
      VALUES (v_sub.id, p_booking_id, +1, 'CANCEL_RESTORE')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED');
END;
$$;

COMMENT ON FUNCTION public.staff_cancel_booking(uuid) IS
'Staff cancels a booking. Tracks restore for all subscriptions including unlimited.';

-- ============================================================================
-- auto_create_booking_for_individual_lesson: Track unlimited usage
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

      -- CHANGED: Create subscription usage for ALL subscriptions (including unlimited)
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
'Auto-creates a booking for individual lessons. Tracks usage for all subscriptions including unlimited.';

-- ============================================================================
-- handle_individual_lesson_update: Track unlimited usage
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

        -- CHANGED: Restore for all subscriptions, not just limited
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
        -- CHANGED: Restore for all subscriptions
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

      -- CHANGED: Track usage for ALL subscriptions
      IF v_subscription_id IS NOT NULL THEN
        INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
        VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_subscription_changed')
        ON CONFLICT DO NOTHING;
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

      -- CHANGED: Track usage for ALL subscriptions
      IF v_subscription_id IS NOT NULL THEN
        INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
        VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_auto_booking');
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_individual_lesson_update() IS
'Keeps bookings in sync for individual lessons. Tracks usage for all subscriptions including unlimited.';
