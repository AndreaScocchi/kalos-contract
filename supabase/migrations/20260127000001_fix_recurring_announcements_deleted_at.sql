-- Migration: Fix process_recurring_announcements - remove deleted_at reference
--
-- Problema: La funzione process_recurring_announcements() usa deleted_at
-- ma la tabella announcements non ha questa colonna.
--
-- Soluzione: Rimuovi il check deleted_at IS NULL dalla query.

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
  -- NOTA: announcements non ha deleted_at, usa is_active per il soft delete
  FOR v_announcement IN
    SELECT *
    FROM announcements
    WHERE is_recurring = true
      AND is_active = true
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
    IF v_queued > 0 THEN
      UPDATE announcements
      SET
        last_sent_at = v_now,
        next_occurrence_at = calculate_next_announcement_occurrence(
          recurrence_frequency,
          recurrence_day_of_week,
          recurrence_day_of_month,
          recurrence_time,
          v_now + interval '1 minute'
        )
      WHERE id = v_announcement.id;
    ELSE
      -- Nessuna notifica creata, aggiorna solo next_occurrence_at
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
'Cron function: processa annunci periodici. Include deduplicazione (max 1 notifica per announcement/client ogni 24h).';
