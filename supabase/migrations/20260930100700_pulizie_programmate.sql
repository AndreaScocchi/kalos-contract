-- Migration 20260930100700: pulizie programmate
--
-- Dalla verifica generale del 30/09/2026 (docs/ISSUES.md §2.1).
--
-- 1. Domande di ammissione respinte: la privacy aggiornata il 30/09 dice che si tengono 12 mesi dalla
--    decisione (per un eventuale ricorso e per rispondere alla persona) e poi si cancellano. Nessun
--    job lo faceva: `internal.purge_rejected_applications()` le cancella. Le ricevute di una quota
--    versata e poi restituita restano con la contabilità (non sono collegate alla domanda).
-- 2. Storico dei job di pg_cron: `cron.job_run_details` cresceva senza limite (233.683 righe e
--    45 MB al 30/09, su un piano con 500 MB di database). `internal.cleanup_job_history()` tiene gli
--    ultimi 30 giorni.
--
-- I job di pg_cron esistono solo in produzione (vedi ACCESS_MODEL.md): si creano a mano dopo il
-- push, una volta al giorno di notte:
--   select cron.schedule('purge-rejected-applications', '15 2 * * *', 'SELECT internal.purge_rejected_applications()');
--   select cron.schedule('cleanup-job-history', '30 2 * * *', 'SELECT internal.cleanup_job_history()');

CREATE OR REPLACE FUNCTION "internal"."purge_rejected_applications"()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_count integer;
BEGIN
    DELETE FROM public.member_applications a
     WHERE a.status = 'rejected'
       AND COALESCE(a.decided_at, a.updated_at) < now() - interval '12 months'
       AND NOT EXISTS (SELECT 1 FROM public.members m WHERE m.application_id = a.id);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION "internal"."purge_rejected_applications"() IS
  'Cancella le domande di ammissione respinte da più di 12 mesi (privacy §7). Job di pg_cron, solo in produzione.';

CREATE OR REPLACE FUNCTION "internal"."cleanup_job_history"()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_count integer := 0;
BEGIN
    IF to_regclass('cron.job_run_details') IS NOT NULL THEN
        EXECUTE 'DELETE FROM cron.job_run_details WHERE end_time < now() - interval ''30 days''';
        GET DIAGNOSTICS v_count = ROW_COUNT;
    END IF;
    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION "internal"."cleanup_job_history"() IS
  'Tiene gli ultimi 30 giorni dello storico di pg_cron. Job di pg_cron, solo in produzione.';

-- migration-lint:allow revoke — reason: funzioni interne nuove di questa migrazione
REVOKE ALL ON FUNCTION "internal"."purge_rejected_applications"() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION "internal"."cleanup_job_history"() FROM PUBLIC, anon, authenticated;
