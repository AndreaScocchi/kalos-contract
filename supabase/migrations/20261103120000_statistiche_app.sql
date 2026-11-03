-- Migration 20261103120000: statistiche d'uso dell'app, solo totali
--
-- Richiesta dell'utente del 03/11/2026: capire quante persone usano l'app, in quali pagine, quanti
-- fanno partire le pratiche, quanti guardano eventi o attività. Decisione dell'utente: **solo
-- totali**, «non mi serve sapere chi». Nessun fornitore esterno: i numeri restano qui.
--
--   * `internal.app_usage_counts` tiene solo contatori, per giorno e per mese: `views` (ogni
--     apertura) e `people` (ognuna contata una volta nel periodo). Nessuna riga per persona, nessun
--     elenco di eventi. Restano nel tempo, perché non riguardano nessuno.
--   * Per non contare due volte la stessa persona, `internal.app_usage_seen` tiene un'impronta
--     (sha256) di chiave del mese + account + periodo + cosa è stato aperto. Quelle del giorno si
--     cancellano il giorno dopo; quelle del mese e la chiave (`internal.app_usage_salts`) a fine
--     mese. Le toglie `record_app_usage` a ogni chiamata, quindi non serve un job di pg_cron.
--   * Il limite: durante il mese in corso chi ha accesso diretto al database potrebbe rifare il
--     calcolo per un account preciso. Il gestionale no, e finito il mese nessuno. Per questo le
--     impronte e le chiavi sono escluse dai backup (`scripts/backup/run-backup.sh`).
--
-- Lo staff non si conta: le sue prove gonfierebbero i numeri. Le pagine stanno in un elenco fisso e
-- una sconosciuta diventa `altro`, così un cliente non può creare righe a piacere e una pagina nuova
-- dimenticata si nota nel gestionale. **Una rotta nuova dell'app va aggiunta qui**, con
-- `src/domain/usage.ts` dell'app e i nomi in `src/features/usage/constants.ts` del gestionale.
-- Diario, notifiche, segnalazioni e questionari non dicono mai quale voce è stata aperta; le lezioni
-- individuali contano solo come pagina.
--
-- Eliminare un account non tocca nulla: i contatori non sono collegati a nessuno.
-- migration-lint:allow revoke — reason: le REVOKE riguardano solo le tabelle e le funzioni nuove di questa migrazione (chiuse ad anon e authenticated).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tabelle
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE "internal"."app_usage_counts" (
    "granularity" "text" NOT NULL,
    "period" "date" NOT NULL,
    "metric" "text" NOT NULL,
    "page" "text",
    "target_id" "uuid",
    "step" smallint,
    "views" integer DEFAULT 0 NOT NULL,
    "people" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "app_usage_counts_granularity_check" CHECK (("granularity" = ANY (ARRAY['day'::"text", 'month'::"text"]))),
    CONSTRAINT "app_usage_counts_unique" UNIQUE NULLS NOT DISTINCT ("granularity", "period", "metric", "page", "target_id", "step")
);

COMMENT ON TABLE "internal"."app_usage_counts" IS
    'Statistiche d''uso dell''app: solo totali, per giorno e per mese. `period` è il giorno, o il primo del mese. Nessun riferimento a persone.';

CREATE TABLE "internal"."app_usage_seen" (
    "hash" "bytea" NOT NULL,
    "expires_on" "date" NOT NULL,
    CONSTRAINT "app_usage_seen_pkey" PRIMARY KEY ("hash")
);

CREATE INDEX "app_usage_seen_expires_on_idx" ON "internal"."app_usage_seen" ("expires_on");

COMMENT ON TABLE "internal"."app_usage_seen" IS
    'Impronte temporanee per contare ogni persona una volta nel periodo. Si cancellano alla scadenza e non vanno nei backup.';

CREATE TABLE "internal"."app_usage_salts" (
    "month" "date" NOT NULL,
    "salt" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    CONSTRAINT "app_usage_salts_pkey" PRIMARY KEY ("month")
);

COMMENT ON TABLE "internal"."app_usage_salts" IS
    'Chiave casuale delle impronte, una per mese. Finito il mese si cancella e le impronte non sono più riconducibili a nessuno. Non va nei backup.';

ALTER TABLE "internal"."app_usage_counts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "internal"."app_usage_seen" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "internal"."app_usage_salts" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON "internal"."app_usage_counts", "internal"."app_usage_seen", "internal"."app_usage_salts"
    FROM PUBLIC, "anon", "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Un contatore in più
-- ─────────────────────────────────────────────────────────────────────────────

CREATE FUNCTION "internal"."app_usage_bump"(
    "p_salt" "uuid",
    "p_uid" "uuid",
    "p_granularity" "text",
    "p_period" "date",
    "p_expires_on" "date",
    "p_metric" "text",
    "p_page" "text",
    "p_target_id" "uuid",
    "p_step" smallint
) RETURNS void
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_hash bytea;
    v_new integer;
BEGIN
    v_hash := sha256(convert_to(concat_ws('|',
        p_salt::text, p_uid::text, p_granularity, p_period::text, p_metric,
        coalesce(p_page, ''), coalesce(p_target_id::text, ''), coalesce(p_step::text, '')
    ), 'UTF8'));

    INSERT INTO internal.app_usage_seen (hash, expires_on)
    VALUES (v_hash, p_expires_on)
    ON CONFLICT (hash) DO NOTHING;
    GET DIAGNOSTICS v_new = ROW_COUNT;

    INSERT INTO internal.app_usage_counts AS c (granularity, period, metric, page, target_id, step, views, people)
    VALUES (p_granularity, p_period, p_metric, p_page, p_target_id, p_step, 1, v_new)
    ON CONFLICT ON CONSTRAINT app_usage_counts_unique
    DO UPDATE SET views = c.views + 1, people = c.people + EXCLUDED.people;
END;
$$;

ALTER FUNCTION "internal"."app_usage_bump"("uuid", "uuid", "text", "date", "date", "text", "text", "uuid", smallint) OWNER TO "postgres";

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. L'app registra quello che è stato aperto
-- ─────────────────────────────────────────────────────────────────────────────

CREATE FUNCTION "public"."record_app_usage"("p_hits" "jsonb") RETURNS void
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
    -- Le rotte di `src/app/(app)` dell'app. Una sconosciuta diventa `altro`.
    c_pages CONSTANT text[] := ARRAY[
        'home', 'calendar', 'explore', 'profile',
        'events', 'event', 'lesson', 'activity', 'team', 'plans', 'plan',
        'membership', 'membership_apply', 'onboarding',
        'card', 'bookings', 'subscriptions', 'receipts', 'journey',
        'practices', 'practice', 'practice_play',
        'journal', 'journal_entry', 'journal_new',
        'notifications', 'notification', 'notification_preferences', 'announcement',
        'settings', 'settings_profile', 'settings_password', 'settings_delete_account',
        'reports', 'report', 'report_new', 'contacts', 'trial_feedback', 'altro'
    ];
    v_uid uuid := auth.uid();
    v_today date := (now() AT TIME ZONE 'Europe/Rome')::date;
    v_month date := date_trunc('month', v_today)::date;
    v_month_end date := (v_month + interval '1 month' - interval '1 day')::date;
    v_salt uuid;
    v_hit jsonb;
    v_metric text;
    v_page text;
    v_raw_target text;
    v_target uuid;
    v_step smallint;
BEGIN
    -- Niente login: niente da contare (e anon non ha EXECUTE). Lo staff non si conta.
    IF v_uid IS NULL OR public.is_staff() THEN
        RETURN;
    END IF;
    IF p_hits IS NULL OR jsonb_typeof(p_hits) <> 'array' THEN
        RETURN;
    END IF;

    -- Impronte e chiavi scadute spariscono prima di ogni altra cosa
    DELETE FROM internal.app_usage_seen WHERE expires_on < v_today;
    DELETE FROM internal.app_usage_salts WHERE month < v_month;

    INSERT INTO internal.app_usage_salts (month) VALUES (v_month) ON CONFLICT (month) DO NOTHING;
    SELECT salt INTO v_salt FROM internal.app_usage_salts WHERE month = v_month;

    FOR v_hit IN SELECT value FROM jsonb_array_elements(p_hits) LIMIT 30 LOOP
        IF jsonb_typeof(v_hit) <> 'object' THEN
            CONTINUE;
        END IF;

        v_metric := v_hit->>'metric';
        v_page := NULL;
        v_target := NULL;
        v_step := NULL;

        v_raw_target := v_hit->>'target_id';
        IF v_raw_target !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
            v_raw_target := NULL;
        END IF;

        IF v_metric = 'open' THEN
            NULL;

        ELSIF v_metric = 'page' THEN
            v_page := v_hit->>'page';
            IF v_page IS NULL OR NOT (v_page = ANY (c_pages)) THEN
                v_page := 'altro';
            END IF;

            -- Solo queste pagine dicono cosa è stato aperto, e solo se esiste davvero
            IF v_raw_target IS NOT NULL THEN
                IF v_page = 'event' THEN
                    SELECT id INTO v_target FROM public.events WHERE id = v_raw_target::uuid;
                ELSIF v_page = 'activity' THEN
                    SELECT id INTO v_target FROM public.activities WHERE id = v_raw_target::uuid;
                ELSIF v_page = 'lesson' THEN
                    -- Una lezione si conta sulla sua attività; quella individuale solo come pagina
                    SELECT activity_id INTO v_target FROM public.lessons
                     WHERE id = v_raw_target::uuid AND NOT is_individual;
                ELSIF v_page = 'team' THEN
                    SELECT id INTO v_target FROM public.operators WHERE id = v_raw_target::uuid;
                ELSIF v_page = 'plan' THEN
                    SELECT id INTO v_target FROM public.plans WHERE id = v_raw_target::uuid;
                ELSIF v_page = 'practice' THEN
                    SELECT id INTO v_target FROM public.practices WHERE id = v_raw_target::uuid;
                ELSIF v_page = 'announcement' THEN
                    SELECT id INTO v_target FROM public.announcements WHERE id = v_raw_target::uuid;
                END IF;
            END IF;

        ELSIF v_metric IN ('practice_start', 'practice_step', 'practice_complete', 'practice_audio') THEN
            IF v_raw_target IS NOT NULL THEN
                SELECT id INTO v_target FROM public.practices WHERE id = v_raw_target::uuid;
            END IF;
            IF v_target IS NULL THEN
                CONTINUE;
            END IF;
            IF v_metric = 'practice_step' THEN
                IF coalesce(v_hit->>'step', '') !~ '^[0-9]{1,2}$' THEN
                    CONTINUE;
                END IF;
                v_step := (v_hit->>'step')::smallint;
            END IF;

        ELSE
            CONTINUE;
        END IF;

        PERFORM internal.app_usage_bump(v_salt, v_uid, 'day', v_today, v_today, v_metric, v_page, v_target, v_step);
        PERFORM internal.app_usage_bump(v_salt, v_uid, 'month', v_month, v_month_end, v_metric, v_page, v_target, v_step);

        -- La pagina con un bersaglio conta anche come pagina: chi apre due eventi è una persona sola
        IF v_metric = 'page' AND v_target IS NOT NULL THEN
            PERFORM internal.app_usage_bump(v_salt, v_uid, 'day', v_today, v_today, v_metric, v_page, NULL, NULL);
            PERFORM internal.app_usage_bump(v_salt, v_uid, 'month', v_month, v_month_end, v_metric, v_page, NULL, NULL);
        END IF;
    END LOOP;
END;
$_$;

ALTER FUNCTION "public"."record_app_usage"("jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."record_app_usage"("jsonb") FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."record_app_usage"("jsonb") TO "authenticated", "service_role";

COMMENT ON FUNCTION "public"."record_app_usage"("jsonb") IS
    'L''app segnala cosa è stato aperto: [{metric, page?, target_id?, step?}], al massimo 30 voci. Scrive solo totali. Lo staff non si conta.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Il gestionale legge i totali di un mese
-- ─────────────────────────────────────────────────────────────────────────────

CREATE FUNCTION "public"."staff_get_app_usage"("p_month" "date" DEFAULT NULL) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_month date;
    v_previous date;
    v_from timestamptz;
    v_to timestamptz;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    v_month := date_trunc('month', coalesce(p_month, (now() AT TIME ZONE 'Europe/Rome')::date))::date;
    v_previous := (v_month - interval '1 month')::date;
    v_from := v_month::timestamp AT TIME ZONE 'Europe/Rome';
    v_to := (v_month + interval '1 month')::timestamp AT TIME ZONE 'Europe/Rome';

    RETURN jsonb_build_object(
        'ok', true,
        'month', v_month,
        -- Dal giorno in cui si conta: prima non ci sono numeri, non zeri
        'first_period', (SELECT min(period) FROM internal.app_usage_counts WHERE granularity = 'day'),
        'totals', (
            SELECT jsonb_build_object('people', coalesce(sum(people), 0), 'opens', coalesce(sum(views), 0))
              FROM internal.app_usage_counts
             WHERE granularity = 'month' AND period = v_month AND metric = 'open'
        ),
        'previous', (
            SELECT jsonb_build_object('people', coalesce(sum(people), 0), 'opens', coalesce(sum(views), 0))
              FROM internal.app_usage_counts
             WHERE granularity = 'month' AND period = v_previous AND metric = 'open'
        ),
        'days', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('day', period, 'people', people, 'opens', views) ORDER BY period), '[]'::jsonb)
              FROM internal.app_usage_counts
             WHERE granularity = 'day' AND metric = 'open'
               AND period >= v_month AND period < (v_month + interval '1 month')::date
        ),
        'pages', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('page', page, 'views', views, 'people', people) ORDER BY people DESC, views DESC, page), '[]'::jsonb)
              FROM internal.app_usage_counts
             WHERE granularity = 'month' AND period = v_month AND metric = 'page' AND target_id IS NULL
        ),
        'events', (
            WITH seen AS (
                SELECT target_id AS id, views, people
                  FROM internal.app_usage_counts
                 WHERE granularity = 'month' AND period = v_month AND metric = 'page' AND page = 'event' AND target_id IS NOT NULL
            ), booked AS (
                SELECT event_id AS id, count(*) AS bookings
                  FROM public.event_bookings
                 WHERE created_at >= v_from AND created_at < v_to AND status <> 'canceled'
                 GROUP BY event_id
            )
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'id', e.id, 'name', e.name, 'starts_at', e.starts_at,
                       'views', coalesce(s.views, 0), 'people', coalesce(s.people, 0),
                       'bookings', coalesce(b.bookings, 0)
                   ) ORDER BY coalesce(s.people, 0) DESC, coalesce(s.views, 0) DESC, e.starts_at DESC), '[]'::jsonb)
              FROM public.events e
              LEFT JOIN seen s ON s.id = e.id
              LEFT JOIN booked b ON b.id = e.id
             WHERE s.id IS NOT NULL OR b.id IS NOT NULL
        ),
        'activities', (
            WITH cards AS (
                SELECT target_id AS id, views, people
                  FROM internal.app_usage_counts
                 WHERE granularity = 'month' AND period = v_month AND metric = 'page' AND page = 'activity' AND target_id IS NOT NULL
            ), lessons_seen AS (
                SELECT target_id AS id, views, people
                  FROM internal.app_usage_counts
                 WHERE granularity = 'month' AND period = v_month AND metric = 'page' AND page = 'lesson' AND target_id IS NOT NULL
            ), booked AS (
                SELECT l.activity_id AS id, count(*) AS bookings
                  FROM public.bookings b
                  JOIN public.lessons l ON l.id = b.lesson_id
                 WHERE b.created_at >= v_from AND b.created_at < v_to AND b.status <> 'canceled' AND NOT l.is_individual
                 GROUP BY l.activity_id
            )
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'id', a.id, 'name', a.name,
                       'card_views', coalesce(c.views, 0), 'card_people', coalesce(c.people, 0),
                       'lesson_views', coalesce(l.views, 0), 'lesson_people', coalesce(l.people, 0),
                       'bookings', coalesce(b.bookings, 0)
                   ) ORDER BY coalesce(c.people, 0) + coalesce(l.people, 0) DESC, coalesce(b.bookings, 0) DESC, a.name), '[]'::jsonb)
              FROM public.activities a
              LEFT JOIN cards c ON c.id = a.id
              LEFT JOIN lessons_seen l ON l.id = a.id
              LEFT JOIN booked b ON b.id = a.id
             WHERE c.id IS NOT NULL OR l.id IS NOT NULL OR b.id IS NOT NULL
        ),
        'practices', (
            WITH counted AS (
                SELECT target_id AS id,
                       coalesce(sum(people) FILTER (WHERE metric = 'page' AND page = 'practice'), 0) AS card_people,
                       coalesce(sum(views) FILTER (WHERE metric = 'page' AND page = 'practice'), 0) AS card_views,
                       coalesce(sum(people) FILTER (WHERE metric = 'practice_start'), 0) AS start_people,
                       coalesce(sum(views) FILTER (WHERE metric = 'practice_start'), 0) AS start_views,
                       coalesce(sum(people) FILTER (WHERE metric = 'practice_audio'), 0) AS audio_people,
                       coalesce(sum(views) FILTER (WHERE metric = 'practice_audio'), 0) AS audio_views,
                       coalesce(sum(people) FILTER (WHERE metric = 'practice_complete'), 0) AS complete_people,
                       coalesce(sum(views) FILTER (WHERE metric = 'practice_complete'), 0) AS complete_views
                  FROM internal.app_usage_counts
                 WHERE granularity = 'month' AND period = v_month AND target_id IS NOT NULL
                   AND (metric IN ('practice_start', 'practice_audio', 'practice_complete') OR (metric = 'page' AND page = 'practice'))
                 GROUP BY target_id
            ), reached AS (
                SELECT target_id AS id,
                       jsonb_agg(jsonb_build_object('step', step, 'people', people) ORDER BY step) AS steps
                  FROM internal.app_usage_counts
                 WHERE granularity = 'month' AND period = v_month AND metric = 'practice_step'
                 GROUP BY target_id
            )
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'id', p.id, 'title', p.title,
                       'card_people', coalesce(c.card_people, 0), 'card_views', coalesce(c.card_views, 0),
                       'start_people', coalesce(c.start_people, 0), 'start_views', coalesce(c.start_views, 0),
                       'audio_people', coalesce(c.audio_people, 0), 'audio_views', coalesce(c.audio_views, 0),
                       'complete_people', coalesce(c.complete_people, 0), 'complete_views', coalesce(c.complete_views, 0),
                       'steps_count', (SELECT count(*) FROM public.practice_steps st WHERE st.practice_id = p.id),
                       'steps', coalesce(r.steps, '[]'::jsonb)
                   ) ORDER BY coalesce(c.start_people, 0) DESC, coalesce(c.card_people, 0) DESC, p.title), '[]'::jsonb)
              FROM public.practices p
              LEFT JOIN counted c ON c.id = p.id
              LEFT JOIN reached r ON r.id = p.id
             WHERE c.id IS NOT NULL OR r.id IS NOT NULL OR (p.is_active AND p.deleted_at IS NULL)
        )
    );
END;
$$;

ALTER FUNCTION "public"."staff_get_app_usage"("date") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "public"."staff_get_app_usage"("date") FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."staff_get_app_usage"("date") TO "authenticated", "service_role";

COMMENT ON FUNCTION "public"."staff_get_app_usage"("date") IS
    'Statistiche d''uso dell''app di un mese, solo totali, per il gestionale. Iscrizioni e prenotazioni comprendono quelle inserite dallo staff.';
