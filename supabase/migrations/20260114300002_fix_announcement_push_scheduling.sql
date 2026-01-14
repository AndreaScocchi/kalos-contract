-- Migration: Fix Announcement Push Scheduling
--
-- Problema: Gli annunci con starts_at futura non ricevevano push notification
-- perché il trigger controllava starts_at <= NOW().
--
-- Soluzione:
-- 1. Rimuovere il controllo starts_at dal trigger
-- 2. Usare starts_at come scheduled_for nella coda (invece di NOW())
-- Così il push viene accodato subito ma processato quando l'annuncio diventa visibile.

-- ============================================================================
-- 1. UPDATE queue_announcement() - usa starts_at come scheduled_for
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."queue_announcement"(
    "p_announcement_id" "uuid",
    "p_title" "text",
    "p_body" "text",
    "p_scheduled_for" timestamptz DEFAULT NOW()
)
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count integer := 0;
BEGIN
    -- Accoda push SOLO ai clienti con token push attivo
    -- Nessun fallback email per gli announcements
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
      AND "public"."client_has_active_push_tokens"(c.id);

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;

COMMENT ON FUNCTION "public"."queue_announcement"("uuid", "text", "text", timestamptz) IS
'Accoda push notification per un nuovo announcement a tutti i clienti con token attivo. scheduled_for determina quando viene inviato.';

-- ============================================================================
-- 2. UPDATE notify_new_announcement() - rimuovi controllo starts_at
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."notify_new_announcement"()
RETURNS trigger
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Invia push solo se l'announcement è attivo
    -- scheduled_for = starts_at, così il push parte quando l'annuncio diventa visibile
    IF NEW.is_active = true THEN
        PERFORM "public"."queue_announcement"(
            NEW.id,
            NEW.title,
            NEW.body,
            NEW.starts_at
        );
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION "public"."notify_new_announcement"() IS
'Trigger function: accoda push quando viene creato un announcement attivo. Il push viene schedulato per starts_at.';

-- ============================================================================
-- 3. GRANT PERMISSIONS per la nuova signature
-- ============================================================================

GRANT EXECUTE ON FUNCTION "public"."queue_announcement"("uuid", "text", "text", timestamptz) TO "service_role";
