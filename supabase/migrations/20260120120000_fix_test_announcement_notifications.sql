-- Migration: Fix Test Announcement Notifications
--
-- Problema: Quando un annuncio ha is_test=true e test_client_id impostato,
-- le notifiche push vengono comunque create per TUTTI i client invece che
-- solo per il client di test.
--
-- Causa: La funzione queue_announcement() non riceve i parametri is_test
-- e test_client_id, quindi non puo' filtrare le notifiche.
--
-- Soluzione:
-- 1. Modificare queue_announcement() per accettare p_is_test e p_test_client_id
-- 2. Modificare notify_new_announcement() per passare questi parametri

-- ============================================================================
-- 1. UPDATE queue_announcement() - aggiungi filtro per test mode
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
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;

COMMENT ON FUNCTION "public"."queue_announcement"("uuid", "text", "text", timestamptz, boolean, "uuid") IS
'Accoda push notification per un nuovo announcement. Se is_test=true, accoda solo al test_client_id.';

-- ============================================================================
-- 2. UPDATE notify_new_announcement() - passa parametri test
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
    -- Se is_test=true, la notifica viene inviata solo al test_client_id
    IF NEW.is_active = true AND (NEW.is_recurring IS NULL OR NEW.is_recurring = false) THEN
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
'Trigger function: accoda push quando viene creato un announcement attivo e NON periodico. Se is_test=true, notifica solo il test_client_id.';

-- ============================================================================
-- 3. UPDATE process_recurring_announcements() - filtra per test mode
-- ============================================================================

CREATE OR REPLACE FUNCTION process_recurring_announcements()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_announcement record;
  v_now timestamptz := now();
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
    -- Queue push notifications
    -- Se is_test=true, accoda SOLO al test_client_id
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
      );

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
  END LOOP;
END;
$$;

COMMENT ON FUNCTION "public"."process_recurring_announcements"() IS
'Cron function: processa annunci periodici. Se is_test=true, notifica solo il test_client_id.';

-- ============================================================================
-- 4. GRANT PERMISSIONS per la nuova signature
-- ============================================================================

GRANT EXECUTE ON FUNCTION "public"."queue_announcement"("uuid", "text", "text", timestamptz, boolean, "uuid") TO "service_role";
