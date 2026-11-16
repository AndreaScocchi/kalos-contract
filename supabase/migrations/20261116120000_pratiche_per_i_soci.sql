-- La Pratica a casa è dei soci (16/11/2026, richiesta dell'utente).
--
-- Tuttə vedono le pratiche (titolo, copertina, durata, descrizione: la tabella `practices` resta
-- leggibile come prima), ma i contenuti, cioè passaggi e blocchi con testi e indirizzi di audio e
-- video, li leggono solo lo staff e chi è sociə in regola: la stessa regola della Bussola (D6) e
-- delle prenotazioni, `internal.member_booking_status` in `ok` (quota pagata o esonerata) o
-- `fee_due_grace` (sociə con la quota dell'anno non ancora scaduta).
--
-- 1. `has_active_membership()`: vero per chi è sociə in regola. La chiamano le policy qui sotto e
--    l'app, per sapere se mostrare una pratica o l'invito a diventare sociə.
-- 2. Le policy di lettura di `practice_steps` e `practice_blocks` chiedono anche di essere sociə.
--    Le policy dello staff restano com'erano.
-- 3. `record_app_usage`: le pagine delle tre sezioni della Pratica a casa (Meditazione, Yoga,
--    Riflessione). Il resto è uguale alla migrazione 20261114140000, che aggiunge `activities`: questa
--    la comprende, quindi vale anche se quella non è ancora stata applicata.
--
-- Limite noto: i file di audio e video stanno nel bucket pubblico `practices`. Il loro indirizzo ora
-- lo legge solo chi è sociə, ma chi lo ha già (o lo riceve da qualcunə) lo può ancora aprire.

-- migration-lint:allow revoke — reason: la REVOKE riguarda solo la funzione nuova di questa migrazione (chiusa ad anon). Le policy di lettura di passaggi e blocchi si restringono per scelta dell'utente (solo soci in regola e staff); nessun consumer le legge fuori dall'app, che dalla stessa versione mostra il blocco ai non soci.

-- ── 1. Sociə in regola ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."has_active_membership"() RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;
    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN false;
    END IF;
    RETURN "internal"."member_booking_status"(v_client_id) IN ('ok', 'fee_due_grace');
END;
$$;

ALTER FUNCTION "public"."has_active_membership"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."has_active_membership"() IS
    'Vero se chi chiama è sociə in regola (internal.member_booking_status in ok o fee_due_grace). La usano le policy dei contenuti della Pratica a casa e l''app (16/11/2026).';

REVOKE ALL ON FUNCTION "public"."has_active_membership"() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."has_active_membership"() TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."has_active_membership"() TO "service_role";

-- ── 2. Passaggi e blocchi solo per i soci ───────────────────────────────────

DROP POLICY IF EXISTS "practice_steps_select_active" ON "public"."practice_steps";
CREATE POLICY "practice_steps_select_active" ON "public"."practice_steps"
    FOR SELECT TO "authenticated"
    USING (
        (SELECT public.has_active_membership())
        AND EXISTS (
            SELECT 1 FROM "public"."practices" "p"
             WHERE "p"."id" = "practice_steps"."practice_id"
               AND "p"."is_active" = true
               AND "p"."deleted_at" IS NULL
        )
    );

DROP POLICY IF EXISTS "practice_blocks_select_active" ON "public"."practice_blocks";
CREATE POLICY "practice_blocks_select_active" ON "public"."practice_blocks"
    FOR SELECT TO "authenticated"
    USING (
        (SELECT public.has_active_membership())
        AND EXISTS (
            SELECT 1 FROM "public"."practice_steps" "ps"
              JOIN "public"."practices" "p" ON "p"."id" = "ps"."practice_id"
             WHERE "ps"."id" = "practice_blocks"."step_id"
               AND "p"."is_active" = true
               AND "p"."deleted_at" IS NULL
        )
    );

-- ── 3. Statistiche: le sezioni della Pratica a casa ─────────────────────────

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
        'practices', 'practices_meditazione', 'practices_yoga', 'practices_riflessione',
        'practice', 'practice_play',
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

