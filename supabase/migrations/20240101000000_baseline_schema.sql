-- ============================================================================
-- BASELINE SCHEMA (squash) — generata da un dump --schema public della PROD (2026-05).
-- Sostituisce le ~144 migrazioni storiche 20240101*..20260526* che erano state
-- ricostruite via 'db pull' e NON erano rigiocabili da zero (ordine rotto + bug di tipo/FK).
-- Questa baseline rispecchia esattamente lo schema di prod ed è dependency-ordered (replay pulito).
-- NB: contiene solo lo schema 'public' (oggetti su 'auth'/'storage' restano gestiti da Supabase/prod).
-- La history di prod va riconciliata con 'supabase migration repair' SOLO al primo push futuro.
-- ============================================================================




SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "postgres";


CREATE TYPE "public"."announcement_recurrence_frequency" AS ENUM (
    'daily',
    'weekly',
    'biweekly',
    'monthly'
);


ALTER TYPE "public"."announcement_recurrence_frequency" OWNER TO "postgres";


CREATE TYPE "public"."booking_status" AS ENUM (
    'booked',
    'canceled',
    'attended',
    'no_show'
);


ALTER TYPE "public"."booking_status" OWNER TO "postgres";


CREATE TYPE "public"."bug_status" AS ENUM (
    'open',
    'in_progress',
    'resolved',
    'closed'
);


ALTER TYPE "public"."bug_status" OWNER TO "postgres";


CREATE TYPE "public"."campaign_content_type" AS ENUM (
    'brief',
    'push_notification',
    'newsletter',
    'instagram_post',
    'instagram_story',
    'instagram_reel',
    'instagram_carousel',
    'facebook_post'
);


ALTER TYPE "public"."campaign_content_type" OWNER TO "postgres";


CREATE TYPE "public"."campaign_tone" AS ENUM (
    'formale',
    'amichevole',
    'urgente',
    'entusiasta',
    'professionale',
    'empatico',
    'diretto',
    'esclusivo'
);


ALTER TYPE "public"."campaign_tone" OWNER TO "postgres";


CREATE TYPE "public"."campaign_type" AS ENUM (
    'promo',
    'evento',
    'annuncio',
    'corso_nuovo'
);


ALTER TYPE "public"."campaign_type" OWNER TO "postgres";


CREATE TYPE "public"."content_status" AS ENUM (
    'pending',
    'generated',
    'edited',
    'scheduled',
    'sent',
    'published',
    'failed',
    'skipped'
);


ALTER TYPE "public"."content_status" OWNER TO "postgres";


CREATE TYPE "public"."marketing_campaign_status" AS ENUM (
    'draft',
    'ai_generating',
    'pending_review',
    'scheduled',
    'executing',
    'completed',
    'failed'
);


ALTER TYPE "public"."marketing_campaign_status" OWNER TO "postgres";


CREATE TYPE "public"."newsletter_campaign_status" AS ENUM (
    'draft',
    'scheduled',
    'sending',
    'sent',
    'failed'
);


ALTER TYPE "public"."newsletter_campaign_status" OWNER TO "postgres";


CREATE TYPE "public"."newsletter_email_status" AS ENUM (
    'pending',
    'sent',
    'delivered',
    'opened',
    'clicked',
    'bounced',
    'complained',
    'failed'
);


ALTER TYPE "public"."newsletter_email_status" OWNER TO "postgres";


CREATE TYPE "public"."newsletter_event_type" AS ENUM (
    'delivered',
    'opened',
    'clicked',
    'bounced',
    'complained'
);


ALTER TYPE "public"."newsletter_event_type" OWNER TO "postgres";


CREATE TYPE "public"."notification_category" AS ENUM (
    'lesson_reminder',
    'subscription_expiry',
    'entries_low',
    're_engagement',
    'first_lesson',
    'milestone',
    'birthday',
    'new_event',
    'announcement',
    'practice_reminder',
    'practice_resume',
    'journal_reminder'
);


ALTER TYPE "public"."notification_category" OWNER TO "postgres";


CREATE TYPE "public"."notification_channel" AS ENUM (
    'push',
    'email'
);


ALTER TYPE "public"."notification_channel" OWNER TO "postgres";


CREATE TYPE "public"."notification_status" AS ENUM (
    'pending',
    'sent',
    'delivered',
    'failed',
    'skipped'
);


ALTER TYPE "public"."notification_status" OWNER TO "postgres";


CREATE TYPE "public"."practice_block_type" AS ENUM (
    'text',
    'image',
    'audio',
    'video'
);


ALTER TYPE "public"."practice_block_type" OWNER TO "postgres";


CREATE TYPE "public"."practice_category" AS ENUM (
    'meditazione',
    'corpo',
    'respiro',
    'scrittura',
    'rilassamento'
);


ALTER TYPE "public"."practice_category" OWNER TO "postgres";


CREATE TYPE "public"."practice_level" AS ENUM (
    'principiante',
    'intermedio',
    'avanzato'
);


ALTER TYPE "public"."practice_level" OWNER TO "postgres";


CREATE TYPE "public"."practice_user_status" AS ENUM (
    'started',
    'completed'
);


ALTER TYPE "public"."practice_user_status" OWNER TO "postgres";


CREATE TYPE "public"."social_platform" AS ENUM (
    'instagram',
    'facebook'
);


ALTER TYPE "public"."social_platform" OWNER TO "postgres";


CREATE TYPE "public"."subscription_status" AS ENUM (
    'active',
    'completed',
    'expired',
    'canceled'
);


ALTER TYPE "public"."subscription_status" OWNER TO "postgres";


CREATE TYPE "public"."user_role" AS ENUM (
    'user',
    'operator',
    'admin',
    'finance'
);


ALTER TYPE "public"."user_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_complete_expired_subscriptions"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_effective_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_plan_entries integer;
BEGIN
  -- Preserva lo stato 'canceled' (non modificare abbonamenti annullati manualmente)
  IF NEW.status = 'canceled' THEN
    RETURN NEW;
  END IF;
  
  -- Calcola effective_entries (custom_entries o entries dal plan)
  SELECT entries INTO v_plan_entries
  FROM plans
  WHERE id = NEW.plan_id;
  
  v_effective_entries := COALESCE(NEW.custom_entries, v_plan_entries);
  
  -- Se l'abbonamento è illimitato (effective_entries è NULL)
  IF v_effective_entries IS NULL THEN
    -- Calcola in base alla scadenza
    IF NEW.expires_at < CURRENT_DATE THEN
      NEW.status := 'expired';
    ELSE
      NEW.status := 'active';
    END IF;
    RETURN NEW;
  END IF;
  
  -- Calcola posti usati
  SELECT COALESCE(SUM(delta), 0) INTO v_used_entries
  FROM subscription_usages
  WHERE subscription_id = NEW.id;
  
  -- Calcola posti rimanenti
  v_remaining_entries := v_effective_entries + v_used_entries;
  
  -- Applica la nuova logica:
  -- 1. Se ha esaurito i posti -> 'completed' (indipendentemente dalla scadenza)
  IF v_remaining_entries <= 0 THEN
    NEW.status := 'completed';
  -- 2. Se ha ancora posti disponibili, calcola in base alla scadenza
  ELSIF NEW.expires_at < CURRENT_DATE THEN
    NEW.status := 'expired';
  ELSE
    NEW.status := 'active';
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_complete_expired_subscriptions"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."auto_complete_expired_subscriptions"() IS 'Funzione trigger che aggiorna automaticamente lo status degli abbonamenti secondo la logica:
- "Completato": se remaining_entries <= 0 (indipendentemente dalla scadenza)
- "Scaduto": se ha ancora prenotazioni disponibili MA è passata la data di scadenza
- "Attivo": se non è ancora scaduto E ha ancora prenotazioni disponibili
- "Annullato": preservato se impostato manualmente (status = canceled)';



CREATE OR REPLACE FUNCTION "public"."auto_create_booking_for_individual_lesson"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
$$;


ALTER FUNCTION "public"."auto_create_booking_for_individual_lesson"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."auto_create_booking_for_individual_lesson"() IS 'Auto-creates a booking for individual lessons. Tracks usage for all subscriptions including unlimited.';



CREATE OR REPLACE FUNCTION "public"."book_event"("p_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_my_client_id uuid;
  v_capacity integer;
  v_starts_at timestamptz;
  v_now timestamptz := now();
  v_booked_count integer;
  v_booking_id uuid;
  v_event_deleted_at timestamptz;
  v_link text;
  v_reactivate_booking_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();

  -- Lock event row per prevenire race conditions
  SELECT 
    capacity, 
    starts_at, 
    deleted_at,
    link
  INTO 
    v_capacity, 
    v_starts_at, 
    v_event_deleted_at,
    v_link
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_FOUND');
  END IF;

  -- Verifica soft delete
  IF v_event_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_FOUND');
  END IF;

  -- Verifica che l'evento sia attivo
  IF NOT EXISTS (
    SELECT 1 FROM public.events 
    WHERE id = p_event_id AND is_active = true
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_ACTIVE');
  END IF;

  -- Verifica che non sia già prenotato
  -- client_id è la fonte di verità: se l'utente ha un client_id, controlla solo quello
  -- Altrimenti controlla user_id
  IF v_my_client_id IS NOT NULL THEN
    -- Utente con client_id: controlla solo client_id (fonte di verità)
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id
        AND client_id = v_my_client_id
        AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  ELSE
    -- Utente senza client_id: controlla user_id
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id
        AND user_id = v_user_id
        AND client_id IS NULL
        AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  END IF;

  -- Cerca se esiste una prenotazione cancellata da riattivare
  -- client_id è la fonte di verità: se l'utente ha un client_id, cerca solo quello
  IF v_my_client_id IS NOT NULL THEN
    SELECT id
    INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND client_id = v_my_client_id
      AND status = 'canceled'
    FOR UPDATE
    LIMIT 1;
  ELSE
    SELECT id
    INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND user_id = v_user_id
      AND client_id IS NULL
      AND status = 'canceled'
    FOR UPDATE
    LIMIT 1;
  END IF;

  -- Verifica capacità (se impostata)
  -- Se stiamo riattivando, la capacità è già stata "liberata" quando è stata cancellata
  -- quindi non dobbiamo verificare di nuovo. Se creiamo una nuova prenotazione, verifichiamo.
  IF v_reactivate_booking_id IS NULL AND v_capacity IS NOT NULL THEN
    -- Conta prenotazioni attive (booked, attended, no_show)
    SELECT count(*) INTO v_booked_count
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND status IN ('booked', 'attended', 'no_show');

    IF v_booked_count >= v_capacity THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;
  END IF;

  -- Riattiva prenotazione esistente o crea nuova
  -- client_id è la fonte di verità: se l'utente ha un client_id, usare SEMPRE client_id (user_id = NULL)
  IF v_reactivate_booking_id IS NOT NULL THEN
    -- Riattiva prenotazione cancellata
    UPDATE public.event_bookings
    SET status = 'booked',
        created_at = now()
    WHERE id = v_reactivate_booking_id;
    v_booking_id := v_reactivate_booking_id;
  ELSE
    -- Crea nuova prenotazione
    -- client_id è la fonte di verità: se disponibile, usare SEMPRE client_id (user_id = NULL)
    INSERT INTO public.event_bookings (event_id, user_id, client_id, status)
    VALUES (
      p_event_id, 
      CASE WHEN v_my_client_id IS NOT NULL THEN NULL ELSE v_user_id END,
      v_my_client_id,
      'booked'
    )
    RETURNING id INTO v_booking_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
END;
$$;


ALTER FUNCTION "public"."book_event"("p_event_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."book_event"("p_event_id" "uuid") IS 'Prenota un evento per l''utente autenticato. Gestisce capacità e prevenzione doppia prenotazione. Riattiva prenotazioni cancellate invece di crearne di nuove. client_id è la fonte di verità: se l''utente ha un client_id, viene sempre usato client_id (user_id = NULL).';



CREATE OR REPLACE FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid") IS 'Book a lesson. Uses FOR UPDATE on lesson and ON CONFLICT on booking to prevent race conditions and double bookings.';



CREATE OR REPLACE FUNCTION "public"."calculate_next_announcement_occurrence"("p_frequency" "public"."announcement_recurrence_frequency", "p_day_of_week" smallint, "p_day_of_month" smallint, "p_time" time without time zone, "p_from_date" timestamp with time zone DEFAULT "now"()) RETURNS timestamp with time zone
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_next timestamptz;
  v_target_date date;
  v_current_dow smallint;
BEGIN
  -- Get current day of week (0=Sunday in PostgreSQL with extract(dow))
  v_current_dow := extract(dow from p_from_date)::smallint;
  v_target_date := p_from_date::date;

  CASE p_frequency
    WHEN 'daily' THEN
      -- Next occurrence is today at the specified time, or tomorrow if already past
      v_next := v_target_date + p_time;
      IF v_next <= p_from_date THEN
        v_next := v_next + interval '1 day';
      END IF;

    WHEN 'weekly' THEN
      -- Find next occurrence of the target day
      IF p_day_of_week IS NULL THEN
        RETURN NULL;
      END IF;

      -- Calculate days until target day
      IF v_current_dow <= p_day_of_week THEN
        v_target_date := v_target_date + (p_day_of_week - v_current_dow);
      ELSE
        v_target_date := v_target_date + (7 - v_current_dow + p_day_of_week);
      END IF;

      v_next := v_target_date + p_time;
      -- If it's today but already past the time, move to next week
      IF v_next <= p_from_date THEN
        v_next := v_next + interval '7 days';
      END IF;

    WHEN 'biweekly' THEN
      -- Same as weekly but add 2 weeks
      IF p_day_of_week IS NULL THEN
        RETURN NULL;
      END IF;

      IF v_current_dow <= p_day_of_week THEN
        v_target_date := v_target_date + (p_day_of_week - v_current_dow);
      ELSE
        v_target_date := v_target_date + (7 - v_current_dow + p_day_of_week);
      END IF;

      v_next := v_target_date + p_time;
      IF v_next <= p_from_date THEN
        v_next := v_next + interval '14 days';
      END IF;

    WHEN 'monthly' THEN
      -- Find next occurrence of the target day of month
      IF p_day_of_month IS NULL THEN
        RETURN NULL;
      END IF;

      -- Try this month first
      v_target_date := date_trunc('month', v_target_date)::date + (p_day_of_month - 1);

      -- Handle months with fewer days
      IF extract(day from (date_trunc('month', v_target_date) + interval '1 month' - interval '1 day')) < p_day_of_month THEN
        -- Use last day of month
        v_target_date := (date_trunc('month', v_target_date) + interval '1 month' - interval '1 day')::date;
      END IF;

      v_next := v_target_date + p_time;

      IF v_next <= p_from_date THEN
        -- Move to next month
        v_target_date := (date_trunc('month', v_target_date) + interval '1 month')::date + (p_day_of_month - 1);
        IF extract(day from (date_trunc('month', v_target_date) + interval '1 month' - interval '1 day')) < p_day_of_month THEN
          v_target_date := (date_trunc('month', v_target_date) + interval '1 month' - interval '1 day')::date;
        END IF;
        v_next := v_target_date + p_time;
      END IF;

    ELSE
      RETURN NULL;
  END CASE;

  RETURN v_next;
END;
$$;


ALTER FUNCTION "public"."calculate_next_announcement_occurrence"("p_frequency" "public"."announcement_recurrence_frequency", "p_day_of_week" smallint, "p_day_of_month" smallint, "p_time" time without time zone, "p_from_date" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_operator_compensation"("p_month_start" "date", "p_month_end" "date", "p_operator_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("operator_id" "uuid", "operator_name" "text", "lesson_id" "uuid", "lesson_date" timestamp with time zone, "activity_name" "text", "lesson_duration_minutes" integer, "generated_revenue_cents" bigint, "revenue_per_hour_cents" bigint, "room_rental_cents" bigint, "operator_payout_cents" bigint, "alice_share_cents" bigint, "studio_margin_cents" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  WITH lesson_revenue AS (
    -- Calculate revenue generated per lesson from bookings
    -- Revenue = sum of (subscription price / entries) for each booking
    -- Priority: custom_price_cents > subscription.discount_percent > plan.discount_percent
    SELECT
      l.id AS lesson_id,
      l.operator_id,
      l.starts_at,
      l.ends_at,
      a.name AS activity_name,
      COALESCE(a.duration_minutes,
        EXTRACT(EPOCH FROM (l.ends_at - l.starts_at)) / 60
      )::INTEGER AS duration_minutes,
      COALESCE(SUM(
        CASE
          -- Custom subscription: use custom price / custom entries
          WHEN s.custom_price_cents IS NOT NULL AND COALESCE(s.custom_entries, 0) > 0
            THEN s.custom_price_cents / s.custom_entries
          -- Subscription discount: use plan price with subscription discount / entries
          WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
               AND p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
            THEN ROUND(p.price_cents * (1 - s.discount_percent / 100.0)) / p.entries
          -- Regular subscription: use plan price (with plan discount) / entries
          WHEN p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
            THEN ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0)) / p.entries
          ELSE 0
        END
      ), 0)::BIGINT AS generated_revenue_cents
    FROM lessons l
    JOIN activities a ON l.activity_id = a.id
    LEFT JOIN bookings b ON b.lesson_id = l.id
      AND b.status IN ('booked', 'attended', 'no_show')
    LEFT JOIN subscriptions s ON b.subscription_id = s.id
    LEFT JOIN plans p ON s.plan_id = p.id
    WHERE l.starts_at >= p_month_start
      AND l.starts_at < (p_month_end + INTERVAL '1 day')
      AND l.deleted_at IS NULL
      AND l.operator_id IS NOT NULL
      AND (p_operator_id IS NULL OR l.operator_id = p_operator_id)
    GROUP BY l.id, l.operator_id, l.starts_at, l.ends_at, a.name, a.duration_minutes
  ),
  compensation_calc AS (
    SELECT
      lr.lesson_id,
      lr.operator_id,
      o.name AS operator_name,
      lr.starts_at AS lesson_date,
      lr.activity_name,
      GREATEST(lr.duration_minutes, 1) AS lesson_duration_minutes, -- Avoid division by zero
      lr.generated_revenue_cents,
      -- Revenue per hour calculation
      CASE
        WHEN lr.duration_minutes > 0
        THEN (lr.generated_revenue_cents * 60 / lr.duration_minutes)::BIGINT
        ELSE lr.generated_revenue_cents
      END AS revenue_per_hour_cents,
      -- Room rental: always 15%
      ROUND(lr.generated_revenue_cents * 0.15)::BIGINT AS room_rental_cents
    FROM lesson_revenue lr
    JOIN operators o ON lr.operator_id = o.id
    WHERE o.deleted_at IS NULL
  )
  SELECT
    cc.operator_id,
    cc.operator_name,
    cc.lesson_id,
    cc.lesson_date,
    cc.activity_name,
    cc.lesson_duration_minutes::INTEGER,
    cc.generated_revenue_cents,
    cc.revenue_per_hour_cents,
    cc.room_rental_cents,
    -- Operator payout calculation
    CASE
      WHEN cc.revenue_per_hour_cents > 4000 -- > 40 EUR/hour (4000 cents)
      THEN ROUND(4000.0 * cc.lesson_duration_minutes / 60.0)::BIGINT -- 40 EUR/hour prorated
      ELSE GREATEST(cc.generated_revenue_cents - cc.room_rental_cents, 0)::BIGINT -- Revenue minus room rental (floor at 0)
    END AS operator_payout_cents,
    -- Alice share calculation (25% of margin, only if > 40/hour)
    CASE
      WHEN cc.revenue_per_hour_cents > 4000 -- > 40 EUR/hour
      THEN ROUND(
        GREATEST(
          cc.generated_revenue_cents
          - cc.room_rental_cents
          - ROUND(4000.0 * cc.lesson_duration_minutes / 60.0),
          0
        ) * 0.25
      )::BIGINT
      ELSE 0::BIGINT
    END AS alice_share_cents,
    -- Studio margin calculation (75% of margin, only if > 40/hour)
    CASE
      WHEN cc.revenue_per_hour_cents > 4000 -- > 40 EUR/hour
      THEN ROUND(
        GREATEST(
          cc.generated_revenue_cents
          - cc.room_rental_cents
          - ROUND(4000.0 * cc.lesson_duration_minutes / 60.0),
          0
        ) * 0.75
      )::BIGINT
      ELSE 0::BIGINT
    END AS studio_margin_cents
  FROM compensation_calc cc
  ORDER BY cc.lesson_date, cc.operator_name;
END;
$$;


ALTER FUNCTION "public"."calculate_operator_compensation"("p_month_start" "date", "p_month_end" "date", "p_operator_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."call_edge_function"("p_function_name" "text", "p_body" "jsonb" DEFAULT '{}'::"jsonb") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_url text;
    v_service_key text;
    v_request_id bigint;
BEGIN
    -- Get configuration from Vault
    SELECT decrypted_secret INTO v_url 
    FROM vault.decrypted_secrets 
    WHERE name = 'supabase_url';
    
    SELECT decrypted_secret INTO v_service_key 
    FROM vault.decrypted_secrets 
    WHERE name = 'service_role_key';

    IF v_url IS NULL OR v_service_key IS NULL THEN
        RAISE EXCEPTION 'Missing supabase_url or service_role_key in vault.secrets';
    END IF;

    -- Make HTTP POST request via pg_net
    SELECT net.http_post(
        url := v_url || '/functions/v1/' || p_function_name,
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || v_service_key,
            'Content-Type', 'application/json'
        ),
        body := p_body
    ) INTO v_request_id;

    RETURN v_request_id;
END;
$$;


ALTER FUNCTION "public"."call_edge_function"("p_function_name" "text", "p_body" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."call_edge_function"("p_function_name" "text", "p_body" "jsonb") IS 'Helper per chiamare Edge Functions via pg_net. Richiede app.settings.supabase_url e app.settings.service_role_key.';



CREATE OR REPLACE FUNCTION "public"."can_access_finance"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    return exists (
        select 1 from public.profiles
        where id = auth.uid()
        and role in ('admin', 'finance')
    );
end;
$$;


ALTER FUNCTION "public"."can_access_finance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_send_re_engagement"("p_client_id" "uuid", "p_days" integer DEFAULT 7) RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE
    v_last_re_engagement timestamp with time zone;
    v_has_upcoming_booking boolean;
    v_days_since_last_booking integer;
BEGIN
    -- Check if this specific re-engagement (4d or 7d) was already sent
    SELECT sent_at INTO v_last_re_engagement
    FROM "public"."notification_logs"
    WHERE client_id = p_client_id
      AND category = 're_engagement'
      AND (data->>'days')::int = p_days
      AND sent_at > NOW() - INTERVAL '30 days'
    ORDER BY sent_at DESC
    LIMIT 1;

    IF v_last_re_engagement IS NOT NULL THEN
        RETURN false; -- Already sent this type recently
    END IF;

    -- Check if user has upcoming booking (don't send if they're already coming)
    SELECT EXISTS (
        SELECT 1 FROM "public"."bookings" b
        JOIN "public"."lessons" l ON b.lesson_id = l.id
        WHERE b.client_id = p_client_id
          AND b.status = 'booked'
          AND l.starts_at > NOW()
    ) INTO v_has_upcoming_booking;

    IF v_has_upcoming_booking THEN
        RETURN false; -- Has upcoming booking, no need to re-engage
    END IF;

    -- Check days since last booking
    SELECT EXTRACT(DAY FROM NOW() - MAX(l.starts_at))::integer
    INTO v_days_since_last_booking
    FROM "public"."bookings" b
    JOIN "public"."lessons" l ON b.lesson_id = l.id
    WHERE b.client_id = p_client_id
      AND b.status IN ('booked', 'attended')
      AND l.starts_at < NOW();

    -- Can send if days since last booking matches the threshold
    RETURN v_days_since_last_booking IS NOT NULL AND v_days_since_last_booking >= p_days;
END;
$$;


ALTER FUNCTION "public"."can_send_re_engagement"("p_client_id" "uuid", "p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") IS 'Cancels a booking. Removed dangerous Strategy 3 (random subscription lookup). Tracks restore for all subscriptions including unlimited.';



CREATE OR REPLACE FUNCTION "public"."cancel_event_booking"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_my_client_id uuid;
  v_booking_user_id uuid;
  v_booking_client_id uuid;
  v_status booking_status;
  v_event_starts_at timestamptz;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();

  -- Recupera booking con lock
  SELECT user_id, client_id, status
  INTO v_booking_user_id, v_booking_client_id, v_status
  FROM public.event_bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  END IF;

  -- Verifica ownership
  -- client_id è la fonte di verità: se l'utente ha un client_id, verificare solo quello
  -- Altrimenti verificare user_id
  IF NOT (
    public.is_staff() 
    OR (
      -- Se l'utente ha un client_id, verificare solo client_id (fonte di verità)
      (v_my_client_id IS NOT NULL AND v_booking_client_id = v_my_client_id)
      OR
      -- Se l'utente non ha client_id, verificare user_id
      (v_my_client_id IS NULL AND v_booking_user_id = v_user_id AND v_booking_client_id IS NULL)
    )
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'UNAUTHORIZED');
  END IF;

  -- Verifica che non sia già cancellato
  IF v_status = 'canceled' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_CANCELED');
  END IF;

  -- Verifica che non sia già concluso
  IF v_status IN ('attended', 'no_show') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CANNOT_CANCEL_CONCLUDED');
  END IF;

  -- Recupera starts_at dell'evento per verifiche future (se necessario)
  SELECT starts_at INTO v_event_starts_at
  FROM public.events
  WHERE id = (SELECT event_id FROM public.event_bookings WHERE id = p_booking_id);

  -- Aggiorna status a canceled
  UPDATE public.event_bookings
  SET status = 'canceled'::booking_status
  WHERE id = p_booking_id;

  RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED');
END;
$$;


ALTER FUNCTION "public"."cancel_event_booking"("p_booking_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cancel_event_booking"("p_booking_id" "uuid") IS 'Cancella una prenotazione evento per l''utente autenticato. Non permette cancellazione di prenotazioni già concluse (attended/no_show). client_id è la fonte di verità per la verifica ownership: se l''utente ha un client_id, viene verificato solo quello.';



CREATE OR REPLACE FUNCTION "public"."check_milestone_on_attended"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_attended_count integer;
    v_milestones integer[] := ARRAY[10, 25, 50, 100];
    v_milestone integer;
BEGIN
    -- Only trigger when status changes to 'attended'
    IF NEW.status = 'attended' AND (OLD.status IS NULL OR OLD.status != 'attended') THEN
        -- Get attended count for this client
        v_attended_count := "public"."count_attended_lessons"(NEW.client_id);

        -- Check for first lesson
        IF v_attended_count = 1 THEN
            PERFORM "public"."queue_first_lesson"(NEW.client_id);
        END IF;

        -- Check for milestones
        FOREACH v_milestone IN ARRAY v_milestones LOOP
            IF v_attended_count = v_milestone THEN
                PERFORM "public"."queue_milestone"(NEW.client_id, v_milestone);
                EXIT; -- Only one milestone at a time
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_milestone_on_attended"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."client_has_active_push_tokens"("p_client_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM "public"."device_tokens"
        WHERE "client_id" = p_client_id AND "is_active" = true
    );
END;
$$;


ALTER FUNCTION "public"."client_has_active_push_tokens"("p_client_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."count_attended_lessons"("p_client_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
    SELECT COALESCE(COUNT(*)::integer, 0)
    FROM "public"."bookings"
    WHERE client_id = p_client_id AND status = 'attended';
$$;


ALTER FUNCTION "public"."count_attended_lessons"("p_client_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "full_name" "text",
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "deleted_at" timestamp with time zone,
    "phone" "text",
    "notes" "text",
    "accepted_terms_at" timestamp with time zone,
    "accepted_privacy_at" timestamp with time zone,
    "role" "public"."user_role" DEFAULT 'user'::"public"."user_role" NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."profiles"."deleted_at" IS 'Soft delete: timestamp di archiviazione. NULL = record attivo. I record soft-deleted non vengono mostrati nelle UI standard ma sono preservati per audit.';



COMMENT ON COLUMN "public"."profiles"."role" IS 'Ruolo dell''utente: user (cliente), operator (staff), admin (amministratore)';



CREATE OR REPLACE FUNCTION "public"."create_user_profile"("user_id" "uuid", "full_name" "text", "phone" "text" DEFAULT NULL::"text", "role" "public"."user_role" DEFAULT 'user'::"public"."user_role") RETURNS "public"."profiles"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  new_profile profiles;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() 
    AND role IN ('operator', 'admin')
  ) THEN
    RAISE EXCEPTION 'Solo operatori e amministratori possono creare profili utente';
  END IF;

  -- Use UPSERT: insert or update if already exists (from trigger)
  INSERT INTO profiles (id, full_name, email, phone, role)
  VALUES (user_id, full_name, (SELECT email FROM auth.users WHERE id = user_id), phone, role)
  ON CONFLICT (id) DO UPDATE
  SET
    full_name = excluded.full_name,
    email = excluded.email,
    phone = excluded.phone,
    role = excluded.role
  RETURNING * INTO new_profile;

  RETURN new_profile;
END;
$$;


ALTER FUNCTION "public"."create_user_profile"("user_id" "uuid", "full_name" "text", "phone" "text", "role" "public"."user_role") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cron_execute_scheduled_campaigns"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'execute-scheduled-campaigns',
        '{}'::jsonb
    );
END;
$$;


ALTER FUNCTION "public"."cron_execute_scheduled_campaigns"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_execute_scheduled_campaigns"() IS 'Wrapper per cron job che esegue le campagne marketing schedulate via Edge Function.';



CREATE OR REPLACE FUNCTION "public"."cron_fetch_social_analytics"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'meta-fetch-analytics',
        '{}'::jsonb
    );
END;
$$;


ALTER FUNCTION "public"."cron_fetch_social_analytics"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_fetch_social_analytics"() IS 'Wrapper per cron job che aggiorna le analytics social via Edge Function.';



CREATE OR REPLACE FUNCTION "public"."cron_process_notification_queue"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'process-notification-queue',
        '{}'::jsonb
    );
END;
$$;


ALTER FUNCTION "public"."cron_process_notification_queue"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_process_notification_queue"() IS 'Wrapper per cron job che processa la coda notifiche via Edge Function.';



CREATE OR REPLACE FUNCTION "public"."cron_queue_birthday"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Chiamata diretta alla RPC invece di passare per Edge Function
    PERFORM "public"."queue_birthday"();
END;
$$;


ALTER FUNCTION "public"."cron_queue_birthday"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_queue_birthday"() IS 'Wrapper cron: accoda auguri compleanno chiamando direttamente la RPC.';



CREATE OR REPLACE FUNCTION "public"."cron_queue_entries_low"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Chiamata diretta alla RPC invece di passare per Edge Function
    PERFORM "public"."queue_entries_low"();
END;
$$;


ALTER FUNCTION "public"."cron_queue_entries_low"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_queue_entries_low"() IS 'Wrapper cron: accoda notifiche ingressi bassi chiamando direttamente la RPC.';



CREATE OR REPLACE FUNCTION "public"."cron_queue_journal_reminder"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    PERFORM "public"."queue_journal_reminder"();
END;
$$;


ALTER FUNCTION "public"."cron_queue_journal_reminder"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_queue_journal_reminder"() IS 'Wrapper cron: accoda promemoria diario chiamando direttamente la RPC.';



CREATE OR REPLACE FUNCTION "public"."cron_queue_lesson_reminders"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Chiamata diretta alla RPC invece di passare per Edge Function
    PERFORM "public"."queue_lesson_reminders"();
END;
$$;


ALTER FUNCTION "public"."cron_queue_lesson_reminders"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_queue_lesson_reminders"() IS 'Wrapper cron: accoda promemoria lezioni chiamando direttamente la RPC.';



CREATE OR REPLACE FUNCTION "public"."cron_queue_practice_reminder"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    PERFORM "public"."queue_practice_reminder"();
END;
$$;


ALTER FUNCTION "public"."cron_queue_practice_reminder"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_queue_practice_reminder"() IS 'Wrapper cron: accoda promemoria pratica chiamando direttamente la RPC.';



CREATE OR REPLACE FUNCTION "public"."cron_queue_practice_resume"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    PERFORM "public"."queue_practice_resume"();
END;
$$;


ALTER FUNCTION "public"."cron_queue_practice_resume"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_queue_practice_resume"() IS 'Wrapper cron: accoda promemoria ripresa pratica chiamando direttamente la RPC.';



CREATE OR REPLACE FUNCTION "public"."cron_queue_re_engagement"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Chiamata diretta alla RPC invece di passare per Edge Function
    PERFORM "public"."queue_re_engagement"();
END;
$$;


ALTER FUNCTION "public"."cron_queue_re_engagement"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_queue_re_engagement"() IS 'Wrapper cron: accoda notifiche re-engagement chiamando direttamente la RPC.';



CREATE OR REPLACE FUNCTION "public"."cron_queue_subscription_expiry"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Chiamata diretta alla RPC invece di passare per Edge Function
    PERFORM "public"."queue_subscription_expiry"();
END;
$$;


ALTER FUNCTION "public"."cron_queue_subscription_expiry"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_queue_subscription_expiry"() IS 'Wrapper cron: accoda notifiche scadenza abbonamento chiamando direttamente la RPC.';



CREATE OR REPLACE FUNCTION "public"."cron_update_subscription_statuses"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_result record;
BEGIN
    SELECT * INTO v_result FROM update_expired_subscription_statuses();

    -- Log solo se ci sono stati aggiornamenti
    IF v_result.updated_count > 0 THEN
        RAISE NOTICE 'Subscription status update: % total (active->expired: %, active->completed: %, completed->expired: %)',
            v_result.updated_count,
            v_result.active_to_expired,
            v_result.active_to_completed,
            v_result.completed_to_expired;
    END IF;
END;
$$;


ALTER FUNCTION "public"."cron_update_subscription_statuses"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cron_update_subscription_statuses"() IS 'Wrapper per cron job che aggiorna gli stati degli abbonamenti. Eseguire giornalmente.';



CREATE OR REPLACE FUNCTION "public"."delete_campaign"("campaign_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Verify user is staff
  IF NOT is_staff() THEN
    RAISE EXCEPTION 'Permission denied: user is not staff';
  END IF;

  -- Soft delete the campaign
  UPDATE campaigns
  SET deleted_at = now()
  WHERE id = campaign_id;
END;
$$;


ALTER FUNCTION "public"."delete_campaign"("campaign_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_subscription_canceled_on_deleted_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Se deleted_at viene impostato (passa da NULL a NOT NULL), imposta status = "canceled"
  -- Gestisce sia INSERT (OLD è NULL) che UPDATE (OLD esiste)
  IF NEW.deleted_at IS NOT NULL THEN
    -- Per INSERT: OLD è NULL, quindi se NEW.deleted_at IS NOT NULL, imposta canceled
    -- Per UPDATE: se OLD.deleted_at era NULL e NEW.deleted_at è NOT NULL, imposta canceled
    IF OLD IS NULL OR OLD.deleted_at IS NULL THEN
      NEW.status := 'canceled'::subscription_status;
    END IF;
  END IF;
  
  -- Se deleted_at viene resettato a NULL (non dovrebbe succedere, ma per sicurezza)
  -- non modifichiamo lo status (potrebbe essere stato impostato manualmente)
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."ensure_subscription_canceled_on_deleted_at"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."ensure_subscription_canceled_on_deleted_at"() IS 'Trigger function che garantisce che quando deleted_at viene impostato su subscriptions, lo status venga automaticamente impostato a "canceled". Questo mantiene la consistenza dei dati: un abbonamento cancellato (deleted_at IS NOT NULL) deve sempre avere status = "canceled".';



CREATE OR REPLACE FUNCTION "public"."fix_missing_cancel_restore_entries"() RETURNS TABLE("booking_id" "uuid", "subscription_id" "uuid", "restored" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_booking_record RECORD;
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_total_entries integer;
  v_restore_exists boolean;
BEGIN
  -- Trova tutte le prenotazioni cancellate che hanno un usage con delta = -1
  -- ma NON hanno un usage con delta = +1
  FOR v_booking_record IN
    SELECT DISTINCT
      b.id as booking_id,
      su.subscription_id
    FROM bookings b
    INNER JOIN subscription_usages su ON su.booking_id = b.id
    WHERE b.status = 'canceled'
      AND su.delta = -1
      AND NOT EXISTS (
        SELECT 1
        FROM subscription_usages su2
        WHERE su2.booking_id = b.id
          AND su2.delta = +1
      )
  LOOP
    -- Verifica che la subscription esista e non sia soft-deleted
    SELECT *
    INTO v_sub
    FROM subscriptions
    WHERE id = v_booking_record.subscription_id
      AND deleted_at IS NULL;

    -- Se la subscription esiste, verifica il piano e crea il record di ripristino
    IF FOUND THEN
      SELECT *
      INTO v_plan
      FROM plans
      WHERE id = v_sub.plan_id;

      -- Verifica che il piano non sia soft-deleted
      IF v_plan.deleted_at IS NULL THEN
        v_total_entries := coalesce(v_sub.custom_entries, v_plan.entries);

        -- Solo se la subscription ha ingressi limitati (non unlimited)
        IF v_total_entries IS NOT NULL THEN
          -- Verifica che non esista già un record di ripristino
          SELECT EXISTS(
            SELECT 1
            FROM subscription_usages
            WHERE booking_id = v_booking_record.booking_id
              AND delta = +1
          ) INTO v_restore_exists;

          -- Crea il record di ripristino se non esiste
          IF NOT v_restore_exists THEN
            INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
            VALUES (v_booking_record.subscription_id, v_booking_record.booking_id, +1, 'CANCEL_RESTORE_FIX')
            ON CONFLICT DO NOTHING;

            -- Return the fixed record
            booking_id := v_booking_record.booking_id;
            subscription_id := v_booking_record.subscription_id;
            restored := true;
            RETURN NEXT;
          END IF;
        END IF;
      END IF;
    END IF;
  END LOOP;

  RETURN;
END;
$$;


ALTER FUNCTION "public"."fix_missing_cancel_restore_entries"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."fix_missing_cancel_restore_entries"() IS 'Trova e corregge tutte le prenotazioni cancellate che hanno un record subscription_usages con delta = -1 ma NON hanno un record con delta = +1. Crea i record mancanti per ripristinare gli ingressi.';



CREATE OR REPLACE FUNCTION "public"."generate_slug_from_discipline"("discipline_text" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $_$
BEGIN
  -- Converte in lowercase, rimuove caratteri speciali, sostituisce spazi con trattini
  -- Esempio: "Yoga Flow" -> "yoga-flow", "Pilates & Stretching" -> "pilates-stretching"
  RETURN lower(
    regexp_replace(
      regexp_replace(
        regexp_replace(discipline_text, '[^a-zA-Z0-9\s-]', '', 'g'), -- Rimuove caratteri speciali
        '\s+', '-', 'g' -- Sostituisce spazi multipli con un trattino
      ),
      '^-+|-+$', '', 'g' -- Rimuove trattini all'inizio e alla fine
    )
  );
END;
$_$;


ALTER FUNCTION "public"."generate_slug_from_discipline"("discipline_text" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."generate_slug_from_discipline"("discipline_text" "text") IS 'Genera uno slug URL-friendly da un testo discipline. Converte in lowercase, rimuove caratteri speciali e sostituisce spazi con trattini.';



CREATE OR REPLACE FUNCTION "public"."get_activity_booking_counts"() RETURNS TABLE("activity_id" "uuid", "booking_count" bigint)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT l.activity_id, COUNT(b.id) AS booking_count
  FROM lessons l
  JOIN bookings b ON b.lesson_id = l.id
  WHERE l.deleted_at IS NULL
  GROUP BY l.activity_id;
$$;


ALTER FUNCTION "public"."get_activity_booking_counts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_auth_email_stats"("p_user_id" "uuid") RETURNS TABLE("total_sent" bigint, "last_sent_at" timestamp with time zone, "last_status" "text", "failed_count" bigint, "bounced_count" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Only staff can access
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN QUERY
    SELECT
        COUNT(*)::bigint AS total_sent,
        MAX(ael.created_at) AS last_sent_at,
        (SELECT status FROM public.auth_email_logs WHERE user_id = p_user_id ORDER BY created_at DESC LIMIT 1) AS last_status,
        COUNT(*) FILTER (WHERE ael.status = 'failed')::bigint AS failed_count,
        COUNT(*) FILTER (WHERE ael.status = 'bounced')::bigint AS bounced_count
    FROM public.auth_email_logs ael
    WHERE ael.user_id = p_user_id;
END;
$$;


ALTER FUNCTION "public"."get_auth_email_stats"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_event_booking_count"("p_event_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT count(*)::integer
  FROM public.event_bookings
  WHERE event_id = p_event_id
    AND status IN ('booked', 'attended', 'no_show');
$$;


ALTER FUNCTION "public"."get_event_booking_count"("p_event_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_event_booking_count"("p_event_id" "uuid") IS 'Conta tutte le prenotazioni attive per un evento (booked, attended, no_show).
   Usa SECURITY DEFINER per bypassare le RLS e restituire il conteggio totale.';



CREATE OR REPLACE FUNCTION "public"."get_events_booking_counts"("p_event_ids" "uuid"[]) RETURNS TABLE("event_id" "uuid", "booked_count" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    eb.event_id,
    count(*)::integer AS booked_count
  FROM public.event_bookings eb
  WHERE eb.event_id = ANY(p_event_ids)
    AND eb.status IN ('booked', 'attended', 'no_show')
  GROUP BY eb.event_id;
$$;


ALTER FUNCTION "public"."get_events_booking_counts"("p_event_ids" "uuid"[]) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_events_booking_counts"("p_event_ids" "uuid"[]) IS 'Conta tutte le prenotazioni attive per più eventi in una singola query (batch).
   Usa SECURITY DEFINER per bypassare le RLS e restituire i conteggi totali.';



CREATE OR REPLACE FUNCTION "public"."get_financial_kpis"("p_month_start" "date" DEFAULT ("date_trunc"('month'::"text", (CURRENT_DATE)::timestamp with time zone))::"date", "p_month_end" "date" DEFAULT (("date_trunc"('month'::"text", (CURRENT_DATE)::timestamp with time zone) + '1 mon -1 days'::interval))::"date") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_result json;
    v_revenue_from_lessons numeric := 0;
    v_revenue_from_events numeric := 0;
    v_revenue_from_subscriptions numeric := 0;
    v_total_revenue numeric;
    v_expenses numeric;
    v_fixed_expenses numeric;
    v_variable_expenses numeric;
    v_margin numeric;
    v_payments_count integer;
begin
    -- Check access
    if not can_access_finance() then
        raise exception 'Access denied: finance role required';
    end if;

    -- Revenue from lessons: bookings with subscriptions
    -- Calculation: subscription custom_price_cents / custom_entries OR plan.price_cents / plan.entries
    select coalesce(sum(lesson_revenue), 0) into v_revenue_from_lessons
    from (
        select 
            case 
                when s.custom_price_cents is not null 
                     and s.custom_entries is not null 
                     and s.custom_entries > 0
                    then round(s.custom_price_cents::numeric / s.custom_entries)
                when p.price_cents is not null 
                     and p.entries is not null 
                     and p.entries > 0
                    then round(p.price_cents::numeric / p.entries)
                else 0
            end as lesson_revenue
        from bookings b
        join lessons l on l.id = b.lesson_id
        left join subscriptions s on s.id = b.subscription_id
        left join plans p on p.id = s.plan_id
        where b.status in ('booked', 'attended', 'no_show')
          and l.starts_at >= p_month_start::timestamp
          and l.starts_at < (p_month_end + interval '1 day')::timestamp
          and b.subscription_id is not null
    ) lesson_revenues;

    -- Revenue from events: event_bookings * event.price_cents
    select coalesce(sum(e.price_cents), 0) into v_revenue_from_events
    from event_bookings eb
    join events e on e.id = eb.event_id
    where eb.status in ('booked', 'attended', 'no_show')
      and e.starts_at >= p_month_start::timestamp
      and e.starts_at < (p_month_end + interval '1 day')::timestamp
      and e.price_cents is not null;

    -- Revenue from new subscriptions created in the month
    -- This counts the full subscription price when it's purchased/started
    select coalesce(sum(
        case 
            when s.custom_price_cents is not null then s.custom_price_cents
            when p.price_cents is not null then p.price_cents
            else 0
        end
    ), 0) into v_revenue_from_subscriptions
    from subscriptions s
    left join plans p on p.id = s.plan_id
    where s.started_at >= p_month_start::timestamp
      and s.started_at < (p_month_end + interval '1 day')::timestamp;

    v_total_revenue := v_revenue_from_lessons + v_revenue_from_events + v_revenue_from_subscriptions;

    -- Expenses (from expenses table - still manual)
    select coalesce(sum(amount_cents), 0) into v_expenses
    from expenses
    where expense_date >= p_month_start
      and expense_date <= p_month_end;

    select coalesce(sum(amount_cents), 0) into v_fixed_expenses
    from expenses
    where expense_date >= p_month_start
      and expense_date <= p_month_end
      and is_fixed = true;

    select coalesce(sum(amount_cents), 0) into v_variable_expenses
    from expenses
    where expense_date >= p_month_start
      and expense_date <= p_month_end
      and is_fixed = false;

    v_margin := v_total_revenue - v_expenses;

    -- Count of "payments" (bookings + events + subscriptions)
    select 
        (select count(distinct b.id) 
         from bookings b 
         join lessons l on l.id = b.lesson_id
         where b.status in ('booked', 'attended', 'no_show')
           and l.starts_at >= p_month_start::timestamp
           and l.starts_at < (p_month_end + interval '1 day')::timestamp
           and b.subscription_id is not null)
        +
        (select count(distinct eb.id) 
         from event_bookings eb 
         join events e on e.id = eb.event_id
         where eb.status in ('booked', 'attended', 'no_show')
           and e.starts_at >= p_month_start::timestamp
           and e.starts_at < (p_month_end + interval '1 day')::timestamp)
        +
        (select count(*) 
         from subscriptions 
         where started_at >= p_month_start::timestamp
           and started_at < (p_month_end + interval '1 day')::timestamp)
    into v_payments_count;

    select json_build_object(
        'revenue_cents', v_total_revenue::integer,
        'expenses_cents', v_expenses::integer,
        'fixed_expenses_cents', v_fixed_expenses::integer,
        'variable_expenses_cents', v_variable_expenses::integer,
        'margin_cents', v_margin::integer,
        'completed_payments_count', v_payments_count
    ) into v_result;

    return v_result;
end;
$$;


ALTER FUNCTION "public"."get_financial_kpis"("p_month_start" "date", "p_month_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_monthly_revenue_by_client"("p_month_start" "date", "p_month_end" "date") RETURNS TABLE("client_id" "uuid", "client_name" "text", "client_email" "text", "total_revenue_cents" bigint, "subscription_count" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id AS client_id,
    c.full_name AS client_name,
    c.email AS client_email,
    COALESCE(SUM(
      CASE
        -- Custom subscription: use custom price
        WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
        -- Subscription discount: use plan price with subscription discount
        WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
          THEN ROUND(p.price_cents * (1 - s.discount_percent / 100.0))
        -- Regular subscription: use plan price with plan discount
        ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
      END
    ), 0)::BIGINT AS total_revenue_cents,
    COUNT(DISTINCT s.id)::INTEGER AS subscription_count
  FROM clients c
  INNER JOIN subscriptions s ON s.client_id = c.id
    AND s.created_at >= p_month_start
    AND s.created_at < (p_month_end + INTERVAL '1 day')
    AND s.deleted_at IS NULL
  LEFT JOIN plans p ON s.plan_id = p.id
  WHERE c.deleted_at IS NULL
  GROUP BY c.id, c.full_name, c.email
  HAVING COALESCE(SUM(
    CASE
      WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
      WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
        THEN ROUND(p.price_cents * (1 - s.discount_percent / 100.0))
      ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
    END
  ), 0) > 0
  ORDER BY total_revenue_cents DESC;
END;
$$;


ALTER FUNCTION "public"."get_monthly_revenue_by_client"("p_month_start" "date", "p_month_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_monthly_revenue_by_plan"("p_month_start" "date", "p_month_end" "date") RETURNS TABLE("plan_id" "uuid", "plan_name" "text", "total_revenue_cents" bigint, "subscription_count" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS plan_id,
    COALESCE(s.custom_name, p.name) AS plan_name,
    COALESCE(SUM(
      CASE
        -- Custom subscription: use custom price
        WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
        -- Subscription discount: use plan price with subscription discount
        WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
          THEN ROUND(p.price_cents * (1 - s.discount_percent / 100.0))
        -- Regular subscription: use plan price with plan discount
        ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
      END
    ), 0)::BIGINT AS total_revenue_cents,
    COUNT(DISTINCT s.id)::INTEGER AS subscription_count
  FROM subscriptions s
  JOIN plans p ON s.plan_id = p.id
  WHERE s.created_at >= p_month_start
    AND s.created_at < (p_month_end + INTERVAL '1 day')
    AND s.deleted_at IS NULL
  GROUP BY p.id, COALESCE(s.custom_name, p.name)
  HAVING COALESCE(SUM(
    CASE
      WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
      WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
        THEN ROUND(p.price_cents * (1 - s.discount_percent / 100.0))
      ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
    END
  ), 0) > 0
  ORDER BY total_revenue_cents DESC;
END;
$$;


ALTER FUNCTION "public"."get_monthly_revenue_by_plan"("p_month_start" "date", "p_month_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_client_id"() RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT c.id
  FROM public.clients c
  WHERE c.profile_id = auth.uid()
  ORDER BY c.created_at DESC NULLS LAST
  LIMIT 1
$$;


ALTER FUNCTION "public"."get_my_client_id"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_my_client_id"() IS 'Returns the client_id linked to the current authenticated user via clients.profile_id.';



CREATE OR REPLACE FUNCTION "public"."get_notification_channel"("p_client_id" "uuid", "p_category" "public"."notification_category") RETURNS "public"."notification_channel"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE
    v_pref RECORD;
    v_has_push boolean;
BEGIN
    -- Get preferences
    SELECT push_enabled, email_enabled INTO v_pref
    FROM "public"."notification_preferences"
    WHERE client_id = p_client_id AND category = p_category;

    -- Default to all enabled if no preference set
    IF NOT FOUND THEN
        v_pref.push_enabled := true;
        v_pref.email_enabled := true;
    END IF;

    -- Check if user has active push tokens
    v_has_push := "public"."client_has_active_push_tokens"(p_client_id);

    -- Prefer push if enabled and available
    IF v_pref.push_enabled AND v_has_push THEN
        RETURN 'push'::"public"."notification_channel";
    ELSIF v_pref.email_enabled THEN
        RETURN 'email'::"public"."notification_channel";
    ELSE
        -- Both disabled, return null (will skip notification)
        RETURN NULL;
    END IF;
END;
$$;


ALTER FUNCTION "public"."get_notification_channel"("p_client_id" "uuid", "p_category" "public"."notification_category") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_revenue_breakdown"("p_month_start" "date" DEFAULT ("date_trunc"('month'::"text", (CURRENT_DATE)::timestamp with time zone))::"date", "p_month_end" "date" DEFAULT (("date_trunc"('month'::"text", (CURRENT_DATE)::timestamp with time zone) + '1 mon -1 days'::interval))::"date") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_result json;
begin
    -- Check access
    if not can_access_finance() then
        raise exception 'Access denied: finance role required';
    end if;

    select json_build_object(
        'by_lesson', coalesce(
            (select json_agg(json_build_object(
                'lesson_id', lesson_id,
                'activity_name', activity_name,
                'total_cents', total_cents,
                'count', booking_count
            ))
            from (
                select 
                    l.id as lesson_id,
                    a.name as activity_name,
                    sum(case 
                        when s.custom_price_cents is not null 
                             and s.custom_entries is not null 
                             and s.custom_entries > 0
                            then round(s.custom_price_cents::numeric / s.custom_entries)
                        when p.price_cents is not null 
                             and p.entries is not null 
                             and p.entries > 0
                            then round(p.price_cents::numeric / p.entries)
                        else 0
                    end)::integer as total_cents,
                    count(b.id) as booking_count
                from bookings b
                join lessons l on l.id = b.lesson_id
                join activities a on a.id = l.activity_id
                left join subscriptions s on s.id = b.subscription_id
                left join plans p on p.id = s.plan_id
                where b.status in ('booked', 'attended', 'no_show')
                  and l.starts_at >= p_month_start::timestamp
                  and l.starts_at < (p_month_end + interval '1 day')::timestamp
                  and b.subscription_id is not null
                group by l.id, a.name
            ) lesson_revenue), '[]'::json),
        'by_event', coalesce(
            (select json_agg(json_build_object(
                'event_id', event_id,
                'event_name', event_name,
                'total_cents', total_cents,
                'count', booking_count
            ))
            from (
                select 
                    e.id as event_id,
                    e.name as event_name,
                    sum(e.price_cents)::integer as total_cents,
                    count(eb.id) as booking_count
                from event_bookings eb
                join events e on e.id = eb.event_id
                where eb.status in ('booked', 'attended', 'no_show')
                  and e.starts_at >= p_month_start::timestamp
                  and e.starts_at < (p_month_end + interval '1 day')::timestamp
                  and e.price_cents is not null
                group by e.id, e.name
            ) event_revenue), '[]'::json),
        'by_subscription', coalesce(
            (select json_agg(json_build_object(
                'subscription_id', subscription_id,
                'subscription_name', subscription_name,
                'total_cents', total_cents,
                'count', 1
            ))
            from (
                select 
                    s.id as subscription_id,
                    coalesce(s.custom_name, p.name, 'Abbonamento') as subscription_name,
                    case 
                        when s.custom_price_cents is not null then s.custom_price_cents
                        when p.price_cents is not null then p.price_cents
                        else 0
                    end as total_cents
                from subscriptions s
                left join plans p on p.id = s.plan_id
                where s.started_at >= p_month_start::timestamp
                  and s.started_at < (p_month_end + interval '1 day')::timestamp
            ) subscription_revenue), '[]'::json)
    ) into v_result;

    return v_result;
end;
$$;


ALTER FUNCTION "public"."get_revenue_breakdown"("p_month_start" "date", "p_month_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unread_notifications_count"() RETURNS integer
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE
    v_client_id uuid;
    v_unread_logs integer;
    v_unread_announcements integer;
BEGIN
    v_client_id := "public"."get_my_client_id"();
    IF v_client_id IS NULL THEN
        RETURN 0;
    END IF;

    -- Count unread notification logs (last 30 days)
    -- Exclude announcement category logs (they are shown from announcements table)
    SELECT COUNT(*) INTO v_unread_logs
    FROM "public"."notification_logs" nl
    WHERE nl.client_id = v_client_id
      AND nl.sent_at > NOW() - INTERVAL '30 days'
      AND nl.category != 'announcement'
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_reads" nr
          WHERE nr.notification_log_id = nl.id
            AND nr.client_id = v_client_id
      );

    -- Count unread active announcements
    -- IMPORTANT: Filter test announcements - show only non-test OR test for this specific client
    SELECT COUNT(*) INTO v_unread_announcements
    FROM "public"."announcements" a
    WHERE a.is_active = true
      AND a.starts_at <= NOW()
      AND (a.ends_at IS NULL OR a.ends_at > NOW())
      AND (a.is_test = false OR a.test_client_id = v_client_id)
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_reads" nr
          WHERE nr.announcement_id = a.id
            AND nr.client_id = v_client_id
      );

    RETURN v_unread_logs + v_unread_announcements;
END;
$$;


ALTER FUNCTION "public"."get_unread_notifications_count"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_unread_notifications_count"() IS 'Conta notifiche non lette (logs ultimi 30gg esclusi announcement + annunci attivi). Per badge UI.';



CREATE OR REPLACE FUNCTION "public"."handle_individual_lesson_update"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
$$;


ALTER FUNCTION "public"."handle_individual_lesson_update"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."handle_individual_lesson_update"() IS 'Keeps bookings in sync for individual lessons. Tracks usage for all subscriptions including unlimited.';



CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client clients%rowtype;
  v_full_name text;
BEGIN
  -- Cerca se esiste un client con la stessa email
  SELECT * INTO v_client
  FROM clients
  WHERE email = new.email
    AND deleted_at IS NULL
  LIMIT 1;

  -- Se esiste un client con la stessa email, sincronizza i dati
  IF FOUND THEN
    -- Inserisci il profilo con i dati dal client
    INSERT INTO public.profiles (
      id, 
      email, 
      role,
      full_name,
      phone,
      notes
    )
    VALUES (
      new.id,
      new.email,
      'user'::user_role,
      v_client.full_name,
      v_client.phone,
      v_client.notes
    );

    -- Aggiorna il client con il profile_id per collegarli
    UPDATE clients
    SET profile_id = new.id
    WHERE id = v_client.id;
  ELSE
    -- Se non esiste un client, crea sia il profilo che il client
    -- Estrai il nome completo dai metadati se disponibile
    v_full_name := COALESCE(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      split_part(new.email, '@', 1),  -- Fallback: parte prima della @ nell'email
      'Utente'  -- Ultimo fallback
    );

    -- Crea il profilo minimale
    INSERT INTO public.profiles (id, email, role)
    VALUES (
      new.id,
      new.email,
      'user'::user_role
    );

    -- Crea un nuovo client collegato al profilo
    INSERT INTO public.clients (
      profile_id,
      email,
      full_name,
      phone,
      is_active
    )
    VALUES (
      new.id,
      new.email,
      v_full_name,
      new.raw_user_meta_data->>'phone',  -- Opzionale, può essere NULL
      true
    );
  END IF;

  RETURN new;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."handle_new_user"() IS 'Crea automaticamente un profilo quando viene creato un nuovo utente Auth. Se esiste un client con la stessa email, sincronizza i dati e collega il client al profilo. Se non esiste un client, crea automaticamente sia il profilo che il client per permettere all''utente di fare prenotazioni.';



CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_role user_role;
begin
  -- Se non c'è un utente autenticato, ritorna false
  if auth.uid() is null then
    return false;
  end if;

  -- Recupera il ruolo dell'utente
  select role into v_role
  from profiles
  where id = auth.uid();

  -- Ritorna true solo se è admin
  return v_role = 'admin';
end;
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_admin"() IS 'Verifica se l''utente corrente è admin';



CREATE OR REPLACE FUNCTION "public"."is_finance"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    return exists (
        select 1 from public.profiles
        where id = auth.uid()
        and role = 'finance'
    );
end;
$$;


ALTER FUNCTION "public"."is_finance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_staff"() RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_role user_role;
begin
  -- Se non c'è un utente autenticato, ritorna false
  if auth.uid() is null then
    return false;
  end if;

  -- Recupera il ruolo dell'utente
  select role into v_role
  from profiles
  where id = auth.uid();

  -- Ritorna true se è operator, admin o finance
  return v_role in ('operator', 'admin', 'finance');
end;
$$;


ALTER FUNCTION "public"."is_staff"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_staff"() IS 'Verifica se l''utente corrente è staff (operator, admin o finance)';



CREATE OR REPLACE FUNCTION "public"."link_client_to_profile_by_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  -- se non c'è email sul profilo, non fare nulla
  if new.email is null then
    return new;
  end if;

  -- collega (solo se esiste un client con quella email e non è già collegato)
  update public.clients c
  set profile_id = new.id,
      updated_at = now()
  where c.email = new.email
    and c.deleted_at is null
    and (c.profile_id is null or c.profile_id <> new.id);

  return new;
end;
$$;


ALTER FUNCTION "public"."link_client_to_profile_by_email"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_all_notifications_read"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_client_id uuid;
    v_count integer := 0;
    v_temp integer;
BEGIN
    v_client_id := "public"."get_my_client_id"();
    IF v_client_id IS NULL THEN
        RETURN 0;
    END IF;

    -- Mark all unread notification logs (excluding announcement category)
    INSERT INTO "public"."notification_reads" (client_id, notification_log_id)
    SELECT v_client_id, nl.id
    FROM "public"."notification_logs" nl
    WHERE nl.client_id = v_client_id
      AND nl.sent_at > NOW() - INTERVAL '30 days'
      AND nl.category != 'announcement'
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_reads" nr
          WHERE nr.notification_log_id = nl.id
            AND nr.client_id = v_client_id
      )
    ON CONFLICT (client_id, notification_log_id) DO NOTHING;

    GET DIAGNOSTICS v_temp = ROW_COUNT;
    v_count := v_count + v_temp;

    -- Mark all unread announcements (only those visible to this client)
    INSERT INTO "public"."notification_reads" (client_id, announcement_id)
    SELECT v_client_id, a.id
    FROM "public"."announcements" a
    WHERE a.is_active = true
      AND a.starts_at <= NOW()
      AND (a.ends_at IS NULL OR a.ends_at > NOW())
      AND (a.is_test = false OR a.test_client_id = v_client_id)
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_reads" nr
          WHERE nr.announcement_id = a.id
            AND nr.client_id = v_client_id
      )
    ON CONFLICT (client_id, announcement_id) DO NOTHING;

    GET DIAGNOSTICS v_temp = ROW_COUNT;
    v_count := v_count + v_temp;

    RETURN v_count;
END;
$$;


ALTER FUNCTION "public"."mark_all_notifications_read"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."mark_all_notifications_read"() IS 'Segna tutte le notifiche come lette. Ritorna il numero segnate.';



CREATE OR REPLACE FUNCTION "public"."mark_notification_read"("p_notification_log_id" "uuid" DEFAULT NULL::"uuid", "p_announcement_id" "uuid" DEFAULT NULL::"uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_client_id uuid;
BEGIN
    v_client_id := "public"."get_my_client_id"();
    IF v_client_id IS NULL THEN
        RETURN false;
    END IF;

    IF p_notification_log_id IS NOT NULL THEN
        INSERT INTO "public"."notification_reads" (client_id, notification_log_id)
        VALUES (v_client_id, p_notification_log_id)
        ON CONFLICT (client_id, notification_log_id) DO NOTHING;
    ELSIF p_announcement_id IS NOT NULL THEN
        INSERT INTO "public"."notification_reads" (client_id, announcement_id)
        VALUES (v_client_id, p_announcement_id)
        ON CONFLICT (client_id, announcement_id) DO NOTHING;
    ELSE
        RETURN false;
    END IF;

    RETURN true;
END;
$$;


ALTER FUNCTION "public"."mark_notification_read"("p_notification_log_id" "uuid", "p_announcement_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."mark_notification_read"("p_notification_log_id" "uuid", "p_announcement_id" "uuid") IS 'Segna una singola notifica come letta.';



CREATE OR REPLACE FUNCTION "public"."milestone_already_sent"("p_client_id" "uuid", "p_milestone" integer) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM "public"."notification_logs"
        WHERE client_id = p_client_id
          AND category = 'milestone'
          AND (data->>'milestone')::int = p_milestone
    );
$$;


ALTER FUNCTION "public"."milestone_already_sent"("p_client_id" "uuid", "p_milestone" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_new_announcement"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Invia push solo se:
    -- 1. L'announcement e' attivo
    -- 2. NON e' un annuncio periodico (quelli vengono gestiti dal cron)
    -- 3. NON viene da una marketing campaign (quella accoda già le notifiche)
    -- Se is_test=true, la notifica viene inviata solo al test_client_id
    IF NEW.is_active = true
       AND (NEW.is_recurring IS NULL OR NEW.is_recurring = false)
       AND NEW.marketing_campaign_id IS NULL  -- <-- NUOVO: skip se da campaign
    THEN
        PERFORM "public"."queue_announcement"(
            NEW.id,
            NEW.title,
            NEW.body,
            NEW.starts_at,
            COALESCE(NEW.is_test, false),
            NEW.test_client_id
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_new_announcement"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."notify_new_announcement"() IS 'Trigger function: accoda push quando viene creato un announcement attivo, NON periodico e NON da marketing campaign. Se is_test=true, notifica solo il test_client_id.';



CREATE OR REPLACE FUNCTION "public"."process_recurring_announcements"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_announcement record;
  v_now timestamptz := now();
  v_queued integer;
BEGIN
  -- Find recurring announcements that are due
  -- NOTA: announcements non ha deleted_at, usa is_active per il soft delete
  FOR v_announcement IN
    SELECT *
    FROM announcements
    WHERE is_recurring = true
      AND is_active = true
      AND next_occurrence_at IS NOT NULL
      AND next_occurrence_at <= v_now
      AND (ends_at IS NULL OR ends_at > v_now)
  LOOP
    -- Queue push notifications for all clients with active tokens
    -- DEDUPLICAZIONE: non creare se esiste già una notifica pending/sent
    -- per questo announcement nelle ultime 24 ore (per evitare spam)
    INSERT INTO notification_queue (
      client_id,
      category,
      channel,
      title,
      body,
      data,
      scheduled_for,
      status
    )
    SELECT
      c.id,
      'announcement',
      'push',
      v_announcement.title,
      v_announcement.body,
      jsonb_build_object(
        'announcementId', v_announcement.id,
        'category', v_announcement.category,
        'imageUrl', v_announcement.image_url,
        'linkUrl', v_announcement.link_url,
        'linkLabel', v_announcement.link_label
      ),
      v_now,
      'pending'
    FROM clients c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      AND EXISTS (
        SELECT 1 FROM device_tokens dt
        WHERE dt.client_id = c.id
          AND dt.is_active = true
      )
      -- Filtro test: se is_test=true, solo il test_client_id
      AND (
          COALESCE(v_announcement.is_test, false) = false
          OR (v_announcement.is_test = true AND c.id = v_announcement.test_client_id)
      )
      -- DEDUPLICAZIONE: non creare se esiste già una notifica per questo
      -- announcement+client nelle ultime 24 ore (evita spam da cron)
      AND NOT EXISTS (
          SELECT 1 FROM notification_queue nq
          WHERE nq.client_id = c.id
            AND nq.category = 'announcement'
            AND (nq.data->>'announcementId' = v_announcement.id::text
                 OR nq.data->>'announcement_id' = v_announcement.id::text)
            AND nq.created_at > v_now - interval '24 hours'
      );

    GET DIAGNOSTICS v_queued = ROW_COUNT;

    -- Solo se abbiamo accodato almeno una notifica, aggiorna last_sent_at
    IF v_queued > 0 THEN
      UPDATE announcements
      SET
        last_sent_at = v_now,
        next_occurrence_at = calculate_next_announcement_occurrence(
          recurrence_frequency,
          recurrence_day_of_week,
          recurrence_day_of_month,
          recurrence_time,
          v_now + interval '1 minute'
        )
      WHERE id = v_announcement.id;
    ELSE
      -- Nessuna notifica creata, aggiorna solo next_occurrence_at
      UPDATE announcements
      SET
        next_occurrence_at = calculate_next_announcement_occurrence(
          recurrence_frequency,
          recurrence_day_of_week,
          recurrence_day_of_month,
          recurrence_time,
          v_now + interval '1 minute'
        )
      WHERE id = v_announcement.id;
    END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."process_recurring_announcements"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."process_recurring_announcements"() IS 'Cron function: processa annunci periodici. Include deduplicazione (max 1 notifica per announcement/client ogni 24h).';



CREATE OR REPLACE FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count integer := 0;
BEGIN
    -- Accoda push SOLO ai clienti con token push attivo
    -- Nessun fallback email per gli announcements
    INSERT INTO "public"."notification_queue" (
        client_id,
        category,
        channel,
        title,
        body,
        data,
        scheduled_for
    )
    SELECT
        c.id,
        'announcement'::"public"."notification_category",
        'push'::"public"."notification_channel",
        p_title,
        p_body,
        jsonb_build_object('announcement_id', p_announcement_id),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      AND "public"."client_has_active_push_tokens"(c.id);

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;


ALTER FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text") IS 'Accoda push notification per un nuovo announcement a tutti i clienti con token attivo.';



CREATE OR REPLACE FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text", "p_scheduled_for" timestamp with time zone DEFAULT "now"()) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count integer := 0;
BEGIN
    -- Accoda push SOLO ai clienti con token push attivo
    -- Nessun fallback email per gli announcements
    INSERT INTO "public"."notification_queue" (
        client_id,
        category,
        channel,
        title,
        body,
        data,
        scheduled_for
    )
    SELECT
        c.id,
        'announcement'::"public"."notification_category",
        'push'::"public"."notification_channel",
        p_title,
        p_body,
        jsonb_build_object('announcement_id', p_announcement_id),
        p_scheduled_for
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      AND "public"."client_has_active_push_tokens"(c.id);

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;


ALTER FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text", "p_scheduled_for" timestamp with time zone) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text", "p_scheduled_for" timestamp with time zone) IS 'Accoda push notification per un nuovo announcement a tutti i clienti con token attivo. scheduled_for determina quando viene inviato.';



CREATE OR REPLACE FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text", "p_scheduled_for" timestamp with time zone DEFAULT "now"(), "p_is_test" boolean DEFAULT false, "p_test_client_id" "uuid" DEFAULT NULL::"uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count integer := 0;
BEGIN
    -- Accoda push ai clienti con token push attivo
    -- Se is_test=true, accoda SOLO al test_client_id
    -- DEDUPLICAZIONE: non creare se esiste già una notifica per questo announcement+client
    INSERT INTO "public"."notification_queue" (
        client_id,
        category,
        channel,
        title,
        body,
        data,
        scheduled_for
    )
    SELECT
        c.id,
        'announcement'::"public"."notification_category",
        'push'::"public"."notification_channel",
        p_title,
        p_body,
        jsonb_build_object('announcement_id', p_announcement_id),
        p_scheduled_for
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      AND "public"."client_has_active_push_tokens"(c.id)
      -- Filtro test: se is_test=true, solo il test_client_id
      AND (
          p_is_test = false
          OR (p_is_test = true AND c.id = p_test_client_id)
      )
      -- DEDUPLICAZIONE: escludi client che hanno già una notifica per questo announcement
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = c.id
            AND nq.category = 'announcement'
            AND nq.data->>'announcement_id' = p_announcement_id::text
            AND nq.status IN ('pending', 'sent')
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;


ALTER FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text", "p_scheduled_for" timestamp with time zone, "p_is_test" boolean, "p_test_client_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text", "p_scheduled_for" timestamp with time zone, "p_is_test" boolean, "p_test_client_id" "uuid") IS 'Accoda push notification per un nuovo announcement. Se is_test=true, accoda solo al test_client_id. Include deduplicazione per evitare notifiche duplicate.';



CREATE OR REPLACE FUNCTION "public"."queue_birthday"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count integer := 0;
    v_today date := CURRENT_DATE;
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        'birthday'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 'birthday'),
            'email'::"public"."notification_channel"
        ),
        'Buon compleanno, ' || COALESCE(SPLIT_PART(c.full_name, ' ', 1), '') || '!',
        'Il team di Studio Kalos ti augura un meraviglioso compleanno!',
        jsonb_build_object(
            'year', EXTRACT(YEAR FROM v_today),
            'client_name', c.full_name
        ),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      AND c.birthday IS NOT NULL
      -- Birthday matches today (month and day)
      AND EXTRACT(MONTH FROM c.birthday) = EXTRACT(MONTH FROM v_today)
      AND EXTRACT(DAY FROM c.birthday) = EXTRACT(DAY FROM v_today)
      -- Not already sent this year
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = c.id
            AND nl.category = 'birthday'
            AND (nl.data->>'year')::int = EXTRACT(YEAR FROM v_today)
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;


ALTER FUNCTION "public"."queue_birthday"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_birthday"() IS 'Accoda auguri compleanno. Chiamata giornalmente alle 9:00.';



CREATE OR REPLACE FUNCTION "public"."queue_entries_low"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count integer := 0;
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT DISTINCT ON (s.client_id)
        s.client_id,
        'entries_low'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(s.client_id, 'entries_low'),
            'push'::"public"."notification_channel"
        ),
        'Ti restano solo 2 ingressi',
        'Rinnova per continuare ad allenarti senza interruzioni.',
        jsonb_build_object(
            'subscription_id', s.id,
            'plan_name', COALESCE(s.custom_name, p.name),
            'entries_left', 2
        ),
        NOW()
    FROM "public"."subscriptions" s
    JOIN "public"."plans" p ON s.plan_id = p.id
    WHERE s.status = 'active'
      AND s.client_id IS NOT NULL
      -- Has entry-based plan
      AND COALESCE(s.custom_entries, p.entries) IS NOT NULL
      -- Calculate remaining entries = total - used
      AND (
          COALESCE(s.custom_entries, p.entries) -
          COALESCE((
              SELECT COALESCE(SUM(-su.delta), 0)
              FROM "public"."subscription_usages" su
              WHERE su.subscription_id = s.id
          ), 0)
      ) = 2
      -- Not already sent for this subscription
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = s.client_id
            AND nl.data->>'subscription_id' = s.id::text
            AND nl.category = 'entries_low'
      )
    ORDER BY s.client_id, s.expires_at;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;


ALTER FUNCTION "public"."queue_entries_low"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_entries_low"() IS 'Accoda notifica ingressi esauriti quando rimangono esattamente 2. Chiamata giornalmente.';



CREATE OR REPLACE FUNCTION "public"."queue_first_lesson"("p_client_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Check if already sent
    IF EXISTS (
        SELECT 1 FROM "public"."notification_logs"
        WHERE client_id = p_client_id AND category = 'first_lesson'
    ) THEN
        RETURN false;
    END IF;

    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    VALUES (
        p_client_id,
        'first_lesson'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(p_client_id, 'first_lesson'),
            'push'::"public"."notification_channel"
        ),
        'Complimenti per la tua prima lezione!',
        'Il benessere inizia cosi, un passo alla volta.',
        jsonb_build_object('first_lesson', true),
        NOW()
    );

    RETURN true;
END;
$$;


ALTER FUNCTION "public"."queue_first_lesson"("p_client_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_first_lesson"("p_client_id" "uuid") IS 'Accoda celebrazione prima lezione. Chiamata dal trigger su bookings.';



CREATE OR REPLACE FUNCTION "public"."queue_journal_reminder"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count integer := 0;
    v_now timestamp with time zone := NOW();
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        'journal_reminder'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 'journal_reminder'),
            'push'::"public"."notification_channel"
        ),
        'Come stai questa settimana? ✍️',
        'Prenditi un momento per scrivere nel tuo diario. Anche poche parole possono fare la differenza.',
        jsonb_build_object(
            'type', 'weekly_reminder',
            'screen', 'JournalList'
        ),
        v_now
    FROM "public"."clients" c
    WHERE c.is_active = true
      AND c.deleted_at IS NULL
      AND c.profile_id IS NOT NULL
      -- Ha token push attivi
      AND "public"."client_has_active_push_tokens"(c.id)
      -- Ha già usato il diario almeno una volta (non spam a chi non l'ha mai usato)
      AND EXISTS (
          SELECT 1 FROM "public"."journal_entries" je
          WHERE je.client_id = c.id
      )
      -- Non ha scritto negli ultimi 7 giorni
      AND NOT EXISTS (
          SELECT 1 FROM "public"."journal_entries" je
          WHERE je.client_id = c.id
            AND je.created_at > v_now - INTERVAL '7 days'
      )
      -- Non già accodato questa settimana
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = c.id
            AND nq.category = 'journal_reminder'
            AND nq.scheduled_for > v_now - INTERVAL '7 days'
      )
      -- Non già inviato questa settimana
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = c.id
            AND nl.category = 'journal_reminder'
            AND nl.sent_at > v_now - INTERVAL '7 days'
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object(
        'journal_reminders', v_count,
        'timestamp', v_now
    );
END;
$$;


ALTER FUNCTION "public"."queue_journal_reminder"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_journal_reminder"() IS 'Accoda promemoria settimanale diario per utenti che non scrivono da 7+ giorni. Solo per chi ha già usato il diario.';



CREATE OR REPLACE FUNCTION "public"."queue_lesson_reminders"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count_evening integer := 0;
    v_count_2h integer := 0;
    v_now timestamp with time zone := NOW();
    v_today_8pm timestamp with time zone;
    v_tomorrow date;
BEGIN
    -- Calculate today at 20:00 Rome time
    v_today_8pm := DATE_TRUNC('day', v_now AT TIME ZONE 'Europe/Rome') + INTERVAL '20 hours';
    v_today_8pm := v_today_8pm AT TIME ZONE 'Europe/Rome';
    v_tomorrow := (v_now AT TIME ZONE 'Europe/Rome')::date + 1;

    -- Evening reminder: lessons tomorrow, schedule for 20:00 today
    -- Only queue if it's before 20:00
    IF v_now < v_today_8pm THEN
        INSERT INTO "public"."notification_queue" (
            client_id, category, channel, title, body, data, scheduled_for
        )
        SELECT
            b.client_id,
            'lesson_reminder'::"public"."notification_category",
            COALESCE(
                "public"."get_notification_channel"(b.client_id, 'lesson_reminder'),
                'email'::"public"."notification_channel"
            ),
            'Domani alle ' || TO_CHAR(l.starts_at AT TIME ZONE 'Europe/Rome', 'HH24:MI') ||
                ': ' || a.name || ' con ' || COALESCE(o.name, 'lo staff'),
            'Preparati per la tua lezione! Ti aspettiamo in studio.',
            jsonb_build_object(
                'lesson_id', l.id,
                'booking_id', b.id,
                'type', 'evening',
                'activity', a.name,
                'operator', o.name,
                'starts_at', l.starts_at
            ),
            v_today_8pm
        FROM "public"."bookings" b
        JOIN "public"."lessons" l ON b.lesson_id = l.id
        JOIN "public"."activities" a ON l.activity_id = a.id
        LEFT JOIN "public"."operators" o ON l.operator_id = o.id
        WHERE b.status = 'booked'
          AND b.client_id IS NOT NULL
          AND (l.starts_at AT TIME ZONE 'Europe/Rome')::date = v_tomorrow
          -- Not already queued for this booking
          AND NOT EXISTS (
              SELECT 1 FROM "public"."notification_queue" nq
              WHERE nq.client_id = b.client_id
                AND nq.data->>'booking_id' = b.id::text
                AND nq.category = 'lesson_reminder'
                AND nq.data->>'type' = 'evening'
          )
          -- Not already sent for this booking
          AND NOT EXISTS (
              SELECT 1 FROM "public"."notification_logs" nl
              WHERE nl.client_id = b.client_id
                AND nl.data->>'booking_id' = b.id::text
                AND nl.category = 'lesson_reminder'
                AND nl.data->>'type' = 'evening'
          );

        GET DIAGNOSTICS v_count_evening = ROW_COUNT;
    END IF;

    -- 2h reminder: lessons starting in 2-3 hours from now
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        b.client_id,
        'lesson_reminder'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(b.client_id, 'lesson_reminder'),
            'push'::"public"."notification_channel"  -- Default to push for 2h reminder
        ),
        'La tua lezione inizia tra 2 ore',
        a.name || ' alle ' || TO_CHAR(l.starts_at AT TIME ZONE 'Europe/Rome', 'HH24:MI') ||
            ' - ci vediamo presto!',
        jsonb_build_object(
            'lesson_id', l.id,
            'booking_id', b.id,
            'type', '2h',
            'activity', a.name,
            'starts_at', l.starts_at
        ),
        l.starts_at - INTERVAL '2 hours'
    FROM "public"."bookings" b
    JOIN "public"."lessons" l ON b.lesson_id = l.id
    JOIN "public"."activities" a ON l.activity_id = a.id
    WHERE b.status = 'booked'
      AND b.client_id IS NOT NULL
      AND l.starts_at > v_now + INTERVAL '2 hours'
      AND l.starts_at <= v_now + INTERVAL '3 hours'
      -- Not already queued
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = b.client_id
            AND nq.data->>'booking_id' = b.id::text
            AND nq.category = 'lesson_reminder'
            AND nq.data->>'type' = '2h'
      )
      -- Not already sent
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = b.client_id
            AND nl.data->>'booking_id' = b.id::text
            AND nl.category = 'lesson_reminder'
            AND nl.data->>'type' = '2h'
      );

    GET DIAGNOSTICS v_count_2h = ROW_COUNT;

    RETURN json_build_object(
        'evening_reminders', v_count_evening,
        '2h_reminders', v_count_2h,
        'timestamp', v_now
    );
END;
$$;


ALTER FUNCTION "public"."queue_lesson_reminders"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_lesson_reminders"() IS 'Accoda promemoria lezioni: sera prima (20:00) e 2h prima. Chiamata ogni ora dal cron.';



CREATE OR REPLACE FUNCTION "public"."queue_milestone"("p_client_id" "uuid", "p_milestone" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Check if already sent
    IF "public"."milestone_already_sent"(p_client_id, p_milestone) THEN
        RETURN false;
    END IF;

    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    VALUES (
        p_client_id,
        'milestone'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(p_client_id, 'milestone'),
            'push'::"public"."notification_channel"
        ),
        p_milestone || ' lezioni completate!',
        'Stai costruendo un''abitudine fantastica. Continua cosi!',
        jsonb_build_object('milestone', p_milestone),
        NOW()
    );

    RETURN true;
END;
$$;


ALTER FUNCTION "public"."queue_milestone"("p_client_id" "uuid", "p_milestone" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_milestone"("p_client_id" "uuid", "p_milestone" integer) IS 'Accoda notifica traguardo. Chiamata dal trigger su bookings.';



CREATE OR REPLACE FUNCTION "public"."queue_new_event"("p_event_id" "uuid", "p_event_name" "text", "p_event_date" timestamp with time zone) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count integer := 0;
    v_title text;
BEGIN
    -- Costruisci il titolo che verrà usato per la deduplicazione
    v_title := 'Nuovo evento: ' || p_event_name;

    -- Accoda notifica nuovo evento a tutti i clienti attivi
    -- DEDUPLICAZIONE: non creare se esiste già una notifica con lo stesso TITOLO
    -- creata negli ultimi 60 secondi (per gestire creazione batch di eventi)
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        'new_event'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 'new_event'),
            'email'::"public"."notification_channel"
        ),
        v_title,
        TO_CHAR(p_event_date AT TIME ZONE 'Europe/Rome', 'DD/MM alle HH24:MI') ||
            ' - I posti sono limitati, iscriviti ora!',
        jsonb_build_object(
            'event_id', p_event_id,
            'event_name', p_event_name,
            'event_date', p_event_date
        ),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      -- DEDUPLICAZIONE: escludi client che hanno già una notifica con stesso titolo
      -- creata negli ultimi 60 secondi (batch creation window)
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = c.id
            AND nq.category = 'new_event'
            AND nq.title = v_title
            AND nq.created_at > NOW() - INTERVAL '60 seconds'
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;


ALTER FUNCTION "public"."queue_new_event"("p_event_id" "uuid", "p_event_name" "text", "p_event_date" timestamp with time zone) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_new_event"("p_event_id" "uuid", "p_event_name" "text", "p_event_date" timestamp with time zone) IS 'Accoda notifica nuovo evento a tutti i clienti attivi. Deduplicazione per titolo + finestra 60s per evitare spam quando si creano eventi con più date/orari.';



CREATE OR REPLACE FUNCTION "public"."queue_new_event"("p_event_id" "uuid", "p_event_name" "text", "p_event_date" timestamp with time zone, "p_send_push" boolean DEFAULT true, "p_send_email" boolean DEFAULT false) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_push_count integer := 0;
    v_email_count integer := 0;
    v_title text;
    v_body text;
    v_data jsonb;
BEGIN
    -- Se nessun canale selezionato, non fare nulla
    IF NOT p_send_push AND NOT p_send_email THEN
        RETURN json_build_object('queued_push', 0, 'queued_email', 0);
    END IF;

    v_title := 'Nuovo evento: ' || p_event_name;
    v_body := TO_CHAR(p_event_date AT TIME ZONE 'Europe/Rome', 'DD/MM alle HH24:MI') ||
              ' - I posti sono limitati, iscriviti ora!';
    v_data := jsonb_build_object(
        'event_id', p_event_id,
        'event_name', p_event_name,
        'event_date', p_event_date
    );

    -- Accoda notifiche PUSH (solo per clienti con token attivi)
    IF p_send_push THEN
        INSERT INTO "public"."notification_queue" (
            client_id, category, channel, title, body, data, scheduled_for
        )
        SELECT
            c.id,
            'new_event'::"public"."notification_category",
            'push'::"public"."notification_channel",
            v_title,
            v_body,
            v_data,
            NOW()
        FROM "public"."clients" c
        WHERE c.deleted_at IS NULL
          AND c.is_active = true
          AND "public"."client_has_active_push_tokens"(c.id)
          -- Deduplicazione: escludi client che hanno già una notifica push con stesso titolo
          AND NOT EXISTS (
              SELECT 1 FROM "public"."notification_queue" nq
              WHERE nq.client_id = c.id
                AND nq.category = 'new_event'
                AND nq.channel = 'push'
                AND nq.title = v_title
                AND nq.created_at > NOW() - INTERVAL '60 seconds'
          );

        GET DIAGNOSTICS v_push_count = ROW_COUNT;
    END IF;

    -- Accoda notifiche EMAIL (solo per clienti con email)
    IF p_send_email THEN
        INSERT INTO "public"."notification_queue" (
            client_id, category, channel, title, body, data, scheduled_for
        )
        SELECT
            c.id,
            'new_event'::"public"."notification_category",
            'email'::"public"."notification_channel",
            v_title,
            v_body,
            v_data,
            NOW()
        FROM "public"."clients" c
        WHERE c.deleted_at IS NULL
          AND c.is_active = true
          AND c.email IS NOT NULL
          AND c.email != ''
          AND COALESCE(c.email_bounced, false) = false
          -- Deduplicazione: escludi client che hanno già una notifica email con stesso titolo
          AND NOT EXISTS (
              SELECT 1 FROM "public"."notification_queue" nq
              WHERE nq.client_id = c.id
                AND nq.category = 'new_event'
                AND nq.channel = 'email'
                AND nq.title = v_title
                AND nq.created_at > NOW() - INTERVAL '60 seconds'
          );

        GET DIAGNOSTICS v_email_count = ROW_COUNT;
    END IF;

    RETURN json_build_object('queued_push', v_push_count, 'queued_email', v_email_count);
END;
$$;


ALTER FUNCTION "public"."queue_new_event"("p_event_id" "uuid", "p_event_name" "text", "p_event_date" timestamp with time zone, "p_send_push" boolean, "p_send_email" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_new_event"("p_event_id" "uuid", "p_event_name" "text", "p_event_date" timestamp with time zone, "p_send_push" boolean, "p_send_email" boolean) IS 'Accoda notifiche nuovo evento ai clienti attivi. Canali controllabili via p_send_push e p_send_email. Deduplicazione per titolo + canale + finestra 60s.';



CREATE OR REPLACE FUNCTION "public"."queue_practice_reminder"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count integer := 0;
    v_now timestamp with time zone := NOW();
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        'practice_reminder'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 'practice_reminder'),
            'push'::"public"."notification_channel"
        ),
        'Prenditi un momento per te 🧘',
        'Una breve pratica può fare la differenza. Trova quella giusta per oggi.',
        jsonb_build_object(
            'type', 'daily_reminder',
            'screen', 'PracticeLibrary'
        ),
        v_now
    FROM "public"."clients" c
    WHERE c.is_active = true
      AND c.deleted_at IS NULL
      AND c.profile_id IS NOT NULL
      -- Ha almeno un token push attivo (solo push per questo tipo)
      AND "public"."client_has_active_push_tokens"(c.id)
      -- Non ha praticato negli ultimi 2 giorni
      AND NOT EXISTS (
          SELECT 1 FROM "public"."practice_user_state" pus
          WHERE pus.client_id = c.id
            AND pus.last_accessed_at > v_now - INTERVAL '2 days'
      )
      -- Non già accodato oggi
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = c.id
            AND nq.category = 'practice_reminder'
            AND nq.scheduled_for::date = v_now::date
      )
      -- Non già inviato oggi
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = c.id
            AND nl.category = 'practice_reminder'
            AND nl.sent_at::date = v_now::date
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object(
        'practice_reminders', v_count,
        'timestamp', v_now
    );
END;
$$;


ALTER FUNCTION "public"."queue_practice_reminder"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_practice_reminder"() IS 'Accoda promemoria pratica giornaliero per utenti inattivi da 2+ giorni.';



CREATE OR REPLACE FUNCTION "public"."queue_practice_resume"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count integer := 0;
    v_now timestamp with time zone := NOW();
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT DISTINCT ON (pus.client_id)
        pus.client_id,
        'practice_resume'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(pus.client_id, 'practice_resume'),
            'push'::"public"."notification_channel"
        ),
        'Riprendi da dove eri rimast' || CASE WHEN true THEN 'o' END || ' 📖',
        'Hai una pratica in corso: ' || p.title || '. Continua il tuo percorso!',
        jsonb_build_object(
            'type', 'resume',
            'screen', 'PracticePlayer',
            'practice_id', p.id,
            'practice_title', p.title
        ),
        v_now
    FROM "public"."practice_user_state" pus
    JOIN "public"."practices" p ON pus.practice_id = p.id
    JOIN "public"."clients" c ON pus.client_id = c.id
    WHERE pus.status = 'started'
      AND pus.completed_at IS NULL
      -- Abbandonata da 3+ giorni
      AND pus.last_accessed_at < v_now - INTERVAL '3 days'
      -- Client attivo
      AND c.is_active = true
      AND c.deleted_at IS NULL
      -- Pratica ancora attiva
      AND p.is_active = true
      AND p.deleted_at IS NULL
      -- Ha token push attivi
      AND "public"."client_has_active_push_tokens"(pus.client_id)
      -- Non già accodato questa settimana
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = pus.client_id
            AND nq.category = 'practice_resume'
            AND nq.scheduled_for > v_now - INTERVAL '7 days'
      )
      -- Non già inviato questa settimana
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = pus.client_id
            AND nl.category = 'practice_resume'
            AND nl.sent_at > v_now - INTERVAL '7 days'
      )
    ORDER BY pus.client_id, pus.last_accessed_at DESC;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object(
        'practice_resume', v_count,
        'timestamp', v_now
    );
END;
$$;


ALTER FUNCTION "public"."queue_practice_resume"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_practice_resume"() IS 'Accoda promemoria per riprendere pratiche in corso abbandonate da 3+ giorni. Max 1 per settimana per utente.';



CREATE OR REPLACE FUNCTION "public"."queue_re_engagement"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count_4d integer := 0;
    v_count_7d integer := 0;
BEGIN
    -- 4 days re-engagement (push only)
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        're_engagement'::"public"."notification_category",
        'push'::"public"."notification_channel",
        'Ti aspettiamo!',
        'Ti va di riprendere? Ti aspettiamo in studio!',
        jsonb_build_object(
            'days', 4,
            'last_booking_date', (
                SELECT MAX(l.starts_at)
                FROM "public"."bookings" b
                JOIN "public"."lessons" l ON b.lesson_id = l.id
                WHERE b.client_id = c.id AND b.status IN ('booked', 'attended')
            )::text
        ),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      -- Has push token (required for this notification)
      AND "public"."client_has_active_push_tokens"(c.id)
      -- Passes anti-spam check for 4 days
      AND "public"."can_send_re_engagement"(c.id, 4);

    GET DIAGNOSTICS v_count_4d = ROW_COUNT;

    -- 7 days re-engagement (push + email)
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        're_engagement'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 're_engagement'),
            'email'::"public"."notification_channel"
        ),
        'Ci manchi!',
        'Riprendi da dove hai lasciato - scopri le lezioni della settimana!',
        jsonb_build_object(
            'days', 7,
            'last_booking_date', (
                SELECT MAX(l.starts_at)
                FROM "public"."bookings" b
                JOIN "public"."lessons" l ON b.lesson_id = l.id
                WHERE b.client_id = c.id AND b.status IN ('booked', 'attended')
            )::text
        ),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      -- Passes anti-spam check for 7 days
      AND "public"."can_send_re_engagement"(c.id, 7);

    GET DIAGNOSTICS v_count_7d = ROW_COUNT;

    RETURN json_build_object(
        '4_days', v_count_4d,
        '7_days', v_count_7d
    );
END;
$$;


ALTER FUNCTION "public"."queue_re_engagement"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_re_engagement"() IS 'Accoda re-engagement: 4gg (solo push) e 7gg (push+email). Anti-spam integrato.';



CREATE OR REPLACE FUNCTION "public"."queue_subscription_expiry"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count_21d integer := 0;
    v_count_7d integer := 0;
    v_count_2d integer := 0;
    v_today date := CURRENT_DATE;
BEGIN
    -- 21 days before expiry
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        s.client_id,
        'subscription_expiry'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(s.client_id, 'subscription_expiry'),
            'email'::"public"."notification_channel"
        ),
        'Il tuo abbonamento scade il ' || TO_CHAR(s.expires_at, 'DD/MM'),
        'Hai ancora 3 settimane per rinnovare e continuare il tuo percorso di benessere.',
        jsonb_build_object(
            'subscription_id', s.id,
            'plan_name', COALESCE(s.custom_name, p.name),
            'expires_at', s.expires_at,
            'days_left', 21
        ),
        NOW()
    FROM "public"."subscriptions" s
    JOIN "public"."plans" p ON s.plan_id = p.id
    WHERE s.status = 'active'
      AND s.client_id IS NOT NULL
      AND s.expires_at = v_today + 21
      -- Not already sent
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = s.client_id
            AND nl.data->>'subscription_id' = s.id::text
            AND nl.category = 'subscription_expiry'
            AND (nl.data->>'days_left')::int = 21
      );

    GET DIAGNOSTICS v_count_21d = ROW_COUNT;

    -- 7 days before expiry
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        s.client_id,
        'subscription_expiry'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(s.client_id, 'subscription_expiry'),
            'email'::"public"."notification_channel"
        ),
        'Il tuo abbonamento scade tra una settimana',
        'Rinnova ora per continuare il tuo percorso di benessere.',
        jsonb_build_object(
            'subscription_id', s.id,
            'plan_name', COALESCE(s.custom_name, p.name),
            'expires_at', s.expires_at,
            'days_left', 7
        ),
        NOW()
    FROM "public"."subscriptions" s
    JOIN "public"."plans" p ON s.plan_id = p.id
    WHERE s.status = 'active'
      AND s.client_id IS NOT NULL
      AND s.expires_at = v_today + 7
      -- Not already sent
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = s.client_id
            AND nl.data->>'subscription_id' = s.id::text
            AND nl.category = 'subscription_expiry'
            AND (nl.data->>'days_left')::int = 7
      );

    GET DIAGNOSTICS v_count_7d = ROW_COUNT;

    -- 2 days before expiry
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        s.client_id,
        'subscription_expiry'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(s.client_id, 'subscription_expiry'),
            'email'::"public"."notification_channel"
        ),
        'Ultimi 2 giorni del tuo abbonamento',
        'Non perdere l''accesso alle tue lezioni preferite!',
        jsonb_build_object(
            'subscription_id', s.id,
            'plan_name', COALESCE(s.custom_name, p.name),
            'expires_at', s.expires_at,
            'days_left', 2
        ),
        NOW()
    FROM "public"."subscriptions" s
    JOIN "public"."plans" p ON s.plan_id = p.id
    WHERE s.status = 'active'
      AND s.client_id IS NOT NULL
      AND s.expires_at = v_today + 2
      -- Not already sent
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = s.client_id
            AND nl.data->>'subscription_id' = s.id::text
            AND nl.category = 'subscription_expiry'
            AND (nl.data->>'days_left')::int = 2
      );

    GET DIAGNOSTICS v_count_2d = ROW_COUNT;

    RETURN json_build_object(
        '21_days', v_count_21d,
        '7_days', v_count_7d,
        '2_days', v_count_2d
    );
END;
$$;


ALTER FUNCTION "public"."queue_subscription_expiry"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."queue_subscription_expiry"() IS 'Accoda notifiche scadenza abbonamento: 21, 7 e 2 giorni prima. Chiamata giornalmente.';



CREATE OR REPLACE FUNCTION "public"."restore_subscription_entry_on_booking_cancel"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_subscription_id uuid;
  v_total_entries integer;
  v_plan_entries integer;
  v_custom_entries integer;
BEGIN
  -- Solo se status passa da 'booked' a 'canceled'
  IF OLD.status = 'booked' AND NEW.status = 'canceled' THEN
    
    -- Usa subscription_id dalla booking (più semplice e diretto)
    v_subscription_id := NEW.subscription_id;

    -- Se non c'è subscription_id sulla booking, prova a trovarlo da subscription_usages
    IF v_subscription_id IS NULL THEN
      SELECT su.subscription_id
      INTO v_subscription_id
      FROM subscription_usages su
      WHERE su.booking_id = NEW.id
        AND su.delta = -1
      ORDER BY su.created_at DESC
      LIMIT 1;
    END IF;

    -- Se abbiamo trovato una subscription, verifica se ha ingressi limitati
    IF v_subscription_id IS NOT NULL THEN
      SELECT 
        s.custom_entries,
        p.entries
      INTO 
        v_custom_entries,
        v_plan_entries
      FROM subscriptions s
      LEFT JOIN plans p ON p.id = s.plan_id
      WHERE s.id = v_subscription_id
        AND s.deleted_at IS NULL;

      -- Se la subscription esiste e non è soft-deleted
      IF FOUND THEN
        v_total_entries := COALESCE(v_custom_entries, v_plan_entries);

        -- Solo se ha ingressi limitati (non unlimited)
        IF v_total_entries IS NOT NULL THEN
          -- Verifica che non esista già un record di ripristino
          IF NOT EXISTS (
            SELECT 1
            FROM subscription_usages
            WHERE booking_id = NEW.id
              AND delta = +1
          ) THEN
            -- Crea il record di ripristino
            INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
            VALUES (v_subscription_id, NEW.id, +1, 'CANCEL_RESTORE')
            ON CONFLICT DO NOTHING;
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."restore_subscription_entry_on_booking_cancel"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."restore_subscription_entry_on_booking_cancel"() IS 'Trigger function che ripristina automaticamente gli ingressi quando una prenotazione viene cancellata. Usa solo client_id e subscription_id, nessun riferimento a user_id.';



CREATE OR REPLACE FUNCTION "public"."staff_book_event"("p_event_id" "uuid", "p_client_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_staff_id uuid := auth.uid();
  v_capacity integer;
  v_starts_at timestamptz;
  v_now timestamptz := now();
  v_booked_count integer;
  v_booking_id uuid;
  v_event_deleted_at timestamptz;
  v_client_deleted_at timestamptz;
  v_reactivate_booking_id uuid;
  v_client_profile_id uuid;
BEGIN
  -- Check if user is staff
  IF NOT public.is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'UNAUTHORIZED');
  END IF;

  -- Lock event row
  SELECT 
    capacity, 
    starts_at, 
    deleted_at
  INTO 
    v_capacity, 
    v_starts_at, 
    v_event_deleted_at
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_FOUND');
  END IF;

  -- Verifica soft delete evento
  IF v_event_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_FOUND');
  END IF;

  -- Verifica che l'evento sia attivo
  IF NOT EXISTS (
    SELECT 1 FROM public.events 
    WHERE id = p_event_id AND is_active = true
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_ACTIVE');
  END IF;

  -- Verifica che il cliente esista e non sia soft-deleted
  SELECT deleted_at, profile_id
  INTO v_client_deleted_at, v_client_profile_id
  FROM public.clients
  WHERE id = p_client_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  IF v_client_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Verifica che non sia già prenotato dal cliente (solo prenotazioni attive)
  -- Se il cliente ha un account, controlla sia client_id che user_id (profile_id)
  IF v_client_profile_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id
        AND (
          client_id = p_client_id OR
          user_id = v_client_profile_id
        )
        AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id
        AND client_id = p_client_id
        AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  END IF;

  -- Cerca se esiste una prenotazione cancellata da riattivare
  -- Se il cliente ha un account, controlla sia client_id che user_id (profile_id)
  IF v_client_profile_id IS NOT NULL THEN
    SELECT id
    INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND (
        client_id = p_client_id OR
        user_id = v_client_profile_id
      )
      AND status = 'canceled'
    FOR UPDATE
    LIMIT 1;
  ELSE
    SELECT id
    INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND client_id = p_client_id
      AND status = 'canceled'
    FOR UPDATE
    LIMIT 1;
  END IF;

  -- Verifica capacità (se impostata)
  -- Se stiamo riattivando, la capacità è già stata "liberata" quando è stata cancellata
  -- quindi non dobbiamo verificare di nuovo. Se creiamo una nuova prenotazione, verifichiamo.
  IF v_reactivate_booking_id IS NULL AND v_capacity IS NOT NULL THEN
    SELECT count(*) INTO v_booked_count
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND status IN ('booked', 'attended', 'no_show');

    IF v_booked_count >= v_capacity THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;
  END IF;

  -- Riattiva prenotazione esistente o crea nuova
  IF v_reactivate_booking_id IS NOT NULL THEN
    -- Riattiva prenotazione cancellata
    -- Mantiene il client_id o user_id originale dalla prenotazione cancellata
    UPDATE public.event_bookings
    SET status = 'booked',
        created_at = now()
    WHERE id = v_reactivate_booking_id;
    v_booking_id := v_reactivate_booking_id;
  ELSE
    -- Crea nuova prenotazione con client_id
    INSERT INTO public.event_bookings (event_id, user_id, client_id, status)
    VALUES (p_event_id, NULL, p_client_id, 'booked')
    RETURNING id INTO v_booking_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
END;
$$;


ALTER FUNCTION "public"."staff_book_event"("p_event_id" "uuid", "p_client_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."staff_book_event"("p_event_id" "uuid", "p_client_id" "uuid") IS 'Prenota un evento per un cliente CRM (staff only). Usa sempre client_id. Gestisce capacità e prevenzione doppia prenotazione. Riattiva prenotazioni cancellate invece di crearne di nuove.';



CREATE OR REPLACE FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
    -- For reactivation: clean up old usage records first
    IF v_reactivate_booking IS NOT NULL THEN
      -- Delete the cancel restore (+1) if exists
      DELETE FROM public.subscription_usages
      WHERE booking_id = v_reactivate_booking AND delta = +1;

      -- Delete the old booking usage (-1) - required for unique constraint
      -- and to ensure correct subscription_id
      DELETE FROM public.subscription_usages
      WHERE booking_id = v_reactivate_booking AND delta = -1;
    END IF;

    -- Always create new usage record with current subscription
    INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
    VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');
  END IF;

  RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED', 'booking_id', v_booking_id);
END;
$$;


ALTER FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid") IS 'Staff booking with race condition protection. Correctly handles reactivation with different subscription.';



CREATE OR REPLACE FUNCTION "public"."staff_cancel_booking"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."staff_cancel_booking"("p_booking_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."staff_cancel_booking"("p_booking_id" "uuid") IS 'Staff cancels a booking. Tracks restore for all subscriptions including unlimited.';



CREATE OR REPLACE FUNCTION "public"."staff_cancel_event_booking"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_staff_id uuid := auth.uid();
  v_status booking_status;
BEGIN
  -- Check if user is staff
  IF NOT public.is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'UNAUTHORIZED');
  END IF;

  -- Recupera booking con lock
  SELECT status
  INTO v_status
  FROM public.event_bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  END IF;

  -- Verifica che non sia già cancellato
  IF v_status = 'canceled' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_CANCELED');
  END IF;

  -- Staff può cancellare anche prenotazioni concluse (attended/no_show) se necessario

  -- Aggiorna status a canceled
  UPDATE public.event_bookings
  SET status = 'canceled'::booking_status
  WHERE id = p_booking_id;

  RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED');
END;
$$;


ALTER FUNCTION "public"."staff_cancel_event_booking"("p_booking_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."staff_cancel_event_booking"("p_booking_id" "uuid") IS 'Cancella una prenotazione evento (staff only). Permette cancellazione anche di prenotazioni concluse.';



CREATE OR REPLACE FUNCTION "public"."staff_get_user_email_status"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_email text;
  v_email_confirmed_at timestamptz;
BEGIN
  -- Verify caller is staff
  IF NOT is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'UNAUTHORIZED');
  END IF;

  -- Get email and confirmation status from auth.users
  SELECT email, email_confirmed_at
  INTO v_email, v_email_confirmed_at
  FROM auth.users
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'USER_NOT_FOUND');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'email', v_email,
    'email_confirmed_at', v_email_confirmed_at,
    'is_confirmed', v_email_confirmed_at IS NOT NULL
  );
END;
$$;


ALTER FUNCTION "public"."staff_get_user_email_status"("p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."staff_get_user_email_status"("p_user_id" "uuid") IS 'Returns email confirmation status for a user. Staff only.';



CREATE OR REPLACE FUNCTION "public"."staff_update_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_booking bookings%rowtype;
BEGIN
  -- Check if user is staff
  IF NOT is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
  END IF;

  -- Get booking
  SELECT *
  INTO v_booking
  FROM bookings
  WHERE id = p_booking_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  END IF;

  -- Validate status
  IF p_status NOT IN ('booked', 'attended', 'no_show', 'canceled') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_STATUS');
  END IF;

  -- Update booking status
  -- Se si sta cancellando (status = 'canceled'), il trigger gestirà il ripristino
  UPDATE bookings
  SET status = p_status
  WHERE id = p_booking_id;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'UPDATED',
    'booking_id', p_booking_id
  );
END;
$$;


ALTER FUNCTION "public"."staff_update_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."staff_update_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status") IS 'Aggiorna lo stato di una prenotazione. Se si cancella (status = canceled), il trigger ripristina automaticamente gli ingressi.';



CREATE OR REPLACE FUNCTION "public"."subscription_covers_activity"("p_subscription_id" "uuid", "p_activity_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
$$;


ALTER FUNCTION "public"."subscription_covers_activity"("p_subscription_id" "uuid", "p_activity_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."subscription_covers_activity"("p_subscription_id" "uuid", "p_activity_id" "uuid") IS 'Returns true if the subscription''s plan covers the given activity. A plan with no plan_activities rows is treated as universal (covers all activities), consistent with book_lesson/staff_book_lesson.';



CREATE OR REPLACE FUNCTION "public"."sync_profile_from_client"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Se il client ha un profile_id, sincronizza i dati al profilo
  IF NEW.profile_id IS NOT NULL THEN
    UPDATE public.profiles
    SET 
      full_name = NEW.full_name,
      phone = NEW.phone,
      notes = NEW.notes,
      email = COALESCE(NEW.email, profiles.email) -- Mantieni l'email del profilo se il client non ha email
    WHERE id = NEW.profile_id;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_profile_from_client"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."sync_profile_from_client"() IS 'Sincronizza i dati da clients a profiles quando viene creato o aggiornato un client con un profile_id.';



CREATE OR REPLACE FUNCTION "public"."update_activity_slug"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Aggiorna lo slug quando discipline viene inserito o modificato
  IF NEW.discipline IS NOT NULL AND NEW.discipline != '' THEN
    NEW.slug := public.generate_slug_from_discipline(NEW.discipline);
  ELSE
    NEW.slug := NULL;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_activity_slug"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_activity_slug"() IS 'Trigger function che aggiorna automaticamente lo slug quando discipline viene inserito o modificato.';



CREATE OR REPLACE FUNCTION "public"."update_announcement_next_occurrence"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.is_recurring = true AND NEW.recurrence_frequency IS NOT NULL THEN
    NEW.next_occurrence_at := calculate_next_announcement_occurrence(
      NEW.recurrence_frequency,
      NEW.recurrence_day_of_week,
      NEW.recurrence_day_of_month,
      NEW.recurrence_time,
      COALESCE(NEW.starts_at, now())
    );
  ELSE
    NEW.next_occurrence_at := NULL;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_announcement_next_occurrence"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_bug_reports_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW."updated_at" = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_bug_reports_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_expired_subscription_statuses"() RETURNS TABLE("updated_count" integer, "active_to_expired" integer, "active_to_completed" integer, "completed_to_expired" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_active_to_expired integer := 0;
    v_active_to_completed integer := 0;
    v_completed_to_expired integer := 0;
BEGIN
    -- Aggiorna abbonamenti "active" che sono scaduti -> "expired"
    -- (solo quelli con remaining_entries > 0 o illimitati)
    WITH usage_totals AS (
        SELECT
            subscription_id,
            COALESCE(SUM(delta), 0) AS delta_sum
        FROM subscription_usages
        GROUP BY subscription_id
    ),
    to_expire AS (
        SELECT s.id
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        LEFT JOIN usage_totals u ON u.subscription_id = s.id
        WHERE s.deleted_at IS NULL
          AND s.status = 'active'
          AND s.expires_at < CURRENT_DATE
          AND (
              -- Illimitato
              COALESCE(s.custom_entries, p.entries) IS NULL
              OR
              -- Ha ancora ingressi
              (COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)) > 0
          )
    )
    UPDATE subscriptions s
    SET status = 'expired'
    FROM to_expire te
    WHERE s.id = te.id;

    GET DIAGNOSTICS v_active_to_expired = ROW_COUNT;

    -- Aggiorna abbonamenti "active" che hanno esaurito gli ingressi -> "completed"
    WITH usage_totals AS (
        SELECT
            subscription_id,
            COALESCE(SUM(delta), 0) AS delta_sum
        FROM subscription_usages
        GROUP BY subscription_id
    ),
    to_complete AS (
        SELECT s.id
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        LEFT JOIN usage_totals u ON u.subscription_id = s.id
        WHERE s.deleted_at IS NULL
          AND s.status = 'active'
          AND COALESCE(s.custom_entries, p.entries) IS NOT NULL  -- Non illimitato
          AND (COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)) <= 0
    )
    UPDATE subscriptions s
    SET status = 'completed'
    FROM to_complete tc
    WHERE s.id = tc.id;

    GET DIAGNOSTICS v_active_to_completed = ROW_COUNT;

    -- Correggi abbonamenti "completed" che in realta hanno ancora ingressi -> "expired"
    -- (caso edge: errore di stato precedente)
    WITH usage_totals AS (
        SELECT
            subscription_id,
            COALESCE(SUM(delta), 0) AS delta_sum
        FROM subscription_usages
        GROUP BY subscription_id
    ),
    to_fix AS (
        SELECT s.id
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        LEFT JOIN usage_totals u ON u.subscription_id = s.id
        WHERE s.deleted_at IS NULL
          AND s.status = 'completed'
          AND s.expires_at < CURRENT_DATE
          AND (
              -- Illimitato
              COALESCE(s.custom_entries, p.entries) IS NULL
              OR
              -- Ha ancora ingressi
              (COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)) > 0
          )
    )
    UPDATE subscriptions s
    SET status = 'expired'
    FROM to_fix tf
    WHERE s.id = tf.id;

    GET DIAGNOSTICS v_completed_to_expired = ROW_COUNT;

    RETURN QUERY SELECT
        (v_active_to_expired + v_active_to_completed + v_completed_to_expired)::integer,
        v_active_to_expired,
        v_active_to_completed,
        v_completed_to_expired;
END;
$$;


ALTER FUNCTION "public"."update_expired_subscription_statuses"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_expired_subscription_statuses"() IS 'Aggiorna automaticamente lo stato degli abbonamenti in base a scadenza e ingressi rimanenti.
Chiamata giornalmente dal cron job. Ritorna il conteggio degli aggiornamenti effettuati.';



CREATE OR REPLACE FUNCTION "public"."update_subscription_status_on_usage"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_subscription subscriptions%ROWTYPE;
  v_plan plans%ROWTYPE;
  v_effective_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_new_status subscription_status;
BEGIN
  -- Recupera l'abbonamento
  SELECT * INTO v_subscription
  FROM subscriptions
  WHERE id = NEW.subscription_id;
  
  -- Se non trovato o già in stato finale, esci
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;
  
  -- Preserva stati finali (canceled non deve essere modificato)
  IF v_subscription.status = 'canceled' THEN
    RETURN NEW;
  END IF;
  
  -- Recupera il piano
  SELECT * INTO v_plan
  FROM plans
  WHERE id = v_subscription.plan_id;
  
  -- Calcola effective_entries
  v_effective_entries := COALESCE(v_subscription.custom_entries, v_plan.entries);
  
  -- Se l'abbonamento è illimitato, non fare nulla (rimane active o expired in base alla scadenza)
  IF v_effective_entries IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- Calcola posti usati (somma di tutti i delta)
  SELECT COALESCE(SUM(delta), 0) INTO v_used_entries
  FROM subscription_usages
  WHERE subscription_id = NEW.subscription_id;
  
  -- Calcola posti rimanenti
  v_remaining_entries := v_effective_entries + v_used_entries;
  
  -- Determina il nuovo stato
  IF v_remaining_entries <= 0 THEN
    -- Ingressi esauriti -> completed (indipendentemente dalla scadenza)
    v_new_status := 'completed';
  ELSIF v_subscription.expires_at < CURRENT_DATE THEN
    -- Ha ancora ingressi ma è scaduto -> expired
    v_new_status := 'expired';
  ELSE
    -- Ha ancora ingressi e non è scaduto -> active
    v_new_status := 'active';
  END IF;
  
  -- Aggiorna solo se lo stato è cambiato
  IF v_subscription.status != v_new_status THEN
    UPDATE subscriptions
    SET status = v_new_status
    WHERE id = NEW.subscription_id;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_subscription_status_on_usage"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_subscription_status_on_usage"() IS 'Trigger function che aggiorna automaticamente lo stato dell''abbonamento quando vengono
modificati i subscription_usages. Se gli ingressi sono esauriti (remaining_entries <= 0),
imposta lo stato a "completed". Preserva lo stato "canceled".';



CREATE OR REPLACE FUNCTION "public"."update_subscription_status_on_usage_after_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_subscription subscriptions%ROWTYPE;
  v_plan plans%ROWTYPE;
  v_effective_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_new_status subscription_status;
BEGIN
  -- Recupera l'abbonamento
  SELECT * INTO v_subscription
  FROM subscriptions
  WHERE id = OLD.subscription_id;
  
  -- Se non trovato o già in stato finale, esci
  IF NOT FOUND THEN
    RETURN OLD;
  END IF;
  
  -- Preserva stati finali (canceled non deve essere modificato)
  IF v_subscription.status = 'canceled' THEN
    RETURN OLD;
  END IF;
  
  -- Recupera il piano
  SELECT * INTO v_plan
  FROM plans
  WHERE id = v_subscription.plan_id;
  
  -- Calcola effective_entries
  v_effective_entries := COALESCE(v_subscription.custom_entries, v_plan.entries);
  
  -- Se l'abbonamento è illimitato, non fare nulla
  IF v_effective_entries IS NULL THEN
    RETURN OLD;
  END IF;
  
  -- Calcola posti usati (somma di tutti i delta)
  SELECT COALESCE(SUM(delta), 0) INTO v_used_entries
  FROM subscription_usages
  WHERE subscription_id = OLD.subscription_id;
  
  -- Calcola posti rimanenti
  v_remaining_entries := v_effective_entries + v_used_entries;
  
  -- Determina il nuovo stato
  IF v_remaining_entries <= 0 THEN
    v_new_status := 'completed';
  ELSIF v_subscription.expires_at < CURRENT_DATE THEN
    v_new_status := 'expired';
  ELSE
    v_new_status := 'active';
  END IF;
  
  -- Aggiorna solo se lo stato è cambiato
  IF v_subscription.status != v_new_status THEN
    UPDATE subscriptions
    SET status = v_new_status
    WHERE id = OLD.subscription_id;
  END IF;
  
  RETURN OLD;
END;
$$;


ALTER FUNCTION "public"."update_subscription_status_on_usage_after_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."activities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "discipline" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "deleted_at" timestamp with time zone,
    "color" "text",
    "duration_minutes" integer,
    "slug" "text",
    "landing_title" "text",
    "landing_subtitle" "text",
    "active_months" "jsonb",
    "target_audience" "jsonb",
    "program_objectives" "jsonb",
    "why_participate" "jsonb",
    "journey_structure" "jsonb",
    "image_url" "text",
    "is_active" boolean DEFAULT true,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "icon_name" "text"
);


ALTER TABLE "public"."activities" OWNER TO "postgres";


COMMENT ON COLUMN "public"."activities"."deleted_at" IS 'Soft delete: timestamp di archiviazione. NULL = record attivo. Le attività archiviate non appaiono nelle selezioni ma i dati storici (lessons, subscriptions) rimangono collegati.';



COMMENT ON COLUMN "public"."activities"."color" IS 'Colore dell''attività selezionato dalla palette disponibile (turquoise, magenta, orange, purple, darkBlue, cyan, darkGreen, oliveGreen, lightGreen, brown, primaryGreen). NULL se non specificato.';



COMMENT ON COLUMN "public"."activities"."duration_minutes" IS 'Durata consigliata delle lezioni in minuti. Può essere modificata dal gestionale. Utilizzata principalmente dal sito web per mostrare la durata delle attività.';



COMMENT ON COLUMN "public"."activities"."slug" IS 'Slug generato automaticamente dalla colonna discipline. Utilizzato principalmente dal sito web per matchare i file JSON activity.{slug}.json. Viene aggiornato automaticamente quando discipline cambia.';



COMMENT ON COLUMN "public"."activities"."landing_title" IS 'Titolo principale per la landing page dell''attività. Utilizzato principalmente dal sito web per personalizzare la presentazione dell''attività.';



COMMENT ON COLUMN "public"."activities"."landing_subtitle" IS 'Sottotitolo per la landing page dell''attività. Utilizzato principalmente dal sito web per personalizzare la presentazione dell''attività.';



COMMENT ON COLUMN "public"."activities"."active_months" IS 'Array di stringhe rappresentanti i mesi in cui l''attività è attiva. Valori: "1" per Gennaio, "2" per Febbraio, ..., "12" per Dicembre. Esempio: ["1", "2", "3", "9", "10", "11", "12"]';



COMMENT ON COLUMN "public"."activities"."target_audience" IS 'Array di oggetti con struttura {title: string, description: string}[] rappresentante il pubblico target dell''attività. Esempio: [{"title": "Principianti", "description": "Perfetto per chi si avvicina per la prima volta"}]';



COMMENT ON COLUMN "public"."activities"."program_objectives" IS 'Array di stringhe, ognuna rappresenta un obiettivo del programma. Esempio: ["Ridurre lo stress", "Migliorare la concentrazione"]';



COMMENT ON COLUMN "public"."activities"."why_participate" IS 'Array di stringhe, ognuna rappresenta un motivo per partecipare. Esempio: ["Impara tecniche pratiche", "Ricevi supporto da istruttori esperti"]';



COMMENT ON COLUMN "public"."activities"."journey_structure" IS 'Array di stringhe, ognuna rappresenta una fase del "Viaggio di Consapevolezza". Esempio: ["Fase 1: Introduzione", "Fase 2: Pratiche guidate"]';



COMMENT ON COLUMN "public"."activities"."image_url" IS 'URL dell''immagine dell''attività. Utilizzato per la visualizzazione sul sito web.';



COMMENT ON COLUMN "public"."activities"."is_active" IS 'Se false, l''attività non viene mostrata pubblicamente. Default: true.';



COMMENT ON COLUMN "public"."activities"."updated_at" IS 'Timestamp di ultimo aggiornamento. Aggiornato automaticamente tramite trigger.';



COMMENT ON COLUMN "public"."activities"."icon_name" IS 'Nome esatto dell''icona della libreria iconsax-react. Popolato automaticamente per le attività esistenti basandosi sul mapping slug->icona. Può essere modificato manualmente dal gestionale. Se NULL, l''app utilizzerà un''icona di default.';



CREATE TABLE IF NOT EXISTS "public"."announcements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "image_url" "text",
    "link_url" "text",
    "link_label" "text",
    "category" "text" DEFAULT 'general'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "starts_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ends_at" timestamp with time zone,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "marketing_campaign_id" "uuid",
    "is_test" boolean DEFAULT false NOT NULL,
    "test_client_id" "uuid",
    "is_recurring" boolean DEFAULT false NOT NULL,
    "recurrence_frequency" "public"."announcement_recurrence_frequency",
    "recurrence_day_of_week" smallint,
    "recurrence_day_of_month" smallint,
    "recurrence_time" time without time zone,
    "next_occurrence_at" timestamp with time zone,
    "last_sent_at" timestamp with time zone,
    CONSTRAINT "announcements_recurrence_day_of_month_check" CHECK ((("recurrence_day_of_month" IS NULL) OR (("recurrence_day_of_month" >= 1) AND ("recurrence_day_of_month" <= 31)))),
    CONSTRAINT "announcements_recurrence_day_of_week_check" CHECK ((("recurrence_day_of_week" IS NULL) OR (("recurrence_day_of_week" >= 0) AND ("recurrence_day_of_week" <= 6))))
);


ALTER TABLE "public"."announcements" OWNER TO "postgres";


COMMENT ON TABLE "public"."announcements" IS 'Comunicazioni broadcast dallo staff (promozioni, nuovi corsi, annunci generali).';



COMMENT ON COLUMN "public"."announcements"."category" IS 'Categoria annuncio: general, promotion, course, event';



COMMENT ON COLUMN "public"."announcements"."starts_at" IS 'Quando iniziare a mostrare l''annuncio';



COMMENT ON COLUMN "public"."announcements"."ends_at" IS 'Quando smettere di mostrare l''annuncio (opzionale)';



COMMENT ON COLUMN "public"."announcements"."marketing_campaign_id" IS 'Reference to the marketing campaign that generated this announcement (null if created manually)';



COMMENT ON COLUMN "public"."announcements"."is_test" IS 'True if announcement was created from a test campaign execution';



COMMENT ON COLUMN "public"."announcements"."test_client_id" IS 'Se non NULL, l''annuncio è visibile solo a questo client (test mode da marketing campaigns)';



COMMENT ON COLUMN "public"."announcements"."recurrence_day_of_week" IS '0=Sunday, 1=Monday, ..., 6=Saturday (JS convention)';



CREATE TABLE IF NOT EXISTS "public"."auth_email_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "email_type" "text" NOT NULL,
    "source" "text" NOT NULL,
    "resend_id" "text",
    "status" "text" DEFAULT 'sent'::"text" NOT NULL,
    "error_message" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."auth_email_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lesson_id" "uuid" NOT NULL,
    "status" "public"."booking_status" DEFAULT 'booked'::"public"."booking_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "subscription_id" "uuid",
    "client_id" "uuid"
);


ALTER TABLE "public"."bookings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bug_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "image_url" "text",
    "created_by_user_id" "uuid",
    "created_by_client_id" "uuid",
    "status" "public"."bug_status" DEFAULT 'open'::"public"."bug_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "bug_reports_user_client_xor" CHECK (((("created_by_user_id" IS NOT NULL) AND ("created_by_client_id" IS NULL)) OR (("created_by_user_id" IS NULL) AND ("created_by_client_id" IS NOT NULL))))
);


ALTER TABLE "public"."bug_reports" OWNER TO "postgres";


COMMENT ON TABLE "public"."bug_reports" IS 'Tabella per segnalazioni bug da parte di clienti e operatori. Gli admin possono visualizzare tutti i bug.';



COMMENT ON COLUMN "public"."bug_reports"."title" IS 'Titolo del bug (obbligatorio)';



COMMENT ON COLUMN "public"."bug_reports"."description" IS 'Descrizione dettagliata del bug (obbligatorio)';



COMMENT ON COLUMN "public"."bug_reports"."image_url" IS 'URL dell immagine/screenshot del bug (opzionale ma consigliato)';



COMMENT ON COLUMN "public"."bug_reports"."created_by_user_id" IS 'ID del profilo utente che ha creato il bug (per clienti con account)';



COMMENT ON COLUMN "public"."bug_reports"."created_by_client_id" IS 'ID del cliente che ha creato il bug (per clienti senza account, creato da staff)';



COMMENT ON COLUMN "public"."bug_reports"."status" IS 'Stato del bug: open, in_progress, resolved, closed';



CREATE TABLE IF NOT EXISTS "public"."campaign_analytics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "content_id" "uuid",
    "channel" "text" NOT NULL,
    "reach" integer DEFAULT 0,
    "impressions" integer DEFAULT 0,
    "clicks" integer DEFAULT 0,
    "engagement" integer DEFAULT 0,
    "emails_sent" integer DEFAULT 0,
    "emails_delivered" integer DEFAULT 0,
    "emails_opened" integer DEFAULT 0,
    "emails_clicked" integer DEFAULT 0,
    "emails_bounced" integer DEFAULT 0,
    "push_sent" integer DEFAULT 0,
    "push_delivered" integer DEFAULT 0,
    "push_clicked" integer DEFAULT 0,
    "likes" integer DEFAULT 0,
    "comments" integer DEFAULT 0,
    "shares" integer DEFAULT 0,
    "saves" integer DEFAULT 0,
    "story_views" integer DEFAULT 0,
    "story_replies" integer DEFAULT 0,
    "last_fetched_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."campaign_analytics" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_analytics" IS 'Analytics metrics per channel for marketing campaigns';



CREATE TABLE IF NOT EXISTS "public"."campaign_contents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "content_type" "public"."campaign_content_type" NOT NULL,
    "platform" "public"."social_platform",
    "title" "text",
    "body" "text",
    "hashtags" "text"[],
    "image_suggestions" "text"[],
    "image_url" "text",
    "video_url" "text",
    "link_url" "text",
    "link_label" "text",
    "ai_generated_title" "text",
    "ai_generated_body" "text",
    "ai_generated_hashtags" "text"[],
    "ai_generated_image_suggestions" "text"[],
    "is_edited" boolean DEFAULT false,
    "status" "public"."content_status" DEFAULT 'pending'::"public"."content_status" NOT NULL,
    "scheduled_for" timestamp with time zone,
    "sent_at" timestamp with time zone,
    "published_at" timestamp with time zone,
    "newsletter_campaign_id" "uuid",
    "meta_post_id" "text",
    "meta_container_id" "text",
    "error_message" "text",
    "retry_count" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "social_connection_id" "uuid",
    "slides" "jsonb" DEFAULT '[]'::"jsonb",
    "story_text_overlays" "text"[],
    "scheduled_offset_days" integer,
    "sequence_index" integer DEFAULT 0
);


ALTER TABLE "public"."campaign_contents" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaign_contents" IS 'Generated content for each marketing channel';



COMMENT ON COLUMN "public"."campaign_contents"."is_edited" IS 'True if user modified AI-generated content';



COMMENT ON COLUMN "public"."campaign_contents"."social_connection_id" IS 'Selected social account for publishing (allows choosing between multiple connected accounts)';



COMMENT ON COLUMN "public"."campaign_contents"."slides" IS 'JSON array of carousel slides: [{image_url?: string, image_suggestion: string}]';



COMMENT ON COLUMN "public"."campaign_contents"."story_text_overlays" IS 'Array of text overlays to display on story images';



COMMENT ON COLUMN "public"."campaign_contents"."scheduled_offset_days" IS 'Days offset from event_date for story scheduling (-7, -3, -1, 0)';



COMMENT ON COLUMN "public"."campaign_contents"."sequence_index" IS 'Index for multiple contents of same type (e.g., story 0, 1, 2)';



CREATE TABLE IF NOT EXISTS "public"."campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "type" "public"."campaign_type" NOT NULL,
    "target" "jsonb" DEFAULT '{"segment": "tutti"}'::"jsonb" NOT NULL,
    "message" "text" NOT NULL,
    "event_date" timestamp with time zone,
    "tone" "public"."campaign_tone" DEFAULT 'amichevole'::"public"."campaign_tone" NOT NULL,
    "status" "public"."marketing_campaign_status" DEFAULT 'draft'::"public"."marketing_campaign_status" NOT NULL,
    "current_step" integer DEFAULT 1 NOT NULL,
    "skipped_steps" integer[] DEFAULT '{}'::integer[],
    "ai_prompt_used" "text",
    "ai_model_used" "text",
    "ai_generated_at" timestamp with time zone,
    "scheduled_for" timestamp with time zone,
    "executed_at" timestamp with time zone,
    "total_reach" integer DEFAULT 0,
    "total_engagement" integer DEFAULT 0,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "test_client_id" "uuid"
);


ALTER TABLE "public"."campaigns" OWNER TO "postgres";


COMMENT ON TABLE "public"."campaigns" IS 'Marketing campaigns with multi-channel content generation';



COMMENT ON COLUMN "public"."campaigns"."target" IS 'JSON object: {segment: string, categories?: string[]}';



COMMENT ON COLUMN "public"."campaigns"."skipped_steps" IS 'Array of step IDs that were skipped in the wizard';



COMMENT ON COLUMN "public"."campaigns"."test_client_id" IS 'When set, campaign is sent only to this client (for testing)';



CREATE TABLE IF NOT EXISTS "public"."clients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "full_name" "text" NOT NULL,
    "phone" "text",
    "email" "text",
    "profile_id" "uuid",
    "notes" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "birthday" "date",
    "email_bounced" boolean DEFAULT false,
    "email_bounced_at" timestamp with time zone,
    "newsletter_subscribed" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."clients" OWNER TO "postgres";


COMMENT ON COLUMN "public"."clients"."deleted_at" IS 'Soft delete: timestamp di archiviazione. NULL = record attivo. I clienti archiviati non appaiono nelle liste standard ma i dati storici (bookings, subscriptions) rimangono collegati.';



COMMENT ON COLUMN "public"."clients"."birthday" IS 'Data di nascita del cliente per invio auguri di compleanno';



COMMENT ON COLUMN "public"."clients"."email_bounced" IS 'True if email has hard bounced, excluding client from newsletter sends';



COMMENT ON COLUMN "public"."clients"."email_bounced_at" IS 'Timestamp of when the email bounced';



COMMENT ON COLUMN "public"."clients"."newsletter_subscribed" IS 'False when the client has opted out via the one-click unsubscribe link. Newsletter sends must exclude these clients.';



CREATE TABLE IF NOT EXISTS "public"."device_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "expo_push_token" "text" NOT NULL,
    "device_id" "text",
    "platform" "text",
    "app_version" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_used_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."device_tokens" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_tokens" IS 'Token push Expo per ogni dispositivo registrato. Un client puo avere piu dispositivi.';



COMMENT ON COLUMN "public"."device_tokens"."expo_push_token" IS 'Token Expo Push nel formato ExponentPushToken[xxx] o per web push';



COMMENT ON COLUMN "public"."device_tokens"."platform" IS 'Piattaforma: ios, android, web';



CREATE TABLE IF NOT EXISTS "public"."event_bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "event_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "status" "public"."booking_status" DEFAULT 'booked'::"public"."booking_status" NOT NULL,
    "client_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "event_bookings_user_client_xor" CHECK (((("user_id" IS NOT NULL) AND ("client_id" IS NULL)) OR (("user_id" IS NULL) AND ("client_id" IS NOT NULL))))
);


ALTER TABLE "public"."event_bookings" OWNER TO "postgres";


COMMENT ON TABLE "public"."event_bookings" IS 'Prenotazioni per eventi. Può essere collegata a un utente (user_id) o a un cliente CRM (client_id), ma non entrambi (XOR constraint).';



COMMENT ON COLUMN "public"."event_bookings"."user_id" IS 'ID dell''utente con account che ha prenotato. NULL se client_id è impostato.';



COMMENT ON COLUMN "public"."event_bookings"."client_id" IS 'ID del cliente CRM (senza account) che ha prenotato. NULL se user_id è impostato.';



COMMENT ON COLUMN "public"."event_bookings"."updated_at" IS 'Timestamp dell''ultimo aggiornamento della prenotazione. Aggiornato automaticamente dal trigger update_event_bookings_updated_at.';



CREATE TABLE IF NOT EXISTS "public"."events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "image_url" "text",
    "link" "text",
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "capacity" integer,
    "location" "text",
    "price_cents" integer DEFAULT 0,
    "currency" "text" DEFAULT 'EUR'::"text",
    "time_slots" "jsonb",
    CONSTRAINT "time_slots_format_check" CHECK ((("time_slots" IS NULL) OR ("jsonb_typeof"("time_slots") = 'array'::"text")))
);


ALTER TABLE "public"."events" OWNER TO "postgres";


COMMENT ON TABLE "public"."events" IS 'Eventi esterni (Eventbrite, ecc.) con link per registrazione';



COMMENT ON COLUMN "public"."events"."image_url" IS 'URL dell''immagine dell''evento';



COMMENT ON COLUMN "public"."events"."link" IS 'URL esterno per registrazione/partecipazione all''evento. NULL se la prenotazione è gestita internamente tramite event_bookings.';



COMMENT ON COLUMN "public"."events"."is_active" IS 'Se false, l''evento non viene mostrato (anche se è futuro)';



COMMENT ON COLUMN "public"."events"."deleted_at" IS 'Soft delete: timestamp di archiviazione. NULL = record attivo. Gli eventi archiviati non appaiono nelle viste pubbliche.';



COMMENT ON COLUMN "public"."events"."time_slots" IS 'Array di orari per eventi con più sessioni nella stessa data. 
   Formato: [{"starts_at": "ISO8601", "ends_at": "ISO8601|null"}]. 
   Opzionale: se NULL, l''applicazione usa starts_at e ends_at come fallback.';



COMMENT ON CONSTRAINT "time_slots_format_check" ON "public"."events" IS 'Valida che time_slots sia NULL o un array JSON. La validazione dettagliata 
   della struttura (verifica che ogni elemento sia un oggetto con starts_at) 
   è gestita a livello applicativo, poiché PostgreSQL non permette subquery 
   nei CHECK constraints.';



CREATE TABLE IF NOT EXISTS "public"."expenses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "amount_cents" integer NOT NULL,
    "expense_date" "date" NOT NULL,
    "category" "text" NOT NULL,
    "vendor" "text",
    "notes" "text",
    "is_fixed" boolean DEFAULT false NOT NULL,
    "activity_id" "uuid",
    "operator_id" "uuid",
    "lesson_id" "uuid",
    "event_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "expenses_category_check" CHECK (("category" = ANY (ARRAY['staff_compensation'::"text", 'materials'::"text", 'location_fee'::"text", 'software'::"text", 'marketing'::"text", 'utilities'::"text", 'rent'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."expenses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lessons" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "activity_id" "uuid" NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone NOT NULL,
    "capacity" integer NOT NULL,
    "booking_deadline_minutes" integer DEFAULT 120,
    "cancel_deadline_minutes" integer DEFAULT 120,
    "notes" "text",
    "operator_id" "uuid",
    "deleted_at" timestamp with time zone,
    "recurring_series_id" "uuid",
    "is_individual" boolean DEFAULT false NOT NULL,
    "assigned_client_id" "uuid",
    "assigned_subscription_id" "uuid",
    CONSTRAINT "lessons_capacity_check" CHECK (("capacity" > 0)),
    CONSTRAINT "lessons_individual_capacity_check" CHECK ((("is_individual" = false) OR ("capacity" = 1))),
    CONSTRAINT "lessons_individual_check" CHECK ((("is_individual" = false) OR ("assigned_client_id" IS NOT NULL))),
    CONSTRAINT "lessons_individual_client_check" CHECK ((("is_individual" = true) OR ("assigned_client_id" IS NULL)))
);


ALTER TABLE "public"."lessons" OWNER TO "postgres";


COMMENT ON COLUMN "public"."lessons"."deleted_at" IS 'Soft delete: timestamp di archiviazione. NULL = record attivo. Le lezioni archiviate non appaiono negli schedule pubblici ma i bookings storici rimangono collegati.';



COMMENT ON COLUMN "public"."lessons"."is_individual" IS 'Se true, questa è una lezione individuale/privata assegnata a un cliente specifico';



COMMENT ON COLUMN "public"."lessons"."assigned_client_id" IS 'Cliente assegnato alla lezione individuale. Deve essere null se is_individual=false, e non null se is_individual=true';



COMMENT ON COLUMN "public"."lessons"."assigned_subscription_id" IS 'Abbonamento utilizzato per questa lezione individuale. Impostato solo per lezioni individuali (is_individual = true) con cliente assegnato (assigned_client_id IS NOT NULL).';



CREATE TABLE IF NOT EXISTS "public"."plans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "discipline" "text",
    "price_cents" integer NOT NULL,
    "currency" "text" DEFAULT 'EUR'::"text",
    "entries" integer,
    "validity_days" integer NOT NULL,
    "description" "text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "deleted_at" timestamp with time zone,
    "discount_percent" numeric(5,2),
    CONSTRAINT "plans_discount_percent_check" CHECK ((("discount_percent" >= (0)::numeric) AND ("discount_percent" <= (100)::numeric)))
);


ALTER TABLE "public"."plans" OWNER TO "postgres";


COMMENT ON COLUMN "public"."plans"."deleted_at" IS 'Soft delete: timestamp di archiviazione. NULL = record attivo. I piani archiviati non appaiono nelle selezioni pubbliche ma le subscriptions esistenti rimangono valide.';



CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "plan_id" "uuid" NOT NULL,
    "status" "public"."subscription_status" DEFAULT 'active'::"public"."subscription_status" NOT NULL,
    "started_at" "date" DEFAULT CURRENT_DATE NOT NULL,
    "expires_at" "date" NOT NULL,
    "custom_name" "text",
    "custom_price_cents" integer,
    "custom_entries" integer,
    "custom_validity_days" integer,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "client_id" "uuid",
    "deleted_at" timestamp with time zone,
    "discount_percent" numeric(5,2) DEFAULT NULL::numeric,
    "discount_reason" "text",
    CONSTRAINT "subscriptions_discount_percent_range" CHECK ((("discount_percent" IS NULL) OR (("discount_percent" >= (0)::numeric) AND ("discount_percent" <= (100)::numeric))))
);


ALTER TABLE "public"."subscriptions" OWNER TO "postgres";


COMMENT ON COLUMN "public"."subscriptions"."deleted_at" IS 'Timestamp di cancellazione definitiva (soft delete). Se NULL, l''abbonamento è attivo. Se NOT NULL, l''abbonamento è stato cancellato definitivamente e non è più visibile.';



COMMENT ON COLUMN "public"."subscriptions"."discount_percent" IS 'Discount percentage (0-100) applied to this subscription. Takes priority over plan discount.';



COMMENT ON COLUMN "public"."subscriptions"."discount_reason" IS 'Reason for the discount (e.g., "Referral - Porta un Amico", "Promo Natale")';



CREATE OR REPLACE VIEW "public"."financial_monthly_summary" WITH ("security_invoker"='true') AS
 WITH "lesson_revenue" AS (
         SELECT ("date_trunc"('month'::"text", "l"."starts_at"))::"date" AS "month",
            ("sum"(
                CASE
                    WHEN (("s"."custom_price_cents" IS NOT NULL) AND ("s"."custom_entries" IS NOT NULL) AND ("s"."custom_entries" > 0)) THEN "round"((("s"."custom_price_cents")::numeric / ("s"."custom_entries")::numeric))
                    WHEN (("p"."price_cents" IS NOT NULL) AND ("p"."entries" IS NOT NULL) AND ("p"."entries" > 0)) THEN "round"((("p"."price_cents")::numeric / ("p"."entries")::numeric))
                    ELSE (0)::numeric
                END))::integer AS "revenue_cents",
            "count"(DISTINCT "b"."id") AS "bookings_count"
           FROM ((("public"."bookings" "b"
             JOIN "public"."lessons" "l" ON (("l"."id" = "b"."lesson_id")))
             LEFT JOIN "public"."subscriptions" "s" ON (("s"."id" = "b"."subscription_id")))
             LEFT JOIN "public"."plans" "p" ON (("p"."id" = "s"."plan_id")))
          WHERE (("b"."status" = ANY (ARRAY['booked'::"public"."booking_status", 'attended'::"public"."booking_status", 'no_show'::"public"."booking_status"])) AND ("b"."subscription_id" IS NOT NULL))
          GROUP BY (("date_trunc"('month'::"text", "l"."starts_at"))::"date")
        ), "event_revenue" AS (
         SELECT ("date_trunc"('month'::"text", "e"."starts_at"))::"date" AS "month",
            ("sum"("e"."price_cents"))::integer AS "revenue_cents",
            "count"(DISTINCT "eb"."id") AS "bookings_count"
           FROM ("public"."event_bookings" "eb"
             JOIN "public"."events" "e" ON (("e"."id" = "eb"."event_id")))
          WHERE (("eb"."status" = ANY (ARRAY['booked'::"public"."booking_status", 'attended'::"public"."booking_status", 'no_show'::"public"."booking_status"])) AND ("e"."price_cents" IS NOT NULL))
          GROUP BY (("date_trunc"('month'::"text", "e"."starts_at"))::"date")
        ), "subscription_revenue" AS (
         SELECT ("date_trunc"('month'::"text", ("s"."started_at")::timestamp with time zone))::"date" AS "month",
            ("sum"(
                CASE
                    WHEN ("s"."custom_price_cents" IS NOT NULL) THEN "s"."custom_price_cents"
                    WHEN ("p"."price_cents" IS NOT NULL) THEN "p"."price_cents"
                    ELSE 0
                END))::integer AS "revenue_cents",
            "count"(*) AS "subscriptions_count"
           FROM ("public"."subscriptions" "s"
             LEFT JOIN "public"."plans" "p" ON (("p"."id" = "s"."plan_id")))
          GROUP BY (("date_trunc"('month'::"text", ("s"."started_at")::timestamp with time zone))::"date")
        ), "all_months" AS (
         SELECT DISTINCT "lesson_revenue"."month"
           FROM "lesson_revenue"
        UNION
         SELECT DISTINCT "event_revenue"."month"
           FROM "event_revenue"
        UNION
         SELECT DISTINCT "subscription_revenue"."month"
           FROM "subscription_revenue"
        )
 SELECT "am"."month",
    ((COALESCE("lr"."revenue_cents", 0) + COALESCE("er"."revenue_cents", 0)) + COALESCE("sr"."revenue_cents", 0)) AS "revenue_cents",
    ((COALESCE("lr"."revenue_cents", 0) + COALESCE("er"."revenue_cents", 0)) + COALESCE("sr"."revenue_cents", 0)) AS "gross_revenue_cents",
    0 AS "refunds_cents",
    ((COALESCE("lr"."bookings_count", (0)::bigint) + COALESCE("er"."bookings_count", (0)::bigint)) + COALESCE("sr"."subscriptions_count", (0)::bigint)) AS "completed_payments_count",
    0 AS "refunded_payments_count"
   FROM ((("all_months" "am"
     LEFT JOIN "lesson_revenue" "lr" ON (("lr"."month" = "am"."month")))
     LEFT JOIN "event_revenue" "er" ON (("er"."month" = "am"."month")))
     LEFT JOIN "subscription_revenue" "sr" ON (("sr"."month" = "am"."month")))
  ORDER BY "am"."month" DESC;


ALTER VIEW "public"."financial_monthly_summary" OWNER TO "postgres";


COMMENT ON VIEW "public"."financial_monthly_summary" IS 'View per il sommario finanziario mensile. Usa SECURITY INVOKER - accessibile solo a utenti con permessi finanziari.';



CREATE TABLE IF NOT EXISTS "public"."journal_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "title" "text",
    "body" "text" NOT NULL,
    "practice_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."journal_entries" OWNER TO "postgres";


COMMENT ON TABLE "public"."journal_entries" IS 'Diario personale dell''utente. Puo essere collegato a una pratica completata.';



COMMENT ON COLUMN "public"."journal_entries"."practice_id" IS 'Se la nota e stata creata al termine di una pratica, riferimento alla pratica';



CREATE OR REPLACE VIEW "public"."lesson_occupancy" AS
 SELECT "l"."id" AS "lesson_id",
    "count"("b".*) FILTER (WHERE ("b"."status" = 'booked'::"public"."booking_status")) AS "booked_count",
    "l"."capacity",
    GREATEST(("l"."capacity" - "count"("b".*) FILTER (WHERE ("b"."status" = 'booked'::"public"."booking_status"))), (0)::bigint) AS "free_spots"
   FROM ("public"."lessons" "l"
     LEFT JOIN "public"."bookings" "b" ON ((("b"."lesson_id" = "l"."id") AND ("b"."status" = 'booked'::"public"."booking_status"))))
  GROUP BY "l"."id", "l"."capacity";


ALTER VIEW "public"."lesson_occupancy" OWNER TO "postgres";


COMMENT ON VIEW "public"."lesson_occupancy" IS 'Aggregated lesson occupancy data. Does NOT use security_invoker so all users see real counts.';



CREATE TABLE IF NOT EXISTS "public"."newsletter_campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "subject" "text" NOT NULL,
    "content" "text" NOT NULL,
    "status" "public"."newsletter_campaign_status" DEFAULT 'draft'::"public"."newsletter_campaign_status" NOT NULL,
    "scheduled_at" timestamp with time zone,
    "sent_at" timestamp with time zone,
    "recipient_count" integer DEFAULT 0 NOT NULL,
    "delivered_count" integer DEFAULT 0 NOT NULL,
    "opened_count" integer DEFAULT 0 NOT NULL,
    "clicked_count" integer DEFAULT 0 NOT NULL,
    "bounced_count" integer DEFAULT 0 NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "recipients" "jsonb" DEFAULT '[]'::"jsonb",
    "archived" boolean DEFAULT false NOT NULL,
    "image_url" "text",
    "preview_text" "text",
    "marketing_campaign_id" "uuid",
    "delivery_mode" "text" DEFAULT 'promotions'::"text" NOT NULL,
    "from_name_override" "text",
    CONSTRAINT "newsletter_campaigns_delivery_mode_check" CHECK (("delivery_mode" = ANY (ARRAY['promotions'::"text", 'primary'::"text"])))
);


ALTER TABLE "public"."newsletter_campaigns" OWNER TO "postgres";


COMMENT ON TABLE "public"."newsletter_campaigns" IS 'Campagne newsletter. Il contenuto e in testo semplice. Supporta {{nome}} come placeholder per il nome del destinatario.';



COMMENT ON COLUMN "public"."newsletter_campaigns"."content" IS 'Contenuto della newsletter in testo semplice. Supporta {{nome}} come placeholder.';



COMMENT ON COLUMN "public"."newsletter_campaigns"."status" IS 'Stato della campagna: draft (bozza), scheduled (programmata), sending (in invio), sent (inviata), failed (fallita)';



COMMENT ON COLUMN "public"."newsletter_campaigns"."recipients" IS 'Lista dei destinatari selezionati salvati con la bozza. Formato: [{email, name, clientId?}]';



COMMENT ON COLUMN "public"."newsletter_campaigns"."archived" IS 'Whether the campaign is archived (hidden from default list view)';



COMMENT ON COLUMN "public"."newsletter_campaigns"."image_url" IS 'Path relativo dell''immagine nel bucket storage newsletter, o URL completo';



COMMENT ON COLUMN "public"."newsletter_campaigns"."preview_text" IS 'Preview text (preheader) shown after the subject line in email clients';



COMMENT ON COLUMN "public"."newsletter_campaigns"."marketing_campaign_id" IS 'Reference to the marketing campaign that generated this newsletter (null if created manually)';



COMMENT ON COLUMN "public"."newsletter_campaigns"."delivery_mode" IS 'Send strategy: ''promotions'' (branded HTML, bulk headers) or ''primary'' (plain HTML, no bulk headers, aiming for Gmail Primary tab).';



COMMENT ON COLUMN "public"."newsletter_campaigns"."from_name_override" IS 'Optional sender display name override, used in primary mode (e.g. "Tommaso da Studio Kalòs"). Email address stays on the verified domain.';



CREATE TABLE IF NOT EXISTS "public"."newsletter_emails" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "client_id" "uuid",
    "email_address" "text" NOT NULL,
    "client_name" "text" NOT NULL,
    "resend_id" "text",
    "status" "public"."newsletter_email_status" DEFAULT 'pending'::"public"."newsletter_email_status" NOT NULL,
    "sent_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "opened_at" timestamp with time zone,
    "clicked_at" timestamp with time zone,
    "bounced_at" timestamp with time zone,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."newsletter_emails" OWNER TO "postgres";


COMMENT ON TABLE "public"."newsletter_emails" IS 'Singole email inviate come parte di una campagna. Traccia lo stato di ogni email inviata.';



COMMENT ON COLUMN "public"."newsletter_emails"."client_id" IS 'ID del cliente destinatario. NULL per email manuali non associate a un cliente.';



COMMENT ON COLUMN "public"."newsletter_emails"."resend_id" IS 'ID univoco dell email restituito da Resend, usato per tracciare gli eventi webhook';



COMMENT ON COLUMN "public"."newsletter_emails"."status" IS 'Stato dell email: pending, sent, delivered, opened, clicked, bounced, complained, failed';



CREATE TABLE IF NOT EXISTS "public"."newsletter_extra_emails" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" "text" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."newsletter_extra_emails" OWNER TO "postgres";


COMMENT ON TABLE "public"."newsletter_extra_emails" IS 'Extra email addresses for newsletter recipients (non-clients)';



CREATE TABLE IF NOT EXISTS "public"."newsletter_tracking_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email_id" "uuid" NOT NULL,
    "event_type" "public"."newsletter_event_type" NOT NULL,
    "event_data" "jsonb",
    "occurred_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."newsletter_tracking_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."newsletter_tracking_events" IS 'Eventi di tracking ricevuti dai webhook Resend (aperture, click, bounce).';



CREATE TABLE IF NOT EXISTS "public"."notification_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "category" "public"."notification_category" NOT NULL,
    "channel" "public"."notification_channel" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text",
    "data" "jsonb" DEFAULT '{}'::"jsonb",
    "expo_receipt_id" "text",
    "resend_id" "text",
    "status" "public"."notification_status" DEFAULT 'sent'::"public"."notification_status" NOT NULL,
    "sent_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "delivered_at" timestamp with time zone,
    "error_message" "text"
);


ALTER TABLE "public"."notification_logs" OWNER TO "postgres";


COMMENT ON TABLE "public"."notification_logs" IS 'Storico notifiche inviate con stato di delivery. Usato per analytics e anti-spam.';



COMMENT ON COLUMN "public"."notification_logs"."expo_receipt_id" IS 'ID ricevuta Expo per verificare delivery push';



COMMENT ON COLUMN "public"."notification_logs"."resend_id" IS 'ID email Resend per tracking delivery email';



CREATE TABLE IF NOT EXISTS "public"."notification_preferences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "category" "public"."notification_category" NOT NULL,
    "push_enabled" boolean DEFAULT true NOT NULL,
    "email_enabled" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."notification_preferences" OWNER TO "postgres";


COMMENT ON TABLE "public"."notification_preferences" IS 'Preferenze notifiche per ogni client e categoria. Permette di abilitare/disabilitare push ed email separatamente.';



CREATE TABLE IF NOT EXISTS "public"."notification_queue" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "category" "public"."notification_category" NOT NULL,
    "channel" "public"."notification_channel" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "data" "jsonb" DEFAULT '{}'::"jsonb",
    "scheduled_for" timestamp with time zone NOT NULL,
    "status" "public"."notification_status" DEFAULT 'pending'::"public"."notification_status" NOT NULL,
    "attempts" integer DEFAULT 0 NOT NULL,
    "last_attempt_at" timestamp with time zone,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone
);


ALTER TABLE "public"."notification_queue" OWNER TO "postgres";


COMMENT ON TABLE "public"."notification_queue" IS 'Coda notifiche da processare. RLS disabilitato - accessibile solo via Edge Functions con service_role key.';



COMMENT ON COLUMN "public"."notification_queue"."data" IS 'Dati aggiuntivi come lesson_id, subscription_id, etc. per deep linking';



COMMENT ON COLUMN "public"."notification_queue"."scheduled_for" IS 'Quando la notifica deve essere inviata. Il processor legge solo quelle con scheduled_for <= NOW()';



CREATE TABLE IF NOT EXISTS "public"."notification_reads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "notification_log_id" "uuid",
    "announcement_id" "uuid",
    "read_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_reads_one_source" CHECK (((("notification_log_id" IS NOT NULL) AND ("announcement_id" IS NULL)) OR (("notification_log_id" IS NULL) AND ("announcement_id" IS NOT NULL))))
);


ALTER TABLE "public"."notification_reads" OWNER TO "postgres";


COMMENT ON TABLE "public"."notification_reads" IS 'Traccia quali notifiche/annunci sono stati letti da ogni client.';



CREATE TABLE IF NOT EXISTS "public"."operators" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "role" "text" NOT NULL,
    "bio" "text",
    "disciplines" "text"[],
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "profile_id" "uuid",
    "is_admin" boolean DEFAULT false,
    "deleted_at" timestamp with time zone,
    "image_url" "text",
    "display_order" integer,
    "is_visible_on_site" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."operators" OWNER TO "postgres";


COMMENT ON COLUMN "public"."operators"."deleted_at" IS 'Soft delete: timestamp di archiviazione. NULL = record attivo. Gli operatori archiviati non appaiono nelle selezioni ma i dati storici (lessons, expenses) rimangono collegati.';



COMMENT ON COLUMN "public"."operators"."image_url" IS 'URL pubblico dell''immagine profilo dell''operatore. Le immagini sono caricate nel bucket "operators".';



COMMENT ON COLUMN "public"."operators"."display_order" IS 'Ordine di visualizzazione degli operatori nel sito pubblico. Valori più bassi = posizioni più alte.';



COMMENT ON COLUMN "public"."operators"."is_visible_on_site" IS 'Controlla se l''operatore è mostrato nella sezione team del sito pubblico. Indipendente da is_active: un operatore può essere attivo nel gestionale ma non visibile sul sito (es. nuovo arrivato non ancora annunciato).';



CREATE TABLE IF NOT EXISTS "public"."payout_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "month" "date" NOT NULL,
    "cash_reserve_pct" numeric(5,2) DEFAULT 0 NOT NULL,
    "marketing_pct" numeric(5,2) DEFAULT 0 NOT NULL,
    "team_pct" numeric(5,2) DEFAULT 0 NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "payout_rules_cash_reserve_pct_check" CHECK ((("cash_reserve_pct" >= (0)::numeric) AND ("cash_reserve_pct" <= (100)::numeric))),
    CONSTRAINT "payout_rules_marketing_pct_check" CHECK ((("marketing_pct" >= (0)::numeric) AND ("marketing_pct" <= (100)::numeric))),
    CONSTRAINT "payout_rules_percentage_check" CHECK (((("cash_reserve_pct" + "marketing_pct") + "team_pct") <= (100)::numeric)),
    CONSTRAINT "payout_rules_team_pct_check" CHECK ((("team_pct" >= (0)::numeric) AND ("team_pct" <= (100)::numeric)))
);


ALTER TABLE "public"."payout_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payouts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "month" "date" NOT NULL,
    "operator_id" "uuid",
    "amount_cents" integer NOT NULL,
    "reason" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "paid_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "payouts_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."payouts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."plan_activities" (
    "plan_id" "uuid" NOT NULL,
    "activity_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."plan_activities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."practice_activities" (
    "practice_id" "uuid" NOT NULL,
    "activity_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."practice_activities" OWNER TO "postgres";


COMMENT ON TABLE "public"."practice_activities" IS 'Associazione tra pratiche e attivita/discipline correlate.';



CREATE TABLE IF NOT EXISTS "public"."practice_blocks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "step_id" "uuid" NOT NULL,
    "block_type" "public"."practice_block_type" NOT NULL,
    "content" "text" NOT NULL,
    "caption" "text",
    "sort_order" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."practice_blocks" OWNER TO "postgres";


COMMENT ON TABLE "public"."practice_blocks" IS 'Blocchi di contenuto (testo, immagine, audio, video) dentro uno step di pratica.';



CREATE TABLE IF NOT EXISTS "public"."practice_steps" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "practice_id" "uuid" NOT NULL,
    "title" "text",
    "sort_order" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."practice_steps" OWNER TO "postgres";


COMMENT ON TABLE "public"."practice_steps" IS 'Passi ordinati di una pratica guidata. Ogni step contiene blocchi di contenuto.';



CREATE TABLE IF NOT EXISTS "public"."practice_user_state" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "practice_id" "uuid" NOT NULL,
    "status" "public"."practice_user_status" DEFAULT 'started'::"public"."practice_user_status" NOT NULL,
    "current_step_index" integer DEFAULT 0 NOT NULL,
    "is_favorite" boolean DEFAULT false NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "last_accessed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "time_spent_seconds" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."practice_user_state" OWNER TO "postgres";


COMMENT ON TABLE "public"."practice_user_state" IS 'Stato di avanzamento dell''utente per ogni pratica: progresso, preferiti, tempo speso.';



COMMENT ON COLUMN "public"."practice_user_state"."current_step_index" IS 'Indice dell''ultimo step raggiunto dall''utente (0-based)';



COMMENT ON COLUMN "public"."practice_user_state"."time_spent_seconds" IS 'Tempo totale accumulato dall''utente sulla pratica in secondi';



CREATE TABLE IF NOT EXISTS "public"."practices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "subtitle" "text",
    "description" "text",
    "duration_minutes" integer,
    "category" "public"."practice_category" NOT NULL,
    "level" "public"."practice_level" DEFAULT 'principiante'::"public"."practice_level" NOT NULL,
    "goals" "jsonb" DEFAULT '[]'::"jsonb",
    "cover_image_url" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "is_featured" boolean DEFAULT false NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."practices" OWNER TO "postgres";


COMMENT ON TABLE "public"."practices" IS 'Pratiche guidate per la pratica a casa. Ogni pratica ha step con blocchi di contenuto.';



COMMENT ON COLUMN "public"."practices"."goals" IS 'Array JSON di obiettivi: calmarsi, energia, rallentare, sciogliere_tensioni, riconnettersi';



COMMENT ON COLUMN "public"."practices"."is_featured" IS 'Flag "In evidenza" per mostrare nella home dell''app';



CREATE TABLE IF NOT EXISTS "public"."promotions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "image_url" "text",
    "link" "text" NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "discount_percent" integer,
    "plan_id" "uuid",
    CONSTRAINT "promotions_discount_percent_check" CHECK ((("discount_percent" >= 0) AND ("discount_percent" <= 100)))
);


ALTER TABLE "public"."promotions" OWNER TO "postgres";


COMMENT ON TABLE "public"."promotions" IS 'Promozioni e offerte speciali con link per dettagli/acquisto';



COMMENT ON COLUMN "public"."promotions"."image_url" IS 'URL dell''immagine della promozione';



COMMENT ON COLUMN "public"."promotions"."link" IS 'URL interno (es. piano) o esterno per la promozione';



COMMENT ON COLUMN "public"."promotions"."ends_at" IS 'Se null, la promozione non ha data di scadenza';



COMMENT ON COLUMN "public"."promotions"."is_active" IS 'Se false, la promozione non viene mostrata';



COMMENT ON COLUMN "public"."promotions"."deleted_at" IS 'Soft delete: timestamp di archiviazione. NULL = record attivo. Le promozioni archiviate non appaiono nelle viste pubbliche.';



CREATE OR REPLACE VIEW "public"."public_site_activities" AS
 SELECT "id",
    "name",
    "slug",
    "description",
    "discipline",
    "color",
    "duration_minutes",
    "image_url",
    "is_active",
    "icon_name",
    "landing_title",
    "landing_subtitle",
    "active_months",
    "target_audience",
    "program_objectives",
    "why_participate",
    "journey_structure",
    "created_at",
    "updated_at"
   FROM "public"."activities" "a"
  WHERE (("deleted_at" IS NULL) AND (COALESCE("is_active", true) = true))
  ORDER BY "name";


ALTER VIEW "public"."public_site_activities" OWNER TO "postgres";


COMMENT ON VIEW "public"."public_site_activities" IS 'View pubblica per le attività visibili sul sito. Filtra per deleted_at IS NULL AND is_active = true.';



CREATE OR REPLACE VIEW "public"."public_site_events" WITH ("security_invoker"='true') AS
 SELECT "id",
    "name" AS "title",
    "description",
    "image_url",
    "starts_at" AS "start_date",
    "ends_at" AS "end_date",
    "link" AS "registration_url",
    "link" AS "link_url",
    "created_at",
    "updated_at"
   FROM "public"."events" "e"
  WHERE ("deleted_at" IS NULL)
  ORDER BY "starts_at" DESC;


ALTER VIEW "public"."public_site_events" OWNER TO "postgres";


COMMENT ON VIEW "public"."public_site_events" IS 'View pubblica per gli eventi. Usa SECURITY INVOKER per rispettare le policy RLS.';



CREATE OR REPLACE VIEW "public"."public_site_operators" AS
 SELECT "id",
    "name",
    "role",
    "bio",
    "image_url",
    NULL::"text" AS "image_alt",
    "display_order",
    "is_active"
   FROM "public"."operators" "o"
  WHERE (("is_active" = true) AND ("is_visible_on_site" = true) AND ("deleted_at" IS NULL))
  ORDER BY "display_order", "name";


ALTER VIEW "public"."public_site_operators" OWNER TO "postgres";


COMMENT ON VIEW "public"."public_site_operators" IS 'View pubblica per gli operatori visibili sul sito. Filtra per is_active = true AND is_visible_on_site = true AND deleted_at IS NULL.';



CREATE OR REPLACE VIEW "public"."public_site_pricing" WITH ("security_invoker"='true') AS
 SELECT "p"."id",
    "p"."name",
    "p"."discipline",
    "p"."price_cents",
    "p"."currency",
    "p"."entries",
    "p"."validity_days",
    "p"."description",
    "p"."discount_percent",
    COALESCE("json_agg"("json_build_object"('id', "pa"."activity_id", 'name', "a"."name", 'discipline', "a"."discipline")) FILTER (WHERE ("pa"."activity_id" IS NOT NULL)), '[]'::json) AS "activities"
   FROM (("public"."plans" "p"
     LEFT JOIN "public"."plan_activities" "pa" ON (("pa"."plan_id" = "p"."id")))
     LEFT JOIN "public"."activities" "a" ON ((("a"."id" = "pa"."activity_id") AND ("a"."deleted_at" IS NULL))))
  WHERE (("p"."deleted_at" IS NULL) AND ("p"."is_active" = true))
  GROUP BY "p"."id", "p"."name", "p"."discipline", "p"."price_cents", "p"."currency", "p"."entries", "p"."validity_days", "p"."description", "p"."discount_percent"
  ORDER BY "p"."price_cents";


ALTER VIEW "public"."public_site_pricing" OWNER TO "postgres";


COMMENT ON VIEW "public"."public_site_pricing" IS 'View pubblica per i piani e prezzi. Usa SECURITY INVOKER per rispettare le policy RLS.';



CREATE OR REPLACE VIEW "public"."public_site_schedule" WITH ("security_invoker"='true') AS
 SELECT "l"."id",
    "l"."starts_at",
    "l"."ends_at",
    "l"."capacity",
    "a"."id" AS "activity_id",
    "a"."name" AS "activity_name",
    "a"."discipline",
    "a"."color" AS "activity_color",
    "lo"."booked_count",
    "lo"."free_spots",
    "o"."id" AS "operator_id",
    "o"."name" AS "operator_name",
    "l"."booking_deadline_minutes",
    "l"."cancel_deadline_minutes"
   FROM ((("public"."lessons" "l"
     JOIN "public"."activities" "a" ON (("a"."id" = "l"."activity_id")))
     LEFT JOIN "public"."lesson_occupancy" "lo" ON (("lo"."lesson_id" = "l"."id")))
     LEFT JOIN "public"."operators" "o" ON ((("o"."id" = "l"."operator_id") AND ("o"."is_active" = true) AND ("o"."deleted_at" IS NULL))))
  WHERE (("l"."deleted_at" IS NULL) AND ("a"."deleted_at" IS NULL) AND ("l"."is_individual" = false) AND ("l"."starts_at" >= CURRENT_DATE))
  ORDER BY "l"."starts_at";


ALTER VIEW "public"."public_site_schedule" OWNER TO "postgres";


COMMENT ON VIEW "public"."public_site_schedule" IS 'View pubblica per lo schedule delle lezioni. Usa SECURITY INVOKER per rispettare le policy RLS.';



CREATE TABLE IF NOT EXISTS "public"."social_connections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "operator_id" "uuid" NOT NULL,
    "platform" "public"."social_platform" NOT NULL,
    "account_id" "text" NOT NULL,
    "account_name" "text",
    "page_id" "text",
    "page_name" "text",
    "instagram_business_id" "text",
    "instagram_username" "text",
    "access_token" "text" NOT NULL,
    "token_expires_at" timestamp with time zone,
    "permissions" "text"[] DEFAULT '{}'::"text"[],
    "is_active" boolean DEFAULT true NOT NULL,
    "last_used_at" timestamp with time zone,
    "last_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_test" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."social_connections" OWNER TO "postgres";


COMMENT ON TABLE "public"."social_connections" IS 'Meta OAuth connections for social media publishing';



COMMENT ON COLUMN "public"."social_connections"."access_token" IS 'Long-lived access token (60 days)';



COMMENT ON COLUMN "public"."social_connections"."is_test" IS 'True for test accounts, false for production accounts';



CREATE TABLE IF NOT EXISTS "public"."subscription_usages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "subscription_id" "uuid" NOT NULL,
    "booking_id" "uuid",
    "delta" integer NOT NULL,
    "reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."subscription_usages" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."subscriptions_with_remaining" WITH ("security_invoker"='true') AS
 WITH "usage_totals" AS (
         SELECT "subscription_usages"."subscription_id",
            COALESCE("sum"("subscription_usages"."delta"), (0)::bigint) AS "delta_sum"
           FROM "public"."subscription_usages"
          GROUP BY "subscription_usages"."subscription_id"
        )
 SELECT "s"."id",
    "s"."client_id",
    "s"."plan_id",
    "s"."status",
    "s"."started_at",
    "s"."expires_at",
    "s"."custom_name",
    "s"."custom_price_cents",
    "s"."custom_entries",
    "s"."custom_validity_days",
    "s"."metadata",
    "s"."created_at",
    COALESCE("s"."custom_entries", "p"."entries") AS "effective_entries",
        CASE
            WHEN (COALESCE("s"."custom_entries", "p"."entries") IS NOT NULL) THEN (COALESCE("s"."custom_entries", "p"."entries") + COALESCE("u"."delta_sum", (0)::bigint))
            ELSE NULL::bigint
        END AS "remaining_entries"
   FROM (("public"."subscriptions" "s"
     LEFT JOIN "public"."plans" "p" ON (("p"."id" = "s"."plan_id")))
     LEFT JOIN "usage_totals" "u" ON (("u"."subscription_id" = "s"."id")))
  WHERE ("s"."deleted_at" IS NULL);


ALTER VIEW "public"."subscriptions_with_remaining" OWNER TO "postgres";


COMMENT ON VIEW "public"."subscriptions_with_remaining" IS 'View che calcola i posti rimanenti per ogni subscription. Usa solo client_id (user_id rimosso).';



CREATE TABLE IF NOT EXISTS "public"."waitlist" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lesson_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."waitlist" OWNER TO "postgres";


ALTER TABLE ONLY "public"."activities"
    ADD CONSTRAINT "activities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."announcements"
    ADD CONSTRAINT "announcements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auth_email_logs"
    ADD CONSTRAINT "auth_email_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bug_reports"
    ADD CONSTRAINT "bug_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_analytics"
    ADD CONSTRAINT "campaign_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_analytics"
    ADD CONSTRAINT "campaign_analytics_unique" UNIQUE ("campaign_id", "channel");



ALTER TABLE ONLY "public"."campaign_contents"
    ADD CONSTRAINT "campaign_contents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."campaign_contents"
    ADD CONSTRAINT "campaign_contents_unique" UNIQUE ("campaign_id", "content_type", "sequence_index");



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_expo_push_token_unique" UNIQUE ("expo_push_token");



ALTER TABLE ONLY "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."event_bookings"
    ADD CONSTRAINT "event_bookings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."journal_entries"
    ADD CONSTRAINT "journal_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."newsletter_campaigns"
    ADD CONSTRAINT "newsletter_campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."newsletter_emails"
    ADD CONSTRAINT "newsletter_emails_campaign_email_unique" UNIQUE ("campaign_id", "email_address");



ALTER TABLE ONLY "public"."newsletter_emails"
    ADD CONSTRAINT "newsletter_emails_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."newsletter_extra_emails"
    ADD CONSTRAINT "newsletter_extra_emails_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."newsletter_tracking_events"
    ADD CONSTRAINT "newsletter_tracking_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_logs"
    ADD CONSTRAINT "notification_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_client_category_unique" UNIQUE ("client_id", "category");



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_announcement_unique" UNIQUE ("client_id", "announcement_id");



ALTER TABLE ONLY "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_log_unique" UNIQUE ("client_id", "notification_log_id");



ALTER TABLE ONLY "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."operators"
    ADD CONSTRAINT "operators_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payout_rules"
    ADD CONSTRAINT "payout_rules_month_unique" UNIQUE ("month");



ALTER TABLE ONLY "public"."payout_rules"
    ADD CONSTRAINT "payout_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."plan_activities"
    ADD CONSTRAINT "plan_activities_pkey" PRIMARY KEY ("plan_id", "activity_id");



ALTER TABLE ONLY "public"."plans"
    ADD CONSTRAINT "plans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."practice_activities"
    ADD CONSTRAINT "practice_activities_pkey" PRIMARY KEY ("practice_id", "activity_id");



ALTER TABLE ONLY "public"."practice_blocks"
    ADD CONSTRAINT "practice_blocks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."practice_steps"
    ADD CONSTRAINT "practice_steps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."practice_user_state"
    ADD CONSTRAINT "practice_user_state_client_practice_unique" UNIQUE ("client_id", "practice_id");



ALTER TABLE ONLY "public"."practice_user_state"
    ADD CONSTRAINT "practice_user_state_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."practices"
    ADD CONSTRAINT "practices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."social_connections"
    ADD CONSTRAINT "social_connections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."social_connections"
    ADD CONSTRAINT "social_connections_unique" UNIQUE ("operator_id", "platform", "is_test");



ALTER TABLE ONLY "public"."subscription_usages"
    ADD CONSTRAINT "subscription_usages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."waitlist"
    ADD CONSTRAINT "waitlist_lesson_id_user_id_key" UNIQUE ("lesson_id", "user_id");



ALTER TABLE ONLY "public"."waitlist"
    ADD CONSTRAINT "waitlist_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "bookings_lesson_client_unique" ON "public"."bookings" USING "btree" ("lesson_id", "client_id") WHERE (("client_id" IS NOT NULL) AND ("status" = 'booked'::"public"."booking_status"));



CREATE INDEX "bug_reports_created_at_idx" ON "public"."bug_reports" USING "btree" ("created_at" DESC);



CREATE INDEX "bug_reports_created_by_client_id_idx" ON "public"."bug_reports" USING "btree" ("created_by_client_id");



CREATE INDEX "bug_reports_created_by_user_id_idx" ON "public"."bug_reports" USING "btree" ("created_by_user_id");



CREATE INDEX "bug_reports_deleted_at_idx" ON "public"."bug_reports" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "bug_reports_status_idx" ON "public"."bug_reports" USING "btree" ("status");



CREATE UNIQUE INDEX "clients_email_unique" ON "public"."clients" USING "btree" ("email") WHERE ("email" IS NOT NULL);



CREATE INDEX "expenses_activity_id_idx" ON "public"."expenses" USING "btree" ("activity_id") WHERE ("activity_id" IS NOT NULL);



CREATE INDEX "expenses_category_idx" ON "public"."expenses" USING "btree" ("category");



CREATE INDEX "expenses_event_id_idx" ON "public"."expenses" USING "btree" ("event_id") WHERE ("event_id" IS NOT NULL);



CREATE INDEX "expenses_expense_date_idx" ON "public"."expenses" USING "btree" ("expense_date");



CREATE INDEX "expenses_is_fixed_idx" ON "public"."expenses" USING "btree" ("is_fixed");



CREATE INDEX "expenses_lesson_id_idx" ON "public"."expenses" USING "btree" ("lesson_id") WHERE ("lesson_id" IS NOT NULL);



CREATE INDEX "expenses_operator_id_idx" ON "public"."expenses" USING "btree" ("operator_id") WHERE ("operator_id" IS NOT NULL);



CREATE INDEX "idx_activities_deleted_at_null" ON "public"."activities" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_announcements_active" ON "public"."announcements" USING "btree" ("is_active", "starts_at" DESC) WHERE ("is_active" = true);



CREATE INDEX "idx_announcements_dates" ON "public"."announcements" USING "btree" ("starts_at", "ends_at");



CREATE INDEX "idx_announcements_is_test" ON "public"."announcements" USING "btree" ("is_test");



CREATE INDEX "idx_announcements_marketing_campaign" ON "public"."announcements" USING "btree" ("marketing_campaign_id") WHERE ("marketing_campaign_id" IS NOT NULL);



CREATE INDEX "idx_announcements_test_client" ON "public"."announcements" USING "btree" ("test_client_id") WHERE ("test_client_id" IS NOT NULL);



CREATE INDEX "idx_auth_email_logs_created_at" ON "public"."auth_email_logs" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_auth_email_logs_email" ON "public"."auth_email_logs" USING "btree" ("email");



CREATE INDEX "idx_auth_email_logs_resend_id" ON "public"."auth_email_logs" USING "btree" ("resend_id") WHERE ("resend_id" IS NOT NULL);



CREATE INDEX "idx_auth_email_logs_status" ON "public"."auth_email_logs" USING "btree" ("status");



CREATE INDEX "idx_auth_email_logs_user_id" ON "public"."auth_email_logs" USING "btree" ("user_id");



CREATE UNIQUE INDEX "idx_booking_lesson_client_active" ON "public"."bookings" USING "btree" ("lesson_id", "client_id") WHERE (("status" = 'booked'::"public"."booking_status") AND ("client_id" IS NOT NULL));



CREATE INDEX "idx_bookings_client" ON "public"."bookings" USING "btree" ("client_id") WHERE ("client_id" IS NOT NULL);



CREATE INDEX "idx_bookings_client_id" ON "public"."bookings" USING "btree" ("client_id") WHERE ("client_id" IS NOT NULL);



CREATE INDEX "idx_bookings_lesson_status" ON "public"."bookings" USING "btree" ("lesson_id", "status");



CREATE INDEX "idx_campaign_analytics_campaign" ON "public"."campaign_analytics" USING "btree" ("campaign_id");



CREATE INDEX "idx_campaign_analytics_channel" ON "public"."campaign_analytics" USING "btree" ("channel");



CREATE INDEX "idx_campaign_contents_campaign" ON "public"."campaign_contents" USING "btree" ("campaign_id");



CREATE INDEX "idx_campaign_contents_meta_post" ON "public"."campaign_contents" USING "btree" ("meta_post_id") WHERE ("meta_post_id" IS NOT NULL);



CREATE INDEX "idx_campaign_contents_sequence" ON "public"."campaign_contents" USING "btree" ("campaign_id", "content_type", "sequence_index");



CREATE INDEX "idx_campaign_contents_social_connection" ON "public"."campaign_contents" USING "btree" ("social_connection_id") WHERE ("social_connection_id" IS NOT NULL);



CREATE INDEX "idx_campaign_contents_status" ON "public"."campaign_contents" USING "btree" ("status");



CREATE INDEX "idx_campaign_contents_type" ON "public"."campaign_contents" USING "btree" ("content_type");



CREATE INDEX "idx_campaigns_created_at" ON "public"."campaigns" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_campaigns_not_deleted" ON "public"."campaigns" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_campaigns_scheduled" ON "public"."campaigns" USING "btree" ("scheduled_for") WHERE (("scheduled_for" IS NOT NULL) AND ("status" = 'scheduled'::"public"."marketing_campaign_status"));



CREATE INDEX "idx_campaigns_status" ON "public"."campaigns" USING "btree" ("status");



CREATE INDEX "idx_campaigns_test_client" ON "public"."campaigns" USING "btree" ("test_client_id") WHERE ("test_client_id" IS NOT NULL);



CREATE INDEX "idx_campaigns_type" ON "public"."campaigns" USING "btree" ("type");



CREATE INDEX "idx_clients_deleted_at" ON "public"."clients" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_clients_email" ON "public"."clients" USING "btree" ("email");



CREATE INDEX "idx_clients_email_bounced" ON "public"."clients" USING "btree" ("email_bounced") WHERE ("email_bounced" = false);



CREATE INDEX "idx_clients_newsletter_subscribed" ON "public"."clients" USING "btree" ("newsletter_subscribed") WHERE ("newsletter_subscribed" = true);



CREATE INDEX "idx_clients_phone" ON "public"."clients" USING "btree" ("phone");



CREATE INDEX "idx_clients_profile_id" ON "public"."clients" USING "btree" ("profile_id");



CREATE INDEX "idx_device_tokens_client_id" ON "public"."device_tokens" USING "btree" ("client_id");



CREATE INDEX "idx_device_tokens_is_active" ON "public"."device_tokens" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_event_bookings_client" ON "public"."event_bookings" USING "btree" ("client_id") WHERE ("client_id" IS NOT NULL);



CREATE INDEX "idx_event_bookings_event" ON "public"."event_bookings" USING "btree" ("event_id");



CREATE INDEX "idx_event_bookings_status" ON "public"."event_bookings" USING "btree" ("status");



CREATE INDEX "idx_event_bookings_user" ON "public"."event_bookings" USING "btree" ("user_id");



CREATE INDEX "idx_events_deleted_at_null" ON "public"."events" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_events_is_active" ON "public"."events" USING "btree" ("is_active");



CREATE INDEX "idx_events_starts_at" ON "public"."events" USING "btree" ("starts_at");



CREATE INDEX "idx_journal_entries_client_id" ON "public"."journal_entries" USING "btree" ("client_id", "created_at" DESC);



CREATE INDEX "idx_journal_entries_practice_id" ON "public"."journal_entries" USING "btree" ("practice_id") WHERE ("practice_id" IS NOT NULL);



CREATE INDEX "idx_lessons_assigned_client_id" ON "public"."lessons" USING "btree" ("assigned_client_id") WHERE ("assigned_client_id" IS NOT NULL);



CREATE INDEX "idx_lessons_assigned_subscription_id" ON "public"."lessons" USING "btree" ("assigned_subscription_id") WHERE ("assigned_subscription_id" IS NOT NULL);



CREATE INDEX "idx_lessons_deleted_at_null" ON "public"."lessons" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_lessons_recurring_series_id" ON "public"."lessons" USING "btree" ("recurring_series_id");



CREATE INDEX "idx_lessons_starts_at" ON "public"."lessons" USING "btree" ("starts_at");



CREATE INDEX "idx_newsletter_campaigns_archived" ON "public"."newsletter_campaigns" USING "btree" ("archived");



CREATE INDEX "idx_newsletter_campaigns_created_at" ON "public"."newsletter_campaigns" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_newsletter_campaigns_deleted_at" ON "public"."newsletter_campaigns" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_newsletter_campaigns_marketing_campaign" ON "public"."newsletter_campaigns" USING "btree" ("marketing_campaign_id") WHERE ("marketing_campaign_id" IS NOT NULL);



CREATE INDEX "idx_newsletter_campaigns_status" ON "public"."newsletter_campaigns" USING "btree" ("status");



CREATE INDEX "idx_newsletter_emails_campaign_id" ON "public"."newsletter_emails" USING "btree" ("campaign_id");



CREATE INDEX "idx_newsletter_emails_client_id" ON "public"."newsletter_emails" USING "btree" ("client_id");



CREATE INDEX "idx_newsletter_emails_resend_id" ON "public"."newsletter_emails" USING "btree" ("resend_id") WHERE ("resend_id" IS NOT NULL);



CREATE INDEX "idx_newsletter_emails_status" ON "public"."newsletter_emails" USING "btree" ("status");



CREATE INDEX "idx_newsletter_extra_emails_deleted_at" ON "public"."newsletter_extra_emails" USING "btree" ("deleted_at");



CREATE INDEX "idx_newsletter_tracking_events_email_id" ON "public"."newsletter_tracking_events" USING "btree" ("email_id");



CREATE INDEX "idx_newsletter_tracking_events_type" ON "public"."newsletter_tracking_events" USING "btree" ("event_type");



CREATE INDEX "idx_notification_logs_category" ON "public"."notification_logs" USING "btree" ("category");



CREATE INDEX "idx_notification_logs_client_category_sent" ON "public"."notification_logs" USING "btree" ("client_id", "category", "sent_at" DESC);



CREATE INDEX "idx_notification_logs_client_id" ON "public"."notification_logs" USING "btree" ("client_id");



CREATE INDEX "idx_notification_logs_sent_at" ON "public"."notification_logs" USING "btree" ("sent_at" DESC);



CREATE INDEX "idx_notification_preferences_client_id" ON "public"."notification_preferences" USING "btree" ("client_id");



CREATE INDEX "idx_notification_queue_category" ON "public"."notification_queue" USING "btree" ("category");



CREATE INDEX "idx_notification_queue_client_id" ON "public"."notification_queue" USING "btree" ("client_id");



CREATE INDEX "idx_notification_queue_pending" ON "public"."notification_queue" USING "btree" ("scheduled_for", "status") WHERE ("status" = 'pending'::"public"."notification_status");



CREATE INDEX "idx_notification_reads_announcement" ON "public"."notification_reads" USING "btree" ("announcement_id") WHERE ("announcement_id" IS NOT NULL);



CREATE INDEX "idx_notification_reads_client" ON "public"."notification_reads" USING "btree" ("client_id");



CREATE INDEX "idx_notification_reads_log" ON "public"."notification_reads" USING "btree" ("notification_log_id") WHERE ("notification_log_id" IS NOT NULL);



CREATE INDEX "idx_operators_deleted_at_null" ON "public"."operators" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_plan_activities_activity" ON "public"."plan_activities" USING "btree" ("activity_id");



CREATE INDEX "idx_plan_activities_activity_id" ON "public"."plan_activities" USING "btree" ("activity_id");



CREATE INDEX "idx_plan_activities_plan" ON "public"."plan_activities" USING "btree" ("plan_id");



CREATE INDEX "idx_plan_activities_plan_id" ON "public"."plan_activities" USING "btree" ("plan_id");



CREATE INDEX "idx_plans_deleted_at_null" ON "public"."plans" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_practice_blocks_step_id" ON "public"."practice_blocks" USING "btree" ("step_id", "sort_order");



CREATE INDEX "idx_practice_steps_practice_id" ON "public"."practice_steps" USING "btree" ("practice_id", "sort_order");



CREATE INDEX "idx_practice_user_state_client_id" ON "public"."practice_user_state" USING "btree" ("client_id");



CREATE INDEX "idx_practice_user_state_favorites" ON "public"."practice_user_state" USING "btree" ("client_id") WHERE ("is_favorite" = true);



CREATE INDEX "idx_practices_active" ON "public"."practices" USING "btree" ("sort_order") WHERE (("is_active" = true) AND ("deleted_at" IS NULL));



CREATE INDEX "idx_practices_category" ON "public"."practices" USING "btree" ("category") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_practices_featured" ON "public"."practices" USING "btree" ("sort_order") WHERE (("is_featured" = true) AND ("is_active" = true) AND ("deleted_at" IS NULL));



CREATE INDEX "idx_profiles_deleted_at_null" ON "public"."profiles" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_profiles_role" ON "public"."profiles" USING "btree" ("role");



CREATE INDEX "idx_promotions_deleted_at_null" ON "public"."promotions" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_promotions_ends_at" ON "public"."promotions" USING "btree" ("ends_at");



CREATE INDEX "idx_promotions_is_active" ON "public"."promotions" USING "btree" ("is_active");



CREATE INDEX "idx_promotions_starts_at" ON "public"."promotions" USING "btree" ("starts_at");



CREATE INDEX "idx_social_connections_active" ON "public"."social_connections" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_social_connections_is_test" ON "public"."social_connections" USING "btree" ("is_test");



CREATE INDEX "idx_social_connections_operator" ON "public"."social_connections" USING "btree" ("operator_id");



CREATE INDEX "idx_subscription_usages_booking" ON "public"."subscription_usages" USING "btree" ("booking_id");



CREATE UNIQUE INDEX "idx_subscription_usages_booking_minus" ON "public"."subscription_usages" USING "btree" ("booking_id") WHERE (("delta" = '-1'::integer) AND ("booking_id" IS NOT NULL));



COMMENT ON INDEX "public"."idx_subscription_usages_booking_minus" IS 'Ensures only one delta=-1 (booking usage) per booking_id';



CREATE UNIQUE INDEX "idx_subscription_usages_booking_plus" ON "public"."subscription_usages" USING "btree" ("booking_id") WHERE (("delta" = (+ 1)) AND ("booking_id" IS NOT NULL));



COMMENT ON INDEX "public"."idx_subscription_usages_booking_plus" IS 'Ensures only one delta=+1 (cancel restore) per booking_id';



CREATE INDEX "idx_subscription_usages_subscription" ON "public"."subscription_usages" USING "btree" ("subscription_id");



CREATE INDEX "idx_subscriptions_client" ON "public"."subscriptions" USING "btree" ("client_id") WHERE ("client_id" IS NOT NULL);



CREATE INDEX "idx_subscriptions_deleted_at_null" ON "public"."subscriptions" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_waitlist_lesson" ON "public"."waitlist" USING "btree" ("lesson_id");



CREATE UNIQUE INDEX "newsletter_extra_emails_email_unique" ON "public"."newsletter_extra_emails" USING "btree" ("email") WHERE ("deleted_at" IS NULL);



CREATE INDEX "payout_rules_month_idx" ON "public"."payout_rules" USING "btree" ("month" DESC);



CREATE INDEX "payouts_month_idx" ON "public"."payouts" USING "btree" ("month" DESC);



CREATE INDEX "payouts_operator_id_idx" ON "public"."payouts" USING "btree" ("operator_id") WHERE ("operator_id" IS NOT NULL);



CREATE INDEX "payouts_status_idx" ON "public"."payouts" USING "btree" ("status");



CREATE OR REPLACE TRIGGER "announcements_notify_insert" AFTER INSERT ON "public"."announcements" FOR EACH ROW EXECUTE FUNCTION "public"."notify_new_announcement"();



COMMENT ON TRIGGER "announcements_notify_insert" ON "public"."announcements" IS 'Invia push notification automatica quando viene creato un nuovo announcement attivo.';



CREATE OR REPLACE TRIGGER "announcements_update_next_occurrence" BEFORE INSERT OR UPDATE ON "public"."announcements" FOR EACH ROW EXECUTE FUNCTION "public"."update_announcement_next_occurrence"();



CREATE OR REPLACE TRIGGER "announcements_updated_at" BEFORE UPDATE ON "public"."announcements" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "auth_email_logs_updated_at" BEFORE UPDATE ON "public"."auth_email_logs" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "bookings_check_milestone" AFTER UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."check_milestone_on_attended"();



CREATE OR REPLACE TRIGGER "bug_reports_updated_at" BEFORE UPDATE ON "public"."bug_reports" FOR EACH ROW EXECUTE FUNCTION "public"."update_bug_reports_updated_at"();



CREATE OR REPLACE TRIGGER "campaign_analytics_updated_at" BEFORE UPDATE ON "public"."campaign_analytics" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "campaign_contents_updated_at" BEFORE UPDATE ON "public"."campaign_contents" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "campaigns_updated_at" BEFORE UPDATE ON "public"."campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "device_tokens_updated_at" BEFORE UPDATE ON "public"."device_tokens" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "journal_entries_updated_at" BEFORE UPDATE ON "public"."journal_entries" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "newsletter_campaigns_updated_at" BEFORE UPDATE ON "public"."newsletter_campaigns" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "notification_preferences_updated_at" BEFORE UPDATE ON "public"."notification_preferences" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "practices_updated_at" BEFORE UPDATE ON "public"."practices" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "social_connections_updated_at" BEFORE UPDATE ON "public"."social_connections" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "sync_profile_on_client_change" AFTER INSERT OR UPDATE OF "full_name", "phone", "notes", "email", "profile_id" ON "public"."clients" FOR EACH ROW WHEN (("new"."profile_id" IS NOT NULL)) EXECUTE FUNCTION "public"."sync_profile_from_client"();



CREATE OR REPLACE TRIGGER "trg_link_client_to_profile_by_email" AFTER INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."link_client_to_profile_by_email"();



CREATE OR REPLACE TRIGGER "trigger_auto_complete_expired_subscriptions" BEFORE INSERT OR UPDATE ON "public"."subscriptions" FOR EACH ROW EXECUTE FUNCTION "public"."auto_complete_expired_subscriptions"();



CREATE OR REPLACE TRIGGER "trigger_auto_create_booking_individual_lesson" AFTER INSERT ON "public"."lessons" FOR EACH ROW WHEN ((("new"."is_individual" = true) AND ("new"."assigned_client_id" IS NOT NULL))) EXECUTE FUNCTION "public"."auto_create_booking_for_individual_lesson"();



CREATE OR REPLACE TRIGGER "trigger_ensure_subscription_canceled_on_deleted_at" BEFORE UPDATE ON "public"."subscriptions" FOR EACH ROW WHEN (("new"."deleted_at" IS DISTINCT FROM "old"."deleted_at")) EXECUTE FUNCTION "public"."ensure_subscription_canceled_on_deleted_at"();



CREATE OR REPLACE TRIGGER "trigger_ensure_subscription_canceled_on_deleted_at_insert" BEFORE INSERT ON "public"."subscriptions" FOR EACH ROW WHEN (("new"."deleted_at" IS NOT NULL)) EXECUTE FUNCTION "public"."ensure_subscription_canceled_on_deleted_at"();



CREATE OR REPLACE TRIGGER "trigger_handle_individual_lesson_update" BEFORE UPDATE ON "public"."lessons" FOR EACH ROW WHEN ((("old"."is_individual" IS DISTINCT FROM "new"."is_individual") OR ("old"."assigned_client_id" IS DISTINCT FROM "new"."assigned_client_id") OR ("old"."assigned_subscription_id" IS DISTINCT FROM "new"."assigned_subscription_id"))) EXECUTE FUNCTION "public"."handle_individual_lesson_update"();



CREATE OR REPLACE TRIGGER "trigger_restore_subscription_entry_on_booking_cancel" AFTER UPDATE OF "status" ON "public"."bookings" FOR EACH ROW WHEN ((("old"."status" = 'booked'::"public"."booking_status") AND ("new"."status" = 'canceled'::"public"."booking_status"))) EXECUTE FUNCTION "public"."restore_subscription_entry_on_booking_cancel"();



CREATE OR REPLACE TRIGGER "trigger_update_activity_slug" BEFORE INSERT OR UPDATE OF "discipline" ON "public"."activities" FOR EACH ROW EXECUTE FUNCTION "public"."update_activity_slug"();



CREATE OR REPLACE TRIGGER "trigger_update_subscription_status_on_usage" AFTER INSERT ON "public"."subscription_usages" FOR EACH ROW EXECUTE FUNCTION "public"."update_subscription_status_on_usage"();



CREATE OR REPLACE TRIGGER "trigger_update_subscription_status_on_usage_delete" AFTER DELETE ON "public"."subscription_usages" FOR EACH ROW EXECUTE FUNCTION "public"."update_subscription_status_on_usage_after_delete"();



CREATE OR REPLACE TRIGGER "update_activities_updated_at" BEFORE UPDATE ON "public"."activities" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_clients_updated_at" BEFORE UPDATE ON "public"."clients" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_event_bookings_updated_at" BEFORE UPDATE ON "public"."event_bookings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_events_updated_at" BEFORE UPDATE ON "public"."events" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_promotions_updated_at" BEFORE UPDATE ON "public"."promotions" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."announcements"
    ADD CONSTRAINT "announcements_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."announcements"
    ADD CONSTRAINT "announcements_marketing_campaign_id_fkey" FOREIGN KEY ("marketing_campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."announcements"
    ADD CONSTRAINT "announcements_test_client_id_fkey" FOREIGN KEY ("test_client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_subscription_id_fkey" FOREIGN KEY ("subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bug_reports"
    ADD CONSTRAINT "bug_reports_created_by_client_id_fkey" FOREIGN KEY ("created_by_client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bug_reports"
    ADD CONSTRAINT "bug_reports_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_analytics"
    ADD CONSTRAINT "campaign_analytics_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_analytics"
    ADD CONSTRAINT "campaign_analytics_content_id_fkey" FOREIGN KEY ("content_id") REFERENCES "public"."campaign_contents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_contents"
    ADD CONSTRAINT "campaign_contents_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."campaign_contents"
    ADD CONSTRAINT "campaign_contents_newsletter_campaign_id_fkey" FOREIGN KEY ("newsletter_campaign_id") REFERENCES "public"."newsletter_campaigns"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaign_contents"
    ADD CONSTRAINT "campaign_contents_social_connection_id_fkey" FOREIGN KEY ("social_connection_id") REFERENCES "public"."social_connections"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."campaigns"
    ADD CONSTRAINT "campaigns_test_client_id_fkey" FOREIGN KEY ("test_client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_bookings"
    ADD CONSTRAINT "event_bookings_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."event_bookings"
    ADD CONSTRAINT "event_bookings_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_bookings"
    ADD CONSTRAINT "event_bookings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."journal_entries"
    ADD CONSTRAINT "journal_entries_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."journal_entries"
    ADD CONSTRAINT "journal_entries_practice_id_fkey" FOREIGN KEY ("practice_id") REFERENCES "public"."practices"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_assigned_client_id_fkey" FOREIGN KEY ("assigned_client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_assigned_subscription_id_fkey" FOREIGN KEY ("assigned_subscription_id") REFERENCES "public"."subscriptions"("id");



ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."newsletter_campaigns"
    ADD CONSTRAINT "newsletter_campaigns_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."newsletter_campaigns"
    ADD CONSTRAINT "newsletter_campaigns_marketing_campaign_id_fkey" FOREIGN KEY ("marketing_campaign_id") REFERENCES "public"."campaigns"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."newsletter_emails"
    ADD CONSTRAINT "newsletter_emails_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "public"."newsletter_campaigns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."newsletter_emails"
    ADD CONSTRAINT "newsletter_emails_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."newsletter_tracking_events"
    ADD CONSTRAINT "newsletter_tracking_events_email_id_fkey" FOREIGN KEY ("email_id") REFERENCES "public"."newsletter_emails"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_logs"
    ADD CONSTRAINT "notification_logs_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_announcement_id_fkey" FOREIGN KEY ("announcement_id") REFERENCES "public"."announcements"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_notification_log_id_fkey" FOREIGN KEY ("notification_log_id") REFERENCES "public"."notification_logs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."operators"
    ADD CONSTRAINT "operators_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."payout_rules"
    ADD CONSTRAINT "payout_rules_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."plan_activities"
    ADD CONSTRAINT "plan_activities_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."plan_activities"
    ADD CONSTRAINT "plan_activities_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."practice_activities"
    ADD CONSTRAINT "practice_activities_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."practice_activities"
    ADD CONSTRAINT "practice_activities_practice_id_fkey" FOREIGN KEY ("practice_id") REFERENCES "public"."practices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."practice_blocks"
    ADD CONSTRAINT "practice_blocks_step_id_fkey" FOREIGN KEY ("step_id") REFERENCES "public"."practice_steps"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."practice_steps"
    ADD CONSTRAINT "practice_steps_practice_id_fkey" FOREIGN KEY ("practice_id") REFERENCES "public"."practices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."practice_user_state"
    ADD CONSTRAINT "practice_user_state_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."practice_user_state"
    ADD CONSTRAINT "practice_user_state_practice_id_fkey" FOREIGN KEY ("practice_id") REFERENCES "public"."practices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id");



ALTER TABLE ONLY "public"."social_connections"
    ADD CONSTRAINT "social_connections_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subscription_usages"
    ADD CONSTRAINT "subscription_usages_subscription_id_fkey" FOREIGN KEY ("subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id");



ALTER TABLE ONLY "public"."waitlist"
    ADD CONSTRAINT "waitlist_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."waitlist"
    ADD CONSTRAINT "waitlist_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



CREATE POLICY "Clients can view their lessons" ON "public"."lessons" FOR SELECT TO "authenticated" USING (("public"."is_staff"() OR (("is_individual" = false) AND ("deleted_at" IS NULL)) OR (("is_individual" = true) AND ("assigned_client_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."clients"
  WHERE (("clients"."id" = "lessons"."assigned_client_id") AND ("clients"."profile_id" = "auth"."uid"()) AND ("clients"."deleted_at" IS NULL)))))));



COMMENT ON POLICY "Clients can view their lessons" ON "public"."lessons" IS 'RLS: I clienti possono vedere solo lezioni pubbliche (non individuali) o lezioni individuali assegnate a loro. Esclude automaticamente lezioni soft-deleted.';



CREATE POLICY "Only staff can manage lessons" ON "public"."lessons" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



CREATE POLICY "Staff can delete extra emails" ON "public"."newsletter_extra_emails" FOR DELETE TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "Staff can insert extra emails" ON "public"."newsletter_extra_emails" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());



CREATE POLICY "Staff can update extra emails" ON "public"."newsletter_extra_emails" FOR UPDATE TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



CREATE POLICY "Staff can view extra emails" ON "public"."newsletter_extra_emails" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



ALTER TABLE "public"."activities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "activities_select_public" ON "public"."activities" FOR SELECT USING (true);



CREATE POLICY "activities_write_staff" ON "public"."activities" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."announcements" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "announcements_select_active" ON "public"."announcements" FOR SELECT TO "authenticated" USING ((("is_active" = true) AND ("starts_at" <= "now"()) AND (("ends_at" IS NULL) OR ("ends_at" > "now"()))));



CREATE POLICY "announcements_service_all" ON "public"."announcements" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "announcements_staff_all" ON "public"."announcements" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."auth_email_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "auth_email_logs_service_all" ON "public"."auth_email_logs" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "auth_email_logs_staff_select" ON "public"."auth_email_logs" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



ALTER TABLE "public"."bookings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bookings_insert_own_or_staff" ON "public"."bookings" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_staff"() OR ("client_id" = "public"."get_my_client_id"())));



COMMENT ON POLICY "bookings_insert_own_or_staff" ON "public"."bookings" IS 'RLS: Permette INSERT solo delle proprie prenotazioni (client_id = get_my_client_id()) o se staff.';



CREATE POLICY "bookings_select_own_or_staff" ON "public"."bookings" FOR SELECT TO "authenticated" USING (("public"."is_staff"() OR ("client_id" = "public"."get_my_client_id"())));



COMMENT ON POLICY "bookings_select_own_or_staff" ON "public"."bookings" IS 'RLS: Permette SELECT solo delle proprie prenotazioni (client_id = get_my_client_id()) o se staff.';



CREATE POLICY "bookings_update_own_or_staff" ON "public"."bookings" FOR UPDATE TO "authenticated" USING (("public"."is_staff"() OR ("client_id" = "public"."get_my_client_id"()))) WITH CHECK (("public"."is_staff"() OR (("client_id" = "public"."get_my_client_id"()) AND ("status" = 'canceled'::"public"."booking_status"))));



COMMENT ON POLICY "bookings_update_own_or_staff" ON "public"."bookings" IS 'RLS: Permette UPDATE solo delle proprie prenotazioni (client_id = get_my_client_id()) o se staff. Gli utenti possono solo cancellare (status = canceled).';



ALTER TABLE "public"."bug_reports" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bug_reports_delete_admin" ON "public"."bug_reports" FOR DELETE TO "authenticated" USING ("public"."is_admin"());



COMMENT ON POLICY "bug_reports_delete_admin" ON "public"."bug_reports" IS 'RLS: Solo admin può fare soft delete dei bug.';



CREATE POLICY "bug_reports_insert_authenticated" ON "public"."bug_reports" FOR INSERT TO "authenticated" WITH CHECK (((("created_by_user_id" = "auth"."uid"()) AND ("created_by_client_id" IS NULL)) OR ("public"."is_staff"() AND ("created_by_user_id" IS NULL) AND ("created_by_client_id" IS NOT NULL)) OR ("public"."is_staff"() AND ("created_by_user_id" = "auth"."uid"()) AND ("created_by_client_id" IS NULL))));



COMMENT ON POLICY "bug_reports_insert_authenticated" ON "public"."bug_reports" IS 'RLS: Permette INSERT a tutti gli utenti autenticati. Clienti usano user_id, staff può usare client_id.';



CREATE POLICY "bug_reports_select_own_or_admin" ON "public"."bug_reports" FOR SELECT TO "authenticated" USING (("public"."is_admin"() OR (("deleted_at" IS NULL) AND ("created_by_user_id" = "auth"."uid"()) AND ("created_by_client_id" IS NULL))));



CREATE POLICY "bug_reports_update_admin" ON "public"."bug_reports" FOR UPDATE TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."campaign_analytics" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaign_analytics_service" ON "public"."campaign_analytics" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "campaign_analytics_staff_select" ON "public"."campaign_analytics" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



ALTER TABLE "public"."campaign_contents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaign_contents_service" ON "public"."campaign_contents" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "campaign_contents_staff_delete" ON "public"."campaign_contents" FOR DELETE TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "campaign_contents_staff_insert" ON "public"."campaign_contents" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());



CREATE POLICY "campaign_contents_staff_select" ON "public"."campaign_contents" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "campaign_contents_staff_update" ON "public"."campaign_contents" FOR UPDATE TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."campaigns" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campaigns_service" ON "public"."campaigns" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "campaigns_staff_delete" ON "public"."campaigns" FOR DELETE TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "campaigns_staff_insert" ON "public"."campaigns" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());



CREATE POLICY "campaigns_staff_select" ON "public"."campaigns" FOR SELECT TO "authenticated" USING (("public"."is_staff"() AND ("deleted_at" IS NULL)));



CREATE POLICY "campaigns_staff_update" ON "public"."campaigns" FOR UPDATE TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."clients" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "clients_anon_select" ON "public"."clients" FOR SELECT TO "anon" USING (true);



CREATE POLICY "clients_delete_staff" ON "public"."clients" FOR DELETE TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "clients_insert_staff" ON "public"."clients" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());



CREATE POLICY "clients_select_staff" ON "public"."clients" FOR SELECT TO "authenticated" USING (("public"."is_staff"() OR ("profile_id" = "auth"."uid"())));



CREATE POLICY "clients_update_staff" ON "public"."clients" FOR UPDATE TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."device_tokens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_tokens_anon_all" ON "public"."device_tokens" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "device_tokens_delete_own" ON "public"."device_tokens" FOR DELETE TO "authenticated" USING (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "device_tokens_insert_own" ON "public"."device_tokens" FOR INSERT TO "authenticated" WITH CHECK (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "device_tokens_select_own" ON "public"."device_tokens" FOR SELECT TO "authenticated" USING (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "device_tokens_select_staff" ON "public"."device_tokens" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



COMMENT ON POLICY "device_tokens_select_staff" ON "public"."device_tokens" IS 'Permette allo staff (operator, admin, finance) di vedere tutti i device tokens per il gestionale';



CREATE POLICY "device_tokens_update_own" ON "public"."device_tokens" FOR UPDATE TO "authenticated" USING (("client_id" = "public"."get_my_client_id"())) WITH CHECK (("client_id" = "public"."get_my_client_id"()));



ALTER TABLE "public"."event_bookings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "event_bookings_delete_staff" ON "public"."event_bookings" FOR DELETE TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "event_bookings_insert_own_or_staff" ON "public"."event_bookings" FOR INSERT TO "authenticated" WITH CHECK (("public"."is_staff"() OR (("user_id" = "auth"."uid"()) AND ("client_id" IS NULL)) OR (("client_id" = "public"."get_my_client_id"()) AND ("user_id" IS NULL))));



COMMENT ON POLICY "event_bookings_insert_own_or_staff" ON "public"."event_bookings" IS 'RLS: Permette INSERT solo delle proprie prenotazioni (user_id = auth.uid() o client_id = get_my_client_id()) o se staff.';



CREATE POLICY "event_bookings_select_own_or_staff" ON "public"."event_bookings" FOR SELECT TO "authenticated" USING (("public"."is_staff"() OR ("user_id" = "auth"."uid"()) OR ("client_id" = "public"."get_my_client_id"())));



COMMENT ON POLICY "event_bookings_select_own_or_staff" ON "public"."event_bookings" IS 'RLS: Permette SELECT solo delle proprie prenotazioni (user_id = auth.uid() o client_id = get_my_client_id()) o se staff.';



CREATE POLICY "event_bookings_update_own_or_staff" ON "public"."event_bookings" FOR UPDATE TO "authenticated" USING (("public"."is_staff"() OR ("user_id" = "auth"."uid"()) OR ("client_id" = "public"."get_my_client_id"()))) WITH CHECK (("public"."is_staff"() OR ((("user_id" = "auth"."uid"()) OR ("client_id" = "public"."get_my_client_id"())) AND ("status" = 'canceled'::"public"."booking_status"))));



COMMENT ON POLICY "event_bookings_update_own_or_staff" ON "public"."event_bookings" IS 'RLS: Permette UPDATE solo delle proprie prenotazioni o se staff. Gli utenti possono solo cancellare (status = canceled).';



ALTER TABLE "public"."events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "events_select_public_active" ON "public"."events" FOR SELECT USING ((("is_active" IS TRUE) AND ("deleted_at" IS NULL)));



CREATE POLICY "events_select_public_for_site_view" ON "public"."events" FOR SELECT TO "anon" USING (("deleted_at" IS NULL));



COMMENT ON POLICY "events_select_public_for_site_view" ON "public"."events" IS 'RLS: Permette accesso anonimo a TUTTI gli eventi non soft-deleted per la vista public_site_events. 
   Non filtra per is_active o per data (starts_at/ends_at), permettendo di mostrare sia eventi 
   passati che futuri.';



CREATE POLICY "events_write_staff" ON "public"."events" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."expenses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "expenses_delete_admin" ON "public"."expenses" FOR DELETE TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "expenses_insert_finance_admin" ON "public"."expenses" FOR INSERT TO "authenticated" WITH CHECK ("public"."can_access_finance"());



CREATE POLICY "expenses_select_finance_admin" ON "public"."expenses" FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());



CREATE POLICY "expenses_update_finance_admin" ON "public"."expenses" FOR UPDATE TO "authenticated" USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());



ALTER TABLE "public"."journal_entries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "journal_entries_delete_own" ON "public"."journal_entries" FOR DELETE TO "authenticated" USING (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "journal_entries_insert_own" ON "public"."journal_entries" FOR INSERT TO "authenticated" WITH CHECK (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "journal_entries_select_own" ON "public"."journal_entries" FOR SELECT TO "authenticated" USING (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "journal_entries_service_all" ON "public"."journal_entries" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "journal_entries_update_own" ON "public"."journal_entries" FOR UPDATE TO "authenticated" USING (("client_id" = "public"."get_my_client_id"())) WITH CHECK (("client_id" = "public"."get_my_client_id"()));



ALTER TABLE "public"."lessons" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lessons_select_public_active" ON "public"."lessons" FOR SELECT USING ((("deleted_at" IS NULL) AND ("is_individual" = false)));



COMMENT ON POLICY "lessons_select_public_active" ON "public"."lessons" IS 'RLS: Accesso pubblico (anon) solo a lezioni pubbliche (non individuali) non soft-deleted. Le lezioni individuali sono accessibili solo tramite "Clients can view their lessons" (staff o assegnatari).';



CREATE POLICY "lessons_write_staff" ON "public"."lessons" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."newsletter_campaigns" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "newsletter_campaigns_delete_staff" ON "public"."newsletter_campaigns" FOR DELETE TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "newsletter_campaigns_insert_staff" ON "public"."newsletter_campaigns" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());



CREATE POLICY "newsletter_campaigns_select_staff" ON "public"."newsletter_campaigns" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "newsletter_campaigns_update_staff" ON "public"."newsletter_campaigns" FOR UPDATE TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."newsletter_emails" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "newsletter_emails_all_service" ON "public"."newsletter_emails" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "newsletter_emails_select_staff" ON "public"."newsletter_emails" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



ALTER TABLE "public"."newsletter_extra_emails" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."newsletter_tracking_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "newsletter_tracking_events_all_service" ON "public"."newsletter_tracking_events" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "newsletter_tracking_events_select_staff" ON "public"."newsletter_tracking_events" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



ALTER TABLE "public"."notification_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_logs_anon_all" ON "public"."notification_logs" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "notification_logs_select_own" ON "public"."notification_logs" FOR SELECT TO "authenticated" USING (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "notification_logs_select_staff" ON "public"."notification_logs" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



ALTER TABLE "public"."notification_preferences" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_preferences_insert_own" ON "public"."notification_preferences" FOR INSERT TO "authenticated" WITH CHECK (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "notification_preferences_select_own" ON "public"."notification_preferences" FOR SELECT TO "authenticated" USING (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "notification_preferences_service_all" ON "public"."notification_preferences" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "notification_preferences_update_own" ON "public"."notification_preferences" FOR UPDATE TO "authenticated" USING (("client_id" = "public"."get_my_client_id"())) WITH CHECK (("client_id" = "public"."get_my_client_id"()));



ALTER TABLE "public"."notification_queue" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_reads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_reads_delete_own" ON "public"."notification_reads" FOR DELETE TO "authenticated" USING (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "notification_reads_insert_own" ON "public"."notification_reads" FOR INSERT TO "authenticated" WITH CHECK (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "notification_reads_select_own" ON "public"."notification_reads" FOR SELECT TO "authenticated" USING (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "notification_reads_service_all" ON "public"."notification_reads" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."operators" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "operators_select_public_active" ON "public"."operators" FOR SELECT USING (("is_active" IS TRUE));



CREATE POLICY "operators_write_admin" ON "public"."operators" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."payout_rules" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "payout_rules_delete_admin" ON "public"."payout_rules" FOR DELETE TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "payout_rules_insert_finance_admin" ON "public"."payout_rules" FOR INSERT TO "authenticated" WITH CHECK ("public"."can_access_finance"());



CREATE POLICY "payout_rules_select_finance_admin" ON "public"."payout_rules" FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());



CREATE POLICY "payout_rules_update_finance_admin" ON "public"."payout_rules" FOR UPDATE TO "authenticated" USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());



ALTER TABLE "public"."payouts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "payouts_delete_admin" ON "public"."payouts" FOR DELETE TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "payouts_insert_finance_admin" ON "public"."payouts" FOR INSERT TO "authenticated" WITH CHECK ("public"."can_access_finance"());



CREATE POLICY "payouts_select_finance_admin" ON "public"."payouts" FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());



CREATE POLICY "payouts_update_finance_admin" ON "public"."payouts" FOR UPDATE TO "authenticated" USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());



ALTER TABLE "public"."plan_activities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "plan_activities_select_public" ON "public"."plan_activities" FOR SELECT USING (true);



CREATE POLICY "plan_activities_write_staff" ON "public"."plan_activities" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."plans" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "plans_select_own_subscription" ON "public"."plans" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."subscriptions" "s"
     JOIN "public"."clients" "c" ON (("s"."client_id" = "c"."id")))
  WHERE (("s"."plan_id" = "plans"."id") AND ("c"."profile_id" = "auth"."uid"())))));



COMMENT ON POLICY "plans_select_own_subscription" ON "public"."plans" IS 'Allows authenticated users to read plans linked to their own subscriptions, even if the plan is inactive';



CREATE POLICY "plans_select_public_active" ON "public"."plans" FOR SELECT USING ((("is_active" IS TRUE) AND ("deleted_at" IS NULL)));



CREATE POLICY "plans_write_staff" ON "public"."plans" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."practice_activities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "practice_activities_select_active" ON "public"."practice_activities" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."practices" "p"
  WHERE (("p"."id" = "practice_activities"."practice_id") AND ("p"."is_active" = true) AND ("p"."deleted_at" IS NULL)))));



CREATE POLICY "practice_activities_service_all" ON "public"."practice_activities" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "practice_activities_staff_all" ON "public"."practice_activities" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."practice_blocks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "practice_blocks_select_active" ON "public"."practice_blocks" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."practice_steps" "ps"
     JOIN "public"."practices" "p" ON (("p"."id" = "ps"."practice_id")))
  WHERE (("ps"."id" = "practice_blocks"."step_id") AND ("p"."is_active" = true) AND ("p"."deleted_at" IS NULL)))));



CREATE POLICY "practice_blocks_service_all" ON "public"."practice_blocks" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "practice_blocks_staff_all" ON "public"."practice_blocks" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."practice_steps" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "practice_steps_select_active" ON "public"."practice_steps" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."practices" "p"
  WHERE (("p"."id" = "practice_steps"."practice_id") AND ("p"."is_active" = true) AND ("p"."deleted_at" IS NULL)))));



CREATE POLICY "practice_steps_service_all" ON "public"."practice_steps" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "practice_steps_staff_all" ON "public"."practice_steps" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."practice_user_state" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "practice_user_state_insert_own" ON "public"."practice_user_state" FOR INSERT TO "authenticated" WITH CHECK (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "practice_user_state_select_own" ON "public"."practice_user_state" FOR SELECT TO "authenticated" USING (("client_id" = "public"."get_my_client_id"()));



CREATE POLICY "practice_user_state_service_all" ON "public"."practice_user_state" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "practice_user_state_staff_select" ON "public"."practice_user_state" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



CREATE POLICY "practice_user_state_update_own" ON "public"."practice_user_state" FOR UPDATE TO "authenticated" USING (("client_id" = "public"."get_my_client_id"())) WITH CHECK (("client_id" = "public"."get_my_client_id"()));



ALTER TABLE "public"."practices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "practices_select_active" ON "public"."practices" FOR SELECT TO "authenticated" USING ((("is_active" = true) AND ("deleted_at" IS NULL)));



CREATE POLICY "practices_service_all" ON "public"."practices" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "practices_staff_all" ON "public"."practices" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles insert staff" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());



CREATE POLICY "profiles_select_own_or_staff" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("id" = "auth"."uid"()) OR "public"."is_staff"() OR (EXISTS ( SELECT 1
   FROM ("public"."clients" "c"
     JOIN "public"."bookings" "b" ON (("b"."client_id" = "c"."id")))
  WHERE (("c"."profile_id" = "profiles"."id") AND ("c"."profile_id" = "auth"."uid"()))))));



COMMENT ON POLICY "profiles_select_own_or_staff" ON "public"."profiles" IS 'RLS: Permette SELECT del proprio profilo, staff, o profili collegati a bookings tramite client_id.';



CREATE POLICY "profiles_update_own_or_staff" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ((("id" = "auth"."uid"()) OR "public"."is_staff"())) WITH CHECK ((("id" = "auth"."uid"()) OR "public"."is_staff"()));



ALTER TABLE "public"."promotions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "promotions_select_public_active_now" ON "public"."promotions" FOR SELECT USING ((("is_active" IS TRUE) AND ("deleted_at" IS NULL) AND ("starts_at" <= "now"()) AND (("ends_at" IS NULL) OR ("ends_at" >= "now"()))));



CREATE POLICY "promotions_write_staff" ON "public"."promotions" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."social_connections" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "social_connections_own_delete" ON "public"."social_connections" FOR DELETE TO "authenticated" USING (("public"."is_staff"() AND ("operator_id" = "auth"."uid"())));



CREATE POLICY "social_connections_own_update" ON "public"."social_connections" FOR UPDATE TO "authenticated" USING (("public"."is_staff"() AND ("operator_id" = "auth"."uid"()))) WITH CHECK (("public"."is_staff"() AND ("operator_id" = "auth"."uid"())));



CREATE POLICY "social_connections_service" ON "public"."social_connections" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "social_connections_staff_insert" ON "public"."social_connections" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());



CREATE POLICY "social_connections_staff_select" ON "public"."social_connections" FOR SELECT TO "authenticated" USING ("public"."is_staff"());



ALTER TABLE "public"."subscription_usages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "subscription_usages_select_own_or_staff" ON "public"."subscription_usages" FOR SELECT TO "authenticated" USING (("public"."is_staff"() OR (EXISTS ( SELECT 1
   FROM "public"."subscriptions" "s"
  WHERE (("s"."id" = "subscription_usages"."subscription_id") AND ("s"."client_id" = "public"."get_my_client_id"()))))));



COMMENT ON POLICY "subscription_usages_select_own_or_staff" ON "public"."subscription_usages" IS 'RLS: Permette SELECT solo degli usages collegati a subscriptions proprie (client_id = get_my_client_id()) o se staff.';



CREATE POLICY "subscription_usages_write_staff" ON "public"."subscription_usages" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



COMMENT ON POLICY "subscription_usages_write_staff" ON "public"."subscription_usages" IS 'RLS: Solo staff può scrivere subscription_usages. Gli utenti non possono modificare direttamente gli usi: devono usare RPC (book_lesson, cancel_booking) che gestiscono automaticamente gli usi.';



ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "subscriptions_select_own_or_staff" ON "public"."subscriptions" FOR SELECT TO "authenticated" USING (("public"."is_staff"() OR ("client_id" = "public"."get_my_client_id"())));



COMMENT ON POLICY "subscriptions_select_own_or_staff" ON "public"."subscriptions" IS 'RLS: Permette SELECT solo delle proprie subscriptions (client_id = get_my_client_id()) o se staff.';



CREATE POLICY "subscriptions_write_staff" ON "public"."subscriptions" TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());



ALTER TABLE "public"."waitlist" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "waitlist_delete_own_or_staff" ON "public"."waitlist" FOR DELETE TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_staff"()));



CREATE POLICY "waitlist_insert_own" ON "public"."waitlist" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "waitlist_select_own_or_staff" ON "public"."waitlist" FOR SELECT TO "authenticated" USING ((("user_id" = "auth"."uid"()) OR "public"."is_staff"()));



REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT ALL ON SCHEMA "public" TO "anon";
GRANT ALL ON SCHEMA "public" TO "authenticated";
GRANT ALL ON SCHEMA "public" TO "service_role";
GRANT ALL ON SCHEMA "public" TO PUBLIC;



GRANT ALL ON TYPE "public"."bug_status" TO "authenticated";



GRANT ALL ON FUNCTION "public"."book_event"("p_event_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."calculate_operator_compensation"("p_month_start" "date", "p_month_end" "date", "p_operator_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."cancel_event_booking"("p_booking_id" "uuid") TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."profiles" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_user_profile"("user_id" "uuid", "full_name" "text", "phone" "text", "role" "public"."user_role") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_user_profile"("user_id" "uuid", "full_name" "text", "phone" "text", "role" "public"."user_role") TO "authenticated";



GRANT ALL ON FUNCTION "public"."delete_campaign"("campaign_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_activity_booking_counts"() TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_auth_email_stats"("p_user_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_event_booking_count"("p_event_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_events_booking_counts"("p_event_ids" "uuid"[]) TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_financial_kpis"("p_month_start" "date", "p_month_end" "date") TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_monthly_revenue_by_client"("p_month_start" "date", "p_month_end" "date") TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_monthly_revenue_by_plan"("p_month_start" "date", "p_month_end" "date") TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_revenue_breakdown"("p_month_start" "date", "p_month_end" "date") TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_unread_notifications_count"() TO "authenticated";



GRANT ALL ON FUNCTION "public"."is_staff"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_staff"() TO "anon";



GRANT ALL ON FUNCTION "public"."mark_all_notifications_read"() TO "authenticated";



GRANT ALL ON FUNCTION "public"."mark_notification_read"("p_notification_log_id" "uuid", "p_announcement_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text", "p_scheduled_for" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."queue_announcement"("p_announcement_id" "uuid", "p_title" "text", "p_body" "text", "p_scheduled_for" timestamp with time zone, "p_is_test" boolean, "p_test_client_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."staff_book_event"("p_event_id" "uuid", "p_client_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."staff_cancel_event_booking"("p_booking_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."staff_get_user_email_status"("p_user_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."staff_update_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status") TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."activities" TO "authenticated";
GRANT SELECT ON TABLE "public"."activities" TO "service_role";
GRANT SELECT ON TABLE "public"."activities" TO "anon";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."announcements" TO "authenticated";
GRANT SELECT ON TABLE "public"."announcements" TO "anon";
GRANT ALL ON TABLE "public"."announcements" TO "service_role";



GRANT SELECT ON TABLE "public"."auth_email_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."auth_email_logs" TO "service_role";



GRANT SELECT ON TABLE "public"."bookings" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."bug_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."bug_reports" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_analytics" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_analytics" TO "service_role";



GRANT ALL ON TABLE "public"."campaign_contents" TO "authenticated";
GRANT ALL ON TABLE "public"."campaign_contents" TO "service_role";



GRANT ALL ON TABLE "public"."campaigns" TO "authenticated";
GRANT ALL ON TABLE "public"."campaigns" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."clients" TO "authenticated";
GRANT SELECT ON TABLE "public"."clients" TO "anon";
GRANT SELECT ON TABLE "public"."clients" TO "service_role";



GRANT ALL ON TABLE "public"."device_tokens" TO "anon";
GRANT ALL ON TABLE "public"."device_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."device_tokens" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."event_bookings" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."events" TO "authenticated";
GRANT SELECT ON TABLE "public"."events" TO "anon";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."expenses" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."lessons" TO "authenticated";
GRANT SELECT ON TABLE "public"."lessons" TO "service_role";
GRANT SELECT ON TABLE "public"."lessons" TO "anon";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."plans" TO "authenticated";
GRANT SELECT ON TABLE "public"."plans" TO "anon";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."subscriptions" TO "authenticated";



GRANT SELECT ON TABLE "public"."financial_monthly_summary" TO "authenticated";



GRANT ALL ON TABLE "public"."journal_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."journal_entries" TO "service_role";



GRANT SELECT ON TABLE "public"."lesson_occupancy" TO "anon";
GRANT SELECT ON TABLE "public"."lesson_occupancy" TO "authenticated";



GRANT ALL ON TABLE "public"."newsletter_campaigns" TO "authenticated";
GRANT ALL ON TABLE "public"."newsletter_campaigns" TO "service_role";



GRANT ALL ON TABLE "public"."newsletter_emails" TO "authenticated";
GRANT ALL ON TABLE "public"."newsletter_emails" TO "service_role";



GRANT ALL ON TABLE "public"."newsletter_extra_emails" TO "authenticated";
GRANT ALL ON TABLE "public"."newsletter_extra_emails" TO "service_role";



GRANT ALL ON TABLE "public"."newsletter_tracking_events" TO "authenticated";
GRANT ALL ON TABLE "public"."newsletter_tracking_events" TO "service_role";



GRANT ALL ON TABLE "public"."notification_logs" TO "anon";
GRANT ALL ON TABLE "public"."notification_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_logs" TO "service_role";



GRANT ALL ON TABLE "public"."notification_preferences" TO "anon";
GRANT ALL ON TABLE "public"."notification_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_preferences" TO "service_role";



GRANT ALL ON TABLE "public"."notification_queue" TO "anon";
GRANT ALL ON TABLE "public"."notification_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_queue" TO "service_role";



GRANT SELECT,INSERT,DELETE ON TABLE "public"."notification_reads" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_reads" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."operators" TO "authenticated";
GRANT SELECT ON TABLE "public"."operators" TO "service_role";
GRANT SELECT ON TABLE "public"."operators" TO "anon";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."payout_rules" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."payouts" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."plan_activities" TO "authenticated";
GRANT SELECT ON TABLE "public"."plan_activities" TO "service_role";
GRANT SELECT ON TABLE "public"."plan_activities" TO "anon";



GRANT ALL ON TABLE "public"."practice_activities" TO "authenticated";
GRANT ALL ON TABLE "public"."practice_activities" TO "service_role";



GRANT ALL ON TABLE "public"."practice_blocks" TO "authenticated";
GRANT ALL ON TABLE "public"."practice_blocks" TO "service_role";



GRANT ALL ON TABLE "public"."practice_steps" TO "authenticated";
GRANT ALL ON TABLE "public"."practice_steps" TO "service_role";



GRANT ALL ON TABLE "public"."practice_user_state" TO "authenticated";
GRANT ALL ON TABLE "public"."practice_user_state" TO "service_role";



GRANT ALL ON TABLE "public"."practices" TO "authenticated";
GRANT ALL ON TABLE "public"."practices" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."promotions" TO "authenticated";
GRANT SELECT ON TABLE "public"."promotions" TO "anon";



GRANT SELECT ON TABLE "public"."public_site_activities" TO "anon";
GRANT SELECT ON TABLE "public"."public_site_activities" TO "authenticated";



GRANT SELECT ON TABLE "public"."public_site_events" TO "anon";
GRANT SELECT ON TABLE "public"."public_site_events" TO "authenticated";



GRANT SELECT ON TABLE "public"."public_site_operators" TO "anon";
GRANT SELECT ON TABLE "public"."public_site_operators" TO "authenticated";



GRANT SELECT ON TABLE "public"."public_site_pricing" TO "anon";
GRANT SELECT ON TABLE "public"."public_site_pricing" TO "authenticated";



GRANT SELECT ON TABLE "public"."public_site_schedule" TO "anon";
GRANT SELECT ON TABLE "public"."public_site_schedule" TO "authenticated";



GRANT ALL ON TABLE "public"."social_connections" TO "authenticated";
GRANT ALL ON TABLE "public"."social_connections" TO "service_role";



GRANT SELECT ON TABLE "public"."subscription_usages" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."waitlist" TO "authenticated";




