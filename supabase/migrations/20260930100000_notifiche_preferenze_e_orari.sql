-- Migration 20260930100000: notifiche che rispettano le preferenze, una volta sola, all'ora giusta
--
-- Dalla verifica generale del 30/09/2026 (docs/ISSUES.md §1 punti 3 e 8, §3.1).
--
-- 1. Il canale. `internal.get_notification_channel` restituisce un canale solo se si può davvero
--    usare: la push se è accesa per quella categoria e c'è un dispositivo, l'email se è accesa e la
--    scheda ha un indirizzo non rimbalzato. Altrimenti NULL, e NULL vuol dire «non accodare». Prima
--    molte code scrivevano `COALESCE(canale, 'email')` o `'push'`: chi aveva spento tutto riceveva
--    comunque, e chi non ha l'email finiva ogni giorno in coda come «skipped».
-- 2. Una volta sola. Le code guardano anche le righe già in coda (qualsiasi stato), non solo i log
--    degli invii: una notifica saltata non si riaccoda il giorno dopo (4.516 righe di re-engagement e
--    fino a 44 «ingressi in esaurimento» per lo stesso abbonamento).
-- 3. «Ci manchi!» una volta per ogni assenza: dopo l'ultima lezione, la push a 4 giorni e il
--    messaggio a 7 partono una volta sola, e non oltre 60 giorni di assenza (prima ogni 30 giorni,
--    anche a chi non viene da anni). La push rispetta le preferenze.
-- 4. Il promemoria della sera alle 20:00 italiane. Prima un valore senza fuso finiva in una variabile
--    timestamptz: il promemoria «Domani alle…» partiva a mezzanotte d'estate e alle 22 d'inverno.
--    E un promemoria in coda sparisce se la prenotazione non è più attiva o la lezione cambia orario
--    o viene archiviata (il job orario lo rimette con l'orario nuovo).
-- 5. Nuovo evento: solo per un evento pubblicato, una volta per evento e canale, con le preferenze;
--    l'email solo a chi non si è disiscrittə dalla newsletter (è un invito, non un servizio).
-- 6. Annunci: la push rispetta le preferenze; modificare, spegnere o cancellare un annuncio
--    programmato aggiorna o ritira le push ancora in coda; gli annunci ricorrenti si calcolano in ora
--    italiana e aprono l'annuncio (`announcement_id`, prima `announcementId`).
-- 7. `queue_feedback_request` era aperta a chiunque abbia un account e accettava qualsiasi data: un
--    cliente poteva riempire la coda. Ora solo staff e sistema, mai nel passato.
-- 8. Pratica a casa e diario (code senza job, pronte per quando si accenderanno): solo push, solo con
--    le preferenze, la pratica solo con `home_practice` acceso, giorno in ora italiana.
--
-- Compatibilità: firme invariate, tranne due sovraccarichi morti che si tolgono
-- (`queue_new_event` a 3 parametri, `internal.queue_announcement` a 3 e 4 parametri: nessun
-- chiamante in sito, gestionale, webapp, app o database). Due trigger nuovi.
--
-- migration-lint:allow revoke — reason: queue_feedback_request non la chiama nessuna app (solo lo staff o il sistema: verificato su sito, gestionale, webapp e app); le altre REVOKE riguardano funzioni interne nuove di questa migrazione

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Oggi in Italia
-- ─────────────────────────────────────────────────────────────────────────────

-- Il database lavora in UTC: fra le 00:00 e le 02:00 italiane `CURRENT_DATE` è ancora ieri.
CREATE OR REPLACE FUNCTION "internal"."rome_today"()
RETURNS date
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT (now() AT TIME ZONE 'Europe/Rome')::date;
$$;

COMMENT ON FUNCTION "internal"."rome_today"() IS
  'La data di oggi in Italia (il database è in UTC).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Il canale e il controllo «già in coda»
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."get_notification_channel"(p_client_id uuid, p_category "public"."notification_category")
RETURNS "public"."notification_channel"
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_push_enabled boolean;
    v_email_enabled boolean;
    v_email text;
    v_bounced boolean;
BEGIN
    SELECT np.push_enabled, np.email_enabled INTO v_push_enabled, v_email_enabled
      FROM "public"."notification_preferences" np
     WHERE np.client_id = p_client_id AND np.category = p_category;

    -- Senza una riga, notifica ed email sono accese (così le mostra anche l'app).
    v_push_enabled := COALESCE(v_push_enabled, true);
    v_email_enabled := COALESCE(v_email_enabled, true);

    IF v_push_enabled AND "internal"."client_has_active_push_tokens"(p_client_id) THEN
        RETURN 'push'::"public"."notification_channel";
    END IF;

    IF v_email_enabled THEN
        SELECT c.email, COALESCE(c.email_bounced, false) INTO v_email, v_bounced
          FROM "public"."clients" c
         WHERE c.id = p_client_id;
        IF NULLIF(btrim(COALESCE(v_email, '')), '') IS NOT NULL AND NOT v_bounced THEN
            RETURN 'email'::"public"."notification_channel";
        END IF;
    END IF;

    -- Nessun canale che si possa usare: non si accoda nulla.
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION "internal"."get_notification_channel"(uuid, "public"."notification_category") IS
  'Canale da usare per una categoria: push se accesa e c''è un dispositivo, altrimenti email se accesa e l''indirizzo c''è e non rimbalza; NULL = non accodare.';

-- Una notifica di questa categoria per questa persona, con questi dati, è già in coda (qualsiasi
-- stato, anche «skipped») o già inviata dopo `p_since`?
CREATE OR REPLACE FUNCTION "internal"."notification_exists"(
    p_client_id uuid,
    p_category "public"."notification_category",
    p_match jsonb,
    p_since timestamptz DEFAULT '-infinity'
)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
           SELECT 1 FROM "public"."notification_queue" nq
            WHERE nq.client_id = p_client_id
              AND nq.category = p_category
              AND nq.data @> p_match
              AND nq.created_at >= p_since
         )
      OR EXISTS (
           SELECT 1 FROM "public"."notification_logs" nl
            WHERE nl.client_id = p_client_id
              AND nl.category = p_category
              AND nl.data @> p_match
              AND nl.sent_at >= p_since
         );
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. «Ci manchi!»: una volta per assenza
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."can_send_re_engagement"(p_client_id uuid, p_days integer DEFAULT 7)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_last_lesson timestamptz;
BEGIN
    -- Chi ha già una lezione in programma sta tornando.
    IF EXISTS (
        SELECT 1
          FROM "public"."bookings" b
          JOIN "public"."lessons" l ON l.id = b.lesson_id
         WHERE b.client_id = p_client_id
           AND b.status = 'booked'
           AND l.deleted_at IS NULL
           AND l.starts_at > now()
    ) THEN
        RETURN false;
    END IF;

    SELECT max(l.starts_at) INTO v_last_lesson
      FROM "public"."bookings" b
      JOIN "public"."lessons" l ON l.id = b.lesson_id
     WHERE b.client_id = p_client_id
       AND b.status IN ('booked', 'attended')
       AND l.starts_at < now();

    -- Mai venutə, oppure non ancora abbastanza giorni, oppure un'assenza troppo lunga (oltre 60
    -- giorni non si scrive più: prima partiva un «Ci manchi!» ogni 30 giorni, anche dopo anni).
    IF v_last_lesson IS NULL
       OR v_last_lesson > now() - make_interval(days => p_days)
       OR v_last_lesson < now() - interval '60 days' THEN
        RETURN false;
    END IF;

    -- Una volta per questa assenza: niente se dopo l'ultima lezione è già in coda o partito.
    RETURN NOT "internal"."notification_exists"(
        p_client_id, 're_engagement', jsonb_build_object('days', p_days), v_last_lesson
    );
END;
$$;

CREATE OR REPLACE FUNCTION "public"."queue_re_engagement"()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_count_4d integer := 0;
    v_count_7d integer := 0;
BEGIN
    -- 4 giorni: solo una notifica push, e solo se la push è accesa per questa categoria.
    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    SELECT x.id, 're_engagement', 'push',
           'Ti aspettiamo!',
           'Ti va di riprendere? Guarda le lezioni della settimana.',
           jsonb_build_object('days', 4, 'last_booking_date', x.last_lesson::text),
           now()
      FROM (
        SELECT c.id,
               "internal"."get_notification_channel"(c.id, 're_engagement') AS channel,
               (SELECT max(l.starts_at)
                  FROM "public"."bookings" b
                  JOIN "public"."lessons" l ON l.id = b.lesson_id
                 WHERE b.client_id = c.id AND b.status IN ('booked', 'attended')) AS last_lesson
          FROM "public"."clients" c
         WHERE c.deleted_at IS NULL
           AND c.is_active = true
           AND "internal"."can_send_re_engagement"(c.id, 4)
      ) x
     WHERE x.channel = 'push';

    GET DIAGNOSTICS v_count_4d = ROW_COUNT;

    -- 7 giorni: push o email, secondo le preferenze.
    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    SELECT x.id, 're_engagement', x.channel,
           'Ci manchi!',
           'Riprendi da dove hai lasciato: scopri le lezioni della settimana.',
           jsonb_build_object('days', 7, 'last_booking_date', x.last_lesson::text),
           now()
      FROM (
        SELECT c.id,
               "internal"."get_notification_channel"(c.id, 're_engagement') AS channel,
               (SELECT max(l.starts_at)
                  FROM "public"."bookings" b
                  JOIN "public"."lessons" l ON l.id = b.lesson_id
                 WHERE b.client_id = c.id AND b.status IN ('booked', 'attended')) AS last_lesson
          FROM "public"."clients" c
         WHERE c.deleted_at IS NULL
           AND c.is_active = true
           AND "internal"."can_send_re_engagement"(c.id, 7)
      ) x
     WHERE x.channel IS NOT NULL;

    GET DIAGNOSTICS v_count_7d = ROW_COUNT;

    RETURN json_build_object('4_days', v_count_4d, '7_days', v_count_7d);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Compleanno, ingressi in esaurimento, scadenze
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."queue_birthday"()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_count integer := 0;
    v_today date := "internal"."rome_today"();
BEGIN
    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    SELECT x.id, 'birthday', x.channel,
           'Buon compleanno, ' || COALESCE(NULLIF(split_part(btrim(x.full_name), ' ', 1), ''), 'da tuttə noi') || '!',
           'Tutto lo Studio Kalòs ti augura un meraviglioso compleanno!',
           jsonb_build_object('year', extract(year FROM v_today)::int, 'client_name', x.full_name),
           now()
      FROM (
        SELECT c.id, c.full_name, "internal"."get_notification_channel"(c.id, 'birthday') AS channel
          FROM "public"."clients" c
         WHERE c.deleted_at IS NULL
           AND c.is_active = true
           AND c.birthday IS NOT NULL
           AND extract(month FROM c.birthday) = extract(month FROM v_today)
           AND extract(day FROM c.birthday) = extract(day FROM v_today)
           AND NOT "internal"."notification_exists"(
                 c.id, 'birthday', jsonb_build_object('year', extract(year FROM v_today)::int))
      ) x
     WHERE x.channel IS NOT NULL;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN json_build_object('queued', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION "public"."queue_entries_low"()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_count integer := 0;
    v_today date := "internal"."rome_today"();
BEGIN
    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    SELECT DISTINCT ON (x.client_id)
           x.client_id, 'entries_low', x.channel,
           'Ti restano solo 2 ingressi',
           'Rinnova per continuare il tuo percorso senza interruzioni.',
           jsonb_build_object('subscription_id', x.id, 'plan_name', x.plan_name, 'entries_left', 2),
           now()
      FROM (
        SELECT s.id, s.client_id, s.expires_at,
               COALESCE(s.custom_name, p.name) AS plan_name,
               "internal"."get_notification_channel"(s.client_id, 'entries_low') AS channel
          FROM "public"."subscriptions" s
          JOIN "public"."plans" p ON p.id = s.plan_id
         WHERE s.status = 'active'
           AND s.deleted_at IS NULL
           AND s.client_id IS NOT NULL
           AND s.expires_at >= v_today
           AND COALESCE(s.custom_entries, p.entries) IS NOT NULL
           AND COALESCE(s.custom_entries, p.entries)
               - COALESCE((SELECT sum(-su.delta) FROM "public"."subscription_usages" su
                            WHERE su.subscription_id = s.id), 0) = 2
           AND NOT "internal"."notification_exists"(
                 s.client_id, 'entries_low', jsonb_build_object('subscription_id', s.id))
      ) x
     WHERE x.channel IS NOT NULL
     ORDER BY x.client_id, x.expires_at;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN json_build_object('queued', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION "public"."queue_subscription_expiry"()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_today date := "internal"."rome_today"();
    v_days integer;
    v_counts jsonb := '{}'::jsonb;
    v_n integer;
BEGIN
    FOREACH v_days IN ARRAY ARRAY[21, 7, 2] LOOP
        INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
        SELECT x.client_id, 'subscription_expiry', x.channel,
               CASE v_days
                 WHEN 21 THEN 'Il tuo abbonamento scade il ' || to_char(x.expires_at, 'DD/MM')
                 WHEN 7  THEN 'Il tuo abbonamento scade tra una settimana'
                 ELSE 'Ultimi 2 giorni del tuo abbonamento'
               END,
               CASE v_days
                 WHEN 21 THEN 'Hai ancora 3 settimane per rinnovare e continuare il tuo percorso di benessere.'
                 WHEN 7  THEN 'Rinnova ora per continuare il tuo percorso di benessere.'
                 ELSE 'Non perdere l''accesso alle tue lezioni preferite!'
               END,
               jsonb_build_object('subscription_id', x.id, 'plan_name', x.plan_name,
                                  'expires_at', x.expires_at, 'days_left', v_days),
               now()
          FROM (
            SELECT s.id, s.client_id, s.expires_at,
                   COALESCE(s.custom_name, p.name) AS plan_name,
                   "internal"."get_notification_channel"(s.client_id, 'subscription_expiry') AS channel
              FROM "public"."subscriptions" s
              JOIN "public"."plans" p ON p.id = s.plan_id
             WHERE s.status = 'active'
               AND s.deleted_at IS NULL
               AND s.client_id IS NOT NULL
               AND s.expires_at = v_today + v_days
               AND NOT "internal"."notification_exists"(
                     s.client_id, 'subscription_expiry',
                     jsonb_build_object('subscription_id', s.id, 'days_left', v_days))
          ) x
         WHERE x.channel IS NOT NULL;

        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_counts := v_counts || jsonb_build_object(v_days || '_days', v_n);
    END LOOP;

    RETURN v_counts::json;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Prima lezione e traguardi
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."milestone_already_sent"(p_client_id uuid, p_milestone integer)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT "internal"."notification_exists"(p_client_id, 'milestone', jsonb_build_object('milestone', p_milestone));
$$;

CREATE OR REPLACE FUNCTION "internal"."queue_first_lesson"(p_client_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_channel "public"."notification_channel";
BEGIN
    IF "internal"."notification_exists"(p_client_id, 'first_lesson', '{}'::jsonb) THEN
        RETURN false;
    END IF;

    v_channel := "internal"."get_notification_channel"(p_client_id, 'first_lesson');
    IF v_channel IS NULL THEN
        RETURN false;
    END IF;

    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    VALUES (p_client_id, 'first_lesson', v_channel,
            'Complimenti per la tua prima lezione!',
            'Il benessere inizia così, un passo alla volta.',
            jsonb_build_object('first_lesson', true),
            now());
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION "internal"."queue_milestone"(p_client_id uuid, p_milestone integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_channel "public"."notification_channel";
BEGIN
    IF "internal"."milestone_already_sent"(p_client_id, p_milestone) THEN
        RETURN false;
    END IF;

    v_channel := "internal"."get_notification_channel"(p_client_id, 'milestone');
    IF v_channel IS NULL THEN
        RETURN false;
    END IF;

    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    VALUES (p_client_id, 'milestone', v_channel,
            p_milestone || ' lezioni completate!',
            'Stai costruendo un''abitudine fantastica. Continua così!',
            jsonb_build_object('milestone', p_milestone),
            now());
    RETURN true;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Nuovo evento
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS "public"."queue_new_event"(uuid, text, timestamptz);

CREATE OR REPLACE FUNCTION "public"."queue_new_event"(
    p_event_id uuid,
    p_event_name text,
    p_event_date timestamptz,
    p_send_push boolean DEFAULT true,
    p_send_email boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_push_count integer := 0;
    v_email_count integer := 0;
    v_event record;
    v_title text;
    v_body text;
    v_data jsonb;
BEGIN
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Permission denied: user is not staff' USING ERRCODE = '42501';
    END IF;

    IF NOT p_send_push AND NOT p_send_email THEN
        RETURN json_build_object('queued_push', 0, 'queued_email', 0);
    END IF;

    -- Solo un evento pubblicato e non ancora iniziato: i clienti non vedono le bozze, e un avviso
    -- partito alla creazione di una bozza non sarebbe più partito alla pubblicazione.
    SELECT e.id, e.name, e.starts_at, e.is_active, e.deleted_at INTO v_event
      FROM "public"."events" e
     WHERE e.id = p_event_id;
    IF NOT FOUND OR v_event.deleted_at IS NOT NULL THEN
        RETURN json_build_object('queued_push', 0, 'queued_email', 0, 'reason', 'EVENT_NOT_FOUND');
    END IF;
    IF NOT COALESCE(v_event.is_active, false) THEN
        RETURN json_build_object('queued_push', 0, 'queued_email', 0, 'reason', 'EVENT_NOT_PUBLISHED');
    END IF;
    IF v_event.starts_at IS NOT NULL AND v_event.starts_at <= now() THEN
        RETURN json_build_object('queued_push', 0, 'queued_email', 0, 'reason', 'EVENT_STARTED');
    END IF;

    v_title := 'Nuovo evento: ' || COALESCE(NULLIF(btrim(p_event_name), ''), v_event.name);
    v_body := to_char(COALESCE(v_event.starts_at, p_event_date) AT TIME ZONE 'Europe/Rome', 'DD/MM "alle" HH24:MI')
              || ': i posti sono limitati, iscriviti ora!';
    v_data := jsonb_build_object('event_id', p_event_id, 'event_name', v_title,
                                 'event_date', COALESCE(v_event.starts_at, p_event_date));

    -- Push: a chi la tiene accesa per i nuovi eventi e ha un dispositivo; una volta per evento.
    IF p_send_push THEN
        INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
        SELECT c.id, 'new_event', 'push', v_title, v_body, v_data, now()
          FROM "public"."clients" c
          LEFT JOIN "public"."notification_preferences" np
                 ON np.client_id = c.id AND np.category = 'new_event'
         WHERE c.deleted_at IS NULL
           AND c.is_active = true
           AND COALESCE(np.push_enabled, true)
           AND "internal"."client_has_active_push_tokens"(c.id)
           AND NOT EXISTS (
                 SELECT 1 FROM "public"."notification_queue" nq
                  WHERE nq.client_id = c.id AND nq.category = 'new_event' AND nq.channel = 'push'
                    AND nq.data @> jsonb_build_object('event_id', p_event_id));
        GET DIAGNOSTICS v_push_count = ROW_COUNT;
    END IF;

    -- Email: è un invito, quindi solo a chi riceve la newsletter e tiene accesa l'email per i nuovi
    -- eventi, con un indirizzo che non rimbalza; una volta per evento.
    IF p_send_email THEN
        INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
        SELECT c.id, 'new_event', 'email', v_title, v_body, v_data, now()
          FROM "public"."clients" c
          LEFT JOIN "public"."notification_preferences" np
                 ON np.client_id = c.id AND np.category = 'new_event'
         WHERE c.deleted_at IS NULL
           AND c.is_active = true
           AND COALESCE(c.newsletter_subscribed, true)
           AND COALESCE(np.email_enabled, true)
           AND NULLIF(btrim(COALESCE(c.email, '')), '') IS NOT NULL
           AND NOT COALESCE(c.email_bounced, false)
           AND NOT EXISTS (
                 SELECT 1 FROM "public"."notification_queue" nq
                  WHERE nq.client_id = c.id AND nq.category = 'new_event' AND nq.channel = 'email'
                    AND nq.data @> jsonb_build_object('event_id', p_event_id));
        GET DIAGNOSTICS v_email_count = ROW_COUNT;
    END IF;

    RETURN json_build_object('queued_push', v_push_count, 'queued_email', v_email_count);
END;
$$;

REVOKE ALL ON FUNCTION "public"."queue_new_event"(uuid, text, timestamptz, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION "public"."queue_new_event"(uuid, text, timestamptz, boolean, boolean) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Promemoria delle lezioni
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."queue_lesson_reminders"()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_count_evening integer := 0;
    v_count_2h integer := 0;
    v_now timestamptz := now();
    v_today date := "internal"."rome_today"();
    v_today_8pm timestamptz;
BEGIN
    -- Le 20:00 di oggi in Italia, come istante: il calcolo sta tutto in un'espressione, senza
    -- passare da una variabile timestamptz con un valore senza fuso (era l'errore di prima).
    v_today_8pm := (v_today + time '20:00') AT TIME ZONE 'Europe/Rome';

    -- La sera prima: lezioni di domani, alle 20:00 di oggi; si accodano fino alle 20:00.
    IF v_now < v_today_8pm THEN
        INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
        SELECT
            x.client_id,
            'lesson_reminder',
            x.channel,
            CASE WHEN x.is_trial
                 THEN 'Domani alle ' || to_char(x.starts_at AT TIME ZONE 'Europe/Rome', 'HH24:MI')
                      || ' la tua lezione di prova di ' || x.activity
                 ELSE 'Domani alle ' || to_char(x.starts_at AT TIME ZONE 'Europe/Rome', 'HH24:MI')
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
              JOIN "public"."lessons" l ON l.id = b.lesson_id
              JOIN "public"."activities" a ON a.id = l.activity_id
              LEFT JOIN "public"."operators" o ON o.id = l.operator_id
              LEFT JOIN "public"."locations" loc ON loc.id = l.location_id
             WHERE b.status = 'booked'
               AND b.client_id IS NOT NULL
               AND l.deleted_at IS NULL
               AND (l.starts_at AT TIME ZONE 'Europe/Rome')::date = v_today + 1
               AND NOT "internal"."notification_exists"(
                     b.client_id, 'lesson_reminder',
                     jsonb_build_object('booking_id', b.id, 'type', 'evening'))
        ) x
        WHERE x.channel IS NOT NULL;

        GET DIAGNOSTICS v_count_evening = ROW_COUNT;
    END IF;

    -- Due ore prima: lezioni che iniziano fra 2 e 3 ore.
    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    SELECT
        x.client_id,
        'lesson_reminder',
        x.channel,
        CASE WHEN x.is_trial THEN 'La tua lezione di prova inizia tra 2 ore'
             ELSE 'La tua lezione inizia tra 2 ore' END,
        x.activity || ' alle ' || to_char(x.starts_at AT TIME ZONE 'Europe/Rome', 'HH24:MI')
            || COALESCE(' presso ' || x.place, '') || ': ci vediamo presto!',
        jsonb_build_object(
            'lesson_id', x.lesson_id,
            'booking_id', x.booking_id,
            'type', '2h',
            'activity', x.activity,
            'starts_at', x.starts_at,
            'location_id', x.location_id,
            'is_trial', x.is_trial
        ),
        x.starts_at - interval '2 hours'
    FROM (
        SELECT b.client_id, b.id AS booking_id, b.is_trial,
               l.id AS lesson_id, l.starts_at, l.location_id,
               a.name AS activity,
               "internal"."location_label"(l.location_id) AS place,
               "internal"."get_notification_channel"(b.client_id, 'lesson_reminder') AS channel
          FROM "public"."bookings" b
          JOIN "public"."lessons" l ON l.id = b.lesson_id
          JOIN "public"."activities" a ON a.id = l.activity_id
         WHERE b.status = 'booked'
           AND b.client_id IS NOT NULL
           AND l.deleted_at IS NULL
           AND l.starts_at > v_now + interval '2 hours'
           AND l.starts_at <= v_now + interval '3 hours'
           AND NOT "internal"."notification_exists"(
                 b.client_id, 'lesson_reminder',
                 jsonb_build_object('booking_id', b.id, 'type', '2h'))
    ) x
    WHERE x.channel IS NOT NULL;

    GET DIAGNOSTICS v_count_2h = ROW_COUNT;

    RETURN json_build_object('evening_reminders', v_count_evening, '2h_reminders', v_count_2h, 'timestamp', v_now);
END;
$$;

-- Un promemoria in coda non parte più se la prenotazione non è più attiva.
CREATE OR REPLACE FUNCTION "internal"."withdraw_booking_reminders"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'booked' THEN
        DELETE FROM "public"."notification_queue"
         WHERE status = 'pending'
           AND category = 'lesson_reminder'
           AND data @> jsonb_build_object('booking_id', NEW.id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "bookings_withdraw_reminders" ON "public"."bookings";
CREATE TRIGGER "bookings_withdraw_reminders"
AFTER UPDATE OF "status" ON "public"."bookings"
FOR EACH ROW EXECUTE FUNCTION "internal"."withdraw_booking_reminders"();

-- …né se la lezione cambia orario o viene archiviata: il job orario rimette quelli giusti.
CREATE OR REPLACE FUNCTION "internal"."withdraw_lesson_reminders"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.starts_at IS DISTINCT FROM OLD.starts_at
       OR (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL) THEN
        DELETE FROM "public"."notification_queue"
         WHERE status = 'pending'
           AND category = 'lesson_reminder'
           AND data @> jsonb_build_object('lesson_id', NEW.id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "lessons_withdraw_reminders" ON "public"."lessons";
CREATE TRIGGER "lessons_withdraw_reminders"
AFTER UPDATE OF "starts_at", "deleted_at" ON "public"."lessons"
FOR EACH ROW EXECUTE FUNCTION "internal"."withdraw_lesson_reminders"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Annunci
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS "internal"."queue_announcement"(uuid, text, text);
DROP FUNCTION IF EXISTS "internal"."queue_announcement"(uuid, text, text, timestamptz);

CREATE OR REPLACE FUNCTION "internal"."queue_announcement"(
    p_announcement_id uuid,
    p_title text,
    p_body text,
    p_scheduled_for timestamptz DEFAULT now(),
    p_is_test boolean DEFAULT false,
    p_test_client_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_count integer := 0;
BEGIN
    -- Push a chi tiene accesa quella degli annunci e ha un dispositivo; in prova solo al cliente
    -- scelto; una volta per annuncio (le righe ritirate da una modifica si possono rimettere).
    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    SELECT c.id, 'announcement', 'push', p_title, p_body,
           jsonb_build_object('announcement_id', p_announcement_id),
           COALESCE(p_scheduled_for, now())
      FROM "public"."clients" c
     WHERE c.deleted_at IS NULL
       AND c.is_active = true
       AND "internal"."get_notification_channel"(c.id, 'announcement') = 'push'
       AND (NOT p_is_test OR c.id = p_test_client_id)
       AND NOT EXISTS (
             SELECT 1 FROM "public"."notification_queue" nq
              WHERE nq.client_id = c.id
                AND nq.category = 'announcement'
                AND nq.data->>'announcement_id' = p_announcement_id::text
                AND nq.status IN ('pending', 'sent', 'delivered'));
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN json_build_object('queued', v_count);
END;
$$;

-- Un annuncio programmato che cambia, si spegne o si cancella: le push ancora in coda si ritirano,
-- e se resta attivo si rimettono col testo e l'ora nuovi. Le push già partite non si toccano.
CREATE OR REPLACE FUNCTION "internal"."requeue_announcement"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM "public"."notification_queue"
         WHERE status = 'pending' AND category = 'announcement'
           AND data->>'announcement_id' = OLD.id::text;
        RETURN OLD;
    END IF;

    IF NEW.is_active IS DISTINCT FROM OLD.is_active
       OR NEW.title IS DISTINCT FROM OLD.title
       OR NEW.body IS DISTINCT FROM OLD.body
       OR NEW.starts_at IS DISTINCT FROM OLD.starts_at
       OR NEW.is_test IS DISTINCT FROM OLD.is_test
       OR NEW.test_client_id IS DISTINCT FROM OLD.test_client_id THEN
        DELETE FROM "public"."notification_queue"
         WHERE status = 'pending' AND category = 'announcement'
           AND data->>'announcement_id' = NEW.id::text;

        IF NEW.is_active = true
           AND COALESCE(NEW.is_recurring, false) = false
           AND NEW.marketing_campaign_id IS NULL THEN
            PERFORM "internal"."queue_announcement"(
                NEW.id, NEW.title, NEW.body, NEW.starts_at,
                COALESCE(NEW.is_test, false), NEW.test_client_id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "announcements_requeue" ON "public"."announcements";
CREATE TRIGGER "announcements_requeue"
AFTER UPDATE OR DELETE ON "public"."announcements"
FOR EACH ROW EXECUTE FUNCTION "internal"."requeue_announcement"();

-- Prossima uscita di un annuncio ricorrente, in ora italiana: le 19:00 scelte nel gestionale sono
-- le 19:00 italiane (prima erano le 19:00 UTC, cioè le 21 d'estate e le 20 d'inverno).
CREATE OR REPLACE FUNCTION "public"."calculate_next_announcement_occurrence"(
    p_frequency "public"."announcement_recurrence_frequency",
    p_day_of_week smallint,
    p_day_of_month smallint,
    p_time time without time zone,
    p_from_date timestamptz DEFAULT now()
)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE
    v_from_local timestamp := p_from_date AT TIME ZONE 'Europe/Rome';
    v_date date := v_from_local::date;
    v_dow smallint := extract(dow FROM v_from_local)::smallint;
    v_next_local timestamp;
    v_month_start date;
    v_last_day int;
BEGIN
    IF p_time IS NULL THEN
        RETURN NULL;
    END IF;

    CASE p_frequency
      WHEN 'daily' THEN
        v_next_local := v_date + p_time;
        IF v_next_local <= v_from_local THEN
            v_next_local := (v_date + 1) + p_time;
        END IF;

      WHEN 'weekly', 'biweekly' THEN
        IF p_day_of_week IS NULL THEN
            RETURN NULL;
        END IF;
        v_date := v_date + ((p_day_of_week - v_dow + 7) % 7);
        v_next_local := v_date + p_time;
        IF v_next_local <= v_from_local THEN
            v_next_local := (v_date + CASE WHEN p_frequency = 'weekly' THEN 7 ELSE 14 END) + p_time;
        END IF;

      WHEN 'monthly' THEN
        IF p_day_of_month IS NULL THEN
            RETURN NULL;
        END IF;
        v_month_start := date_trunc('month', v_date)::date;
        v_last_day := extract(day FROM (v_month_start + interval '1 month' - interval '1 day'))::int;
        v_next_local := (v_month_start + (LEAST(p_day_of_month, v_last_day) - 1)) + p_time;
        IF v_next_local <= v_from_local THEN
            v_month_start := (v_month_start + interval '1 month')::date;
            v_last_day := extract(day FROM (v_month_start + interval '1 month' - interval '1 day'))::int;
            v_next_local := (v_month_start + (LEAST(p_day_of_month, v_last_day) - 1)) + p_time;
        END IF;

      ELSE
        RETURN NULL;
    END CASE;

    RETURN v_next_local AT TIME ZONE 'Europe/Rome';
END;
$$;

CREATE OR REPLACE FUNCTION "public"."process_recurring_announcements"()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_announcement record;
    v_now timestamptz := now();
    v_queued integer;
BEGIN
    FOR v_announcement IN
        SELECT *
          FROM "public"."announcements"
         WHERE is_recurring = true
           AND is_active = true
           AND next_occurrence_at IS NOT NULL
           AND next_occurrence_at <= v_now
           AND (ends_at IS NULL OR ends_at > v_now)
    LOOP
        -- `announcement_id` apre l'annuncio (internal.notification_path); `announcementId` resta per
        -- il service worker della webapp di prima.
        INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for, status)
        SELECT c.id, 'announcement', 'push', v_announcement.title, v_announcement.body,
               jsonb_build_object(
                   'announcement_id', v_announcement.id,
                   'announcementId', v_announcement.id,
                   'category', v_announcement.category,
                   'imageUrl', v_announcement.image_url,
                   'linkUrl', v_announcement.link_url,
                   'linkLabel', v_announcement.link_label
               ),
               v_now, 'pending'
          FROM "public"."clients" c
         WHERE c.deleted_at IS NULL
           AND c.is_active = true
           AND "internal"."get_notification_channel"(c.id, 'announcement') = 'push'
           AND (COALESCE(v_announcement.is_test, false) = false OR c.id = v_announcement.test_client_id)
           AND NOT EXISTS (
                 SELECT 1 FROM "public"."notification_queue" nq
                  WHERE nq.client_id = c.id
                    AND nq.category = 'announcement'
                    AND (nq.data->>'announcement_id' = v_announcement.id::text
                         OR nq.data->>'announcementId' = v_announcement.id::text)
                    AND nq.created_at > v_now - interval '24 hours');
        GET DIAGNOSTICS v_queued = ROW_COUNT;

        UPDATE "public"."announcements"
           SET last_sent_at = CASE WHEN v_queued > 0 THEN v_now ELSE last_sent_at END,
               next_occurrence_at = "public"."calculate_next_announcement_occurrence"(
                   recurrence_frequency, recurrence_day_of_week, recurrence_day_of_month,
                   recurrence_time, v_now + interval '1 minute')
         WHERE id = v_announcement.id;
    END LOOP;
END;
$$;

-- Le prossime uscite già calcolate in UTC si ricalcolano in ora italiana.
UPDATE "public"."announcements"
   SET next_occurrence_at = "public"."calculate_next_announcement_occurrence"(
         recurrence_frequency, recurrence_day_of_week, recurrence_day_of_month, recurrence_time, now())
 WHERE is_recurring = true
   AND next_occurrence_at IS NOT NULL
   AND next_occurrence_at > now();

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Richiesta di parere: solo staff e sistema
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."queue_feedback_request"(
    p_client_id uuid,
    p_kind "public"."feedback_kind",
    p_target_id uuid DEFAULT NULL,
    p_scheduled_for timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_channel "public"."notification_channel";
    v_body text;
    v_id uuid;
BEGIN
    -- Solo lo staff (o il sistema, senza utente). Prima la poteva chiamare anche unə cliente, con
    -- qualsiasi data: righe del 1970 in testa alla coda l'avrebbero fermata.
    IF auth.uid() IS NOT NULL AND NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'FORBIDDEN');
    END IF;

    v_channel := "internal"."get_notification_channel"(p_client_id, 'feedback_request');
    IF v_channel IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CHANNEL_DISABLED');
    END IF;

    v_body := CASE p_kind
      WHEN 'practice'   THEN 'Raccontaci com''è andata la tua pratica: il tuo parere ci aiuta a crescere.'
      WHEN 'lesson'     THEN 'Com''è andata la lezione? Lascia un breve parere.'
      WHEN 'event'      THEN 'Com''è andato l''evento? Ci piacerebbe sapere la tua.'
      WHEN 'onboarding' THEN 'Sei con noi da un mese: com''è la tua esperienza con Studio Kalòs?'
      ELSE 'Com''è andata? Il tuo parere ci aiuta a crescere.'
    END;

    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    VALUES (p_client_id, 'feedback_request', v_channel, 'Com''è andata?', v_body,
            jsonb_build_object('kind', p_kind, 'target_id', p_target_id),
            GREATEST(COALESCE(p_scheduled_for, now()), now()))
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('ok', true, 'notification_id', v_id);
END;
$$;

REVOKE ALL ON FUNCTION "public"."queue_feedback_request"(uuid, "public"."feedback_kind", uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION "public"."queue_feedback_request"(uuid, "public"."feedback_kind", uuid, timestamptz) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Pratica a casa e diario (code senza job, pronte per quando si accenderanno)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."queue_practice_reminder"()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_count integer := 0;
    v_today date := "internal"."rome_today"();
BEGIN
    IF NOT COALESCE((SELECT enabled FROM "public"."feature_flags" WHERE key = 'home_practice'), false) THEN
        RETURN json_build_object('practice_reminders', 0, 'reason', 'HOME_PRACTICE_OFF');
    END IF;

    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    SELECT c.id, 'practice_reminder', 'push',
           'Prenditi un momento per te',
           'Una breve pratica può fare la differenza. Trova quella giusta per oggi.',
           jsonb_build_object('type', 'daily_reminder', 'day', v_today),
           now()
      FROM "public"."clients" c
     WHERE c.is_active = true
       AND c.deleted_at IS NULL
       AND c.profile_id IS NOT NULL
       AND "internal"."get_notification_channel"(c.id, 'practice_reminder') = 'push'
       AND NOT EXISTS (
             SELECT 1 FROM "public"."practice_user_state" pus
              WHERE pus.client_id = c.id AND pus.last_accessed_at > now() - interval '2 days')
       AND NOT "internal"."notification_exists"(c.id, 'practice_reminder', jsonb_build_object('day', v_today));

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN json_build_object('practice_reminders', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION "internal"."queue_practice_resume"()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_count integer := 0;
BEGIN
    IF NOT COALESCE((SELECT enabled FROM "public"."feature_flags" WHERE key = 'home_practice'), false) THEN
        RETURN json_build_object('practice_resume', 0, 'reason', 'HOME_PRACTICE_OFF');
    END IF;

    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    SELECT DISTINCT ON (pus.client_id)
           pus.client_id, 'practice_resume', 'push',
           'Riprendi da dove eri rimastə',
           'Hai una pratica in corso: ' || p.title || '. Continua il tuo percorso!',
           jsonb_build_object('type', 'resume', 'practice_id', p.id, 'practice_title', p.title),
           now()
      FROM "public"."practice_user_state" pus
      JOIN "public"."practices" p ON p.id = pus.practice_id
      JOIN "public"."clients" c ON c.id = pus.client_id
     WHERE pus.status = 'started'
       AND pus.completed_at IS NULL
       AND pus.last_accessed_at < now() - interval '3 days'
       AND c.is_active = true
       AND c.deleted_at IS NULL
       AND p.is_active = true
       AND p.deleted_at IS NULL
       AND "internal"."get_notification_channel"(pus.client_id, 'practice_resume') = 'push'
       AND NOT "internal"."notification_exists"(pus.client_id, 'practice_resume', '{}'::jsonb, now() - interval '7 days')
     ORDER BY pus.client_id, pus.last_accessed_at DESC;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN json_build_object('practice_resume', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION "internal"."queue_journal_reminder"()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_count integer := 0;
BEGIN
    INSERT INTO "public"."notification_queue" (client_id, category, channel, title, body, data, scheduled_for)
    SELECT c.id, 'journal_reminder', 'push',
           'Come stai questa settimana?',
           'Prenditi un momento per scrivere nel tuo diario. Anche poche parole possono fare la differenza.',
           jsonb_build_object('type', 'weekly_reminder'),
           now()
      FROM "public"."clients" c
     WHERE c.is_active = true
       AND c.deleted_at IS NULL
       AND c.profile_id IS NOT NULL
       AND "internal"."get_notification_channel"(c.id, 'journal_reminder') = 'push'
       AND EXISTS (SELECT 1 FROM "public"."journal_entries" je WHERE je.client_id = c.id)
       AND NOT EXISTS (SELECT 1 FROM "public"."journal_entries" je
                        WHERE je.client_id = c.id AND je.created_at > now() - interval '7 days')
       AND NOT "internal"."notification_exists"(c.id, 'journal_reminder', '{}'::jsonb, now() - interval '7 days');

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN json_build_object('journal_reminders', v_count);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Permessi delle funzioni nuove: interne, nessuno le chiama da fuori
-- ─────────────────────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION "internal"."rome_today"() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION "internal"."notification_exists"(uuid, "public"."notification_category", jsonb, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION "internal"."withdraw_booking_reminders"() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION "internal"."withdraw_lesson_reminders"() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION "internal"."requeue_announcement"() FROM PUBLIC, anon, authenticated;
