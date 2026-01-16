-- Migration: Setup pg_cron jobs for marketing campaigns
--
-- Questo file aggiunge i CRON jobs per:
-- 1. Esecuzione campagne schedulate (ogni 5 minuti)
-- 2. Aggiornamento analytics social (ogni 6 ore)
--
-- PREREQUISITI: pg_cron e pg_net devono essere abilitati.
-- Le variabili app.settings.supabase_url e app.settings.service_role_key
-- devono essere configurate (vedi 20260114000002_notification_cron.sql)

-- ============================================================================
-- 1. WRAPPER FUNCTIONS PER CRON JOBS MARKETING
-- ============================================================================

-- Wrapper per execute-scheduled-campaigns
CREATE OR REPLACE FUNCTION "public"."cron_execute_scheduled_campaigns"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'execute-scheduled-campaigns',
        '{}'::jsonb
    );
END;
$$;

-- Wrapper per meta-fetch-analytics
CREATE OR REPLACE FUNCTION "public"."cron_fetch_social_analytics"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."call_edge_function"(
        'meta-fetch-analytics',
        '{}'::jsonb
    );
END;
$$;

-- ============================================================================
-- 2. CREATE CRON JOBS
-- ============================================================================

-- NOTA: Esegui questi comandi manualmente dalla SQL Editor di Supabase
-- dopo aver abilitato pg_cron dalla dashboard.

-- 1. Execute scheduled campaigns - Ogni 5 minuti
-- SELECT cron.schedule(
--     'marketing-execute-scheduled-campaigns',
--     '*/5 * * * *',
--     'SELECT public.cron_execute_scheduled_campaigns()'
-- );

-- 2. Fetch social analytics - Ogni 6 ore (00:00, 06:00, 12:00, 18:00 UTC)
-- SELECT cron.schedule(
--     'marketing-fetch-social-analytics',
--     '0 */6 * * *',
--     'SELECT public.cron_fetch_social_analytics()'
-- );

-- ============================================================================
-- 3. COMMENTS
-- ============================================================================

COMMENT ON FUNCTION "public"."cron_execute_scheduled_campaigns" IS
'Wrapper per cron job che esegue le campagne marketing schedulate via Edge Function.';

COMMENT ON FUNCTION "public"."cron_fetch_social_analytics" IS
'Wrapper per cron job che aggiorna le analytics social via Edge Function.';
