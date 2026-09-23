-- Migration 20260923160800: regola "solo soci" (sessione 3, blocco 8)
--
-- Obiettivo: lo statuto riserva le attività ai soci, e la decisione H2 dice che vale DA SUBITO: per
-- prenotare bisogna prima iscriversi. Perché valga davvero, la regola sta nel DATABASE e non
-- nell'interfaccia: così vale anche per la webapp attuale, che non verrà più toccata.
--
-- Come funziona, seguendo A7 e A8:
--   * chi ha PAGATO la quota può PRENOTARE subito, anche prima della delibera del Consiglio Direttivo;
--   * per PARTECIPARE serve l'ammissione deliberata: il controllo sta su `staff_update_booking_status`
--     quando si segna "partecipata", non sulla prenotazione;
--   * chi è già sociə e non ha ancora pagato la quota dell'anno resta sociə e prenota come sempre fino
--     alla data di decadenza dell'anno (di partenza il 31 marzo). Dopo quella data, no.
--
-- L'interruttore `members_only` nasce SPENTO. Con l'interruttore spento queste funzioni si comportano
-- esattamente come prima: è la condizione per poter pubblicare oggi senza cambiare niente per nessuno.
-- Si accende alla fine della sessione 4, quando il gestionale sa registrare domande e quote.
--
-- Le funzioni di prenotazione qui sotto sono le stesse di prima, con SOLO il controllo aggiunto in
-- testa: firme identiche, nessun campo nuovo nella risposta tranne `member_status` nei casi di
-- rifiuto. I consumer mappano i motivi con uno `switch` che ha un `default`, quindi i due motivi nuovi
-- — NOT_A_MEMBER e MEMBERSHIP_FEE_DUE — non rompono nulla: al massimo mostrano un messaggio grezzo
-- finché il gestionale non li traduce (sessione 4).
--
-- Compatibilità: nessuna firma cambiata, nessuna tabella toccata, un interruttore nuovo spento.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 A7, A8, H2 e §5 (rischi).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. L'interruttore
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO "public"."feature_flags" ("key", "enabled", "description") VALUES
    ('members_only', false,
     'Riserva prenotazioni e partecipazione ai soci. Si accende alla fine della sessione 4, quando il gestionale sa registrare domande di ammissione e quote.')
ON CONFLICT ("key") DO NOTHING;

CREATE OR REPLACE FUNCTION "public"."members_only_enabled"() RETURNS boolean
    LANGUAGE "sql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key = 'members_only'), false);
$$;

ALTER FUNCTION "public"."members_only_enabled"() OWNER TO "postgres";
COMMENT ON FUNCTION "public"."members_only_enabled"() IS
    'Se la regola "solo soci" è accesa. Funzione interna: la usano le RPC di prenotazione.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Lo stato di una persona rispetto all'iscrizione
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."member_booking_status"("p_client_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
$$;

ALTER FUNCTION "public"."member_booking_status"("uuid") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."member_booking_status"("uuid") IS
    'Stato di una persona rispetto all''iscrizione: ok, fee_due_grace, pending_admission, fee_unpaid, fee_overdue, ceased, no_application. Prenotano i primi tre; partecipano i primi due.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Le RPC di prenotazione, con il controllo in testa
--    (corpi identici a prima: cambia solo il blocco aggiunto)
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
  IF public.members_only_enabled() THEN
    v_member_gate := public.member_booking_status(v_my_client_id);
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
  IF public.members_only_enabled() THEN
    v_member_gate := public.member_booking_status(v_my_client_id);
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
  IF public.members_only_enabled() THEN
    v_member_gate := public.member_booking_status(p_client_id);
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
  IF public.members_only_enabled() THEN
    v_member_gate := public.member_booking_status(p_client_id);
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
  IF p_status = 'attended' AND public.members_only_enabled() THEN
    v_member_gate := public.member_booking_status(v_booking.client_id);
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


-- I grant sopravvivono a CREATE OR REPLACE, ma li riscriviamo perché restino visibili qui.
GRANT EXECUTE ON FUNCTION "public"."book_lesson"("uuid", "uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."book_event"("uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."staff_book_lesson"("uuid", "uuid", "uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."staff_book_event"("uuid", "uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."staff_update_booking_status"("uuid", "public"."booking_status") TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. La prova segue la stessa regola, con la sua eccezione
-- ─────────────────────────────────────────────────────────────────────────────

-- Rispetto alla migrazione delle prove cambia solo il controllo aggiunto: la prova resta riservata ai
-- soci finché `trial_for_non_members` è spento, cioè finché il commercialista non conferma che si può
-- offrire anche a chi non è ancora iscrittə (domanda 1.2).
CREATE OR REPLACE FUNCTION "public"."create_trial_booking"(
    "p_lesson_id" "uuid",
    "p_client_id" "uuid",
    "p_created_by" "uuid",
    "p_skip_deadline" boolean DEFAULT false
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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

    v_member_gate := public.member_booking_status(p_client_id);
    v_is_member := v_member_gate IN ('ok', 'fee_due_grace');

    -- Con "solo soci" acceso, la prova resta riservata ai soci finché non si accende l'eccezione
    IF public.members_only_enabled() THEN
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
$$;

ALTER FUNCTION "public"."create_trial_booking"("uuid", "uuid", "uuid", boolean) OWNER TO "postgres";
COMMENT ON FUNCTION "public"."create_trial_booking"("uuid", "uuid", "uuid", boolean) IS
    'Motore della prenotazione di prova: capienza, scadenza, una prova per attività e regola "solo soci" con l''eccezione per i non soci. Funzione interna.';
