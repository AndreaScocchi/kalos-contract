-- Migration: Add test_client_id to announcements
--
-- Allows filtering test announcements to show only to the specific test client.
-- Previously, announcements with is_test=true were still visible to all users.

-- Add test_client_id column
ALTER TABLE "public"."announcements"
ADD COLUMN IF NOT EXISTS "test_client_id" uuid REFERENCES "public"."clients"("id") ON DELETE SET NULL;

-- Add index for filtering
CREATE INDEX IF NOT EXISTS "idx_announcements_test_client"
ON "public"."announcements" ("test_client_id")
WHERE "test_client_id" IS NOT NULL;

-- Add comment
COMMENT ON COLUMN "public"."announcements"."test_client_id" IS
'Se non NULL, l''annuncio è visibile solo a questo client (test mode da marketing campaigns)';

-- ============================================================================
-- Update RPC functions to filter test announcements
-- ============================================================================

-- Update get_unread_notifications_count to exclude test announcements for other users
CREATE OR REPLACE FUNCTION "public"."get_unread_notifications_count"()
RETURNS integer
LANGUAGE "plpgsql"
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_client_id uuid;
    v_unread_logs integer;
    v_unread_announcements integer;
BEGIN
    v_client_id := "public"."get_my_client_id"();
    IF v_client_id IS NULL THEN
        RETURN 0;
    END IF;

    -- Count unread notification logs (last 30 days)
    -- Exclude announcement category logs (they are shown from announcements table)
    SELECT COUNT(*) INTO v_unread_logs
    FROM "public"."notification_logs" nl
    WHERE nl.client_id = v_client_id
      AND nl.sent_at > NOW() - INTERVAL '30 days'
      AND nl.category != 'announcement'
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_reads" nr
          WHERE nr.notification_log_id = nl.id
            AND nr.client_id = v_client_id
      );

    -- Count unread active announcements
    -- IMPORTANT: Filter test announcements - show only non-test OR test for this specific client
    SELECT COUNT(*) INTO v_unread_announcements
    FROM "public"."announcements" a
    WHERE a.is_active = true
      AND a.starts_at <= NOW()
      AND (a.ends_at IS NULL OR a.ends_at > NOW())
      AND (a.is_test = false OR a.test_client_id = v_client_id)
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_reads" nr
          WHERE nr.announcement_id = a.id
            AND nr.client_id = v_client_id
      );

    RETURN v_unread_logs + v_unread_announcements;
END;
$$;

-- Update mark_all_notifications_read to only mark visible announcements
CREATE OR REPLACE FUNCTION "public"."mark_all_notifications_read"()
RETURNS integer
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_client_id uuid;
    v_count integer := 0;
    v_temp integer;
BEGIN
    v_client_id := "public"."get_my_client_id"();
    IF v_client_id IS NULL THEN
        RETURN 0;
    END IF;

    -- Mark all unread notification logs (excluding announcement category)
    INSERT INTO "public"."notification_reads" (client_id, notification_log_id)
    SELECT v_client_id, nl.id
    FROM "public"."notification_logs" nl
    WHERE nl.client_id = v_client_id
      AND nl.sent_at > NOW() - INTERVAL '30 days'
      AND nl.category != 'announcement'
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_reads" nr
          WHERE nr.notification_log_id = nl.id
            AND nr.client_id = v_client_id
      )
    ON CONFLICT (client_id, notification_log_id) DO NOTHING;

    GET DIAGNOSTICS v_temp = ROW_COUNT;
    v_count := v_count + v_temp;

    -- Mark all unread announcements (only those visible to this client)
    INSERT INTO "public"."notification_reads" (client_id, announcement_id)
    SELECT v_client_id, a.id
    FROM "public"."announcements" a
    WHERE a.is_active = true
      AND a.starts_at <= NOW()
      AND (a.ends_at IS NULL OR a.ends_at > NOW())
      AND (a.is_test = false OR a.test_client_id = v_client_id)
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_reads" nr
          WHERE nr.announcement_id = a.id
            AND nr.client_id = v_client_id
      )
    ON CONFLICT (client_id, announcement_id) DO NOTHING;

    GET DIAGNOSTICS v_temp = ROW_COUNT;
    v_count := v_count + v_temp;

    RETURN v_count;
END;
$$;
