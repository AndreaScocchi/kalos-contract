-- Migration: Event Notification Manual Control
--
-- Problema: Il trigger events_notify_new invia automaticamente notifiche a TUTTI i clienti
-- ogni volta che un evento viene creato con is_active=true. Questo può superare il limite
-- giornaliero di email (es. 201 email per un singolo evento con 201 clienti attivi).
--
-- Soluzione: Rimuovere il trigger automatico e rendere l'invio controllabile dal gestionale
-- tramite checkbox separati per push e email. La funzione queue_new_event() ora accetta
-- parametri p_send_push e p_send_email per controllare i canali di notifica.

-- ============================================================================
-- 1. RIMUOVI IL TRIGGER AUTOMATICO
-- ============================================================================

DROP TRIGGER IF EXISTS "events_notify_new" ON "public"."events";
DROP FUNCTION IF EXISTS "public"."notify_new_event"();

-- ============================================================================
-- 2. AGGIORNA queue_new_event() CON CONTROLLO CANALI
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."queue_new_event"(
    "p_event_id" "uuid",
    "p_event_name" "text",
    "p_event_date" timestamp with time zone,
    "p_send_push" boolean DEFAULT true,
    "p_send_email" boolean DEFAULT false
)
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_push_count integer := 0;
    v_email_count integer := 0;
    v_title text;
    v_body text;
    v_data jsonb;
BEGIN
    -- Se nessun canale selezionato, non fare nulla
    IF NOT p_send_push AND NOT p_send_email THEN
        RETURN json_build_object('queued_push', 0, 'queued_email', 0);
    END IF;

    v_title := 'Nuovo evento: ' || p_event_name;
    v_body := TO_CHAR(p_event_date AT TIME ZONE 'Europe/Rome', 'DD/MM alle HH24:MI') ||
              ' - I posti sono limitati, iscriviti ora!';
    v_data := jsonb_build_object(
        'event_id', p_event_id,
        'event_name', p_event_name,
        'event_date', p_event_date
    );

    -- Accoda notifiche PUSH (solo per clienti con token attivi)
    IF p_send_push THEN
        INSERT INTO "public"."notification_queue" (
            client_id, category, channel, title, body, data, scheduled_for
        )
        SELECT
            c.id,
            'new_event'::"public"."notification_category",
            'push'::"public"."notification_channel",
            v_title,
            v_body,
            v_data,
            NOW()
        FROM "public"."clients" c
        WHERE c.deleted_at IS NULL
          AND c.is_active = true
          AND "public"."client_has_active_push_tokens"(c.id)
          -- Deduplicazione: escludi client che hanno già una notifica push con stesso titolo
          AND NOT EXISTS (
              SELECT 1 FROM "public"."notification_queue" nq
              WHERE nq.client_id = c.id
                AND nq.category = 'new_event'
                AND nq.channel = 'push'
                AND nq.title = v_title
                AND nq.created_at > NOW() - INTERVAL '60 seconds'
          );

        GET DIAGNOSTICS v_push_count = ROW_COUNT;
    END IF;

    -- Accoda notifiche EMAIL (solo per clienti con email)
    IF p_send_email THEN
        INSERT INTO "public"."notification_queue" (
            client_id, category, channel, title, body, data, scheduled_for
        )
        SELECT
            c.id,
            'new_event'::"public"."notification_category",
            'email'::"public"."notification_channel",
            v_title,
            v_body,
            v_data,
            NOW()
        FROM "public"."clients" c
        WHERE c.deleted_at IS NULL
          AND c.is_active = true
          AND c.email IS NOT NULL
          AND c.email != ''
          AND COALESCE(c.email_bounced, false) = false
          -- Deduplicazione: escludi client che hanno già una notifica email con stesso titolo
          AND NOT EXISTS (
              SELECT 1 FROM "public"."notification_queue" nq
              WHERE nq.client_id = c.id
                AND nq.category = 'new_event'
                AND nq.channel = 'email'
                AND nq.title = v_title
                AND nq.created_at > NOW() - INTERVAL '60 seconds'
          );

        GET DIAGNOSTICS v_email_count = ROW_COUNT;
    END IF;

    RETURN json_build_object('queued_push', v_push_count, 'queued_email', v_email_count);
END;
$$;

COMMENT ON FUNCTION "public"."queue_new_event"("uuid", "text", timestamptz, boolean, boolean) IS
'Accoda notifiche nuovo evento ai clienti attivi. Canali controllabili via p_send_push e p_send_email. Deduplicazione per titolo + canale + finestra 60s.';
