-- Migration: Cron job wrappers call RPC directly instead of pg_net
--
-- Problema: I wrapper cron usano call_edge_function() che richiede
-- app.settings.supabase_url e service_role_key configurati.
-- Queste settings non sono configurate, quindi i cron falliscono silenziosamente.
--
-- Soluzione: Modificare i wrapper per chiamare direttamente le RPC,
-- eliminando la dipendenza da pg_net e dalle settings.
--
-- NOTA: cron_process_notification_queue() rimane invariato perché
-- l'edge function process-notification-queue funziona correttamente.

-- ============================================================================
-- 1. cron_queue_lesson_reminders - chiamata diretta
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."cron_queue_lesson_reminders"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Chiamata diretta alla RPC invece di passare per Edge Function
    PERFORM "public"."queue_lesson_reminders"();
END;
$$;

COMMENT ON FUNCTION "public"."cron_queue_lesson_reminders" IS
'Wrapper cron: accoda promemoria lezioni chiamando direttamente la RPC.';

-- ============================================================================
-- 2. cron_queue_subscription_expiry - chiamata diretta
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."cron_queue_subscription_expiry"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Chiamata diretta alla RPC invece di passare per Edge Function
    PERFORM "public"."queue_subscription_expiry"();
END;
$$;

COMMENT ON FUNCTION "public"."cron_queue_subscription_expiry" IS
'Wrapper cron: accoda notifiche scadenza abbonamento chiamando direttamente la RPC.';

-- ============================================================================
-- 3. cron_queue_entries_low - chiamata diretta
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."cron_queue_entries_low"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Chiamata diretta alla RPC invece di passare per Edge Function
    PERFORM "public"."queue_entries_low"();
END;
$$;

COMMENT ON FUNCTION "public"."cron_queue_entries_low" IS
'Wrapper cron: accoda notifiche ingressi bassi chiamando direttamente la RPC.';

-- ============================================================================
-- 4. cron_queue_re_engagement - chiamata diretta
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."cron_queue_re_engagement"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Chiamata diretta alla RPC invece di passare per Edge Function
    PERFORM "public"."queue_re_engagement"();
END;
$$;

COMMENT ON FUNCTION "public"."cron_queue_re_engagement" IS
'Wrapper cron: accoda notifiche re-engagement chiamando direttamente la RPC.';

-- ============================================================================
-- 5. cron_queue_birthday - chiamata diretta
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."cron_queue_birthday"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Chiamata diretta alla RPC invece di passare per Edge Function
    PERFORM "public"."queue_birthday"();
END;
$$;

COMMENT ON FUNCTION "public"."cron_queue_birthday" IS
'Wrapper cron: accoda auguri compleanno chiamando direttamente la RPC.';
