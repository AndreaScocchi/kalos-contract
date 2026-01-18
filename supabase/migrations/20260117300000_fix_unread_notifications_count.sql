-- Migration: Fix unread notifications count
--
-- La funzione get_unread_notifications_count conta anche le notifiche con
-- category='announcement' nella tabella notification_logs, ma la lista UI
-- le esclude (perché gli annunci vengono mostrati dalla tabella announcements).
-- Questo causa una discrepanza tra badge e lista.
--
-- Fix: Escludere le notifiche con category='announcement' dal conteggio dei logs.

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
    -- Exclude category='announcement' as those are shown from the announcements table
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
    SELECT COUNT(*) INTO v_unread_announcements
    FROM "public"."announcements" a
    WHERE a.is_active = true
      AND a.starts_at <= NOW()
      AND (a.ends_at IS NULL OR a.ends_at > NOW())
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_reads" nr
          WHERE nr.announcement_id = a.id
            AND nr.client_id = v_client_id
      );

    RETURN v_unread_logs + v_unread_announcements;
END;
$$;

-- Also fix mark_all_notifications_read to exclude announcement category
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

    -- Mark all unread notification logs (exclude announcement category)
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

    -- Mark all unread announcements
    INSERT INTO "public"."notification_reads" (client_id, announcement_id)
    SELECT v_client_id, a.id
    FROM "public"."announcements" a
    WHERE a.is_active = true
      AND a.starts_at <= NOW()
      AND (a.ends_at IS NULL OR a.ends_at > NOW())
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

COMMENT ON FUNCTION "public"."get_unread_notifications_count"() IS
'Conta notifiche non lette (logs ultimi 30gg esclusi announcement + annunci attivi). Per badge UI.';
