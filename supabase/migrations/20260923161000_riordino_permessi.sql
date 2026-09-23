-- Migration 20260923161000: riordino dei permessi — schema interno e policy (sessione 3, blocco 10)
--
-- Obiettivo: chiudere il debito che la sessione 1 aveva lasciato aperto e che ACCESS_MODEL.md elenca
-- come "cose note, rimandate":
--   1. le funzioni interne in uno SCHEMA NON ESPOSTO ALL'API;
--   2. le policy doppie accorpate;
--   3. le policy scritte senza `TO`, che valgono per il ruolo `public` e quindi includono anon.
--
-- 1. LO SCHEMA `internal`. Dal 2026-09-22 una funzione nuova in `public` nasce senza EXECUTE per anon
-- e authenticated, quindi le funzioni interne erano già irraggiungibili. Ma restavano ELENCATE
-- nell'API: PostgREST espone `public`, e bastava un GRANT distratto in una migrazione futura per
-- riaprire una porta. Spostarle in uno schema che PostgREST non espone (`config.toml` elenca solo
-- `public` e `graphql_public`) toglie il problema alla radice: non c'è nessun GRANT che possa
-- renderle chiamabili dall'esterno.
--
-- RESTANO IN `public`, di proposito, quelle che qualcuno chiama DA FUORI il database:
--   * `queue_lesson_reminders`, `queue_subscription_expiry`, `queue_entries_low`,
--     `queue_re_engagement`, `queue_birthday` — le chiama l'edge function `schedule-notifications`
--     con la chiave di servizio, cioè attraverso PostgREST. Spostarle spegnerebbe i promemoria;
--   * `process_recurring_announcements`, che non ha un wrapper `cron_*` e con ogni probabilità è
--     chiamata direttamente da un job;
--   * le `cron_*`, che se le sposta la migrazione successiva, dopo aver letto i job veri in
--     produzione (i job di pg_cron non stanno nelle migrazioni: esistono solo in produzione).
-- Sono comunque tutte chiuse ad anon e authenticated, come prima.
--
-- I corpi delle funzioni che citavano `public.<funzione spostata>` sono riscritti qui con il nuovo
-- schema. Il resto del corpo è identico carattere per carattere: le definizioni sono state prese dal
-- database e modificate solo nel riferimento. I trigger continuano a funzionare senza toccarli, perché
-- puntano alla funzione per identificativo interno e non per nome.
--
-- Compatibilità: nessuna firma cambia, nessuna funzione sparisce, nessuna tabella viene toccata. Per
-- anon e authenticated non cambia niente, perché non potevano già chiamarle. Cambia una cosa sola per
-- chi scriverà migrazioni: i trigger di `updated_at` ora si scrivono
-- `EXECUTE FUNCTION "internal"."update_updated_at_column"()`.
-- Vedi ACCESS_MODEL.md e docs/PIANO-APS-E-NUOVA-APP.md §0.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Lo schema interno
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS "internal";
ALTER SCHEMA "internal" OWNER TO "postgres";

COMMENT ON SCHEMA "internal" IS
    'Funzioni interne: code delle notifiche, helper dei trigger, manutenzione. Non è esposto all''API (config.toml espone solo public e graphql_public) e non ha USAGE per anon e authenticated, quindi non è raggiungibile dalle app in nessun modo.';

-- Nessun GRANT ad anon e authenticated: uno schema nuovo non ne dà, e qui non gliene diamo.
-- service_role serve invece: le edge function scrivono tabelle i cui trigger stanno qui dentro.
GRANT USAGE ON SCHEMA "internal" TO "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal"
    GRANT EXECUTE ON FUNCTIONS TO "service_role";

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Spostamento delle funzioni interne
-- ─────────────────────────────────────────────────────────────────────────────

ALTER FUNCTION "public"."auto_complete_expired_subscriptions"() SET SCHEMA "internal";
ALTER FUNCTION "public"."auto_create_booking_for_individual_lesson"() SET SCHEMA "internal";
ALTER FUNCTION "public"."call_edge_function"(p_function_name text, p_body jsonb) SET SCHEMA "internal";
ALTER FUNCTION "public"."can_send_re_engagement"(p_client_id uuid, p_days integer) SET SCHEMA "internal";
ALTER FUNCTION "public"."check_milestone_on_attended"() SET SCHEMA "internal";
ALTER FUNCTION "public"."client_has_active_push_tokens"(p_client_id uuid) SET SCHEMA "internal";
ALTER FUNCTION "public"."compute_compensation"(p_model_id uuid, p_duration_minutes integer, p_participants integer, p_revenue_cents bigint) SET SCHEMA "internal";
ALTER FUNCTION "public"."convert_trial_on_new_subscription"() SET SCHEMA "internal";
ALTER FUNCTION "public"."count_attended_lessons"(p_client_id uuid) SET SCHEMA "internal";
ALTER FUNCTION "public"."create_trial_booking"(p_lesson_id uuid, p_client_id uuid, p_created_by uuid, p_skip_deadline boolean) SET SCHEMA "internal";
ALTER FUNCTION "public"."create_user_profile"(user_id uuid, full_name text, phone text, role user_role) SET SCHEMA "internal";
ALTER FUNCTION "public"."ensure_subscription_canceled_on_deleted_at"() SET SCHEMA "internal";
ALTER FUNCTION "public"."expire_waitlist_offers"() SET SCHEMA "internal";
ALTER FUNCTION "public"."fix_missing_cancel_restore_entries"() SET SCHEMA "internal";
ALTER FUNCTION "public"."get_notification_channel"(p_client_id uuid, p_category notification_category) SET SCHEMA "internal";
ALTER FUNCTION "public"."guard_profile_privileged_columns"() SET SCHEMA "internal";
ALTER FUNCTION "public"."handle_individual_lesson_update"() SET SCHEMA "internal";
ALTER FUNCTION "public"."handle_new_user"() SET SCHEMA "internal";
ALTER FUNCTION "public"."link_client_to_profile_by_email"() SET SCHEMA "internal";
ALTER FUNCTION "public"."member_booking_status"(p_client_id uuid) SET SCHEMA "internal";
ALTER FUNCTION "public"."members_only_enabled"() SET SCHEMA "internal";
ALTER FUNCTION "public"."milestone_already_sent"(p_client_id uuid, p_milestone integer) SET SCHEMA "internal";
ALTER FUNCTION "public"."next_member_number"(p_year integer) SET SCHEMA "internal";
ALTER FUNCTION "public"."next_receipt_number"(p_year integer) SET SCHEMA "internal";
ALTER FUNCTION "public"."notify_new_announcement"() SET SCHEMA "internal";
ALTER FUNCTION "public"."offer_waitlist_on_booking_cancel"() SET SCHEMA "internal";
ALTER FUNCTION "public"."promote_from_waitlist"(p_lesson_id uuid) SET SCHEMA "internal";
ALTER FUNCTION "public"."queue_announcement"(p_announcement_id uuid, p_title text, p_body text) SET SCHEMA "internal";
ALTER FUNCTION "public"."queue_announcement"(p_announcement_id uuid, p_title text, p_body text, p_scheduled_for timestamp with time zone) SET SCHEMA "internal";
ALTER FUNCTION "public"."queue_announcement"(p_announcement_id uuid, p_title text, p_body text, p_scheduled_for timestamp with time zone, p_is_test boolean, p_test_client_id uuid) SET SCHEMA "internal";
ALTER FUNCTION "public"."queue_first_lesson"(p_client_id uuid) SET SCHEMA "internal";
ALTER FUNCTION "public"."queue_journal_reminder"() SET SCHEMA "internal";
ALTER FUNCTION "public"."queue_milestone"(p_client_id uuid, p_milestone integer) SET SCHEMA "internal";
ALTER FUNCTION "public"."queue_practice_reminder"() SET SCHEMA "internal";
ALTER FUNCTION "public"."queue_practice_resume"() SET SCHEMA "internal";
ALTER FUNCTION "public"."record_stripe_fee_expense"() SET SCHEMA "internal";
ALTER FUNCTION "public"."resolve_compensation_model"(p_operator_id uuid, p_activity_id uuid, p_on_date date) SET SCHEMA "internal";
ALTER FUNCTION "public"."restore_subscription_entry_on_booking_cancel"() SET SCHEMA "internal";
ALTER FUNCTION "public"."set_association_year_default_due_date"() SET SCHEMA "internal";
ALTER FUNCTION "public"."subscription_covers_activity"(p_subscription_id uuid, p_activity_id uuid) SET SCHEMA "internal";
ALTER FUNCTION "public"."sync_profile_from_client"() SET SCHEMA "internal";
ALTER FUNCTION "public"."update_activity_slug"() SET SCHEMA "internal";
ALTER FUNCTION "public"."update_announcement_next_occurrence"() SET SCHEMA "internal";
ALTER FUNCTION "public"."update_bug_reports_updated_at"() SET SCHEMA "internal";
ALTER FUNCTION "public"."update_expired_subscription_statuses"() SET SCHEMA "internal";
ALTER FUNCTION "public"."update_subscription_status_on_usage"() SET SCHEMA "internal";
ALTER FUNCTION "public"."update_subscription_status_on_usage_after_delete"() SET SCHEMA "internal";
ALTER FUNCTION "public"."update_updated_at_column"() SET SCHEMA "internal";

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA "internal" TO "service_role";

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Riferimenti aggiornati
--    Corpi identici a prima: cambia solo lo schema delle funzioni spostate.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."auto_complete_expired_subscriptions"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."auto_create_booking_for_individual_lesson"()
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
      IF NOT "internal"."subscription_covers_activity"(NEW.assigned_subscription_id, NEW.activity_id) THEN
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
        AND "internal"."subscription_covers_activity"(swr.id, NEW.activity_id)
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

CREATE OR REPLACE FUNCTION public.book_event(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_gate text;
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

  -- Regola "solo soci" (H2): con l'interruttore acceso si prenota solo da sociə.
  -- Chi ha pagato la quota prenota subito, anche prima della delibera del Consiglio Direttivo (A7).
  IF "internal"."members_only_enabled"() THEN
    v_member_gate := "internal"."member_booking_status"(v_my_client_id);
    IF v_member_gate NOT IN ('ok', 'fee_due_grace', 'pending_admission') THEN
      RETURN jsonb_build_object(
        'ok', false,
        'reason', CASE WHEN v_member_gate IN ('fee_unpaid', 'fee_overdue')
                       THEN 'MEMBERSHIP_FEE_DUE' ELSE 'NOT_A_MEMBER' END,
        'member_status', v_member_gate);
    END IF;
  END IF;

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
$function$;

CREATE OR REPLACE FUNCTION public.book_lesson(p_lesson_id uuid, p_subscription_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_gate text;
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

  -- Regola "solo soci" (H2): con l'interruttore acceso si prenota solo da sociə.
  -- Chi ha pagato la quota prenota subito, anche prima della delibera del Consiglio Direttivo (A7).
  IF "internal"."members_only_enabled"() THEN
    v_member_gate := "internal"."member_booking_status"(v_my_client_id);
    IF v_member_gate NOT IN ('ok', 'fee_due_grace', 'pending_admission') THEN
      RETURN jsonb_build_object(
        'ok', false,
        'reason', CASE WHEN v_member_gate IN ('fee_unpaid', 'fee_overdue')
                       THEN 'MEMBERSHIP_FEE_DUE' ELSE 'NOT_A_MEMBER' END,
        'member_status', v_member_gate);
    END IF;
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
$function$;

CREATE OR REPLACE FUNCTION public.book_trial_lesson(p_lesson_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_client_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    RETURN "internal"."create_trial_booking"(p_lesson_id, v_client_id, auth.uid(), false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_compensation_v2(p_month_start date, p_month_end date, p_operator_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(operator_id uuid, operator_name text, lesson_id uuid, event_id uuid, occurred_at timestamp with time zone, title text, duration_minutes integer, participants integer, revenue_cents bigint, model_id uuid, model_name text, amount_cents bigint, breakdown jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT public.can_access_finance() THEN
        RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH lesson_base AS (
        SELECT
            l.id                AS lesson_id,
            l.operator_id,
            l.starts_at,
            l.activity_id,
            a.name              AS activity_name,
            GREATEST(COALESCE(
                a.duration_minutes,
                (EXTRACT(EPOCH FROM (l.ends_at - l.starts_at)) / 60)::integer
            ), 1)               AS duration_minutes,
            COUNT(b.id) FILTER (WHERE b.status IN ('booked', 'attended', 'no_show'))::integer AS participants,
            COALESCE(SUM(
                CASE
                    WHEN s.custom_price_cents IS NOT NULL AND COALESCE(s.custom_entries, 0) > 0
                        THEN s.custom_price_cents::numeric / s.custom_entries
                    WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
                         AND p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
                        THEN round(p.price_cents * (1 - s.discount_percent / 100.0)) / p.entries
                    WHEN p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
                        THEN round(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0)) / p.entries
                    ELSE 0
                END
            ) FILTER (WHERE b.status IN ('booked', 'attended', 'no_show')), 0)::bigint AS revenue_cents
        FROM public.lessons l
        JOIN public.activities a ON a.id = l.activity_id
        LEFT JOIN public.bookings b ON b.lesson_id = l.id
        LEFT JOIN public.subscriptions s ON s.id = b.subscription_id
        LEFT JOIN public.plans p ON p.id = s.plan_id
        WHERE l.starts_at >= p_month_start
          AND l.starts_at < (p_month_end + INTERVAL '1 day')
          AND l.deleted_at IS NULL
          AND l.operator_id IS NOT NULL
          AND (p_operator_id IS NULL OR l.operator_id = p_operator_id)
        GROUP BY l.id, l.operator_id, l.starts_at, l.activity_id, a.name, a.duration_minutes, l.ends_at
    ),
    event_base AS (
        SELECT
            eo.operator_id,
            e.id                AS event_id,
            e.starts_at,
            e.name              AS event_name,
            eo.model_id         AS override_model_id,
            GREATEST(COALESCE(
                (EXTRACT(EPOCH FROM (e.ends_at - e.starts_at)) / 60)::integer, 90
            ), 1)               AS duration_minutes,
            COUNT(eb.id) FILTER (WHERE eb.status IN ('booked', 'attended', 'no_show'))::integer AS participants,
            (COALESCE(e.price_cents, 0)::bigint
                * COUNT(eb.id) FILTER (WHERE eb.status IN ('booked', 'attended', 'no_show'))) AS revenue_cents
        FROM public.event_operators eo
        JOIN public.events e ON e.id = eo.event_id
        LEFT JOIN public.event_bookings eb ON eb.event_id = e.id
        WHERE e.starts_at >= p_month_start
          AND e.starts_at < (p_month_end + INTERVAL '1 day')
          AND e.deleted_at IS NULL
          AND (p_operator_id IS NULL OR eo.operator_id = p_operator_id)
        GROUP BY eo.operator_id, e.id, e.starts_at, e.name, eo.model_id, e.ends_at, e.price_cents
    ),
    resolved AS (
        SELECT lb.operator_id, lb.lesson_id, NULL::uuid AS event_id, lb.starts_at AS occurred_at,
               lb.activity_name AS title, lb.duration_minutes, lb.participants, lb.revenue_cents,
               "internal"."resolve_compensation_model"(lb.operator_id, lb.activity_id, lb.starts_at::date) AS model_id
          FROM lesson_base lb
        UNION ALL
        SELECT eb.operator_id, NULL::uuid, eb.event_id, eb.starts_at,
               eb.event_name, eb.duration_minutes, eb.participants, eb.revenue_cents,
               COALESCE(eb.override_model_id,
                        "internal"."resolve_compensation_model"(eb.operator_id, NULL, eb.starts_at::date))
          FROM event_base eb
    )
    SELECT
        r.operator_id,
        o.name,
        r.lesson_id,
        r.event_id,
        r.occurred_at,
        r.title,
        r.duration_minutes,
        r.participants,
        r.revenue_cents,
        r.model_id,
        m.name,
        COALESCE((calc.result->>'amount_cents')::bigint, 0),
        COALESCE(calc.result, jsonb_build_object('ok', false, 'reason', 'NO_MODEL'))
    FROM resolved r
    JOIN public.operators o ON o.id = r.operator_id
    LEFT JOIN public.compensation_models m ON m.id = r.model_id
    LEFT JOIN LATERAL (
        SELECT "internal"."compute_compensation"(r.model_id, r.duration_minutes, r.participants, r.revenue_cents) AS result
        WHERE r.model_id IS NOT NULL
    ) calc ON true
    -- I volontari non prendono compensi: solo rimborsi documentati (art. 23)
    WHERE o.deleted_at IS NULL
      AND o.engagement_type = 'paid'::public.staff_engagement_type
    ORDER BY r.occurred_at, o.name;
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."call_edge_function"(p_function_name text, p_body jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."can_send_re_engagement"(p_client_id uuid, p_days integer DEFAULT 7)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."check_milestone_on_attended"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_attended_count integer;
    v_milestones integer[] := ARRAY[10, 25, 50, 100];
    v_milestone integer;
BEGIN
    -- Only trigger when status changes to 'attended'
    IF NEW.status = 'attended' AND (OLD.status IS NULL OR OLD.status != 'attended') THEN
        -- Get attended count for this client
        v_attended_count := "internal"."count_attended_lessons"(NEW.client_id);

        -- Check for first lesson
        IF v_attended_count = 1 THEN
            PERFORM "internal"."queue_first_lesson"(NEW.client_id);
        END IF;

        -- Check for milestones
        FOREACH v_milestone IN ARRAY v_milestones LOOP
            IF v_attended_count = v_milestone THEN
                PERFORM "internal"."queue_milestone"(NEW.client_id, v_milestone);
                EXIT; -- Only one milestone at a time
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."client_has_active_push_tokens"(p_client_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM "public"."device_tokens"
        WHERE "client_id" = p_client_id AND "is_active" = true
    );
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."compute_compensation"(p_model_id uuid, p_duration_minutes integer, p_participants integer, p_revenue_cents bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_model     public.compensation_models%ROWTYPE;
    v_c         public.compensation_components%ROWTYPE;
    v_total     numeric := 0;
    v_duration  integer := GREATEST(COALESCE(p_duration_minutes, 0), 1);
    v_parts     integer := GREATEST(COALESCE(p_participants, 0), 0);
    v_revenue   numeric := GREATEST(COALESCE(p_revenue_cents, 0), 0);
    v_tier      public.compensation_tiers%ROWTYPE;
    v_amount    numeric;
    v_cap       numeric;
    v_details   jsonb := '[]'::jsonb;
BEGIN
    SELECT * INTO v_model FROM public.compensation_models WHERE id = p_model_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MODEL_NOT_FOUND');
    END IF;

    FOR v_c IN
        SELECT * FROM public.compensation_components
         WHERE model_id = p_model_id ORDER BY display_order, id
    LOOP
        v_amount := CASE v_c.kind
            WHEN 'fixed_per_lesson'   THEN v_c.value_cents
            WHEN 'fixed_per_hour'     THEN v_c.value_cents::numeric * v_duration / 60.0
            WHEN 'per_participant'    THEN v_c.value_cents::numeric * v_parts
            WHEN 'percent_of_revenue' THEN v_revenue * v_c.value_percent / 100.0
            WHEN 'room_fee_percent'   THEN -1 * v_revenue * v_c.value_percent / 100.0
        END;

        v_total := v_total + v_amount;
        v_details := v_details || jsonb_build_object(
            'kind', v_c.kind, 'amount_cents', round(v_amount)
        );
    END LOOP;

    -- Scaglione per numero di presenti: se più fasce combaciano vince quella con la soglia più alta
    SELECT * INTO v_tier
      FROM public.compensation_tiers
     WHERE model_id = p_model_id
       AND min_participants <= v_parts
       AND (max_participants IS NULL OR v_parts <= max_participants)
     ORDER BY min_participants DESC
     LIMIT 1;

    IF FOUND THEN
        v_total := v_total + v_tier.amount_cents;
        v_details := v_details || jsonb_build_object(
            'kind', 'tier', 'amount_cents', v_tier.amount_cents,
            'min_participants', v_tier.min_participants, 'max_participants', v_tier.max_participants
        );
    END IF;

    -- Tetto orario, in proporzione alla durata
    IF v_model.max_hourly_cents IS NOT NULL THEN
        v_cap := v_model.max_hourly_cents::numeric * v_duration / 60.0;
        IF v_total > v_cap THEN
            v_details := v_details || jsonb_build_object('kind', 'max_hourly_cap', 'amount_cents', round(v_cap - v_total));
            v_total := v_cap;
        END IF;
    END IF;

    -- Minimo garantito: si applica per ultimo, quindi se è in contrasto col tetto vince il minimo
    IF v_model.min_guaranteed_cents IS NOT NULL AND v_total < v_model.min_guaranteed_cents THEN
        v_details := v_details || jsonb_build_object(
            'kind', 'min_guaranteed', 'amount_cents', round(v_model.min_guaranteed_cents - v_total));
        v_total := v_model.min_guaranteed_cents;
    END IF;

    -- Un compenso non può essere negativo: se le trattenute superano il resto, è zero
    IF v_total < 0 THEN
        v_details := v_details || jsonb_build_object('kind', 'floor_zero', 'amount_cents', round(-v_total));
        v_total := 0;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'amount_cents', round(v_total)::bigint,
        'model_id', p_model_id,
        'duration_minutes', v_duration,
        'participants', v_parts,
        'revenue_cents', v_revenue::bigint,
        'components', v_details
    );
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."convert_trial_on_new_subscription"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_trial public.trials%ROWTYPE;
BEGIN
    IF NEW.client_id IS NULL OR NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- La prova più vecchia ancora da convertire, fra quelle coperte dall'abbonamento.
    -- Una sola per abbonamento: scalarne due senza dirlo sarebbe una sorpresa.
    SELECT t.* INTO v_trial
      FROM public.trials t
     WHERE t.client_id = NEW.client_id
       AND t.status IN ('booked', 'attended', 'no_show')
       AND "internal"."subscription_covers_activity"(NEW.id, t.activity_id)
     ORDER BY t.booked_at
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
    VALUES (NEW.id, v_trial.booking_id, -1, 'TRIAL');

    UPDATE public.trials
       SET status = 'converted',
           converted_subscription_id = NEW.id,
           converted_at = now()
     WHERE id = v_trial.id;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."count_attended_lessons"(p_client_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
    SELECT COALESCE(COUNT(*)::integer, 0)
    FROM "public"."bookings"
    WHERE client_id = p_client_id AND status = 'attended';
$function$;

CREATE OR REPLACE FUNCTION "internal"."create_trial_booking"(p_lesson_id uuid, p_client_id uuid, p_created_by uuid, p_skip_deadline boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_lesson            public.lessons%ROWTYPE;
    v_activity          public.activities%ROWTYPE;
    v_booked_count      integer;
    v_booking_id        uuid;
    v_trial_id          uuid;
    v_is_member         boolean;
    v_member_gate       text;
    v_trial_open_to_all boolean;
BEGIN
    SELECT * INTO v_lesson FROM public.lessons WHERE id = p_lesson_id FOR UPDATE;
    IF NOT FOUND OR v_lesson.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    IF v_lesson.is_individual THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRIAL_NOT_AVAILABLE');
    END IF;

    SELECT * INTO v_activity FROM public.activities WHERE id = v_lesson.activity_id;
    IF NOT FOUND OR v_activity.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    IF v_activity.trial_enabled = false THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRIAL_NOT_AVAILABLE');
    END IF;

    v_member_gate := "internal"."member_booking_status"(p_client_id);
    v_is_member := v_member_gate IN ('ok', 'fee_due_grace');

    -- Con "solo soci" acceso, la prova resta riservata ai soci finché non si accende l'eccezione
    IF "internal"."members_only_enabled"() THEN
        SELECT COALESCE(enabled, false) INTO v_trial_open_to_all
          FROM public.feature_flags WHERE key = 'trial_for_non_members';

        IF NOT COALESCE(v_trial_open_to_all, false)
           AND v_member_gate NOT IN ('ok', 'fee_due_grace', 'pending_admission') THEN
            RETURN jsonb_build_object(
                'ok', false,
                'reason', CASE WHEN v_member_gate IN ('fee_unpaid', 'fee_overdue')
                               THEN 'MEMBERSHIP_FEE_DUE' ELSE 'NOT_A_MEMBER' END,
                'member_status', v_member_gate);
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM public.trials
                WHERE client_id = p_client_id AND activity_id = v_activity.id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRIAL_ALREADY_USED');
    END IF;

    IF NOT p_skip_deadline
       AND now() > v_lesson.starts_at - make_interval(mins => COALESCE(v_lesson.booking_deadline_minutes, 30)) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
    END IF;

    IF EXISTS (SELECT 1 FROM public.bookings
                WHERE lesson_id = p_lesson_id AND client_id = p_client_id AND status = 'booked') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    SELECT count(*) INTO v_booked_count
      FROM public.bookings WHERE lesson_id = p_lesson_id AND status = 'booked';
    IF v_booked_count >= v_lesson.capacity THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;

    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status, is_trial)
    VALUES (p_lesson_id, p_client_id, NULL, 'booked', true)
    ON CONFLICT (lesson_id, client_id) WHERE status = 'booked' AND client_id IS NOT NULL
    DO NOTHING
    RETURNING id INTO v_booking_id;

    IF v_booking_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    INSERT INTO public.trials (client_id, activity_id, lesson_id, booking_id,
                               was_member_at_booking, created_by)
    VALUES (p_client_id, v_activity.id, p_lesson_id, v_booking_id, v_is_member, p_created_by)
    RETURNING id INTO v_trial_id;

    RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED',
                              'booking_id', v_booking_id, 'trial_id', v_trial_id);
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."create_user_profile"(user_id uuid, full_name text, phone text DEFAULT NULL::text, role user_role DEFAULT 'user'::user_role)
 RETURNS profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.cron_execute_scheduled_campaigns()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    PERFORM "internal"."call_edge_function"(
        'execute-scheduled-campaigns',
        '{}'::jsonb
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.cron_fetch_social_analytics()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    PERFORM "internal"."call_edge_function"(
        'meta-fetch-analytics',
        '{}'::jsonb
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.cron_process_notification_queue()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    PERFORM "internal"."call_edge_function"(
        'process-notification-queue',
        '{}'::jsonb
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.cron_queue_journal_reminder()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    PERFORM "internal"."queue_journal_reminder"();
END;
$function$;

CREATE OR REPLACE FUNCTION public.cron_queue_practice_reminder()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    PERFORM "internal"."queue_practice_reminder"();
END;
$function$;

CREATE OR REPLACE FUNCTION public.cron_queue_practice_resume()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    PERFORM "internal"."queue_practice_resume"();
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."ensure_subscription_canceled_on_deleted_at"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."expire_waitlist_offers"()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_lesson_id uuid;
    v_expired   integer := 0;
BEGIN
    FOR v_lesson_id IN
        SELECT DISTINCT lesson_id FROM public.waitlist
         WHERE status = 'offered' AND expires_at < now()
    LOOP
        UPDATE public.waitlist
           SET status = 'expired'
         WHERE lesson_id = v_lesson_id AND status = 'offered' AND expires_at < now();
        v_expired := v_expired + 1;
        PERFORM "internal"."promote_from_waitlist"(v_lesson_id);
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'lessons_processed', v_expired);
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."fix_missing_cancel_restore_entries"()
 RETURNS TABLE(booking_id uuid, subscription_id uuid, restored boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."get_notification_channel"(p_client_id uuid, p_category notification_category)
 RETURNS notification_channel
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
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
    v_has_push := "internal"."client_has_active_push_tokens"(p_client_id);

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
$function$;

CREATE OR REPLACE FUNCTION "internal"."guard_profile_privileged_columns"()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Vale per le scritture fatte direttamente dall'API, dove PostgREST imposta il ruolo anon o
  -- authenticated. Le RPC SECURITY DEFINER e i trigger interni girano come postgres, e hanno i
  -- loro controlli; service_role e supabase_auth_admin sono processi di sistema.
  IF current_user NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.role IS DISTINCT FROM 'user'::"public"."user_role" AND NOT public.is_admin() THEN
      RAISE EXCEPTION 'ROLE_CHANGE_FORBIDDEN: solo un admin può assegnare un ruolo staff'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'ROLE_CHANGE_FORBIDDEN: solo un admin può cambiare il ruolo di un profilo'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.email IS DISTINCT FROM OLD.email AND NOT public.is_staff() THEN
    RAISE EXCEPTION 'EMAIL_CHANGE_FORBIDDEN: l''email del profilo la cambia solo lo staff'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."handle_individual_lesson_update"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_subscription_id uuid;
  v_booking_id uuid;
  v_old_booking_id uuid;
  v_subscription_changed boolean;
  v_old_subscription_id uuid;
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
     AND NOT "internal"."subscription_covers_activity"(NEW.assigned_subscription_id, NEW.activity_id) THEN
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

    -- Check if booking already exists for client (client_id è l'unica fonte di verità)
    SELECT id INTO v_booking_id
    FROM public.bookings
    WHERE lesson_id = NEW.id
      AND client_id = NEW.assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
    LIMIT 1;

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
        SELECT swr.id INTO v_subscription_id
        FROM public.subscriptions_with_remaining swr
        WHERE swr.client_id = NEW.assigned_client_id
          AND swr.status = 'active'
          AND NEW.starts_at::date BETWEEN swr.started_at::date AND swr.expires_at::date
          AND (swr.remaining_entries IS NULL OR swr.remaining_entries > 0)
          AND "internal"."subscription_covers_activity"(swr.id, NEW.activity_id)
        ORDER BY swr.expires_at DESC NULLS LAST
        LIMIT 1;
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
        SELECT swr.id INTO v_subscription_id
        FROM public.subscriptions_with_remaining swr
        WHERE swr.client_id = NEW.assigned_client_id
          AND swr.status = 'active'
          AND NEW.starts_at::date BETWEEN swr.started_at::date AND swr.expires_at::date
          AND (swr.remaining_entries IS NULL OR swr.remaining_entries > 0)
          AND "internal"."subscription_covers_activity"(swr.id, NEW.activity_id)
        ORDER BY swr.expires_at DESC NULLS LAST
        LIMIT 1;
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

CREATE OR REPLACE FUNCTION "internal"."handle_new_user"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.issue_receipt(p_transaction_id uuid, p_causale text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_tx            public.transactions%ROWTYPE;
    v_settings      public.association_settings%ROWTYPE;
    v_year          integer;
    v_number        integer;
    v_full_number   text;
    v_name          text;
    v_fiscal_code   text;
    v_address       text;
    v_stamp         integer := 0;
    v_causale       text;
    v_receipt_id    uuid;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    SELECT * INTO v_tx FROM public.transactions WHERE id = p_transaction_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_FOUND');
    END IF;

    IF v_tx.amount_cents <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AN_INCOME');
    END IF;

    IF v_tx.status <> 'paid' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_PAID');
    END IF;

    IF EXISTS (SELECT 1 FROM public.receipts WHERE transaction_id = p_transaction_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'RECEIPT_ALREADY_ISSUED');
    END IF;

    SELECT * INTO v_settings FROM public.association_settings WHERE id = true;

    -- Dati di chi riceve: prima quelli della domanda di ammissione, che sono i più completi
    SELECT COALESCE(c.full_name, btrim(a.first_name || ' ' || a.last_name)),
           a.fiscal_code,
           NULLIF(btrim(COALESCE(a.address_street, '') || ' ' || COALESCE(a.address_zip, '') || ' '
                  || COALESCE(a.address_city, '') || ' ' || COALESCE(a.address_province, '')), '')
      INTO v_name, v_fiscal_code, v_address
      FROM public.clients c
      LEFT JOIN public.members m ON m.client_id = c.id
      LEFT JOIN public.member_applications a ON a.id = m.application_id
     WHERE c.id = v_tx.client_id;

    IF v_name IS NULL THEN
        v_name := COALESCE(v_tx.description, 'Non indicato');
    END IF;

    v_year := EXTRACT(YEAR FROM v_tx.occurred_on)::integer;
    v_number := "internal"."next_receipt_number"(v_year);
    v_full_number := COALESCE(NULLIF(v_settings.receipt_prefix, ''), '') || v_number::text || '/' || v_year::text;

    IF v_settings.stamp_duty_threshold_cents > 0
       AND v_tx.amount_cents > v_settings.stamp_duty_threshold_cents THEN
        v_stamp := v_settings.stamp_duty_cents;
    END IF;

    v_causale := COALESCE(NULLIF(btrim(COALESCE(p_causale, '')), ''), CASE v_tx.kind
        WHEN 'membership_fee' THEN 'Quota associativa'
        WHEN 'subscription'   THEN 'Contributo per attività associative'
        WHEN 'event'          THEN 'Contributo per evento o laboratorio'
        WHEN 'trial'          THEN 'Lezione di prova'
        WHEN 'donation'       THEN 'Erogazione liberale'
        WHEN 'commercial'     THEN 'Corrispettivo'
        ELSE 'Contributo'
    END);

    INSERT INTO public.receipts (
        transaction_id, year, number, full_number,
        recipient_name, recipient_fiscal_code, recipient_address,
        issuer_snapshot, causale, amount_cents, stamp_duty_cents, created_by
    ) VALUES (
        p_transaction_id, v_year, v_number, v_full_number,
        v_name, v_fiscal_code, v_address,
        jsonb_build_object(
            'legal_name', v_settings.legal_name,
            'short_legal_name', v_settings.short_legal_name,
            'fiscal_code', v_settings.fiscal_code,
            'vat_number', v_settings.vat_number,
            'address', v_settings.address_street || ', ' || v_settings.address_zip || ' '
                       || v_settings.address_city || ' (' || v_settings.address_province || ')',
            'pec', v_settings.pec,
            'email', v_settings.email,
            'footer', v_settings.receipt_footer
        ),
        v_causale, v_tx.amount_cents, v_stamp, auth.uid()
    )
    RETURNING id INTO v_receipt_id;

    RETURN jsonb_build_object(
        'ok', true, 'reason', 'ISSUED',
        'receipt_id', v_receipt_id, 'full_number', v_full_number,
        'number', v_number, 'year', v_year, 'stamp_duty_cents', v_stamp
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.leave_waitlist(p_lesson_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_client_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();

    UPDATE public.waitlist
       SET status = 'left'
     WHERE lesson_id = p_lesson_id AND client_id = v_client_id
       AND status IN ('waiting', 'offered');

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_IN_WAITLIST');
    END IF;

    PERFORM "internal"."promote_from_waitlist"(p_lesson_id);
    RETURN jsonb_build_object('ok', true, 'reason', 'LEFT');
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."link_client_to_profile_by_email"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."member_booking_status"(p_client_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_year      integer := EXTRACT(YEAR FROM CURRENT_DATE)::integer;
    v_member    public.members%ROWTYPE;
    v_fee       public.member_fees%ROWTYPE;
    v_due_date  date;
    v_has_app   boolean;
BEGIN
    IF p_client_id IS NULL THEN
        RETURN 'no_application';
    END IF;

    SELECT * INTO v_member FROM public.members WHERE client_id = p_client_id;
    SELECT * INTO v_fee FROM public.member_fees WHERE client_id = p_client_id AND year = v_year;
    SELECT fee_due_date INTO v_due_date FROM public.association_years WHERE year = v_year;

    IF v_member.id IS NOT NULL AND v_member.status = 'ceased' THEN
        RETURN 'ceased';
    END IF;

    IF v_member.id IS NOT NULL THEN
        -- Già sociə: la quota pagata o esonerata va bene
        IF v_fee.id IS NOT NULL AND v_fee.status IN ('paid', 'waived') THEN
            RETURN 'ok';
        END IF;
        -- Non ancora pagata: resta sociə fino alla data di decadenza dell'anno (art. 5, A8)
        IF v_due_date IS NULL OR CURRENT_DATE <= v_due_date THEN
            RETURN 'fee_due_grace';
        END IF;
        RETURN 'fee_overdue';
    END IF;

    -- Non ancora sociə: serve una domanda aperta e la quota pagata (A7)
    SELECT EXISTS (
        SELECT 1 FROM public.member_applications
         WHERE client_id = p_client_id AND status = 'pending'
    ) INTO v_has_app;

    IF NOT v_has_app THEN
        RETURN 'no_application';
    END IF;

    IF v_fee.id IS NOT NULL AND v_fee.status IN ('paid', 'waived') THEN
        RETURN 'pending_admission';
    END IF;

    RETURN 'fee_unpaid';
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."members_only_enabled"()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key = 'members_only'), false);
$function$;

CREATE OR REPLACE FUNCTION "internal"."milestone_already_sent"(p_client_id uuid, p_milestone integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM "public"."notification_logs"
        WHERE client_id = p_client_id
          AND category = 'milestone'
          AND (data->>'milestone')::int = p_milestone
    );
$function$;

CREATE OR REPLACE FUNCTION "internal"."next_member_number"(p_year integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_next integer;
BEGIN
    INSERT INTO public.member_number_sequences (year, last_number)
    VALUES (p_year, 0)
    ON CONFLICT (year) DO NOTHING;

    UPDATE public.member_number_sequences
       SET last_number = last_number + 1
     WHERE year = p_year
    RETURNING last_number INTO v_next;

    RETURN p_year::text || '-' || lpad(v_next::text, 4, '0');
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."next_receipt_number"(p_year integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_next integer;
BEGIN
    INSERT INTO public.receipt_sequences (year, last_number)
    VALUES (p_year, 0)
    ON CONFLICT (year) DO NOTHING;

    -- UPDATE … RETURNING tiene il lock di riga fino al commit: due emissioni contemporanee si
    -- mettono in coda e ottengono numeri diversi.
    UPDATE public.receipt_sequences
       SET last_number = last_number + 1
     WHERE year = p_year
    RETURNING last_number INTO v_next;

    RETURN v_next;
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."notify_new_announcement"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
        PERFORM "internal"."queue_announcement"(
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."offer_waitlist_on_booking_cancel"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    PERFORM "internal"."promote_from_waitlist"(NEW.lesson_id);
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."promote_from_waitlist"(p_lesson_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_lesson    public.lessons%ROWTYPE;
    v_booked    integer;
    v_offered   integer;
    v_next      public.waitlist%ROWTYPE;
    v_expires   timestamptz;
    v_channel   public.notification_channel;
    v_activity  text;
BEGIN
    SELECT * INTO v_lesson FROM public.lessons WHERE id = p_lesson_id;
    IF NOT FOUND OR v_lesson.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    -- Prima si chiudono le offerte scadute: così non serve un cron dedicato
    UPDATE public.waitlist
       SET status = 'expired'
     WHERE lesson_id = p_lesson_id AND status = 'offered' AND expires_at < now();

    -- Oltre la scadenza delle prenotazioni non ha senso offrire nulla
    IF now() > v_lesson.starts_at - make_interval(mins => COALESCE(v_lesson.booking_deadline_minutes, 30)) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
    END IF;

    SELECT count(*) INTO v_booked
      FROM public.bookings WHERE lesson_id = p_lesson_id AND status = 'booked';
    SELECT count(*) INTO v_offered
      FROM public.waitlist WHERE lesson_id = p_lesson_id AND status = 'offered';

    -- Un'offerta è un posto già impegnato: si offre solo se ne restano davvero
    IF (v_booked + v_offered) >= v_lesson.capacity THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NO_FREE_SEAT');
    END IF;

    SELECT * INTO v_next
      FROM public.waitlist
     WHERE lesson_id = p_lesson_id AND status = 'waiting'
     ORDER BY position, created_at
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'WAITLIST_EMPTY');
    END IF;

    v_expires := LEAST(
        now() + INTERVAL '2 hours',
        v_lesson.starts_at - make_interval(mins => COALESCE(v_lesson.booking_deadline_minutes, 30))
    );

    UPDATE public.waitlist
       SET status = 'offered', offered_at = now(), expires_at = v_expires, notified_at = now()
     WHERE id = v_next.id;

    SELECT a.name INTO v_activity FROM public.activities a WHERE a.id = v_lesson.activity_id;
    v_channel := "internal"."get_notification_channel"(v_next.client_id, 'waitlist_promotion');

    IF v_channel IS NOT NULL THEN
        INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
        VALUES (
            v_next.client_id, 'waitlist_promotion', v_channel,
            'Si è liberato un posto',
            'Si è liberato un posto per ' || COALESCE(v_activity, 'la lezione')
                || ' del ' || to_char(v_lesson.starts_at AT TIME ZONE 'Europe/Rome', 'DD/MM alle HH24:MI')
                || '. Hai tempo fino alle '
                || to_char(v_expires AT TIME ZONE 'Europe/Rome', 'HH24:MI') || ' per prenotare.',
            jsonb_build_object('lesson_id', p_lesson_id, 'expires_at', v_expires),
            now()
        );
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'OFFERED',
                              'client_id', v_next.client_id, 'expires_at', v_expires);
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."queue_announcement"(p_announcement_id uuid, p_title text, p_body text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
      AND "internal"."client_has_active_push_tokens"(c.id);

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."queue_announcement"(p_announcement_id uuid, p_title text, p_body text, p_scheduled_for timestamp with time zone DEFAULT now())
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
      AND "internal"."client_has_active_push_tokens"(c.id);

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."queue_announcement"(p_announcement_id uuid, p_title text, p_body text, p_scheduled_for timestamp with time zone DEFAULT now(), p_is_test boolean DEFAULT false, p_test_client_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
      AND "internal"."client_has_active_push_tokens"(c.id)
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
$function$;

CREATE OR REPLACE FUNCTION public.queue_birthday()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
            "internal"."get_notification_channel"(c.id, 'birthday'),
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
$function$;

CREATE OR REPLACE FUNCTION public.queue_entries_low()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
            "internal"."get_notification_channel"(s.client_id, 'entries_low'),
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
$function$;

CREATE OR REPLACE FUNCTION public.queue_feedback_request(p_client_id uuid, p_kind feedback_kind, p_target_id uuid DEFAULT NULL::uuid, p_scheduled_for timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_channel public.notification_channel;
  v_title text := 'Com''è andata?';
  v_body text;
  v_id uuid;
BEGIN
  -- Autorizzazione: service_role/automazioni (auth.uid() NULL), staff, oppure il cliente stesso.
  IF auth.uid() IS NOT NULL
     AND NOT public.is_staff()
     AND p_client_id <> public.get_my_client_id() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'FORBIDDEN');
  END IF;

  v_channel := "internal"."get_notification_channel"(p_client_id, 'feedback_request');
  IF v_channel IS NULL THEN
    -- Entrambi i canali disattivati dalle preferenze: non accodiamo nulla.
    RETURN jsonb_build_object('ok', false, 'reason', 'CHANNEL_DISABLED');
  END IF;

  v_body := CASE p_kind
    WHEN 'practice'   THEN 'Raccontaci com''è andata la tua pratica: il tuo parere ci aiuta a crescere.'
    WHEN 'lesson'     THEN 'Com''è andata la lezione? Lascia un breve feedback.'
    WHEN 'event'      THEN 'Com''è andato l''evento? Ci piacerebbe sapere la tua.'
    WHEN 'onboarding' THEN 'Sei con noi da un mese: com''è la tua esperienza in Studio Kalòs?'
  END;

  INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
  VALUES (
    p_client_id,
    'feedback_request',
    v_channel,
    v_title,
    v_body,
    jsonb_build_object('kind', p_kind, 'target_id', p_target_id),
    p_scheduled_for
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'notification_id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."queue_first_lesson"(p_client_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
            "internal"."get_notification_channel"(p_client_id, 'first_lesson'),
            'push'::"public"."notification_channel"
        ),
        'Complimenti per la tua prima lezione!',
        'Il benessere inizia cosi, un passo alla volta.',
        jsonb_build_object('first_lesson', true),
        NOW()
    );

    RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."queue_journal_reminder"()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
            "internal"."get_notification_channel"(c.id, 'journal_reminder'),
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
      AND "internal"."client_has_active_push_tokens"(c.id)
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
$function$;

CREATE OR REPLACE FUNCTION public.queue_lesson_reminders()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
                "internal"."get_notification_channel"(b.client_id, 'lesson_reminder'),
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
            "internal"."get_notification_channel"(b.client_id, 'lesson_reminder'),
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."queue_milestone"(p_client_id uuid, p_milestone integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Check if already sent
    IF "internal"."milestone_already_sent"(p_client_id, p_milestone) THEN
        RETURN false;
    END IF;

    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    VALUES (
        p_client_id,
        'milestone'::"public"."notification_category",
        COALESCE(
            "internal"."get_notification_channel"(p_client_id, 'milestone'),
            'push'::"public"."notification_channel"
        ),
        p_milestone || ' lezioni completate!',
        'Stai costruendo un''abitudine fantastica. Continua cosi!',
        jsonb_build_object('milestone', p_milestone),
        NOW()
    );

    RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.queue_new_event(p_event_id uuid, p_event_name text, p_event_date timestamp with time zone)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count integer := 0;
    v_title text;
BEGIN
    -- Sessione 1 (2026-09-22): solo lo staff può inviare "nuovo evento" a tutti i clienti.
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Permission denied: user is not staff' USING ERRCODE = '42501';
    END IF;
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
            "internal"."get_notification_channel"(c.id, 'new_event'),
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
$function$;

CREATE OR REPLACE FUNCTION public.queue_new_event(p_event_id uuid, p_event_name text, p_event_date timestamp with time zone, p_send_push boolean DEFAULT true, p_send_email boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_push_count integer := 0;
    v_email_count integer := 0;
    v_title text;
    v_body text;
    v_data jsonb;
BEGIN
    -- Sessione 1 (2026-09-22): solo lo staff può inviare "nuovo evento" a tutti i clienti.
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Permission denied: user is not staff' USING ERRCODE = '42501';
    END IF;
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
          AND "internal"."client_has_active_push_tokens"(c.id)
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."queue_practice_reminder"()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
            "internal"."get_notification_channel"(c.id, 'practice_reminder'),
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
      AND "internal"."client_has_active_push_tokens"(c.id)
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."queue_practice_resume"()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
            "internal"."get_notification_channel"(pus.client_id, 'practice_resume'),
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
      AND "internal"."client_has_active_push_tokens"(pus.client_id)
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
$function$;

CREATE OR REPLACE FUNCTION public.queue_re_engagement()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
      AND "internal"."client_has_active_push_tokens"(c.id)
      -- Passes anti-spam check for 4 days
      AND "internal"."can_send_re_engagement"(c.id, 4);

    GET DIAGNOSTICS v_count_4d = ROW_COUNT;

    -- 7 days re-engagement (push + email)
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        're_engagement'::"public"."notification_category",
        COALESCE(
            "internal"."get_notification_channel"(c.id, 're_engagement'),
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
      AND "internal"."can_send_re_engagement"(c.id, 7);

    GET DIAGNOSTICS v_count_7d = ROW_COUNT;

    RETURN json_build_object(
        '4_days', v_count_4d,
        '7_days', v_count_7d
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.queue_subscription_expiry()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
            "internal"."get_notification_channel"(s.client_id, 'subscription_expiry'),
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
            "internal"."get_notification_channel"(s.client_id, 'subscription_expiry'),
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
            "internal"."get_notification_channel"(s.client_id, 'subscription_expiry'),
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."record_stripe_fee_expense"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_category_id uuid;
    v_expense_id  uuid;
BEGIN
    -- Solo quando il pagamento riesce, c'è una commissione e non è già stata registrata
    IF NEW.status <> 'succeeded'
       OR COALESCE(NEW.fee_cents, 0) <= 0
       OR NEW.fee_expense_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT id INTO v_category_id FROM public.expense_categories WHERE slug = 'commissioni';

    INSERT INTO public.expenses (
        amount_cents, expense_date, category, category_id, notes,
        is_fixed, source, confirmed_at
    ) VALUES (
        NEW.fee_cents,
        COALESCE(NEW.succeeded_at, now())::date,
        'other', v_category_id,
        'Commissione Stripe — ' || NEW.payment_intent_id,
        false, 'stripe_fee', now()
    )
    RETURNING id INTO v_expense_id;

    UPDATE public.stripe_payments SET fee_expense_id = v_expense_id WHERE id = NEW.id;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."resolve_compensation_model"(p_operator_id uuid, p_activity_id uuid, p_on_date date)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT a.model_id
      FROM public.compensation_assignments a
     WHERE a.operator_id = p_operator_id
       AND (a.activity_id IS NULL OR a.activity_id = p_activity_id)
       AND a.valid_from <= p_on_date
       AND (a.valid_to IS NULL OR a.valid_to >= p_on_date)
     ORDER BY (a.activity_id IS NOT NULL) DESC, a.valid_from DESC
     LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION "internal"."restore_subscription_entry_on_booking_cancel"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."set_association_year_default_due_date"()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.fee_due_date IS NULL THEN
        NEW.fee_due_date := make_date(NEW.year, 3, 31);
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.staff_book_event(p_event_id uuid, p_client_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_gate text;
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

  -- Regola "solo soci" (H2): con l'interruttore acceso si prenota solo da sociə.
  -- Chi ha pagato la quota prenota subito, anche prima della delibera del Consiglio Direttivo (A7).
  IF "internal"."members_only_enabled"() THEN
    v_member_gate := "internal"."member_booking_status"(p_client_id);
    IF v_member_gate NOT IN ('ok', 'fee_due_grace', 'pending_admission') THEN
      RETURN jsonb_build_object(
        'ok', false,
        'reason', CASE WHEN v_member_gate IN ('fee_unpaid', 'fee_overdue')
                       THEN 'MEMBERSHIP_FEE_DUE' ELSE 'NOT_A_MEMBER' END,
        'member_status', v_member_gate);
    END IF;
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
$function$;

CREATE OR REPLACE FUNCTION public.staff_book_lesson(p_lesson_id uuid, p_client_id uuid, p_subscription_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_gate text;
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

  -- Regola "solo soci" (H2): con l'interruttore acceso si prenota solo da sociə.
  -- Chi ha pagato la quota prenota subito, anche prima della delibera del Consiglio Direttivo (A7).
  IF "internal"."members_only_enabled"() THEN
    v_member_gate := "internal"."member_booking_status"(p_client_id);
    IF v_member_gate NOT IN ('ok', 'fee_due_grace', 'pending_admission') THEN
      RETURN jsonb_build_object(
        'ok', false,
        'reason', CASE WHEN v_member_gate IN ('fee_unpaid', 'fee_overdue')
                       THEN 'MEMBERSHIP_FEE_DUE' ELSE 'NOT_A_MEMBER' END,
        'member_status', v_member_gate);
    END IF;
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
$function$;

CREATE OR REPLACE FUNCTION public.staff_book_trial(p_lesson_id uuid, p_client_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clients WHERE id = p_client_id AND deleted_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    -- Allo staff la scadenza non si applica: sta parlando con la persona di persona
    RETURN "internal"."create_trial_booking"(p_lesson_id, p_client_id, auth.uid(), true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.staff_create_client_and_book_trial(p_lesson_id uuid, p_first_name text, p_last_name text, p_phone text, p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_client_id uuid;
    v_full_name text;
    v_email     text := NULLIF(btrim(lower(COALESCE(p_email, ''))), '');
    v_result    jsonb;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF COALESCE(btrim(p_first_name), '') = '' OR COALESCE(btrim(p_last_name), '') = '' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MISSING_REQUIRED_FIELDS');
    END IF;

    v_full_name := btrim(p_first_name) || ' ' || btrim(p_last_name);

    -- Se quell'email esiste già si riusa la scheda, invece di crearne una doppia
    IF v_email IS NOT NULL THEN
        SELECT id INTO v_client_id FROM public.clients
         WHERE lower(email) = v_email AND deleted_at IS NULL LIMIT 1;
    END IF;

    IF v_client_id IS NULL THEN
        INSERT INTO public.clients (full_name, email, phone)
        VALUES (v_full_name, v_email, NULLIF(btrim(COALESCE(p_phone, '')), ''))
        RETURNING id INTO v_client_id;
    END IF;

    v_result := "internal"."create_trial_booking"(p_lesson_id, v_client_id, auth.uid(), true);
    RETURN v_result || jsonb_build_object('client_id', v_client_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.staff_decide_member_applications(p_application_ids uuid[], p_approve boolean, p_resolution_date date DEFAULT NULL::date, p_note text DEFAULT NULL::text, p_rejection_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_id            uuid;
    v_app           public.member_applications%ROWTYPE;
    v_resolution    date := COALESCE(p_resolution_date, CURRENT_DATE);
    v_decided       integer := 0;
    v_skipped       integer := 0;
    v_member_number text;
    v_results       jsonb := '[]'::jsonb;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF p_approve = false AND COALESCE(btrim(p_rejection_reason), '') = '' THEN
        -- Lo statuto (art. 4) vuole che il rifiuto sia motivato
        RETURN jsonb_build_object('ok', false, 'reason', 'REJECTION_REASON_REQUIRED');
    END IF;

    FOREACH v_id IN ARRAY p_application_ids LOOP
        SELECT * INTO v_app FROM public.member_applications WHERE id = v_id FOR UPDATE;

        IF NOT FOUND OR v_app.status <> 'pending' OR v_app.client_id IS NULL THEN
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        IF p_approve THEN
            UPDATE public.member_applications
               SET status = 'approved', decided_at = now(), decided_by = auth.uid(),
                   resolution_date = v_resolution, decision_note = p_note
             WHERE id = v_id;

            -- Chi era già sociə ed è rientratə mantiene il numero: si riattiva la riga esistente.
            IF EXISTS (SELECT 1 FROM public.members WHERE client_id = v_app.client_id) THEN
                UPDATE public.members
                   SET status = 'active', ceased_on = NULL, cease_reason = NULL, cease_note = NULL,
                       application_id = v_app.id, resolution_date = v_resolution
                 WHERE client_id = v_app.client_id
                RETURNING member_number INTO v_member_number;
            ELSE
                v_member_number := "internal"."next_member_number"(EXTRACT(YEAR FROM v_resolution)::integer);
                INSERT INTO public.members (client_id, member_number, application_id, admitted_on, resolution_date)
                VALUES (v_app.client_id, v_member_number, v_app.id, v_resolution, v_resolution);
            END IF;
        ELSE
            UPDATE public.member_applications
               SET status = 'rejected', decided_at = now(), decided_by = auth.uid(),
                   resolution_date = v_resolution, decision_note = p_note,
                   rejection_reason = p_rejection_reason
             WHERE id = v_id;
            v_member_number := NULL;
        END IF;

        v_decided := v_decided + 1;
        v_results := v_results || jsonb_build_object(
            'application_id', v_id,
            'client_id', v_app.client_id,
            'member_number', v_member_number
        );
    END LOOP;

    RETURN jsonb_build_object(
        'ok', true,
        'reason', CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
        'decided', v_decided,
        'skipped', v_skipped,
        'resolution_date', v_resolution,
        'results', v_results
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.staff_update_booking_status(p_booking_id uuid, p_status booking_status)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member_gate text;
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

  -- Partecipare richiede l'ammissione deliberata dal Consiglio Direttivo; per prenotare basta la
  -- quota pagata (A7). Per questo il controllo sta qui e non sulla prenotazione.
  IF p_status = 'attended' AND "internal"."members_only_enabled"() THEN
    v_member_gate := "internal"."member_booking_status"(v_booking.client_id);
    IF v_member_gate NOT IN ('ok', 'fee_due_grace') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'MEMBERSHIP_NOT_APPROVED',
                                'member_status', v_member_gate);
    END IF;
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."subscription_covers_activity"(p_subscription_id uuid, p_activity_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
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

CREATE OR REPLACE FUNCTION "internal"."sync_profile_from_client"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."update_activity_slug"()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Aggiorna lo slug quando discipline viene inserito o modificato
  IF NEW.discipline IS NOT NULL AND NEW.discipline != '' THEN
    NEW.slug := public.generate_slug_from_discipline(NEW.discipline);
  ELSE
    NEW.slug := NULL;
  END IF;
  
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."update_announcement_next_occurrence"()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."update_bug_reports_updated_at"()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW."updated_at" = now();
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION "internal"."update_expired_subscription_statuses"()
 RETURNS TABLE(updated_count integer, active_to_expired integer, active_to_completed integer, completed_to_expired integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."update_subscription_status_on_usage"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."update_subscription_status_on_usage_after_delete"()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION "internal"."update_updated_at_column"()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

-- L'unico riferimento non qualificato rimasto: si appoggiava al search_path, che ora non basta più.
CREATE OR REPLACE FUNCTION "public"."cron_update_subscription_statuses"() RETURNS "void"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    PERFORM "internal"."update_expired_subscription_statuses"();
END;
$$;

ALTER FUNCTION "public"."cron_update_subscription_statuses"() OWNER TO "postgres";

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Policy doppie su `lessons`
-- ─────────────────────────────────────────────────────────────────────────────
--
-- `lessons` aveva quattro policy, due coppie che dicevano la stessa cosa in modi diversi:
--   * "Clients can view their lessons" (TO authenticated) e `lessons_select_public_active`
--     (senza TO, quindi anche per anon);
--   * "Only staff can manage lessons" e `lessons_write_staff`, identiche.
-- Le policy in SELECT si sommano fra loro, quindi averne due significava che il permesso effettivo
-- era quello della più larga: difficile da leggere e facile da sbagliare. Ne restano tre, una per
-- ciascun pubblico.

DROP POLICY IF EXISTS "Clients can view their lessons" ON "public"."lessons";
DROP POLICY IF EXISTS "Only staff can manage lessons" ON "public"."lessons";
DROP POLICY IF EXISTS "lessons_select_public_active" ON "public"."lessons";

CREATE POLICY "lessons_select_anon" ON "public"."lessons"
    FOR SELECT TO "anon"
    USING ("deleted_at" IS NULL AND "is_individual" = false);

CREATE POLICY "lessons_select_authenticated" ON "public"."lessons"
    FOR SELECT TO "authenticated"
    USING (
        "public"."is_staff"()
        OR ("is_individual" = false AND "deleted_at" IS NULL)
        OR ("is_individual" = true AND "assigned_client_id" IS NOT NULL
            AND EXISTS (
                SELECT 1 FROM "public"."clients" c
                 WHERE c."id" = "lessons"."assigned_client_id"
                   AND c."profile_id" = "auth"."uid"()
                   AND c."deleted_at" IS NULL))
    );

COMMENT ON POLICY "lessons_select_anon" ON "public"."lessons" IS
    'Il sito pubblico legge il calendario: solo lezioni di gruppo non cancellate.';
COMMENT ON POLICY "lessons_select_authenticated" ON "public"."lessons" IS
    'Chi ha fatto accesso vede le lezioni di gruppo, le proprie individuali e — se è staff — tutto.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Policy senza `TO`
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Una policy senza `TO` vale per il ruolo `public`, che comprende anon. Finora non era sfruttabile,
-- perché senza GRANT sulla tabella la policy non serve a niente, ma è una rete di sicurezza in meno:
-- basterebbe un GRANT distratto perché diventi una porta. Qui ciascuna dichiara il proprio pubblico.

-- 5.1 — Dati pubblici del sito: leggibili senza accesso, per davvero
DROP POLICY IF EXISTS "activities_select_public" ON "public"."activities";
CREATE POLICY "activities_select_public" ON "public"."activities"
    FOR SELECT TO "anon", "authenticated" USING (true);

DROP POLICY IF EXISTS "operators_select_public_active" ON "public"."operators";
CREATE POLICY "operators_select_public_active" ON "public"."operators"
    FOR SELECT TO "anon", "authenticated" USING ("is_active" IS TRUE);

DROP POLICY IF EXISTS "plans_select_public_active" ON "public"."plans";
CREATE POLICY "plans_select_public_active" ON "public"."plans"
    FOR SELECT TO "anon", "authenticated"
    USING ("is_active" IS TRUE AND "deleted_at" IS NULL);

DROP POLICY IF EXISTS "plan_activities_select_public" ON "public"."plan_activities";
CREATE POLICY "plan_activities_select_public" ON "public"."plan_activities"
    FOR SELECT TO "anon", "authenticated" USING (true);

DROP POLICY IF EXISTS "promotions_select_public_active_now" ON "public"."promotions";
CREATE POLICY "promotions_select_public_active_now" ON "public"."promotions"
    FOR SELECT TO "anon", "authenticated"
    USING ("is_active" IS TRUE AND "deleted_at" IS NULL
           AND "starts_at" <= "now"()
           AND ("ends_at" IS NULL OR "ends_at" >= "now"()));

DROP POLICY IF EXISTS "feature_flags_select_all" ON "public"."feature_flags";
CREATE POLICY "feature_flags_select_all" ON "public"."feature_flags"
    FOR SELECT TO "anon", "authenticated" USING (true);

DROP POLICY IF EXISTS "feature_flags_write_admin" ON "public"."feature_flags";
CREATE POLICY "feature_flags_write_admin" ON "public"."feature_flags"
    FOR ALL TO "authenticated"
    USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());

-- 5.2 — Eventi. Ce n'erano due in SELECT, e quella per anon era la PIÙ LARGA: mostrava anche gli
-- eventi non attivi. Le view `public_site_*` non passano dalle policy (girano come il proprietario),
-- quindi il sito non ne ha bisogno. Ne resta una sola, sugli eventi attivi.
DROP POLICY IF EXISTS "events_select_public_active" ON "public"."events";
DROP POLICY IF EXISTS "events_select_public_for_site_view" ON "public"."events";
CREATE POLICY "events_select_public_active" ON "public"."events"
    FOR SELECT TO "anon", "authenticated"
    USING ("is_active" IS TRUE AND "deleted_at" IS NULL);

-- 5.3 — Il catalogo del Community Pass: resta leggibile, ma con il pubblico dichiarato
DROP POLICY IF EXISTS "pass_tiers_select_all" ON "public"."pass_tiers";
CREATE POLICY "pass_tiers_select_all" ON "public"."pass_tiers"
    FOR SELECT TO "anon", "authenticated" USING (true);

DROP POLICY IF EXISTS "pass_tier_benefits_select_all" ON "public"."pass_tier_benefits";
CREATE POLICY "pass_tier_benefits_select_all" ON "public"."pass_tier_benefits"
    FOR SELECT TO "anon", "authenticated" USING (true);

DROP POLICY IF EXISTS "pass_tiers_write_staff" ON "public"."pass_tiers";
CREATE POLICY "pass_tiers_write_staff" ON "public"."pass_tiers"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

DROP POLICY IF EXISTS "pass_tier_benefits_write_staff" ON "public"."pass_tier_benefits";
CREATE POLICY "pass_tier_benefits_write_staff" ON "public"."pass_tier_benefits"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- 5.4 — Dati personali: solo per chi ha fatto accesso, mai per anon
DROP POLICY IF EXISTS "memberships_select_own" ON "public"."memberships";
CREATE POLICY "memberships_select_own" ON "public"."memberships"
    FOR SELECT TO "authenticated"
    USING ("client_id" = "public"."get_my_client_id"());

DROP POLICY IF EXISTS "memberships_all_staff" ON "public"."memberships";
CREATE POLICY "memberships_all_staff" ON "public"."memberships"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

DROP POLICY IF EXISTS "bussola_requests_select_own" ON "public"."bussola_requests";
CREATE POLICY "bussola_requests_select_own" ON "public"."bussola_requests"
    FOR SELECT TO "authenticated"
    USING ("client_id" = "public"."get_my_client_id"());

DROP POLICY IF EXISTS "bussola_requests_all_staff" ON "public"."bussola_requests";
CREATE POLICY "bussola_requests_all_staff" ON "public"."bussola_requests"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

DROP POLICY IF EXISTS "feedback_select_own" ON "public"."feedback";
CREATE POLICY "feedback_select_own" ON "public"."feedback"
    FOR SELECT TO "authenticated"
    USING ("client_id" = "public"."get_my_client_id"());

DROP POLICY IF EXISTS "feedback_insert_own" ON "public"."feedback";
CREATE POLICY "feedback_insert_own" ON "public"."feedback"
    FOR INSERT TO "authenticated"
    WITH CHECK ("client_id" = "public"."get_my_client_id"());

DROP POLICY IF EXISTS "feedback_update_own" ON "public"."feedback";
CREATE POLICY "feedback_update_own" ON "public"."feedback"
    FOR UPDATE TO "authenticated"
    USING ("client_id" = "public"."get_my_client_id"())
    WITH CHECK ("client_id" = "public"."get_my_client_id"());

DROP POLICY IF EXISTS "feedback_all_staff" ON "public"."feedback";
CREATE POLICY "feedback_all_staff" ON "public"."feedback"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());
