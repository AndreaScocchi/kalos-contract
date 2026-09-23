-- Migration 20260923161100: le funzioni dei job nello schema interno (sessione 3, blocco 11)
--
-- Obiettivo: completare il riordino spostando anche le funzioni `cron_*`, le ultime rimaste in
-- `public` fra quelle interne.
--
-- PERCHÉ È UNA MIGRAZIONE A SÉ, E PERCHÉ È SCRITTA COSÌ.
-- I job di pg_cron NON stanno nelle migrazioni: esistono solo in produzione, creati a mano dalla
-- dashboard. Un job è una stringa di comando, per esempio `SELECT public.cron_queue_lesson_reminders();`.
-- Spostare la funzione senza aggiornare quella stringa non dà nessun errore al momento del push: il
-- job semplicemente comincia a fallire ogni volta che parte, e i promemoria, le scadenze degli
-- abbonamenti e la coda delle notifiche si fermano in silenzio. È il modo peggiore di rompere
-- qualcosa.
--
-- Quindi qui si fa tutto insieme e in modo verificabile:
--   1. si spostano le funzioni;
--   2. si riscrivono i comandi dei job che le chiamano, qualunque forma abbiano
--      (`cron_x()`, `public.cron_x()`, `"public"."cron_x"()`);
--   3. se dopo la riscrittura resta anche un solo job che punta a una funzione che non esiste più,
--      la migrazione FALLISCE e annulla tutto. Meglio un push rifiutato che le notifiche spente.
--
-- In locale `pg_cron` non c'è: il blocco se ne accorge e non fa nulla, così `db reset` resta pulito.
-- Dopo il push in produzione vanno guardati `cron.job` (i comandi aggiornati) e `cron.job_run_details`
-- (le prime esecuzioni verdi).
--
-- Compatibilità: nessuna firma cambia, nessuna funzione sparisce. Restano in `public` le funzioni che
-- l'edge function `schedule-notifications` chiama attraverso PostgREST, elencate nella migrazione
-- precedente. Vedi ACCESS_MODEL.md e docs/PIANO-APS-E-NUOVA-APP.md §0.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Spostamento
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_fn record;
BEGIN
    FOR v_fn IN
        SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
          FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace
           AND p.proname LIKE 'cron\_%'
    LOOP
        EXECUTE format('ALTER FUNCTION public.%I(%s) SET SCHEMA internal', v_fn.proname, v_fn.args);
    END LOOP;
END $$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA "internal" TO "service_role";

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. I comandi dei job seguono le funzioni
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_job       record;
    v_fn        record;
    v_new       text;
    v_broken    text[] := ARRAY[]::text[];
    v_updated   integer := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
        RAISE NOTICE 'pg_cron non presente: nessun job da aggiornare (atteso in locale).';
        RETURN;
    END IF;

    FOR v_job IN SELECT jobid, jobname, command FROM cron.job LOOP
        v_new := v_job.command;

        FOR v_fn IN SELECT DISTINCT proname FROM pg_proc
                     WHERE pronamespace = 'internal'::regnamespace LOOP
            -- "public"."x" → "internal"."x"
            v_new := regexp_replace(v_new,
                '"public"\s*\.\s*"' || v_fn.proname || '"',
                '"internal"."' || v_fn.proname || '"', 'gi');
            -- public.x → internal.x
            v_new := regexp_replace(v_new,
                '\mpublic\s*\.\s*' || v_fn.proname || '\M',
                'internal.' || v_fn.proname, 'gi');
            -- x() senza schema → internal.x()
            v_new := regexp_replace(v_new,
                '(^|[^.\w"])' || v_fn.proname || '\s*\(',
                '\1internal.' || v_fn.proname || '(', 'g');
        END LOOP;

        IF v_new IS DISTINCT FROM v_job.command THEN
            PERFORM cron.alter_job(job_id := v_job.jobid, command := v_new);
            v_updated := v_updated + 1;
            RAISE NOTICE 'job % aggiornato: % → %', v_job.jobname, v_job.command, v_new;
        END IF;

        -- Rete di sicurezza: nessun job deve più citare una funzione che in public non c'è più
        IF v_new ~* '(^|[^.\w"])(public\s*\.\s*)?"?cron_[a-z_]+"?\s*\('
           AND v_new !~* 'internal\s*\.\s*"?cron_' THEN
            v_broken := array_append(v_broken, v_job.jobname || ': ' || v_new);
        END IF;
    END LOOP;

    IF array_length(v_broken, 1) > 0 THEN
        RAISE EXCEPTION 'Job di cron rimasti senza funzione dopo lo spostamento: %',
            array_to_string(v_broken, ' | ')
            USING HINT = 'Aggiorna a mano il comando del job e ripeti il push.';
    END IF;

    RAISE NOTICE 'Job di cron aggiornati: %', v_updated;
END $$;
