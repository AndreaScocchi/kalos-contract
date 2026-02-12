-- Migration: Fix Event Duplicate Notifications
--
-- Problema: Le notifiche per i nuovi eventi vengono create multiple volte quando
-- l'utente crea un evento con più date/orari. Il form crea un evento separato per
-- ogni slot temporale, e ogni INSERT triggera una notifica. Il risultato è che
-- i clienti ricevono N notifiche identiche per lo stesso "evento logico".
--
-- Soluzione: Deduplicare basandosi sul TITOLO della notifica (che contiene il nome
-- dell'evento) invece che sull'event_id. Se esiste già una notifica con lo stesso
-- titolo creata negli ultimi 60 secondi, non accodare.

-- ============================================================================
-- UPDATE queue_new_event() - deduplicazione per titolo + finestra temporale
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."queue_new_event"(
    "p_event_id" "uuid",
    "p_event_name" "text",
    "p_event_date" timestamp with time zone
)
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count integer := 0;
    v_title text;
BEGIN
    -- Costruisci il titolo che verrà usato per la deduplicazione
    v_title := 'Nuovo evento: ' || p_event_name;

    -- Accoda notifica nuovo evento a tutti i clienti attivi
    -- DEDUPLICAZIONE: non creare se esiste già una notifica con lo stesso TITOLO
    -- creata negli ultimi 60 secondi (per gestire creazione batch di eventi)
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        'new_event'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 'new_event'),
            'email'::"public"."notification_channel"
        ),
        v_title,
        TO_CHAR(p_event_date AT TIME ZONE 'Europe/Rome', 'DD/MM alle HH24:MI') ||
            ' - I posti sono limitati, iscriviti ora!',
        jsonb_build_object(
            'event_id', p_event_id,
            'event_name', p_event_name,
            'event_date', p_event_date
        ),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      -- DEDUPLICAZIONE: escludi client che hanno già una notifica con stesso titolo
      -- creata negli ultimi 60 secondi (batch creation window)
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = c.id
            AND nq.category = 'new_event'
            AND nq.title = v_title
            AND nq.created_at > NOW() - INTERVAL '60 seconds'
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;

COMMENT ON FUNCTION "public"."queue_new_event"("uuid", "text", timestamptz) IS
'Accoda notifica nuovo evento a tutti i clienti attivi. Deduplicazione per titolo + finestra 60s per evitare spam quando si creano eventi con più date/orari.';
