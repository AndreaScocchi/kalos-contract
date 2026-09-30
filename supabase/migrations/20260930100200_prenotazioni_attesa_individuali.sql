-- Migration 20260930100200: prenotazioni, lista d'attesa, lezioni individuali, prove
--
-- Dalla verifica generale del 30/09/2026 (docs/ISSUES.md §3.1).
--
-- 1. Un abbonamento eliminato dallo staff (`deleted_at`) non si usa più per prenotare, né dall'app
--    né dal gestionale; e la finestra di validità si guarda sul giorno italiano della lezione
--    (una lezione alle 00:30 del giorno dopo la scadenza passava).
-- 2. Una scheda archiviata dallo staff non prenota più dall'app (lezioni, prove, eventi, lista
--    d'attesa): prima `get_my_client_id` la trovava lo stesso.
-- 3. Lezioni individuali: cambiare l'abbonamento sposta l'ingresso dal vecchio al nuovo (prima il
--    vecchio ne guadagnava uno: un 10 ingressi arrivava a 11); cambiare la persona restituisce
--    l'ingresso una volta sola (prima andava in errore sull'indice unico, perché anche la disdetta
--    lo restituiva).
-- 4. Lista d'attesa dall'app solo per chi potrebbe poi prenotare: regola «solo soci» e un
--    abbonamento valido per quella lezione con ingressi, oppure la prova ancora disponibile. Prima
--    chiunque si metteva in fila e riceveva l'offerta, tenendo il posto per due ore.
-- 5. `staff_update_booking_status`: una prenotazione disdetta non torna «prenotata» o «presente»
--    cambiando lo stato (niente controllo dei posti né dell'ingresso): si prenota di nuovo, come fa
--    già il gestionale.
-- 6. Evento iniziato o concluso: dall'app non si disdice più (spariva l'«Incassa»).
-- 7. Una prova a cui non si è venutə (`no_show`) non diventa il primo ingresso dell'abbonamento.
--
-- Compatibilità: firme invariate. Codici nuovi: nessuno (si usano `CLIENT_NOT_FOUND`,
-- `SUBSCRIPTION_REQUIRED`, `NOT_A_MEMBER`, `MEMBERSHIP_FEE_DUE`, `CANNOT_CANCEL_CONCLUDED`, già
-- gestiti dalle app), più `BOOKING_CANCELED` solo per il gestionale.
--
-- migration-lint:allow revoke — reason: le REVOKE riguardano solo le due funzioni interne nuove di questa migrazione

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Funzioni di supporto
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."client_is_archived"(p_client_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (SELECT 1 FROM public.clients WHERE id = p_client_id AND deleted_at IS NOT NULL);
$$;

-- Chi potrebbe prenotare questa lezione se si liberasse un posto? NULL se sì, altrimenti il motivo.
CREATE OR REPLACE FUNCTION "internal"."lesson_booking_obstacle"(p_client_id uuid, p_lesson_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_lesson public.lessons%ROWTYPE;
    v_day date;
    v_gate text;
    v_trial_open boolean;
    v_trial_available boolean;
BEGIN
    SELECT * INTO v_lesson FROM public.lessons WHERE id = p_lesson_id;
    IF NOT FOUND THEN
        RETURN 'LESSON_NOT_FOUND';
    END IF;
    v_day := (v_lesson.starts_at AT TIME ZONE 'Europe/Rome')::date;

    -- La prova: attività con la prova, lezione di gruppo, nessuna prova già fatta per l'attività.
    v_trial_available := NOT v_lesson.is_individual
        AND EXISTS (SELECT 1 FROM public.activities a
                     WHERE a.id = v_lesson.activity_id AND a.deleted_at IS NULL AND a.trial_enabled)
        AND NOT EXISTS (SELECT 1 FROM public.trials t
                         WHERE t.client_id = p_client_id AND t.activity_id = v_lesson.activity_id
                           AND t.status <> 'canceled');

    IF "internal"."members_only_enabled"() THEN
        v_gate := "internal"."member_booking_status"(p_client_id);
        IF v_gate NOT IN ('ok', 'fee_due_grace', 'pending_admission') THEN
            SELECT COALESCE(enabled, false) INTO v_trial_open FROM public.feature_flags WHERE key = 'trial_for_non_members';
            IF NOT (COALESCE(v_trial_open, false) AND v_trial_available) THEN
                RETURN CASE WHEN v_gate IN ('fee_unpaid', 'fee_overdue') THEN 'MEMBERSHIP_FEE_DUE' ELSE 'NOT_A_MEMBER' END;
            END IF;
        END IF;
    END IF;

    IF v_trial_available THEN
        RETURN NULL;
    END IF;

    -- Un abbonamento valido quel giorno, che copre l'attività e ha ancora ingressi.
    IF EXISTS (
        SELECT 1
          FROM public.subscriptions s
          JOIN public.plans p ON p.id = s.plan_id
         WHERE s.client_id = p_client_id
           AND s.status = 'active'
           AND s.deleted_at IS NULL
           AND v_day BETWEEN s.started_at::date AND s.expires_at::date
           AND "internal"."subscription_covers_activity"(s.id, v_lesson.activity_id)
           AND (COALESCE(s.custom_entries, p.entries) IS NULL
                OR COALESCE(s.custom_entries, p.entries)
                   - COALESCE((SELECT sum(-su.delta) FROM public.subscription_usages su
                                WHERE su.subscription_id = s.id), 0) > 0)
    ) THEN
        RETURN NULL;
    END IF;

    RETURN 'SUBSCRIPTION_REQUIRED';
END;
$$;

REVOKE ALL ON FUNCTION "internal"."client_is_archived"(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION "internal"."lesson_booking_obstacle"(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1–2. Prenotazioni: abbonamenti eliminati, giorno italiano, schede archiviate
-- ─────────────────────────────────────────────────────────────────────────────

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
  v_window jsonb;
BEGIN
  -- Auth check
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Una scheda archiviata dallo staff non prenota più dall'app.
  IF "internal"."client_is_archived"(v_my_client_id) THEN
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

  -- Dalla sessione 8: unə cliente prenota sempre con un abbonamento. Il controllo prima stava solo
  -- nell'interfaccia della webapp. Senza abbonamento prenota solo lo staff (staff_book_lesson,
  -- con l'incasso da saldare); le prove passano da book_trial_lesson.
  IF p_subscription_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_REQUIRED');
  END IF;

  -- Validate subscription. Bloccata (dopo la lezione, come nel trigger del primo ingresso): due
  -- prenotazioni in contemporanea sullo stesso abbonamento non superano insieme ingressi e finestra.
  SELECT * INTO v_sub
  FROM public.subscriptions
  WHERE id = p_subscription_id
    AND client_id = v_my_client_id
    AND status = 'active'
    AND deleted_at IS NULL
    AND (v_starts_at AT TIME ZONE 'Europe/Rome')::date BETWEEN started_at::date AND expires_at::date
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_NOT_FOUND_OR_INACTIVE');
  END IF;

  -- Il piano può essere archiviato: gli abbonamenti già venduti restano validi (sessione 9)
  SELECT * INTO v_plan FROM public.plans WHERE id = v_sub.plan_id;

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

  -- D5: una lezione prima del primo ingresso accorcia la scadenza; le prenotazioni già fatte devono
  -- restarci dentro
  v_window := "internal"."first_entry_window_problem"(v_sub.id, (v_starts_at AT TIME ZONE 'Europe/Rome')::date);
  IF v_window IS NOT NULL THEN
    RETURN v_window;
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

    -- Capacity check (lesson is locked with FOR UPDATE, so this is atomic).
    -- Un posto offerto a chi è in lista d'attesa è occupato, tranne per chi l'ha ricevuto.
    SELECT count(*) INTO v_booked_count
    FROM public.bookings
    WHERE lesson_id = p_lesson_id AND status = 'booked';

    IF v_booked_count + "internal"."waitlist_seats_held"(p_lesson_id, v_my_client_id) >= v_capacity THEN
      RETURN "internal"."full_response"(p_lesson_id, v_my_client_id, v_booked_count, v_capacity);
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
  INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
  VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');

  RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED', 'booking_id', v_booking_id);
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
  v_window jsonb;
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

  -- Capacity for public lessons. Un posto offerto a chi è in lista d'attesa è occupato.
  IF NOT v_is_individual THEN
    SELECT COUNT(*) INTO v_booked_count
    FROM public.bookings
    WHERE lesson_id = p_lesson_id
      AND status = 'booked';
    IF v_booked_count + "internal"."waitlist_seats_held"(p_lesson_id, p_client_id) >= v_capacity THEN
      RETURN "internal"."full_response"(p_lesson_id, p_client_id, v_booked_count, v_capacity);
    END IF;
  END IF;

  -- Validate subscription if provided: valid on lesson date
  IF p_subscription_id IS NOT NULL THEN
    SELECT * INTO v_sub
    FROM public.subscriptions
    WHERE id = p_subscription_id
      AND client_id = p_client_id
      AND status = 'active'
      AND deleted_at IS NULL
      AND (v_starts_at AT TIME ZONE 'Europe/Rome')::date BETWEEN started_at::date AND expires_at::date
    FOR UPDATE;
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

    -- D5 (sessione 9): come in book_lesson
    v_window := "internal"."first_entry_window_problem"(v_sub.id, (v_starts_at AT TIME ZONE 'Europe/Rome')::date);
    IF v_window IS NOT NULL THEN
      RETURN v_window;
    END IF;
  END IF;

  -- Create or reactivate booking
  IF v_reactivate_booking IS NOT NULL THEN
    UPDATE public.bookings
    SET status = 'booked',
        created_at = now(),
        subscription_id = p_subscription_id,
        is_trial = false
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

CREATE OR REPLACE FUNCTION public.book_trial_lesson(p_lesson_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_client_id uuid;
    v_result    jsonb;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

  -- Una scheda archiviata dallo staff non prenota più dall'app.
  IF "internal"."client_is_archived"(v_client_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

    v_result := "internal"."create_trial_booking"(p_lesson_id, v_client_id, auth.uid(), false);

    -- Sessione 9: lo staff lo sa. Un problema dell'avviso non fa mai fallire la prenotazione.
    IF COALESCE((v_result->>'ok')::boolean, false) THEN
        BEGIN
            PERFORM "internal"."queue_trial_booked_staff"((v_result->>'trial_id')::uuid);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Avviso allo staff per la prova % non accodato: %', v_result->>'trial_id', SQLERRM;
        END;
    END IF;

    RETURN v_result;
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
  v_event public.events%ROWTYPE;
  v_booked_count integer;
  v_booking_id uuid;
  v_reactivate_booking_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();

  -- Una scheda archiviata dallo staff non prenota più dall'app.
  IF v_my_client_id IS NOT NULL AND "internal"."client_is_archived"(v_my_client_id) THEN
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

  -- Lock event row per prevenire race conditions
  SELECT * INTO v_event FROM public.events WHERE id = p_event_id FOR UPDATE;

  IF NOT FOUND OR v_event.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_FOUND');
  END IF;

  IF v_event.is_active IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_ACTIVE');
  END IF;

  -- Sessione 9: a un evento finito non ci si iscrive più
  IF "internal"."event_concluded"(v_event.starts_at, v_event.ends_at) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_CONCLUDED');
  END IF;

  -- Verifica che non sia già prenotato
  -- client_id è la fonte di verità: se l'utente ha un client_id, controlla solo quello
  IF v_my_client_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id AND client_id = v_my_client_id AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id AND user_id = v_user_id AND client_id IS NULL AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  END IF;

  -- Cerca se esiste una prenotazione cancellata da riattivare
  IF v_my_client_id IS NOT NULL THEN
    SELECT id INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id AND client_id = v_my_client_id AND status = 'canceled'
    LIMIT 1
    FOR UPDATE;
  ELSE
    SELECT id INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id AND user_id = v_user_id AND client_id IS NULL AND status = 'canceled'
    LIMIT 1
    FOR UPDATE;
  END IF;

  -- Capienza (se impostata), sempre: anche riattivando, il posto disdetto può essere stato preso
  -- da un'altra persona nel frattempo (sessione 9; prima la riattivazione saltava il controllo)
  IF v_event.capacity IS NOT NULL THEN
    SELECT count(*) INTO v_booked_count
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND status IN ('booked', 'attended', 'no_show');

    IF v_booked_count >= v_event.capacity THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;
  END IF;

  -- Riattiva prenotazione esistente o crea nuova
  -- client_id è la fonte di verità: se disponibile, usare SEMPRE client_id (user_id = NULL)
  IF v_reactivate_booking_id IS NOT NULL THEN
    UPDATE public.event_bookings
    SET status = 'booked',
        created_at = now()
    WHERE id = v_reactivate_booking_id;
    v_booking_id := v_reactivate_booking_id;
  ELSE
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Lezioni individuali
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."handle_individual_lesson_update"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_subscription_id uuid;
    v_booking_id uuid;
    v_old_booking_id uuid;
    v_subscription_changed boolean;
    v_day date := (NEW.starts_at AT TIME ZONE 'Europe/Rome')::date;
BEGIN
    IF OLD.is_individual = true AND NEW.is_individual = false THEN
        NEW.assigned_client_id := NULL;
        RETURN NEW;
    END IF;

    v_subscription_changed := OLD.assigned_subscription_id IS DISTINCT FROM NEW.assigned_subscription_id;

    IF NEW.is_individual = true
       AND NEW.assigned_subscription_id IS NOT NULL
       AND NOT "internal"."subscription_covers_activity"(NEW.assigned_subscription_id, NEW.activity_id) THEN
        RAISE EXCEPTION 'SUBSCRIPTION_DISCIPLINE_MISMATCH: subscription % does not cover activity %',
            NEW.assigned_subscription_id, NEW.activity_id
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.is_individual = true AND NEW.assigned_client_id IS NOT NULL THEN
        -- Cambia la persona: la prenotazione di prima si disdice e il suo ingresso torna indietro una
        -- volta sola (da «prenotata» lo restituisce già il trigger della disdetta).
        IF OLD.assigned_client_id IS DISTINCT FROM NEW.assigned_client_id AND OLD.assigned_client_id IS NOT NULL THEN
            SELECT id INTO v_old_booking_id
              FROM public.bookings
             WHERE lesson_id = NEW.id
               AND client_id = OLD.assigned_client_id
               AND status IN ('booked', 'attended', 'no_show')
             LIMIT 1;

            IF v_old_booking_id IS NOT NULL THEN
                UPDATE public.bookings SET status = 'canceled' WHERE id = v_old_booking_id;

                INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
                SELECT su.subscription_id, su.booking_id, +1, 'individual_lesson_client_changed'
                  FROM public.subscription_usages su
                 WHERE su.booking_id = v_old_booking_id
                   AND su.delta = -1
                   AND NOT EXISTS (SELECT 1 FROM public.subscription_usages p
                                    WHERE p.booking_id = v_old_booking_id AND p.delta = +1);
            END IF;
        END IF;

        SELECT id INTO v_booking_id
          FROM public.bookings
         WHERE lesson_id = NEW.id
           AND client_id = NEW.assigned_client_id
           AND status IN ('booked', 'attended', 'no_show')
         LIMIT 1;

        IF NEW.assigned_subscription_id IS NOT NULL THEN
            v_subscription_id := NEW.assigned_subscription_id;
        ELSE
            SELECT swr.id INTO v_subscription_id
              FROM public.subscriptions_with_remaining swr
              JOIN public.subscriptions s ON s.id = swr.id AND s.deleted_at IS NULL
             WHERE swr.client_id = NEW.assigned_client_id
               AND swr.status = 'active'
               AND v_day BETWEEN swr.started_at::date AND swr.expires_at::date
               AND (swr.remaining_entries IS NULL OR swr.remaining_entries > 0)
               AND "internal"."subscription_covers_activity"(swr.id, NEW.activity_id)
             ORDER BY swr.expires_at DESC NULLS LAST
             LIMIT 1;
        END IF;

        IF v_booking_id IS NOT NULL AND v_subscription_changed THEN
            -- Cambia l'abbonamento: l'ingresso si sposta dal vecchio al nuovo (una riga −1 per
            -- prenotazione), senza che il vecchio ne guadagni uno.
            UPDATE public.bookings SET subscription_id = v_subscription_id WHERE id = v_booking_id;

            IF v_subscription_id IS NULL THEN
                DELETE FROM public.subscription_usages WHERE booking_id = v_booking_id AND delta = -1;
            ELSIF EXISTS (SELECT 1 FROM public.subscription_usages WHERE booking_id = v_booking_id AND delta = -1) THEN
                UPDATE public.subscription_usages
                   SET subscription_id = v_subscription_id, reason = 'individual_lesson_subscription_changed'
                 WHERE booking_id = v_booking_id AND delta = -1;
            ELSE
                INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
                VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_subscription_changed');
            END IF;
        ELSIF v_booking_id IS NULL THEN
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Lista d'attesa dall'app
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."join_waitlist"(p_lesson_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_client_id uuid;
    v_obstacle text;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL OR "internal"."client_is_archived"(v_client_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    -- In fila solo chi, liberato il posto, potrebbe prenotarlo: altrimenti l'offerta terrebbe il
    -- posto per due ore a chi non può usarlo.
    v_obstacle := "internal"."lesson_booking_obstacle"(v_client_id, p_lesson_id);
    IF v_obstacle IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', v_obstacle);
    END IF;

    RETURN "internal"."waitlist_enqueue"(p_lesson_id, v_client_id, auth.uid());
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Stato di una prenotazione dal gestionale
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_update_booking_status"(p_booking_id uuid, p_status "public"."booking_status")
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_member_gate text;
    v_booking bookings%ROWTYPE;
BEGIN
    IF NOT is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
    END IF;

    IF p_status NOT IN ('booked', 'attended', 'no_show', 'canceled') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_STATUS');
    END IF;

    -- Una prenotazione disdetta ha già restituito l'ingresso e liberato il posto: per rimetterla si
    -- prenota di nuovo (controllo dei posti e dell'abbonamento), non si cambia lo stato.
    IF v_booking.status = 'canceled' AND p_status <> 'canceled' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_CANCELED');
    END IF;

    IF p_status = 'attended' AND "internal"."members_only_enabled"() THEN
        v_member_gate := "internal"."member_booking_status"(v_booking.client_id);
        IF v_member_gate NOT IN ('ok', 'fee_due_grace') THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'MEMBERSHIP_NOT_APPROVED', 'member_status', v_member_gate);
        END IF;
    END IF;

    UPDATE bookings SET status = p_status WHERE id = p_booking_id;

    RETURN jsonb_build_object('ok', true, 'reason', 'UPDATED', 'booking_id', p_booking_id);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Eventi
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cancel_event_booking(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_my_client_id uuid;
  v_is_staff boolean;
  v_booking_user_id uuid;
  v_booking_client_id uuid;
  v_status booking_status;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  v_is_staff := public.is_staff();

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
  IF NOT (
    v_is_staff
    OR (v_my_client_id IS NOT NULL AND v_booking_client_id = v_my_client_id)
    OR (v_my_client_id IS NULL AND v_booking_user_id = v_user_id AND v_booking_client_id IS NULL)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'UNAUTHORIZED');
  END IF;

  IF v_status = 'canceled' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_CANCELED');
  END IF;

  IF v_status IN ('attended', 'no_show') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CANNOT_CANCEL_CONCLUDED');
  END IF;

  -- Un evento iniziato o concluso non si disdice più dall'app: altrimenti un'iscrizione senza
  -- presenza segnata spariva, e con lei l'«Incassa» dello staff. Lo staff può ancora.
  IF NOT v_is_staff AND EXISTS (
    SELECT 1 FROM public.event_bookings eb JOIN public.events e ON e.id = eb.event_id
     WHERE eb.id = p_booking_id AND e.starts_at <= now()
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CANNOT_CANCEL_CONCLUDED');
  END IF;

  -- Sessione 9: un'iscrizione già pagata si disdice parlando con lo studio, che decide il rimborso
  -- (D4). Lo staff la disdice come prima.
  IF NOT v_is_staff AND EXISTS (
    SELECT 1 FROM public.transactions
     WHERE event_booking_id = p_booking_id AND refund_of_id IS NULL
       AND status IN ('paid', 'partially_refunded')
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'PAID_CONTACT_STUDIO');
  END IF;

  UPDATE public.event_bookings
  SET status = 'canceled'::booking_status
  WHERE id = p_booking_id;

  RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED');
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Prova convertita solo se fatta (o ancora da fare)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."convert_trial_on_new_subscription"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_trial public.trials%ROWTYPE;
BEGIN
    IF NEW.client_id IS NULL OR NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- La prova più vecchia ancora da convertire, fra quelle coperte dall'abbonamento: fatta, o
    -- prenotata e ancora da fare. Una prova a cui non si è venutə non è un ingresso.
    SELECT t.* INTO v_trial
      FROM public.trials t
     WHERE t.client_id = NEW.client_id
       AND t.status IN ('booked', 'attended')
       AND "internal"."subscription_covers_activity"(NEW.id, t.activity_id)
     ORDER BY t.booked_at
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
    VALUES (NEW.id, v_trial.booking_id, -1, 'TRIAL');

    UPDATE public.trials
       SET status = 'converted', converted_subscription_id = NEW.id, converted_at = now()
     WHERE id = v_trial.id;

    RETURN NEW;
END;
$$;
