-- Statistiche d'uso: la pagina «Le nostre attività» (`/activities`) dell'app (14/11/2026).
--
-- Su richiesta dell'utente le attività non sono più una sezione di Esplora ma una pagina sua, aperta
-- dalla card «Attività». `record_app_usage` conta solo le pagine del suo elenco (le altre finiscono in
-- `altro`): qui si aggiunge `activities`. Il resto della funzione è uguale alla migrazione
-- 20261103120000; CREATE OR REPLACE tiene proprietario, permessi e search_path.

CREATE OR REPLACE FUNCTION "public"."record_app_usage"("p_hits" "jsonb") RETURNS void
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
    -- Le rotte di `src/app/(app)` dell'app. Una sconosciuta diventa `altro`.
    c_pages CONSTANT text[] := ARRAY[
        'home', 'calendar', 'explore', 'profile',
        'events', 'event', 'lesson', 'activities', 'activity', 'team', 'plans', 'plan',
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

