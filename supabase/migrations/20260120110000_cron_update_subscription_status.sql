-- Migration: Cron job per aggiornare automaticamente lo stato degli abbonamenti scaduti
--
-- Problema: I trigger esistenti si attivano solo su modifiche al DB, non al passare del tempo.
-- Quando un abbonamento scade naturalmente (expires_at < CURRENT_DATE), lo stato non viene aggiornato.
--
-- Soluzione: Cron job giornaliero che esegue l'UPDATE degli stati secondo la logica:
-- - "active": expires_at >= CURRENT_DATE E remaining_entries > 0 (o illimitato)
-- - "expired": expires_at < CURRENT_DATE E remaining_entries > 0 (o illimitato)
-- - "completed": remaining_entries <= 0 (indipendentemente dalla scadenza)
-- - "canceled": preservato, mai modificato

-- ============================================================================
-- 1. FUNZIONE: Aggiorna stati abbonamenti
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."update_expired_subscription_statuses"()
RETURNS TABLE (
    updated_count integer,
    active_to_expired integer,
    active_to_completed integer,
    completed_to_expired integer
)
LANGUAGE "plpgsql"
SECURITY DEFINER
SET "search_path" TO 'public'
AS $$
DECLARE
    v_active_to_expired integer := 0;
    v_active_to_completed integer := 0;
    v_completed_to_expired integer := 0;
BEGIN
    -- Aggiorna abbonamenti "active" che sono scaduti -> "expired"
    -- (solo quelli con remaining_entries > 0 o illimitati)
    WITH usage_totals AS (
        SELECT
            subscription_id,
            COALESCE(SUM(delta), 0) AS delta_sum
        FROM subscription_usages
        GROUP BY subscription_id
    ),
    to_expire AS (
        SELECT s.id
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        LEFT JOIN usage_totals u ON u.subscription_id = s.id
        WHERE s.deleted_at IS NULL
          AND s.status = 'active'
          AND s.expires_at < CURRENT_DATE
          AND (
              -- Illimitato
              COALESCE(s.custom_entries, p.entries) IS NULL
              OR
              -- Ha ancora ingressi
              (COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)) > 0
          )
    )
    UPDATE subscriptions s
    SET status = 'expired'
    FROM to_expire te
    WHERE s.id = te.id;

    GET DIAGNOSTICS v_active_to_expired = ROW_COUNT;

    -- Aggiorna abbonamenti "active" che hanno esaurito gli ingressi -> "completed"
    WITH usage_totals AS (
        SELECT
            subscription_id,
            COALESCE(SUM(delta), 0) AS delta_sum
        FROM subscription_usages
        GROUP BY subscription_id
    ),
    to_complete AS (
        SELECT s.id
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        LEFT JOIN usage_totals u ON u.subscription_id = s.id
        WHERE s.deleted_at IS NULL
          AND s.status = 'active'
          AND COALESCE(s.custom_entries, p.entries) IS NOT NULL  -- Non illimitato
          AND (COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)) <= 0
    )
    UPDATE subscriptions s
    SET status = 'completed'
    FROM to_complete tc
    WHERE s.id = tc.id;

    GET DIAGNOSTICS v_active_to_completed = ROW_COUNT;

    -- Correggi abbonamenti "completed" che in realta hanno ancora ingressi -> "expired"
    -- (caso edge: errore di stato precedente)
    WITH usage_totals AS (
        SELECT
            subscription_id,
            COALESCE(SUM(delta), 0) AS delta_sum
        FROM subscription_usages
        GROUP BY subscription_id
    ),
    to_fix AS (
        SELECT s.id
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        LEFT JOIN usage_totals u ON u.subscription_id = s.id
        WHERE s.deleted_at IS NULL
          AND s.status = 'completed'
          AND s.expires_at < CURRENT_DATE
          AND (
              -- Illimitato
              COALESCE(s.custom_entries, p.entries) IS NULL
              OR
              -- Ha ancora ingressi
              (COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)) > 0
          )
    )
    UPDATE subscriptions s
    SET status = 'expired'
    FROM to_fix tf
    WHERE s.id = tf.id;

    GET DIAGNOSTICS v_completed_to_expired = ROW_COUNT;

    RETURN QUERY SELECT
        (v_active_to_expired + v_active_to_completed + v_completed_to_expired)::integer,
        v_active_to_expired,
        v_active_to_completed,
        v_completed_to_expired;
END;
$$;

ALTER FUNCTION "public"."update_expired_subscription_statuses"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."update_expired_subscription_statuses"() IS
'Aggiorna automaticamente lo stato degli abbonamenti in base a scadenza e ingressi rimanenti.
Chiamata giornalmente dal cron job. Ritorna il conteggio degli aggiornamenti effettuati.';

-- ============================================================================
-- 2. WRAPPER PER CRON JOB (senza ritorno, per compatibilita)
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."cron_update_subscription_statuses"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
SET "search_path" TO 'public'
AS $$
DECLARE
    v_result record;
BEGIN
    SELECT * INTO v_result FROM update_expired_subscription_statuses();

    -- Log solo se ci sono stati aggiornamenti
    IF v_result.updated_count > 0 THEN
        RAISE NOTICE 'Subscription status update: % total (active->expired: %, active->completed: %, completed->expired: %)',
            v_result.updated_count,
            v_result.active_to_expired,
            v_result.active_to_completed,
            v_result.completed_to_expired;
    END IF;
END;
$$;

ALTER FUNCTION "public"."cron_update_subscription_statuses"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."cron_update_subscription_statuses"() IS
'Wrapper per cron job che aggiorna gli stati degli abbonamenti. Eseguire giornalmente.';

-- ============================================================================
-- 3. ESEGUI CORREZIONE IMMEDIATA
-- ============================================================================

-- Correggi subito gli abbonamenti esistenti con stato errato
SELECT * FROM update_expired_subscription_statuses();

-- ============================================================================
-- 4. CRON JOB (da eseguire manualmente in Supabase Dashboard)
-- ============================================================================

-- Esegui questo comando manualmente nel SQL Editor di Supabase:
--
-- SELECT cron.schedule(
--     'subscription-status-daily-update',
--     '0 1 * * *',  -- Ogni giorno alle 01:00 UTC (02:00 Roma inverno, 03:00 Roma estate)
--     'SELECT public.cron_update_subscription_statuses()'
-- );
--
-- Per verificare che il job sia stato creato:
-- SELECT * FROM cron.job WHERE jobname = 'subscription-status-daily-update';
--
-- Per vedere lo storico delle esecuzioni:
-- SELECT * FROM cron.job_run_details WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'subscription-status-daily-update') ORDER BY start_time DESC LIMIT 10;
--
-- Per rimuovere il job:
-- SELECT cron.unschedule('subscription-status-daily-update');
