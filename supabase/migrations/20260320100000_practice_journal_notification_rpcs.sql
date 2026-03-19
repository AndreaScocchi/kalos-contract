-- Migration: RPC functions per accodare notifiche pratiche e diario
--
-- 3 nuove funzioni di queueing + 3 wrapper cron:
--   - queue_practice_reminder: giornaliero per utenti inattivi da 2+ giorni
--   - queue_practice_resume: per pratiche iniziate e abbandonate da 3+ giorni
--   - queue_journal_reminder: settimanale per utenti che non scrivono da 7+ giorni

-- ============================================================================
-- 1. QUEUE PRACTICE REMINDER
-- Promemoria giornaliero: suggerisce di praticare a utenti inattivi da 2+ giorni
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."queue_practice_reminder"()
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count integer := 0;
    v_now timestamp with time zone := NOW();
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        'practice_reminder'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 'practice_reminder'),
            'push'::"public"."notification_channel"
        ),
        'Prenditi un momento per te 🧘',
        'Una breve pratica può fare la differenza. Trova quella giusta per oggi.',
        jsonb_build_object(
            'type', 'daily_reminder',
            'screen', 'PracticeLibrary'
        ),
        v_now
    FROM "public"."clients" c
    WHERE c.is_active = true
      AND c.deleted_at IS NULL
      AND c.profile_id IS NOT NULL
      -- Ha almeno un token push attivo (solo push per questo tipo)
      AND "public"."client_has_active_push_tokens"(c.id)
      -- Non ha praticato negli ultimi 2 giorni
      AND NOT EXISTS (
          SELECT 1 FROM "public"."practice_user_state" pus
          WHERE pus.client_id = c.id
            AND pus.last_accessed_at > v_now - INTERVAL '2 days'
      )
      -- Non già accodato oggi
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = c.id
            AND nq.category = 'practice_reminder'
            AND nq.scheduled_for::date = v_now::date
      )
      -- Non già inviato oggi
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = c.id
            AND nl.category = 'practice_reminder'
            AND nl.sent_at::date = v_now::date
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object(
        'practice_reminders', v_count,
        'timestamp', v_now
    );
END;
$$;

COMMENT ON FUNCTION "public"."queue_practice_reminder" IS
'Accoda promemoria pratica giornaliero per utenti inattivi da 2+ giorni.';

-- ============================================================================
-- 2. QUEUE PRACTICE RESUME
-- Promemoria per riprendere una pratica iniziata e abbandonata da 3+ giorni
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."queue_practice_resume"()
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count integer := 0;
    v_now timestamp with time zone := NOW();
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT DISTINCT ON (pus.client_id)
        pus.client_id,
        'practice_resume'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(pus.client_id, 'practice_resume'),
            'push'::"public"."notification_channel"
        ),
        'Riprendi da dove eri rimast' || CASE WHEN true THEN 'o' END || ' 📖',
        'Hai una pratica in corso: ' || p.title || '. Continua il tuo percorso!',
        jsonb_build_object(
            'type', 'resume',
            'screen', 'PracticePlayer',
            'practice_id', p.id,
            'practice_title', p.title
        ),
        v_now
    FROM "public"."practice_user_state" pus
    JOIN "public"."practices" p ON pus.practice_id = p.id
    JOIN "public"."clients" c ON pus.client_id = c.id
    WHERE pus.status = 'started'
      AND pus.completed_at IS NULL
      -- Abbandonata da 3+ giorni
      AND pus.last_accessed_at < v_now - INTERVAL '3 days'
      -- Client attivo
      AND c.is_active = true
      AND c.deleted_at IS NULL
      -- Pratica ancora attiva
      AND p.is_active = true
      AND p.deleted_at IS NULL
      -- Ha token push attivi
      AND "public"."client_has_active_push_tokens"(pus.client_id)
      -- Non già accodato questa settimana
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = pus.client_id
            AND nq.category = 'practice_resume'
            AND nq.scheduled_for > v_now - INTERVAL '7 days'
      )
      -- Non già inviato questa settimana
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = pus.client_id
            AND nl.category = 'practice_resume'
            AND nl.sent_at > v_now - INTERVAL '7 days'
      )
    ORDER BY pus.client_id, pus.last_accessed_at DESC;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object(
        'practice_resume', v_count,
        'timestamp', v_now
    );
END;
$$;

COMMENT ON FUNCTION "public"."queue_practice_resume" IS
'Accoda promemoria per riprendere pratiche in corso abbandonate da 3+ giorni. Max 1 per settimana per utente.';

-- ============================================================================
-- 3. QUEUE JOURNAL REMINDER
-- Promemoria settimanale per scrivere nel diario (utenti che non scrivono da 7+ giorni)
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."queue_journal_reminder"()
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count integer := 0;
    v_now timestamp with time zone := NOW();
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        'journal_reminder'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 'journal_reminder'),
            'push'::"public"."notification_channel"
        ),
        'Come stai questa settimana? ✍️',
        'Prenditi un momento per scrivere nel tuo diario. Anche poche parole possono fare la differenza.',
        jsonb_build_object(
            'type', 'weekly_reminder',
            'screen', 'JournalList'
        ),
        v_now
    FROM "public"."clients" c
    WHERE c.is_active = true
      AND c.deleted_at IS NULL
      AND c.profile_id IS NOT NULL
      -- Ha token push attivi
      AND "public"."client_has_active_push_tokens"(c.id)
      -- Ha già usato il diario almeno una volta (non spam a chi non l'ha mai usato)
      AND EXISTS (
          SELECT 1 FROM "public"."journal_entries" je
          WHERE je.client_id = c.id
      )
      -- Non ha scritto negli ultimi 7 giorni
      AND NOT EXISTS (
          SELECT 1 FROM "public"."journal_entries" je
          WHERE je.client_id = c.id
            AND je.created_at > v_now - INTERVAL '7 days'
      )
      -- Non già accodato questa settimana
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = c.id
            AND nq.category = 'journal_reminder'
            AND nq.scheduled_for > v_now - INTERVAL '7 days'
      )
      -- Non già inviato questa settimana
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = c.id
            AND nl.category = 'journal_reminder'
            AND nl.sent_at > v_now - INTERVAL '7 days'
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object(
        'journal_reminders', v_count,
        'timestamp', v_now
    );
END;
$$;

COMMENT ON FUNCTION "public"."queue_journal_reminder" IS
'Accoda promemoria settimanale diario per utenti che non scrivono da 7+ giorni. Solo per chi ha già usato il diario.';

-- ============================================================================
-- CRON WRAPPER FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."cron_queue_practice_reminder"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."queue_practice_reminder"();
END;
$$;

COMMENT ON FUNCTION "public"."cron_queue_practice_reminder" IS
'Wrapper cron: accoda promemoria pratica chiamando direttamente la RPC.';

CREATE OR REPLACE FUNCTION "public"."cron_queue_practice_resume"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."queue_practice_resume"();
END;
$$;

COMMENT ON FUNCTION "public"."cron_queue_practice_resume" IS
'Wrapper cron: accoda promemoria ripresa pratica chiamando direttamente la RPC.';

CREATE OR REPLACE FUNCTION "public"."cron_queue_journal_reminder"()
RETURNS void
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    PERFORM "public"."queue_journal_reminder"();
END;
$$;

COMMENT ON FUNCTION "public"."cron_queue_journal_reminder" IS
'Wrapper cron: accoda promemoria diario chiamando direttamente la RPC.';

-- ============================================================================
-- CRON SCHEDULES (da eseguire manualmente nella SQL console di Supabase)
-- ============================================================================
-- I cron job vanno schedulati manualmente perché pg_cron non supporta
-- la creazione via migrazione in modo affidabile su Supabase hosted.
--
-- Eseguire nella SQL Editor della dashboard Supabase:
--
-- -- Promemoria pratica: ogni giorno alle 10:00 Roma (09:00 UTC estate, 08:00 UTC inverno)
-- SELECT cron.schedule(
--     'notification-queue-practice-reminder',
--     '0 9 * * *',
--     'SELECT public.cron_queue_practice_reminder()'
-- );
--
-- -- Riprendi pratica: ogni giorno alle 18:30 Roma (17:30 UTC estate)
-- SELECT cron.schedule(
--     'notification-queue-practice-resume',
--     '30 17 * * *',
--     'SELECT public.cron_queue_practice_resume()'
-- );
--
-- -- Promemoria diario: ogni lunedì alle 09:00 Roma (08:00 UTC estate)
-- SELECT cron.schedule(
--     'notification-queue-journal-reminder',
--     '0 8 * * 1',
--     'SELECT public.cron_queue_journal_reminder()'
-- );
