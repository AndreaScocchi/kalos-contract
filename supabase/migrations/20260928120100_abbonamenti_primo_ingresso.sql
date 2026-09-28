-- Migration 20260928120100: abbonamenti che partono dal primo ingresso (sessione 9, D5)
--
-- D5: l'abbonamento comprato in app parte dal primo ingresso; se entro 60 giorni dall'acquisto non
-- c'è stato nessun ingresso, parte comunque. F2: una prova convertita scala un ingresso ma non
-- accorcia la validità, che parte dal primo ingresso dopo l'acquisto.
--
-- Come funziona:
--   - `started_at` resta il giorno dell'acquisto e non si sposta MAI: tutte le funzioni di
--     prenotazione (`book_lesson`, `staff_book_lesson`, il trigger delle lezioni individuali) e la
--     webapp accettano una lezione se cade fra `started_at` e `expires_at`. Spostare l'inizio
--     impedirebbe di prenotare proprio le lezioni che diventerebbero il primo ingresso.
--   - `activation_deadline` = acquisto + 60 giorni. Finché non c'è un ingresso, `expires_at` è
--     provvisoria: scadenza di attivazione + validità (il massimo possibile).
--   - Un ingresso è una prenotazione con quell'abbonamento, non di prova, prenotata / partecipata /
--     assente, su una lezione non cancellata. Le presenze si segnano a mano e spesso restano
--     "prenotata"; un'assenza ha già consumato l'ingresso. Le prove non hanno l'abbonamento sulla
--     prenotazione: F2 torna da sé.
--   - Inizio = il minore fra il giorno (Roma) del primo ingresso e la scadenza di attivazione;
--     `expires_at` = inizio + validità. Si ricalcola a ogni cambio di prenotazioni e lezioni.
--   - Se lo staff cambia a mano le date, ha deciso lui: il "primo ingresso" si spegne.
--
-- In più:
--   - `plans.sold_in_app`: il piano si compra dall'app (interruttore del gestionale, spento di
--     partenza). La vendita vera arriva con `…120200_pagamenti_app.sql`.
--   - `book_lesson` non risponde più `PLAN_NOT_FOUND` quando il piano è stato archiviato: la colonna
--     `plans.deleted_at` dice "gli abbonamenti esistenti restano validi", e col nuovo listino i piani
--     vecchi si archiviano. I clienti leggono già i piani dei propri abbonamenti
--     (`plans_select_own_subscription`).
--   - Guardia della finestra in `book_lesson` e `staff_book_lesson` (`OUTSIDE_SUBSCRIPTION_WINDOW`).
--
-- Compatibilità: colonne nuove con default, nessun abbonamento esistente cambia (il "primo ingresso"
-- vale solo per quelli nati con `starts_on_first_entry`). Il corpo delle due funzioni è quello della
-- v0.3.6 (20260928090000) e della sessione 6 (20260924150100), con le sole differenze dette sopra.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Colonne
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."plans"
    ADD COLUMN IF NOT EXISTS "sold_in_app" boolean DEFAULT false NOT NULL;

COMMENT ON COLUMN "public"."plans"."sold_in_app" IS
    'Il piano si compra dall''app con carta (sessione 9). Spento di partenza: lo accende lo staff dal gestionale. Serve anche l''interruttore `payments`.';

ALTER TABLE "public"."subscriptions"
    ADD COLUMN IF NOT EXISTS "starts_on_first_entry" boolean DEFAULT false NOT NULL,
    ADD COLUMN IF NOT EXISTS "activation_deadline" date,
    ADD COLUMN IF NOT EXISTS "first_entry_on" date;

COMMENT ON COLUMN "public"."subscriptions"."starts_on_first_entry" IS
    'D5: la validità parte dal primo ingresso (o dalla `activation_deadline`). Lo accende l''acquisto dall''app; si spegne se lo staff cambia le date a mano.';
COMMENT ON COLUMN "public"."subscriptions"."activation_deadline" IS
    'D5: se entro questa data non c''è un ingresso, l''abbonamento parte comunque da qui (acquisto + 60 giorni).';
COMMENT ON COLUMN "public"."subscriptions"."first_entry_on" IS
    'D5: giorno (ora italiana) del primo ingresso, calcolato dal database. NULL finché non c''è.';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subscriptions_first_entry_deadline') THEN
        ALTER TABLE "public"."subscriptions"
            ADD CONSTRAINT "subscriptions_first_entry_deadline"
            CHECK (NOT "starts_on_first_entry" OR "activation_deadline" IS NOT NULL);
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Calcolo del primo ingresso
-- ─────────────────────────────────────────────────────────────────────────────

-- Giorni di validità di un abbonamento: quelli fotografati all'acquisto, altrimenti quelli del piano
CREATE OR REPLACE FUNCTION "internal"."subscription_validity_days"("p_subscription_id" "uuid")
    RETURNS integer
    LANGUAGE "sql"
    STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT COALESCE(s.custom_validity_days, p.validity_days)
      FROM public.subscriptions s
      JOIN public.plans p ON p.id = s.plan_id
     WHERE s.id = p_subscription_id;
$$;

-- Giorni (ora italiana) delle lezioni che contano come ingressi di un abbonamento
CREATE OR REPLACE FUNCTION "internal"."subscription_entry_days"("p_subscription_id" "uuid")
    RETURNS TABLE("day" date)
    LANGUAGE "sql"
    STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT (l.starts_at AT TIME ZONE 'Europe/Rome')::date
      FROM public.bookings b
      JOIN public.lessons l ON l.id = b.lesson_id
     WHERE b.subscription_id = p_subscription_id
       AND b.is_trial = false
       AND b.status IN ('booked', 'attended', 'no_show')
       AND l.deleted_at IS NULL;
$$;

-- Inizio della validità se il primo ingresso fosse `p_first` (NULL = nessun ingresso)
CREATE OR REPLACE FUNCTION "internal"."first_entry_start"(
    "p_started_at" date, "p_activation_deadline" date, "p_first" date)
    RETURNS date
    LANGUAGE "sql"
    IMMUTABLE
    AS $$
    -- Mai prima dell'acquisto (una prenotazione vecchia spostata a mano su questo abbonamento)
    SELECT GREATEST(LEAST(COALESCE(p_first, p_activation_deadline), p_activation_deadline), p_started_at);
$$;

CREATE OR REPLACE FUNCTION "internal"."recompute_first_entry"("p_subscription_id" "uuid")
    RETURNS void
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_flag      boolean;
    v_sub       public.subscriptions%ROWTYPE;
    v_days      integer;
    v_first     date;
    v_expires   date;
BEGIN
    IF p_subscription_id IS NULL THEN
        RETURN;
    END IF;

    -- Quasi tutti gli abbonamenti non partono dal primo ingresso: si esce senza bloccare la riga
    SELECT starts_on_first_entry INTO v_flag FROM public.subscriptions WHERE id = p_subscription_id;
    IF NOT COALESCE(v_flag, false) THEN
        RETURN;
    END IF;

    SELECT * INTO v_sub FROM public.subscriptions WHERE id = p_subscription_id FOR UPDATE;
    IF NOT v_sub.starts_on_first_entry OR v_sub.deleted_at IS NOT NULL OR v_sub.status = 'canceled' THEN
        RETURN;
    END IF;

    v_days := "internal"."subscription_validity_days"(p_subscription_id);
    IF v_days IS NULL THEN
        RETURN;
    END IF;

    SELECT min(day) INTO v_first FROM "internal"."subscription_entry_days"(p_subscription_id);
    v_expires := "internal"."first_entry_start"(v_sub.started_at, v_sub.activation_deadline, v_first) + v_days;

    IF v_sub.first_entry_on IS DISTINCT FROM v_first OR v_sub.expires_at IS DISTINCT FROM v_expires THEN
        -- Il segnale dice alla guardia qui sotto che le date le cambia il database, non lo staff
        PERFORM set_config('kalos.first_entry', 'on', true);
        UPDATE public.subscriptions
           SET first_entry_on = v_first, expires_at = v_expires
         WHERE id = p_subscription_id;
        PERFORM set_config('kalos.first_entry', 'off', true);
    END IF;
END;
$$;

COMMENT ON FUNCTION "internal"."recompute_first_entry"("uuid") IS
    'D5: ricalcola primo ingresso e scadenza di un abbonamento che parte dal primo ingresso. Non fa nulla per gli altri.';

-- Una prenotazione nuova, disdetta, spostata su un altro abbonamento o su un'altra lezione
CREATE OR REPLACE FUNCTION "internal"."bookings_recompute_first_entry"()
    RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        PERFORM "internal"."recompute_first_entry"(OLD.subscription_id);
    END IF;
    IF TG_OP = 'INSERT'
       OR (TG_OP = 'UPDATE' AND NEW.subscription_id IS DISTINCT FROM OLD.subscription_id) THEN
        PERFORM "internal"."recompute_first_entry"(NEW.subscription_id);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS "bookings_recompute_first_entry" ON "public"."bookings";
CREATE TRIGGER "bookings_recompute_first_entry"
    AFTER INSERT OR DELETE OR UPDATE OF "status", "subscription_id", "lesson_id", "is_trial"
    ON "public"."bookings"
    FOR EACH ROW EXECUTE FUNCTION "internal"."bookings_recompute_first_entry"();

-- Una lezione spostata o cancellata cambia il giorno degli ingressi
CREATE OR REPLACE FUNCTION "internal"."lessons_recompute_first_entry"()
    RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_sub_id uuid;
BEGIN
    -- In ordine fisso: due modifiche contemporanee bloccano gli abbonamenti nello stesso ordine
    FOR v_sub_id IN
        SELECT DISTINCT b.subscription_id
          FROM public.bookings b
          JOIN public.subscriptions s ON s.id = b.subscription_id
         WHERE b.lesson_id = NEW.id AND s.starts_on_first_entry
         ORDER BY 1
    LOOP
        PERFORM "internal"."recompute_first_entry"(v_sub_id);
    END LOOP;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS "lessons_recompute_first_entry" ON "public"."lessons";
CREATE TRIGGER "lessons_recompute_first_entry"
    AFTER UPDATE OF "starts_at", "deleted_at" ON "public"."lessons"
    FOR EACH ROW
    WHEN (OLD."starts_at" IS DISTINCT FROM NEW."starts_at" OR OLD."deleted_at" IS DISTINCT FROM NEW."deleted_at")
    EXECUTE FUNCTION "internal"."lessons_recompute_first_entry"();

-- Lo staff che cambia le date a mano decide lui: il primo ingresso non comanda più
CREATE OR REPLACE FUNCTION "internal"."subscriptions_manual_dates_guard"()
    RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF OLD.starts_on_first_entry AND NEW.starts_on_first_entry
       AND (NEW.started_at IS DISTINCT FROM OLD.started_at OR NEW.expires_at IS DISTINCT FROM OLD.expires_at)
       AND COALESCE(current_setting('kalos.first_entry', true), 'off') <> 'on' THEN
        NEW.starts_on_first_entry := false;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "subscriptions_manual_dates_guard" ON "public"."subscriptions";
CREATE TRIGGER "subscriptions_manual_dates_guard"
    BEFORE UPDATE OF "started_at", "expires_at" ON "public"."subscriptions"
    FOR EACH ROW EXECUTE FUNCTION "internal"."subscriptions_manual_dates_guard"();

-- Una prenotazione PRIMA del primo ingresso ne diventa il nuovo primo e accorcia la scadenza. Se una
-- prenotazione già fatta resterebbe fuori, meglio dirlo subito che lasciarla scoperta.
CREATE OR REPLACE FUNCTION "internal"."first_entry_window_problem"("p_subscription_id" "uuid", "p_lesson_day" date)
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_sub       public.subscriptions%ROWTYPE;
    v_days      integer;
    v_expires   date;
    v_last      date;
BEGIN
    SELECT * INTO v_sub FROM public.subscriptions WHERE id = p_subscription_id;
    IF NOT FOUND OR NOT v_sub.starts_on_first_entry THEN
        RETURN NULL;
    END IF;
    IF v_sub.first_entry_on IS NOT NULL AND p_lesson_day >= v_sub.first_entry_on THEN
        RETURN NULL;
    END IF;

    v_days := "internal"."subscription_validity_days"(p_subscription_id);
    IF v_days IS NULL THEN
        RETURN NULL;
    END IF;
    v_expires := "internal"."first_entry_start"(v_sub.started_at, v_sub.activation_deadline, p_lesson_day) + v_days;

    SELECT max(day) INTO v_last FROM "internal"."subscription_entry_days"(p_subscription_id);
    IF v_last IS NOT NULL AND v_last > v_expires THEN
        RETURN jsonb_build_object(
            'ok', false, 'reason', 'OUTSIDE_SUBSCRIPTION_WINDOW',
            'valid_until', v_expires, 'last_entry_on', v_last);
    END IF;
    RETURN NULL;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. book_lesson: niente più PLAN_NOT_FOUND per i piani archiviati, guardia della finestra
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid" DEFAULT NULL::"uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
    AND v_starts_at::date BETWEEN started_at::date AND expires_at::date
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
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. staff_book_lesson: stessa guardia della finestra
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid" DEFAULT NULL::"uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
      AND v_starts_at::date BETWEEN started_at::date AND expires_at::date
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
$$;
