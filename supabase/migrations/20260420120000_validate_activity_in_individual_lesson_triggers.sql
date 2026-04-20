-- Validate plan_activities coverage when creating/updating bookings for individual lessons.
--
-- Bug context: `auto_create_booking_for_individual_lesson` (INSERT trigger) and
-- `handle_individual_lesson_update` (UPDATE trigger) bypassed the plan_activities
-- validation that `book_lesson` / `staff_book_lesson` enforce. This allowed an
-- individual Training lesson to consume a Yoga subscription because the auto-pick
-- logic only ordered by expires_at without checking activity coverage, and the
-- INSERT path ignored the operator's `assigned_subscription_id` entirely.
--
-- This migration:
--   1. Adds helper `subscription_covers_activity(sub_id, activity_id)` matching
--      the same semantics as book_lesson (plan with no plan_activities = universal).
--   2. INSERT trigger: now respects NEW.assigned_subscription_id (with validation)
--      and filters auto-pick by activity coverage.
--   3. UPDATE trigger: validates NEW.assigned_subscription_id and filters
--      auto-pick by activity coverage.
--
-- When the operator picks an incompatible subscription explicitly, the trigger
-- raises a check_violation error so the lesson save is rejected. When auto-picking,
-- the trigger silently skips incompatible subs (so v_subscription_id may end up
-- NULL, producing a booking without subscription — matches prior fallback behavior).

-- ---------------------------------------------------------------------------
-- 1. Helper function
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.subscription_covers_activity(
  p_subscription_id uuid,
  p_activity_id uuid
) RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_plan_id uuid;
  v_has_restrictions boolean;
  v_covers boolean;
BEGIN
  IF p_subscription_id IS NULL OR p_activity_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT plan_id INTO v_plan_id
  FROM public.subscriptions
  WHERE id = p_subscription_id;

  IF v_plan_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.plan_activities WHERE plan_id = v_plan_id
  ) INTO v_has_restrictions;

  IF NOT v_has_restrictions THEN
    RETURN true;  -- plan without restrictions = universal coverage
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.plan_activities
    WHERE plan_id = v_plan_id AND activity_id = p_activity_id
  ) INTO v_covers;

  RETURN v_covers;
END;
$function$;

COMMENT ON FUNCTION public.subscription_covers_activity(uuid, uuid) IS
  'Returns true if the subscription''s plan covers the given activity. A plan with no plan_activities rows is treated as universal (covers all activities), consistent with book_lesson/staff_book_lesson.';

-- ---------------------------------------------------------------------------
-- 2. INSERT trigger function
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auto_create_booking_for_individual_lesson()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_subscription_id uuid;
  v_booking_id uuid;
BEGIN
  -- Only process if this is an individual lesson with assigned client
  IF NEW.is_individual = true AND NEW.assigned_client_id IS NOT NULL THEN

    -- Resolve subscription: prefer operator's explicit choice, else auto-pick
    IF NEW.assigned_subscription_id IS NOT NULL THEN
      -- Validate activity coverage: reject lesson creation if sub doesn't cover activity
      IF NOT public.subscription_covers_activity(NEW.assigned_subscription_id, NEW.activity_id) THEN
        RAISE EXCEPTION 'SUBSCRIPTION_DISCIPLINE_MISMATCH: subscription % does not cover activity %',
          NEW.assigned_subscription_id, NEW.activity_id
          USING ERRCODE = 'check_violation';
      END IF;
      v_subscription_id := NEW.assigned_subscription_id;
    ELSE
      -- Auto-pick: active subscription valid on lesson date AND covering the activity
      SELECT swr.id INTO v_subscription_id
      FROM public.subscriptions_with_remaining swr
      WHERE swr.client_id = NEW.assigned_client_id
        AND swr.status = 'active'
        AND NEW.starts_at::date BETWEEN swr.started_at::date AND swr.expires_at::date
        AND (swr.remaining_entries IS NULL OR swr.remaining_entries > 0)
        AND public.subscription_covers_activity(swr.id, NEW.activity_id)
      ORDER BY swr.expires_at DESC NULLS LAST
      LIMIT 1;
    END IF;

    -- Check if booking already exists (avoid duplicates)
    SELECT id INTO v_booking_id
    FROM public.bookings
    WHERE lesson_id = NEW.id
      AND client_id = NEW.assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
    LIMIT 1;

    IF v_booking_id IS NULL THEN
      INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
      VALUES (NEW.id, NEW.assigned_client_id, v_subscription_id, 'booked')
      RETURNING id INTO v_booking_id;

      IF v_subscription_id IS NOT NULL THEN
        INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
        VALUES (v_subscription_id, v_booking_id, -1, 'BOOK');
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 3. UPDATE trigger function
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_individual_lesson_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

  -- Validate any explicit assigned_subscription_id against activity
  IF NEW.is_individual = true
     AND NEW.assigned_subscription_id IS NOT NULL
     AND NOT public.subscription_covers_activity(NEW.assigned_subscription_id, NEW.activity_id) THEN
    RAISE EXCEPTION 'SUBSCRIPTION_DISCIPLINE_MISMATCH: subscription % does not cover activity %',
      NEW.assigned_subscription_id, NEW.activity_id
      USING ERRCODE = 'check_violation';
  END IF;

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

      -- Priority: use assigned_subscription_id if present (already validated above);
      -- else pick a valid sub that covers the activity
      IF NEW.assigned_subscription_id IS NOT NULL THEN
        v_subscription_id := NEW.assigned_subscription_id;
      ELSE
        IF v_client_profile_id IS NOT NULL THEN
          SELECT swr.id INTO v_subscription_id
          FROM public.subscriptions_with_remaining swr
          WHERE (
            (swr.client_id = NEW.assigned_client_id) OR (swr.user_id = v_client_profile_id)
          )
            AND swr.status = 'active'
            AND NEW.starts_at::date BETWEEN swr.started_at::date AND swr.expires_at::date
            AND (swr.remaining_entries IS NULL OR swr.remaining_entries > 0)
            AND public.subscription_covers_activity(swr.id, NEW.activity_id)
          ORDER BY swr.expires_at DESC NULLS LAST
          LIMIT 1;
        ELSE
          SELECT swr.id INTO v_subscription_id
          FROM public.subscriptions_with_remaining swr
          WHERE swr.client_id = NEW.assigned_client_id
            AND swr.status = 'active'
            AND NEW.starts_at::date BETWEEN swr.started_at::date AND swr.expires_at::date
            AND (swr.remaining_entries IS NULL OR swr.remaining_entries > 0)
            AND public.subscription_covers_activity(swr.id, NEW.activity_id)
          ORDER BY swr.expires_at DESC NULLS LAST
          LIMIT 1;
        END IF;
      END IF;

      UPDATE public.bookings
      SET subscription_id = v_subscription_id
      WHERE id = v_booking_id;

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
          SELECT swr.id INTO v_subscription_id
          FROM public.subscriptions_with_remaining swr
          WHERE (
            (swr.client_id = NEW.assigned_client_id) OR (swr.user_id = v_client_profile_id)
          )
            AND swr.status = 'active'
            AND NEW.starts_at::date BETWEEN swr.started_at::date AND swr.expires_at::date
            AND (swr.remaining_entries IS NULL OR swr.remaining_entries > 0)
            AND public.subscription_covers_activity(swr.id, NEW.activity_id)
          ORDER BY swr.expires_at DESC NULLS LAST
          LIMIT 1;
        ELSE
          SELECT swr.id INTO v_subscription_id
          FROM public.subscriptions_with_remaining swr
          WHERE swr.client_id = NEW.assigned_client_id
            AND swr.status = 'active'
            AND NEW.starts_at::date BETWEEN swr.started_at::date AND swr.expires_at::date
            AND (swr.remaining_entries IS NULL OR swr.remaining_entries > 0)
            AND public.subscription_covers_activity(swr.id, NEW.activity_id)
          ORDER BY swr.expires_at DESC NULLS LAST
          LIMIT 1;
        END IF;
      END IF;

      INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
      VALUES (NEW.id, NEW.assigned_client_id, v_subscription_id, 'booked')
      RETURNING id INTO v_booking_id;

      IF v_subscription_id IS NOT NULL THEN
        INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
        VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_auto_booking');
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
