-- Migration 20260924150100: gruppi, luoghi, prove e lista d'attesa lato staff (sessione 6)
--
-- La sessione 3 ha messo nel database gruppi, luoghi, prove e lista d'attesa. Qui si collegano le
-- parti che servono perché il gestionale e il sito li usino davvero:
--
--   1. PROVE. Una prova disdetta bloccava per sempre una nuova prova della stessa attività (il
--      vincolo "una per attività" contava anche le disdette), e lo stato della prova non seguiva le
--      presenze. Ora si riprenota, e "presente", "assente" e "disdetta" arrivano sulla prova.
--      Chi riceve una prova inserita dallo staff riceve la conferma con l'invito all'app (F5).
--   2. PROMEMORIA con luogo e orario (F6). Dicevano "ti aspettiamo in studio", che non esiste più.
--      Ora rispettano anche chi ha spento sia push che email per i promemoria (prima partiva
--      comunque un'email).
--   3. LISTA D'ATTESA. Il posto offerto a chi è in fila non era protetto: chiunque prenotasse
--      nel frattempo se lo prendeva. Ora un'offerta in corso occupa il posto per tuttə, lo staff
--      mette in fila e toglie dalla fila, e chi prenota esce dalla fila da solə. Il vecchio vincolo
--      (lezione, utente) impediva di rimettersi in fila dopo esserne uscitə: si riusa la riga.
--   4. QUESTIONARIO DOPO LA PROVA (F6), come feedback di tipo `trial`. Lo compila l'app (sessione
--      11); il gestionale lo mostra da subito.
--   5. RICOSTRUZIONE DEL SITO (B10). Luoghi, gruppi, attività, eventi e l'interruttore del 5x1000
--      segnano "da ricostruire"; un job ogni 5 minuti, dopo 3 minuti senza altre modifiche e al
--      massimo una volta ogni 10, chiama l'edge function `site-rebuild`, che chiama il build hook
--      di Netlify. Così le pagine prerenderizzate (anteprime, sitemap, pagine per comune) si
--      aggiornano senza un deploy a mano.
--   6. 5x1000 (B8): interruttore spento, da accendere dopo RUNTS e accreditamento.
--   7. GRUPPI (B3, B12): le attività nei gruppi decisi e un'immagine di partenza per gruppo.
--   8. SITO: `public_site_events` smette di mostrare gli eventi non pubblicati e aggiunge indirizzo
--      del luogo e contributo, che il sito dichiarava ma non riceveva mai.
--
-- Compatibilità: colonne, tabelle, funzioni e trigger nuovi; funzioni esistenti riscritte con la
-- stessa firma e lo stesso contratto di risposta (i codici nuovi sono solo in aggiunta);
-- `waitlist.user_id` perde il NOT NULL (lo staff mette in fila anche chi non ha l'app).
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 B3, B8, B10, F3–F7, H5.

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Helper di testo per le notifiche
-- ─────────────────────────────────────────────────────────────────────────────

-- "martedì 29/09 alle 18:30", in ora italiana. to_char('TMDay') dipende dalla lingua del server.
CREATE OR REPLACE FUNCTION "internal"."format_when_it"("p_ts" timestamp with time zone)
    RETURNS "text"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
    SELECT (ARRAY['domenica','lunedì','martedì','mercoledì','giovedì','venerdì','sabato'])
               [EXTRACT(DOW FROM p_ts AT TIME ZONE 'Europe/Rome')::int + 1]
           || ' ' || to_char(p_ts AT TIME ZONE 'Europe/Rome', 'DD/MM')
           || ' alle ' || to_char(p_ts AT TIME ZONE 'Europe/Rome', 'HH24:MI');
$$;

ALTER FUNCTION "internal"."format_when_it"(timestamp with time zone) OWNER TO "postgres";

-- "Sala Media, Via Roma 1, Staranzano": come si scrive un luogo in una notifica. NULL se manca.
CREATE OR REPLACE FUNCTION "internal"."location_label"("p_location_id" "uuid")
    RETURNS "text"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
    SELECT concat_ws(', ', l.name, NULLIF(btrim(l.address_street), ''), l.city)
      FROM public.locations l
     WHERE l.id = p_location_id;
$$;

ALTER FUNCTION "internal"."location_label"("uuid") OWNER TO "postgres";

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Lista d'attesa: posti impegnati dalle offerte
-- ─────────────────────────────────────────────────────────────────────────────

-- Posti "promessi" a chi è in fila e non ancora prenotato: un'offerta in corso vale come un posto
-- occupato per tuttə, tranne per chi l'ha ricevuta.
CREATE OR REPLACE FUNCTION "internal"."waitlist_seats_held"("p_lesson_id" "uuid", "p_client_id" "uuid")
    RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT count(*)::int
      FROM public.waitlist w
     WHERE w.lesson_id = p_lesson_id
       AND w.status = 'offered'
       AND w.expires_at > now()
       AND w.client_id IS DISTINCT FROM p_client_id;
$$;

ALTER FUNCTION "internal"."waitlist_seats_held"("uuid", "uuid") OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."waitlist_seats_held"("uuid", "uuid") IS
    'Posti tenuti da offerte della lista d''attesa ancora valide, escluse quelle fatte a p_client_id. Le prenotazioni li contano come occupati.';

-- La prima offerta in scadenza, per dire allo staff fino a quando il posto è tenuto.
CREATE OR REPLACE FUNCTION "internal"."waitlist_first_offer_expiry"("p_lesson_id" "uuid", "p_client_id" "uuid")
    RETURNS timestamp with time zone
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT min(w.expires_at)
      FROM public.waitlist w
     WHERE w.lesson_id = p_lesson_id
       AND w.status = 'offered'
       AND w.expires_at > now()
       AND w.client_id IS DISTINCT FROM p_client_id;
$$;

ALTER FUNCTION "internal"."waitlist_first_offer_expiry"("uuid", "uuid") OWNER TO "postgres";

-- Risposta "piena" uguale a prima (FULL), con in più il motivo quando a riempirla è un'offerta.
-- Le app che conoscono solo FULL continuano a funzionare.
CREATE OR REPLACE FUNCTION "internal"."full_response"("p_lesson_id" "uuid", "p_client_id" "uuid",
                                                      "p_booked" integer, "p_capacity" integer)
    RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF p_booked < p_capacity THEN
        RETURN jsonb_build_object(
            'ok', false, 'reason', 'FULL', 'waitlist_offer', true,
            'offer_expires_at', "internal"."waitlist_first_offer_expiry"(p_lesson_id, p_client_id));
    END IF;
    RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
END;
$$;

ALTER FUNCTION "internal"."full_response"("uuid", "uuid", integer, integer) OWNER TO "postgres";

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Prenotazioni: le offerte occupano il posto
-- ─────────────────────────────────────────────────────────────────────────────

-- 2.1 — book_lesson: identica a prima, tranne il controllo della capienza.
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
  IF p_subscription_id IS NOT NULL THEN
    INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
    VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');
  END IF;

  RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED', 'booking_id', v_booking_id);
END;
$$;

-- 2.2 — staff_book_lesson: capienza con le offerte e, riattivando una prenotazione disdetta che
-- era una prova, la si riporta a prenotazione normale (ora ha un abbonamento, o nessuno).
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

-- 2.3 — Chi prenota esce dalla fila, da qualunque strada arrivi la prenotazione.
CREATE OR REPLACE FUNCTION "internal"."close_waitlist_on_booking"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    UPDATE public.waitlist
       SET status = 'booked'
     WHERE lesson_id = NEW.lesson_id
       AND client_id = NEW.client_id
       AND status IN ('waiting', 'offered');
    RETURN NEW;
END;
$$;

ALTER FUNCTION "internal"."close_waitlist_on_booking"() OWNER TO "postgres";

CREATE OR REPLACE TRIGGER "bookings_close_waitlist"
    AFTER INSERT OR UPDATE OF "status" ON "public"."bookings"
    FOR EACH ROW
    WHEN (NEW."status" = 'booked'::"public"."booking_status" AND NEW."client_id" IS NOT NULL)
    EXECUTE FUNCTION "internal"."close_waitlist_on_booking"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Lista d'attesa: offerte, fila, staff
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."waitlist" ALTER COLUMN "user_id" DROP NOT NULL;

COMMENT ON COLUMN "public"."waitlist"."user_id" IS
    'Account di chi è in fila, quando si è messə in fila dall''app. NULL se l''ha messə in fila lo staff e la persona non ha l''app: fa fede `client_id`.';

-- 3.1 — Offre il posto al primo della fila. Come prima, ma il testo dice anche come prenotare
-- quando la persona non ha l'app (l'ha messa in fila lo staff).
CREATE OR REPLACE FUNCTION "internal"."promote_from_waitlist"("p_lesson_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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

    -- Prima si chiudono le offerte scadute
    UPDATE public.waitlist
       SET status = 'expired'
     WHERE lesson_id = p_lesson_id AND status = 'offered' AND expires_at <= now();

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
                || ' di ' || "internal"."format_when_it"(v_lesson.starts_at)
                || '. Lo teniamo per te fino alle '
                || to_char(v_expires AT TIME ZONE 'Europe/Rome', 'HH24:MI')
                || ': prenotalo dall''app, oppure scrivici.',
            jsonb_build_object('lesson_id', p_lesson_id, 'waitlist_id', v_next.id, 'expires_at', v_expires),
            now()
        );
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'OFFERED',
                              'client_id', v_next.client_id, 'expires_at', v_expires);
END;
$$;

-- 3.2 — Offre tutti i posti liberi, uno per persona in fila (una disdetta ne libera uno, ma
-- un aumento di capienza o una scadenza possono liberarne di più).
CREATE OR REPLACE FUNCTION "internal"."fill_waitlist_offers"("p_lesson_id" "uuid")
    RETURNS integer
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_offers integer := 0;
    v_result jsonb;
BEGIN
    -- Il tetto evita un ciclo infinito se qualcosa andasse storto: più di 50 offerte in una volta
    -- su una lezione non hanno senso.
    FOR i IN 1..50 LOOP
        v_result := "internal"."promote_from_waitlist"(p_lesson_id);
        EXIT WHEN NOT COALESCE((v_result->>'ok')::boolean, false);
        v_offers := v_offers + 1;
    END LOOP;
    RETURN v_offers;
END;
$$;

ALTER FUNCTION "internal"."fill_waitlist_offers"("uuid") OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."fill_waitlist_offers"("uuid") IS
    'Offre i posti liberi a chi è in fila, uno a testa, finché ci sono posti e persone in attesa. Chiude prima le offerte scadute.';

-- 3.3 — Alla disdetta: tutti i posti liberi, non solo uno.
CREATE OR REPLACE FUNCTION "internal"."offer_waitlist_on_booking_cancel"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    PERFORM "internal"."fill_waitlist_offers"(NEW.lesson_id);
    RETURN NEW;
END;
$$;

-- 3.4 — Quando lo staff aumenta i posti di una lezione piena.
CREATE OR REPLACE FUNCTION "internal"."offer_waitlist_on_capacity_increase"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    PERFORM "internal"."fill_waitlist_offers"(NEW.id);
    RETURN NEW;
END;
$$;

ALTER FUNCTION "internal"."offer_waitlist_on_capacity_increase"() OWNER TO "postgres";

CREATE OR REPLACE TRIGGER "lessons_offer_waitlist_on_capacity_increase"
    AFTER UPDATE OF "capacity" ON "public"."lessons"
    FOR EACH ROW
    WHEN (NEW."capacity" > OLD."capacity" AND NEW."deleted_at" IS NULL)
    EXECUTE FUNCTION "internal"."offer_waitlist_on_capacity_increase"();

-- 3.5 — Il job della lista d'attesa: chiude le offerte scadute e passa al successivo anche
-- quando nessuno disdice. Si aggancia a pg_cron in produzione ogni 5 minuti (vedi piano §0-sexies).
CREATE OR REPLACE FUNCTION "internal"."cron_waitlist"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_lesson_id uuid;
    v_lessons   integer := 0;
    v_offers    integer := 0;
BEGIN
    FOR v_lesson_id IN
        SELECT DISTINCT w.lesson_id
          FROM public.waitlist w
          JOIN public.lessons l ON l.id = w.lesson_id
         WHERE w.status IN ('waiting', 'offered')
           AND l.deleted_at IS NULL
           AND l.starts_at > now()
    LOOP
        v_lessons := v_lessons + 1;
        v_offers := v_offers + "internal"."fill_waitlist_offers"(v_lesson_id);
    END LOOP;

    -- Chi è ancora in fila per una lezione ormai chiusa non riceverà più offerte
    UPDATE public.waitlist w
       SET status = 'expired'
      FROM public.lessons l
     WHERE l.id = w.lesson_id
       AND w.status IN ('waiting', 'offered')
       AND now() > l.starts_at - make_interval(mins => COALESCE(l.booking_deadline_minutes, 30));

    RETURN jsonb_build_object('ok', true, 'lessons', v_lessons, 'offers', v_offers);
END;
$$;

ALTER FUNCTION "internal"."cron_waitlist"() OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."cron_waitlist"() IS
    'Job della lista d''attesa (pg_cron, solo in produzione): offerte scadute, posti liberati senza una disdetta, fila chiusa alla scadenza delle prenotazioni.';

-- La vecchia funzione di scadenza resta, ma ora fa lo stesso lavoro del job.
CREATE OR REPLACE FUNCTION "internal"."expire_waitlist_offers"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    RETURN "internal"."cron_waitlist"();
END;
$$;

-- 3.6 — Mettersi in fila dall'app: "piena" conta anche i posti offerti, e chi era uscitə dalla
-- fila ci rientra (in fondo) invece di scontrarsi col vecchio vincolo (lezione, utente).
CREATE OR REPLACE FUNCTION "internal"."waitlist_enqueue"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_user_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_lesson    public.lessons%ROWTYPE;
    v_booked    integer;
    v_position  integer;
    v_id        uuid;
BEGIN
    SELECT * INTO v_lesson FROM public.lessons WHERE id = p_lesson_id FOR UPDATE;
    IF NOT FOUND OR v_lesson.deleted_at IS NOT NULL OR v_lesson.is_individual THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    IF now() > v_lesson.starts_at - make_interval(mins => COALESCE(v_lesson.booking_deadline_minutes, 30)) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
    END IF;

    IF EXISTS (SELECT 1 FROM public.bookings
                WHERE lesson_id = p_lesson_id AND client_id = p_client_id AND status = 'booked') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    -- Ci si mette in fila solo se la lezione è piena, contando i posti offerti ad altrə
    SELECT count(*) INTO v_booked
      FROM public.bookings WHERE lesson_id = p_lesson_id AND status = 'booked';
    IF v_booked + "internal"."waitlist_seats_held"(p_lesson_id, p_client_id) < v_lesson.capacity THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FULL');
    END IF;

    IF EXISTS (SELECT 1 FROM public.waitlist
                WHERE lesson_id = p_lesson_id AND client_id = p_client_id
                  AND status IN ('waiting', 'offered')) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_IN_WAITLIST');
    END IF;

    SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
      FROM public.waitlist WHERE lesson_id = p_lesson_id;

    -- Una riga passata della stessa persona (uscita, scaduta, prenotata e poi disdetta) si riusa
    SELECT id INTO v_id
      FROM public.waitlist
     WHERE lesson_id = p_lesson_id
       AND (client_id = p_client_id OR (p_user_id IS NOT NULL AND user_id = p_user_id))
     ORDER BY created_at DESC
     LIMIT 1;

    IF v_id IS NOT NULL THEN
        UPDATE public.waitlist
           SET status = 'waiting', position = v_position, client_id = p_client_id,
               user_id = COALESCE(p_user_id, user_id),
               offered_at = NULL, expires_at = NULL, notified_at = NULL, created_at = now()
         WHERE id = v_id;
    ELSE
        INSERT INTO public.waitlist (lesson_id, client_id, user_id, status, position)
        VALUES (p_lesson_id, p_client_id, p_user_id, 'waiting', v_position)
        RETURNING id INTO v_id;
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'JOINED',
                              'waitlist_id', v_id, 'position', v_position);
END;
$$;

ALTER FUNCTION "internal"."waitlist_enqueue"("uuid", "uuid", "uuid") OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."waitlist_enqueue"("uuid", "uuid", "uuid") IS
    'Motore comune di join_waitlist e staff_add_to_waitlist: lezione piena (offerte comprese), niente doppioni, riuso della riga di chi era già statə in fila.';

CREATE OR REPLACE FUNCTION "public"."join_waitlist"("p_lesson_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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

    RETURN "internal"."waitlist_enqueue"(p_lesson_id, v_client_id, auth.uid());
END;
$$;

-- 3.7 — Lo staff mette in fila chi chiama o passa in studio.
CREATE OR REPLACE FUNCTION "public"."staff_add_to_waitlist"("p_lesson_id" "uuid", "p_client_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_profile_id uuid;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    SELECT profile_id INTO v_profile_id
      FROM public.clients WHERE id = p_client_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    RETURN "internal"."waitlist_enqueue"(p_lesson_id, p_client_id, v_profile_id);
END;
$$;

ALTER FUNCTION "public"."staff_add_to_waitlist"("uuid", "uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_add_to_waitlist"("uuid", "uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_add_to_waitlist"("uuid", "uuid") IS
    'Lo staff mette in lista d''attesa una persona per una lezione piena. Stesse regole della fila dall''app.';

-- 3.8 — Lo staff toglie qualcunə dalla fila; se aveva un'offerta, il posto passa al successivo.
CREATE OR REPLACE FUNCTION "public"."staff_remove_from_waitlist"("p_waitlist_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_lesson_id uuid;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    UPDATE public.waitlist
       SET status = 'left'
     WHERE id = p_waitlist_id AND status IN ('waiting', 'offered')
    RETURNING lesson_id INTO v_lesson_id;

    IF v_lesson_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_IN_WAITLIST');
    END IF;

    PERFORM "internal"."fill_waitlist_offers"(v_lesson_id);
    RETURN jsonb_build_object('ok', true, 'reason', 'LEFT');
END;
$$;

ALTER FUNCTION "public"."staff_remove_from_waitlist"("uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_remove_from_waitlist"("uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_remove_from_waitlist"("uuid") IS
    'Toglie una persona dalla lista d''attesa. Se aveva un posto offerto, lo offre al successivo.';

-- leave_waitlist passa a fill_waitlist_offers per coerenza con le altre uscite dalla fila.
CREATE OR REPLACE FUNCTION "public"."leave_waitlist"("p_lesson_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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

    PERFORM "internal"."fill_waitlist_offers"(p_lesson_id);
    RETURN jsonb_build_object('ok', true, 'reason', 'LEFT');
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Prove
-- ─────────────────────────────────────────────────────────────────────────────

-- 4.1 — Motore della prova. Rispetto a prima: una prova DISDETTA non conta come usata (la stessa
-- riga si riusa per la nuova data), e i posti offerti alla lista d'attesa sono occupati.
CREATE OR REPLACE FUNCTION "internal"."create_trial_booking"(
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
    v_canceled_trial_id uuid;
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

    -- Una prova per attività (F3). Una prova disdetta non è stata fatta: si può riprenotare.
    IF EXISTS (SELECT 1 FROM public.trials
                WHERE client_id = p_client_id AND activity_id = v_activity.id
                  AND status <> 'canceled') THEN
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

    -- La prova occupa un posto come le altre prenotazioni (F3), e rispetta le offerte in corso
    SELECT count(*) INTO v_booked_count
      FROM public.bookings WHERE lesson_id = p_lesson_id AND status = 'booked';
    IF v_booked_count + "internal"."waitlist_seats_held"(p_lesson_id, p_client_id) >= v_lesson.capacity THEN
        RETURN "internal"."full_response"(p_lesson_id, p_client_id, v_booked_count, v_lesson.capacity);
    END IF;

    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status, is_trial)
    VALUES (p_lesson_id, p_client_id, NULL, 'booked', true)
    ON CONFLICT (lesson_id, client_id) WHERE status = 'booked' AND client_id IS NOT NULL
    DO NOTHING
    RETURNING id INTO v_booking_id;

    IF v_booking_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    SELECT id INTO v_canceled_trial_id
      FROM public.trials
     WHERE client_id = p_client_id AND activity_id = v_activity.id AND status = 'canceled'
     FOR UPDATE;

    IF v_canceled_trial_id IS NOT NULL THEN
        UPDATE public.trials
           SET lesson_id = p_lesson_id,
               booking_id = v_booking_id,
               status = 'booked',
               booked_at = now(),
               was_member_at_booking = v_is_member,
               created_by = p_created_by
         WHERE id = v_canceled_trial_id
        RETURNING id INTO v_trial_id;
    ELSE
        INSERT INTO public.trials (client_id, activity_id, lesson_id, booking_id,
                                   was_member_at_booking, created_by)
        VALUES (p_client_id, v_activity.id, p_lesson_id, v_booking_id, v_is_member, p_created_by)
        RETURNING id INTO v_trial_id;
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED',
                              'booking_id', v_booking_id, 'trial_id', v_trial_id);
END;
$$;

-- 4.2 — Lo stato della prova segue la prenotazione: presente, assente, disdetta, riattivata.
-- Una prova già convertita resta convertita (l'abbonamento è stato comprato; se la lezione di prova
-- viene disdetta, l'ingresso torna all'abbonamento come per ogni disdetta).
CREATE OR REPLACE FUNCTION "internal"."sync_trial_status_from_booking"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    UPDATE public.trials
       SET status = CASE NEW.status
                        WHEN 'attended' THEN 'attended'
                        WHEN 'no_show'  THEN 'no_show'
                        WHEN 'canceled' THEN 'canceled'
                        ELSE 'booked'
                    END::public.trial_status
     WHERE booking_id = NEW.id
       AND status <> 'converted';
    RETURN NEW;
END;
$$;

ALTER FUNCTION "internal"."sync_trial_status_from_booking"() OWNER TO "postgres";

CREATE OR REPLACE TRIGGER "bookings_sync_trial_status"
    AFTER UPDATE OF "status" ON "public"."bookings"
    FOR EACH ROW
    WHEN (NEW."is_trial" AND OLD."status" IS DISTINCT FROM NEW."status")
    EXECUTE FUNCTION "internal"."sync_trial_status_from_booking"();

-- 4.3 — Conferma della prova inserita dallo staff, con l'invito all'app (F5).
CREATE OR REPLACE FUNCTION "internal"."queue_trial_booked"("p_trial_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_trial     public.trials%ROWTYPE;
    v_lesson    public.lessons%ROWTYPE;
    v_client    public.clients%ROWTYPE;
    v_activity  text;
    v_place     text;
    v_channel   public.notification_channel;
BEGIN
    SELECT * INTO v_trial FROM public.trials WHERE id = p_trial_id;
    IF NOT FOUND OR v_trial.lesson_id IS NULL THEN
        RETURN;
    END IF;

    SELECT * INTO v_lesson FROM public.lessons WHERE id = v_trial.lesson_id;
    SELECT * INTO v_client FROM public.clients WHERE id = v_trial.client_id;
    SELECT name INTO v_activity FROM public.activities WHERE id = v_trial.activity_id;
    v_place := "internal"."location_label"(v_lesson.location_id);

    v_channel := "internal"."get_notification_channel"(v_trial.client_id, 'trial_booked');
    -- Senza canale, o con l'email come canale ma senza indirizzo, non c'è nessuno da avvisare
    IF v_channel IS NULL OR (v_channel = 'email' AND NULLIF(btrim(COALESCE(v_client.email, '')), '') IS NULL) THEN
        RETURN;
    END IF;

    INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
    VALUES (
        v_trial.client_id, 'trial_booked', v_channel,
        'La tua lezione di prova di ' || COALESCE(v_activity, 'Studio Kalòs'),
        'Ti aspettiamo ' || "internal"."format_when_it"(v_lesson.starts_at)
            || COALESCE(' presso ' || v_place, '') || '. '
            || CASE WHEN v_client.profile_id IS NOT NULL
                    THEN 'La trovi tra le tue prenotazioni nell''app, da dove puoi anche disdirla.'
                    ELSE 'Nell''app di Studio Kalòs trovi il calendario e le tue prenotazioni: registrati con questa email e la trovi già lì.'
               END,
        jsonb_build_object('lesson_id', v_lesson.id, 'trial_id', v_trial.id,
                           'booking_id', v_trial.booking_id, 'location_id', v_lesson.location_id),
        now()
    );
END;
$$;

ALTER FUNCTION "internal"."queue_trial_booked"("uuid") OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."queue_trial_booked"("uuid") IS
    'Accoda la conferma di una prova inserita dallo staff: quando, dove, e l''invito all''app per chi non ce l''ha (F5).';

CREATE OR REPLACE FUNCTION "public"."staff_book_trial"("p_lesson_id" "uuid", "p_client_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_result jsonb;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clients WHERE id = p_client_id AND deleted_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    -- Allo staff la scadenza non si applica: sta parlando con la persona di persona
    v_result := "internal"."create_trial_booking"(p_lesson_id, p_client_id, auth.uid(), true);

    IF COALESCE((v_result->>'ok')::boolean, false) THEN
        PERFORM "internal"."queue_trial_booked"((v_result->>'trial_id')::uuid);
    END IF;

    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."staff_create_client_and_book_trial"(
    "p_lesson_id" "uuid",
    "p_first_name" "text",
    "p_last_name" "text",
    "p_phone" "text",
    "p_email" "text"
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_full_name text;
    v_email     text := NULLIF(btrim(lower(COALESCE(p_email, ''))), '');
    v_result    jsonb;
    v_created   boolean := false;
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
        v_created := true;
    END IF;

    v_result := "internal"."create_trial_booking"(p_lesson_id, v_client_id, auth.uid(), true);

    IF COALESCE((v_result->>'ok')::boolean, false) THEN
        PERFORM "internal"."queue_trial_booked"((v_result->>'trial_id')::uuid);
    ELSIF v_created THEN
        -- La prova non è andata (lezione piena, prova non disponibile…): la scheda appena creata
        -- non serve a nessuno e resterebbe un doppione quando si riprova.
        DELETE FROM public.clients WHERE id = v_client_id;
        v_client_id := NULL;
    END IF;

    RETURN v_result || jsonb_build_object('client_id', v_client_id, 'client_created', v_created AND v_client_id IS NOT NULL);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Promemoria con luogo e orario (F6)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."queue_lesson_reminders"() RETURNS "json"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
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

    -- Evening reminder: lessons tomorrow, schedule for 20:00 today. Only queue if it's before 20:00.
    -- Luogo e orario nel testo (F6). Chi ha spento sia push che email non riceve nulla: prima
    -- partiva comunque un'email.
    IF v_now < v_today_8pm THEN
        INSERT INTO "public"."notification_queue" (
            client_id, category, channel, title, body, data, scheduled_for
        )
        SELECT
            x.client_id,
            'lesson_reminder'::"public"."notification_category",
            x.channel,
            CASE WHEN x.is_trial
                 THEN 'Domani alle ' || TO_CHAR(x.starts_at AT TIME ZONE 'Europe/Rome', 'HH24:MI')
                      || ' la tua lezione di prova di ' || x.activity
                 ELSE 'Domani alle ' || TO_CHAR(x.starts_at AT TIME ZONE 'Europe/Rome', 'HH24:MI')
                      || ': ' || x.activity || ' con ' || COALESCE(x.operator, 'lo staff')
            END,
            CASE WHEN x.place IS NOT NULL
                 THEN 'Ti aspettiamo presso ' || x.place || '.' || COALESCE(' ' || NULLIF(btrim(x.access_notes), ''), '')
                 ELSE 'Preparati per la tua lezione, ti aspettiamo!'
            END,
            jsonb_build_object(
                'lesson_id', x.lesson_id,
                'booking_id', x.booking_id,
                'type', 'evening',
                'activity', x.activity,
                'operator', x.operator,
                'starts_at', x.starts_at,
                'location_id', x.location_id,
                'is_trial', x.is_trial
            ),
            v_today_8pm
        FROM (
            SELECT b.client_id, b.id AS booking_id, b.is_trial,
                   l.id AS lesson_id, l.starts_at, l.location_id,
                   a.name AS activity, o.name AS operator,
                   "internal"."location_label"(l.location_id) AS place,
                   loc.access_notes,
                   "internal"."get_notification_channel"(b.client_id, 'lesson_reminder') AS channel
              FROM "public"."bookings" b
              JOIN "public"."lessons" l ON b.lesson_id = l.id
              JOIN "public"."activities" a ON l.activity_id = a.id
              LEFT JOIN "public"."operators" o ON l.operator_id = o.id
              LEFT JOIN "public"."locations" loc ON loc.id = l.location_id
             WHERE b.status = 'booked'
               AND b.client_id IS NOT NULL
               AND l.deleted_at IS NULL
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
               )
        ) x
        WHERE x.channel IS NOT NULL;

        GET DIAGNOSTICS v_count_evening = ROW_COUNT;
    END IF;

    -- 2h reminder: lessons starting in 2-3 hours from now
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        x.client_id,
        'lesson_reminder'::"public"."notification_category",
        x.channel,
        CASE WHEN x.is_trial THEN 'La tua lezione di prova inizia tra 2 ore'
             ELSE 'La tua lezione inizia tra 2 ore' END,
        x.activity || ' alle ' || TO_CHAR(x.starts_at AT TIME ZONE 'Europe/Rome', 'HH24:MI')
            || COALESCE(' presso ' || x.place, '') || ' - ci vediamo presto!',
        jsonb_build_object(
            'lesson_id', x.lesson_id,
            'booking_id', x.booking_id,
            'type', '2h',
            'activity', x.activity,
            'starts_at', x.starts_at,
            'location_id', x.location_id,
            'is_trial', x.is_trial
        ),
        x.starts_at - INTERVAL '2 hours'
    FROM (
        SELECT b.client_id, b.id AS booking_id, b.is_trial,
               l.id AS lesson_id, l.starts_at, l.location_id,
               a.name AS activity,
               "internal"."location_label"(l.location_id) AS place,
               "internal"."get_notification_channel"(b.client_id, 'lesson_reminder') AS channel
          FROM "public"."bookings" b
          JOIN "public"."lessons" l ON b.lesson_id = l.id
          JOIN "public"."activities" a ON l.activity_id = a.id
         WHERE b.status = 'booked'
           AND b.client_id IS NOT NULL
           AND l.deleted_at IS NULL
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
           )
    ) x
    WHERE x.channel IS NOT NULL;

    GET DIAGNOSTICS v_count_2h = ROW_COUNT;

    RETURN json_build_object(
        'evening_reminders', v_count_evening,
        '2h_reminders', v_count_2h,
        'timestamp', v_now
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Questionario dopo la prova (F6)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."feedback"
    ADD COLUMN IF NOT EXISTS "trial_id" "uuid";

DO $$ BEGIN
    ALTER TABLE "public"."feedback" ADD CONSTRAINT "feedback_trial_id_fkey"
        FOREIGN KEY ("trial_id") REFERENCES "public"."trials"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Il vincolo esistente sul bersaglio non conosce `trial` (per un tipo che non elenca non dice
-- nulla): questo lo completa senza toccarlo.
DO $$ BEGIN
    ALTER TABLE "public"."feedback" ADD CONSTRAINT "feedback_trial_target" CHECK (
        CASE WHEN "kind" = 'trial'::"public"."feedback_kind"
             THEN "trial_id" IS NOT NULL AND "lesson_id" IS NULL
                  AND "practice_id" IS NULL AND "event_id" IS NULL
             ELSE "trial_id" IS NULL
        END
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "feedback_unique_trial"
    ON "public"."feedback" ("client_id", "trial_id") WHERE "trial_id" IS NOT NULL;

COMMENT ON COLUMN "public"."feedback"."trial_id" IS
    'Prova a cui si riferisce il questionario (kind = trial). Le risposte chiuse stanno in metadata.answers, il voto in rating, il testo libero in comment.';

-- Domande e risposte ammesse: le stesse di `TRIAL_FEEDBACK_QUESTIONS` nel contract (src/labels.ts).
CREATE OR REPLACE FUNCTION "public"."submit_trial_feedback"(
    "p_trial_id" "uuid",
    "p_rating" smallint,
    "p_answers" "jsonb" DEFAULT '{}'::"jsonb",
    "p_comment" "text" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_trial     public.trials%ROWTYPE;
    v_answers   jsonb := COALESCE(p_answers, '{}'::jsonb);
    v_allowed   jsonb := jsonb_build_object(
        'accoglienza', jsonb_build_array('si', 'abbastanza', 'no'),
        'livello',     jsonb_build_array('giusto', 'facile', 'impegnativo'),
        'continuare',  jsonb_build_array('si', 'forse', 'no')
    );
    v_key       text;
    v_comment   text := NULLIF(btrim(COALESCE(p_comment, '')), '');
    v_id        uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    SELECT * INTO v_trial FROM public.trials WHERE id = p_trial_id AND client_id = v_client_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRIAL_NOT_FOUND');
    END IF;

    -- Si risponde solo a una prova fatta (anche se nel frattempo è diventata il primo ingresso)
    IF v_trial.status NOT IN ('attended', 'converted') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_ELIGIBLE');
    END IF;

    IF p_rating IS NULL OR p_rating NOT BETWEEN 1 AND 5 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_RATING');
    END IF;

    IF jsonb_typeof(v_answers) <> 'object' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_ANSWERS');
    END IF;

    FOR v_key IN SELECT jsonb_object_keys(v_answers) LOOP
        IF NOT (v_allowed ? v_key)
           OR jsonb_typeof(v_answers->v_key) <> 'string'
           OR NOT ((v_allowed->v_key) ? (v_answers->>v_key)) THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_ANSWERS', 'question', v_key);
        END IF;
    END LOOP;

    IF length(COALESCE(v_comment, '')) > 2000 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'COMMENT_TOO_LONG');
    END IF;

    INSERT INTO public.feedback (client_id, kind, trial_id, rating, comment, metadata)
    VALUES (v_client_id, 'trial', p_trial_id, p_rating, v_comment,
            jsonb_build_object('questionnaire', 'trial_v1', 'answers', v_answers))
    ON CONFLICT (client_id, trial_id) WHERE trial_id IS NOT NULL
    DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment,
                  metadata = EXCLUDED.metadata, status = 'new', updated_at = now()
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('ok', true, 'feedback_id', v_id);
END;
$$;

ALTER FUNCTION "public"."submit_trial_feedback"("uuid", smallint, "jsonb", "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."submit_trial_feedback"("uuid", smallint, "jsonb", "text") TO "authenticated";
COMMENT ON FUNCTION "public"."submit_trial_feedback"("uuid", smallint, "jsonb", "text") IS
    'Il questionario dopo la prova (F6): voto 1-5, tre domande a scelta chiusa e un commento. Solo per una prova fatta; si può correggere, e il triage riparte da "nuovo".';

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Ricostruzione automatica del sito (B10)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."site_rebuild_state" (
    "id"            boolean DEFAULT true NOT NULL,
    "requested_at"  timestamp with time zone,
    "requested_by"  "text",
    "triggered_at"  timestamp with time zone,
    "reported_at"   timestamp with time zone,
    "last_ok"       boolean,
    "last_status"   integer,
    "last_error"    "text",

    CONSTRAINT "site_rebuild_state_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "site_rebuild_state_single_row" CHECK ("id")
);

ALTER TABLE "public"."site_rebuild_state" OWNER TO "postgres";
ALTER TABLE "public"."site_rebuild_state" ENABLE ROW LEVEL SECURITY;
-- Nessuna policy e nessun grant ad anon e authenticated: la leggono e scrivono solo il job
-- (postgres), l'edge function `site-rebuild` e ops-health (service_role).

COMMENT ON TABLE "public"."site_rebuild_state" IS
    'Una riga sola. requested_at: ultima modifica che il sito deve rispecchiare; triggered_at: ultima chiamata al build hook di Netlify; last_*: esito riportato dall''edge function site-rebuild.';

INSERT INTO "public"."site_rebuild_state" ("id") VALUES (true) ON CONFLICT ("id") DO NOTHING;

CREATE OR REPLACE FUNCTION "internal"."request_site_rebuild"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    UPDATE public.site_rebuild_state
       SET requested_at = now(), requested_by = TG_TABLE_NAME
     WHERE id;
    RETURN NULL;
END;
$$;

ALTER FUNCTION "internal"."request_site_rebuild"() OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."request_site_rebuild"() IS
    'Segna che il sito va ricostruito. Non chiama nulla: lo fa il job cron_site_rebuild, dopo qualche minuto di quiete.';

CREATE OR REPLACE TRIGGER "locations_request_site_rebuild"
    AFTER INSERT OR UPDATE OR DELETE ON "public"."locations"
    FOR EACH STATEMENT EXECUTE FUNCTION "internal"."request_site_rebuild"();

CREATE OR REPLACE TRIGGER "activity_groups_request_site_rebuild"
    AFTER INSERT OR UPDATE OR DELETE ON "public"."activity_groups"
    FOR EACH STATEMENT EXECUTE FUNCTION "internal"."request_site_rebuild"();

CREATE OR REPLACE TRIGGER "activities_request_site_rebuild"
    AFTER INSERT OR UPDATE OR DELETE ON "public"."activities"
    FOR EACH STATEMENT EXECUTE FUNCTION "internal"."request_site_rebuild"();

CREATE OR REPLACE TRIGGER "events_request_site_rebuild"
    AFTER INSERT OR UPDATE OR DELETE ON "public"."events"
    FOR EACH STATEMENT EXECUTE FUNCTION "internal"."request_site_rebuild"();

CREATE OR REPLACE TRIGGER "feature_flags_request_site_rebuild"
    AFTER UPDATE ON "public"."feature_flags"
    FOR EACH ROW
    WHEN (NEW."key" = 'cinque_per_mille' AND OLD."enabled" IS DISTINCT FROM NEW."enabled")
    EXECUTE FUNCTION "internal"."request_site_rebuild"();

-- Il job: dopo 3 minuti senza modifiche (una serie di ritocchi fa una build sola) e non più di
-- una volta ogni 10 minuti. Si aggancia a pg_cron in produzione ogni 5 minuti.
CREATE OR REPLACE FUNCTION "internal"."cron_site_rebuild"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_state public.site_rebuild_state%ROWTYPE;
BEGIN
    SELECT * INTO v_state FROM public.site_rebuild_state WHERE id FOR UPDATE;

    IF v_state.requested_at IS NULL
       OR (v_state.triggered_at IS NOT NULL AND v_state.requested_at <= v_state.triggered_at) THEN
        RETURN jsonb_build_object('ok', true, 'reason', 'UP_TO_DATE');
    END IF;

    IF v_state.requested_at > now() - INTERVAL '3 minutes' THEN
        RETURN jsonb_build_object('ok', true, 'reason', 'WAITING_FOR_QUIET');
    END IF;

    IF v_state.triggered_at IS NOT NULL AND v_state.triggered_at > now() - INTERVAL '10 minutes' THEN
        RETURN jsonb_build_object('ok', true, 'reason', 'TOO_SOON');
    END IF;

    UPDATE public.site_rebuild_state SET triggered_at = now() WHERE id;

    PERFORM "internal"."call_edge_function"(
        'site-rebuild',
        jsonb_build_object('requested_by', v_state.requested_by, 'requested_at', v_state.requested_at)
    );

    RETURN jsonb_build_object('ok', true, 'reason', 'TRIGGERED');
END;
$$;

ALTER FUNCTION "internal"."cron_site_rebuild"() OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."cron_site_rebuild"() IS
    'Job della ricostruzione del sito (pg_cron, solo in produzione): chiama l''edge function site-rebuild quando ci sono modifiche e sono passati 3 minuti di quiete.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. 5x1000 (B8)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO "public"."feature_flags" ("key", "enabled", "description") VALUES
    ('cinque_per_mille', false,
     'Mostra il 5x1000 su sito e app (pagina dedicata e riquadro in Sostienici). Da accendere solo dopo l''iscrizione al RUNTS e l''accreditamento (B8).')
ON CONFLICT ("key") DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Gruppi: attività e immagini di partenza (B3, B12)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- La mappa decisa in B3. Si tocca solo chi non ha ancora un gruppo: se lo staff ne ha già scelto
-- uno, resta. In locale queste attività non esistono e non succede nulla.

UPDATE "public"."activities" a
   SET group_id = g.id
  FROM "public"."activity_groups" g
 WHERE a.group_id IS NULL
   AND ((g.slug = 'benessere' AND a.slug IN ('meditazionemindfulness', 'yogavinyasa', 'yinyoga', 'morningyoga'))
     OR (g.slug = 'mamme'     AND a.slug IN ('mamamoves', 'kalosmomcafe'))
     OR (g.slug = 'terza-eta' AND a.slug IN ('kalosseniorcafe')));

-- Immagini di partenza (B12), da sostituire dal gestionale: quella di un'attività del gruppo, nello
-- stesso formato (percorso nel bucket `activities`); per Laboratori e Eventi quella del sito.
UPDATE "public"."activity_groups" g
   SET image_url = src.image_url
  FROM (VALUES ('benessere', 'yinyoga'), ('mamme', 'mamamoves'), ('terza-eta', 'kalosseniorcafe')) AS m(group_slug, activity_slug)
  JOIN "public"."activities" src ON src.slug = m.activity_slug AND src.deleted_at IS NULL
 WHERE g.slug = m.group_slug
   AND g.image_url IS NULL
   AND src.image_url IS NOT NULL;

UPDATE "public"."activity_groups"
   SET image_url = 'https://kalosstudio.it/assets/img/attivita/laboratori.webp'
 WHERE slug = 'laboratori' AND image_url IS NULL;

COMMENT ON COLUMN "public"."activity_groups"."image_url" IS
    'Immagine del gruppo: un indirizzo completo, oppure un percorso nel bucket pubblico `activities` (come per le attività).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. View del sito
-- ─────────────────────────────────────────────────────────────────────────────
--
-- `public_site_events` mostrava anche gli eventi non pubblicati (la view non passa dalle policy):
-- oggi sono tutti pubblicati, quindi il sito non cambia, ma "Pubblicato" spento ora li nasconde
-- davvero. In fondo, senza toccare le colonne esistenti: indirizzo del luogo e contributo.

CREATE OR REPLACE VIEW "public"."public_site_events" AS
SELECT e.id, e.name AS title, e.description, e.image_url,
       e.starts_at AS start_date, e.ends_at AS end_date,
       e.link AS registration_url, e.link AS link_url,
       e.created_at, e.updated_at,
       e.event_type,
       e.location_id,
       loc.slug AS location_slug,
       loc.name AS location_name,
       loc.city AS location_city,
       loc.map_url AS location_map_url,
       loc.address_street AS location_address,
       loc.address_zip AS location_zip,
       loc.province AS location_province,
       e.price_cents,
       e.currency
  FROM public.events e
  LEFT JOIN public.locations loc ON loc.id = e.location_id AND loc.show_on_site = true AND loc.is_active = true
 WHERE e.deleted_at IS NULL AND COALESCE(e.is_active, true) = true
 ORDER BY e.starts_at DESC;

-- Le attività: in fondo il nome del luogo predefinito, per le pagine per comune.
CREATE OR REPLACE VIEW "public"."public_site_activities" AS
SELECT a.id, a.name, a.slug, a.description, a.discipline, a.color, a.duration_minutes,
       a.image_url, a.is_active, a.icon_name, a.landing_title, a.landing_subtitle,
       a.active_months, a.target_audience, a.program_objectives, a.why_participate,
       a.journey_structure, a.created_at, a.updated_at,
       a.group_id,
       g.slug AS group_slug,
       g.name AS group_name,
       loc.slug AS default_location_slug,
       loc.city AS default_location_city,
       loc.name AS default_location_name,
       a.trial_enabled
  FROM public.activities a
  LEFT JOIN public.activity_groups g ON g.id = a.group_id AND g.is_active = true
  LEFT JOIN public.locations loc ON loc.id = a.default_location_id AND loc.show_on_site = true AND loc.is_active = true
 WHERE a.deleted_at IS NULL AND COALESCE(a.is_active, true) = true
 ORDER BY a.name;
