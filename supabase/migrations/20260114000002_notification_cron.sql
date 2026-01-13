-- Migration: Setup pg_cron jobs for notification scheduling
--
-- NOTA: pg_cron e pg_net devono essere abilitati nel progetto Supabase.
-- I job usano pg_net per chiamare le Edge Functions.
--
-- CONFIGURAZIONE RICHIESTA nel Supabase Dashboard:
-- 1. Vai in Database > Extensions e abilita pg_cron e pg_net
-- 2. Vai in Project Settings > Configuration > Database
-- 3. Aggiungi queste variabili nella configurazione del database:
--    - app.settings.supabase_url = https://tkioedsebdxqblgcctxv.supabase.co
--    - app.settings.service_role_key = <service-role-key>

-- ============================================================================
-- 1. ENABLE EXTENSIONS (se non gia abilitate)
-- ============================================================================

-- pg_cron e pg_net sono gestite a livello di progetto Supabase
-- Questo codice e commentato perche le estensioni vanno abilitate dalla dashboard
-- CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
-- CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ============================================================================
-- 2. HELPER FUNCTION PER CHIAMARE EDGE FUNCTIONS
-- ============================================================================

-- Funzione che chiama una Edge Function via pg_net
CREATE OR REPLACE FUNCTION "public"."call_edge_function"(
    "p_function_name" "text",
    "p_body" "jsonb" DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_url text;
    v_service_key text;
    v_request_id bigint;
BEGIN
    -- Get configuration from database settings
    v_url := current_setting('app.settings.supabase_url', true);
    v_service_key := current_setting('app.settings.service_role_key', true);

    IF v_url IS NULL OR v_service_key IS NULL THEN
        RAISE EXCEPTION 'Missing app.settings.supabase_url or app.settings.service_role_key configuration';
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

-- ============================================================================
-- 3. WRAPPER FUNCTIONS PER CRON JOBS
-- ============================================================================

-- Wrapper per schedule-notifications (lesson reminders)
CREATE OR REPLACE FUNCTION "public"."cron_queue_lesson_reminders"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'schedule-notifications',
        '{"jobType": "lesson_reminders"}'::jsonb
    );
END;
$$;

-- Wrapper per process-notification-queue
CREATE OR REPLACE FUNCTION "public"."cron_process_notification_queue"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'process-notification-queue',
        '{}'::jsonb
    );
END;
$$;

-- Wrapper per schedule-notifications (subscription expiry)
CREATE OR REPLACE FUNCTION "public"."cron_queue_subscription_expiry"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'schedule-notifications',
        '{"jobType": "subscription_expiry"}'::jsonb
    );
END;
$$;

-- Wrapper per schedule-notifications (entries low)
CREATE OR REPLACE FUNCTION "public"."cron_queue_entries_low"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'schedule-notifications',
        '{"jobType": "entries_low"}'::jsonb
    );
END;
$$;

-- Wrapper per schedule-notifications (re-engagement)
CREATE OR REPLACE FUNCTION "public"."cron_queue_re_engagement"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'schedule-notifications',
        '{"jobType": "re_engagement"}'::jsonb
    );
END;
$$;

-- Wrapper per schedule-notifications (birthday)
CREATE OR REPLACE FUNCTION "public"."cron_queue_birthday"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'schedule-notifications',
        '{"jobType": "birthday"}'::jsonb
    );
END;
$$;

-- ============================================================================
-- 4. CREATE CRON JOBS
-- ============================================================================

-- NOTA: Esegui questi comandi manualmente dalla SQL Editor di Supabase
-- dopo aver abilitato pg_cron dalla dashboard.

-- 1. Lesson reminders - Ogni ora per accodare promemoria
-- SELECT cron.schedule(
--     'notification-queue-lesson-reminders',
--     '0 * * * *',
--     'SELECT public.cron_queue_lesson_reminders()'
-- );

-- 2. Process notification queue - Ogni 5 minuti per inviare
-- SELECT cron.schedule(
--     'notification-process-queue',
--     '*/5 * * * *',
--     'SELECT public.cron_process_notification_queue()'
-- );

-- 3. Subscription expiry - Ogni giorno alle 10:00 Rome (09:00 UTC winter)
-- SELECT cron.schedule(
--     'notification-queue-subscription-expiry',
--     '0 9 * * *',
--     'SELECT public.cron_queue_subscription_expiry()'
-- );

-- 4. Entries low - Ogni giorno alle 10:30 Rome
-- SELECT cron.schedule(
--     'notification-queue-entries-low',
--     '30 9 * * *',
--     'SELECT public.cron_queue_entries_low()'
-- );

-- 5. Re-engagement - Ogni giorno alle 18:00 Rome (17:00 UTC winter)
-- SELECT cron.schedule(
--     'notification-queue-re-engagement',
--     '0 17 * * *',
--     'SELECT public.cron_queue_re_engagement()'
-- );

-- 6. Birthday - Ogni giorno alle 09:00 Rome (08:00 UTC winter)
-- SELECT cron.schedule(
--     'notification-queue-birthday',
--     '0 8 * * *',
--     'SELECT public.cron_queue_birthday()'
-- );

-- Per verificare i cron jobs creati:
-- SELECT * FROM cron.job;

-- Per vedere lo storico delle esecuzioni:
-- SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 50;

-- Per rimuovere un cron job:
-- SELECT cron.unschedule('notification-queue-lesson-reminders');

-- ============================================================================
-- 5. ALTERNATIVE: DIRECT RPC EXECUTION (senza pg_net)
-- ============================================================================

-- Se pg_net non e disponibile, questi cron jobs chiamano direttamente le RPC
-- invece di passare per le Edge Functions

-- Alternative: Direct RPC calls (senza Edge Functions)
-- SELECT cron.schedule(
--     'notification-queue-lesson-reminders-direct',
--     '0 * * * *',
--     'SELECT public.queue_lesson_reminders()'
-- );

-- SELECT cron.schedule(
--     'notification-queue-subscription-expiry-direct',
--     '0 9 * * *',
--     'SELECT public.queue_subscription_expiry()'
-- );

-- SELECT cron.schedule(
--     'notification-queue-entries-low-direct',
--     '30 9 * * *',
--     'SELECT public.queue_entries_low()'
-- );

-- SELECT cron.schedule(
--     'notification-queue-re-engagement-direct',
--     '0 17 * * *',
--     'SELECT public.queue_re_engagement()'
-- );

-- SELECT cron.schedule(
--     'notification-queue-birthday-direct',
--     '0 8 * * *',
--     'SELECT public.queue_birthday()'
-- );

-- ============================================================================
-- 6. COMMENTS
-- ============================================================================

COMMENT ON FUNCTION "public"."call_edge_function" IS
'Helper per chiamare Edge Functions via pg_net. Richiede app.settings.supabase_url e app.settings.service_role_key.';

COMMENT ON FUNCTION "public"."cron_queue_lesson_reminders" IS
'Wrapper per cron job che accoda promemoria lezioni via Edge Function.';

COMMENT ON FUNCTION "public"."cron_process_notification_queue" IS
'Wrapper per cron job che processa la coda notifiche via Edge Function.';
