-- Migration: Push Notifications for Announcements
--
-- Aggiunge:
-- 1. Categoria 'announcement' all'enum notification_category
-- 2. Funzione queue_announcement() per accodare push a tutti i clienti con token attivo
-- 3. Trigger su INSERT announcements per inviare push automaticamente

-- ============================================================================
-- 1. ADD 'announcement' TO notification_category ENUM
-- ============================================================================

ALTER TYPE "public"."notification_category" ADD VALUE IF NOT EXISTS 'announcement';

-- ============================================================================
-- 2. CREATE queue_announcement() FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."queue_announcement"(
    "p_announcement_id" "uuid",
    "p_title" "text",
    "p_body" "text"
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
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      AND "public"."client_has_active_push_tokens"(c.id);

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;

COMMENT ON FUNCTION "public"."queue_announcement"("uuid", "text", "text") IS
'Accoda push notification per un nuovo announcement a tutti i clienti con token attivo.';

-- ============================================================================
-- 3. CREATE TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."notify_new_announcement"()
RETURNS trigger
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Invia push solo se:
    -- 1. L'announcement è attivo
    -- 2. La data di inizio è ora o nel passato (visibile immediatamente)
    IF NEW.is_active = true AND NEW.starts_at <= NOW() THEN
        PERFORM "public"."queue_announcement"(
            NEW.id,
            NEW.title,
            NEW.body
        );
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION "public"."notify_new_announcement"() IS
'Trigger function: accoda push quando viene creato un announcement attivo e visibile.';

-- ============================================================================
-- 4. CREATE TRIGGER ON announcements TABLE
-- ============================================================================

CREATE TRIGGER "announcements_notify_insert"
    AFTER INSERT ON "public"."announcements"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."notify_new_announcement"();

COMMENT ON TRIGGER "announcements_notify_insert" ON "public"."announcements" IS
'Invia push notification automatica quando viene creato un nuovo announcement attivo.';

-- ============================================================================
-- 5. GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION "public"."queue_announcement"("uuid", "text", "text") TO "service_role";
