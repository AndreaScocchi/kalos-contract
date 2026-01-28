-- Migration: Fix Announcement Duplicate Notifications
--
-- Problema: Le notifiche per gli announcement vengono create multiple volte:
-- 1. execute-scheduled-campaigns inserisce un announcement E accoda notifiche
-- 2. Il trigger notify_new_announcement() accoda ALTRE notifiche (duplicati)
-- 3. process_recurring_announcements() non controlla se notifiche esistono già
--
-- Soluzione:
-- 1. Il trigger NON accoda se l'announcement viene da una marketing campaign
-- 2. Aggiungi deduplicazione in queue_announcement()
-- 3. Aggiungi deduplicazione in process_recurring_announcements()

-- ============================================================================
-- 1. UPDATE notify_new_announcement() - skip se viene da marketing campaign
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."notify_new_announcement"()
RETURNS trigger
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Invia push solo se:
    -- 1. L'announcement e' attivo
    -- 2. NON e' un annuncio periodico (quelli vengono gestiti dal cron)
    -- 3. NON viene da una marketing campaign (quella accoda già le notifiche)
    -- Se is_test=true, la notifica viene inviata solo al test_client_id
    IF NEW.is_active = true
       AND (NEW.is_recurring IS NULL OR NEW.is_recurring = false)
       AND NEW.marketing_campaign_id IS NULL  -- <-- NUOVO: skip se da campaign
    THEN
        PERFORM "public"."queue_announcement"(
            NEW.id,
            NEW.title,
            NEW.body,
            NEW.starts_at,
            COALESCE(NEW.is_test, false),
            NEW.test_client_id
        );
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION "public"."notify_new_announcement"() IS
'Trigger function: accoda push quando viene creato un announcement attivo, NON periodico e NON da marketing campaign. Se is_test=true, notifica solo il test_client_id.';

-- ============================================================================
-- 2. UPDATE queue_announcement() - aggiungi deduplicazione
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."queue_announcement"(
    "p_announcement_id" "uuid",
    "p_title" "text",
    "p_body" "text",
    "p_scheduled_for" timestamptz DEFAULT NOW(),
    "p_is_test" boolean DEFAULT false,
    "p_test_client_id" "uuid" DEFAULT NULL
)
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count integer := 0;
BEGIN
    -- Accoda push ai clienti con token push attivo
    -- Se is_test=true, accoda SOLO al test_client_id
    -- DEDUPLICAZIONE: non creare se esiste già una notifica per questo announcement+client
    INSERT INTO "public"."notification_queue" (
        client_id,
        category,
        channel,
        title,
        body,
        data,
        scheduled_for
    )
    SELECT
        c.id,
        'announcement'::"public"."notification_category",
        'push'::"public"."notification_channel",
        p_title,
        p_body,
        jsonb_build_object('announcement_id', p_announcement_id),
        p_scheduled_for
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      AND "public"."client_has_active_push_tokens"(c.id)
      -- Filtro test: se is_test=true, solo il test_client_id
      AND (
          p_is_test = false
          OR (p_is_test = true AND c.id = p_test_client_id)
      )
      -- DEDUPLICAZIONE: escludi client che hanno già una notifica per questo announcement
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = c.id
            AND nq.category = 'announcement'
            AND nq.data->>'announcement_id' = p_announcement_id::text
            AND nq.status IN ('pending', 'sent')
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;

COMMENT ON FUNCTION "public"."queue_announcement"("uuid", "text", "text", timestamptz, boolean, "uuid") IS
'Accoda push notification per un nuovo announcement. Se is_test=true, accoda solo al test_client_id. Include deduplicazione per evitare notifiche duplicate.';

-- ============================================================================
-- 3. UPDATE process_recurring_announcements() - aggiungi deduplicazione
-- ============================================================================

CREATE OR REPLACE FUNCTION process_recurring_announcements()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_announcement record;
  v_now timestamptz := now();
  v_queued integer;
BEGIN
  -- Find recurring announcements that are due
  FOR v_announcement IN
    SELECT *
    FROM announcements
    WHERE is_recurring = true
      AND is_active = true
      AND deleted_at IS NULL
      AND next_occurrence_at IS NOT NULL
      AND next_occurrence_at <= v_now
      AND (ends_at IS NULL OR ends_at > v_now)
  LOOP
    -- Queue push notifications for all clients with active tokens
    -- DEDUPLICAZIONE: non creare se esiste già una notifica pending/sent
    -- per questo announcement nelle ultime 24 ore (per evitare spam)
    INSERT INTO notification_queue (
      client_id,
      category,
      channel,
      title,
      body,
      data,
      scheduled_for,
      status
    )
    SELECT
      c.id,
      'announcement',
      'push',
      v_announcement.title,
      v_announcement.body,
      jsonb_build_object(
        'announcementId', v_announcement.id,
        'category', v_announcement.category,
        'imageUrl', v_announcement.image_url,
        'linkUrl', v_announcement.link_url,
        'linkLabel', v_announcement.link_label
      ),
      v_now,
      'pending'
    FROM clients c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      AND EXISTS (
        SELECT 1 FROM device_tokens dt
        WHERE dt.client_id = c.id
          AND dt.is_active = true
      )
      -- Filtro test: se is_test=true, solo il test_client_id
      AND (
          COALESCE(v_announcement.is_test, false) = false
          OR (v_announcement.is_test = true AND c.id = v_announcement.test_client_id)
      )
      -- DEDUPLICAZIONE: non creare se esiste già una notifica per questo
      -- announcement+client nelle ultime 24 ore (evita spam da cron)
      AND NOT EXISTS (
          SELECT 1 FROM notification_queue nq
          WHERE nq.client_id = c.id
            AND nq.category = 'announcement'
            AND (nq.data->>'announcementId' = v_announcement.id::text
                 OR nq.data->>'announcement_id' = v_announcement.id::text)
            AND nq.created_at > v_now - interval '24 hours'
      );

    GET DIAGNOSTICS v_queued = ROW_COUNT;

    -- Solo se abbiamo accodato almeno una notifica, aggiorna last_sent_at
    -- Questo evita di marcare come "inviato" un announcement che non ha prodotto notifiche
    IF v_queued > 0 THEN
      -- Update the announcement's last_sent_at and calculate next occurrence
      UPDATE announcements
      SET
        last_sent_at = v_now,
        next_occurrence_at = calculate_next_announcement_occurrence(
          recurrence_frequency,
          recurrence_day_of_week,
          recurrence_day_of_month,
          recurrence_time,
          v_now + interval '1 minute' -- Add 1 minute to avoid immediate re-trigger
        )
      WHERE id = v_announcement.id;
    ELSE
      -- Nessuna notifica creata (tutti i client hanno già ricevuto)
      -- Aggiorna solo next_occurrence_at per evitare loop infinito
      UPDATE announcements
      SET
        next_occurrence_at = calculate_next_announcement_occurrence(
          recurrence_frequency,
          recurrence_day_of_week,
          recurrence_day_of_month,
          recurrence_time,
          v_now + interval '1 minute'
        )
      WHERE id = v_announcement.id;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION "public"."process_recurring_announcements"() IS
'Cron function: processa annunci periodici. Se is_test=true, notifica solo il test_client_id. Include deduplicazione per evitare spam (max 1 notifica per announcement/client ogni 24h).';
