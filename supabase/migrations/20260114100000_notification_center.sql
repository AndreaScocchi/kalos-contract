-- Migration: Notification Center (announcements + read tracking)
--
-- Aggiunge:
-- 1. Tabella announcements per comunicazioni broadcast dallo staff
-- 2. Tabella notification_reads per tracciare stato letto/non letto
-- 3. RPC functions per conteggio e gestione stato lettura

-- ============================================================================
-- 1. CREATE announcements TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."announcements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "image_url" "text",
    "link_url" "text",
    "link_label" "text",
    "category" "text" DEFAULT 'general' NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "starts_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ends_at" timestamp with time zone,
    "created_by" "uuid" REFERENCES "auth"."users"("id"),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."announcements" OWNER TO "postgres";

ALTER TABLE "public"."announcements"
    ADD CONSTRAINT "announcements_pkey" PRIMARY KEY ("id");

-- Indexes
CREATE INDEX "idx_announcements_active"
    ON "public"."announcements" ("is_active", "starts_at" DESC)
    WHERE "is_active" = true;
CREATE INDEX "idx_announcements_dates"
    ON "public"."announcements" ("starts_at", "ends_at");

-- Trigger for updated_at
CREATE TRIGGER "announcements_updated_at"
    BEFORE UPDATE ON "public"."announcements"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."update_updated_at_column"();

-- Enable RLS
ALTER TABLE "public"."announcements" ENABLE ROW LEVEL SECURITY;

-- Policies: All authenticated users can read active announcements
CREATE POLICY "announcements_select_active"
ON "public"."announcements" FOR SELECT TO "authenticated"
USING (
    "is_active" = true
    AND "starts_at" <= NOW()
    AND ("ends_at" IS NULL OR "ends_at" > NOW())
);

-- Staff can manage announcements
CREATE POLICY "announcements_staff_all"
ON "public"."announcements" FOR ALL TO "authenticated"
USING ("public"."is_staff"())
WITH CHECK ("public"."is_staff"());

-- Service role full access
CREATE POLICY "announcements_service_all"
ON "public"."announcements" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- ============================================================================
-- 2. CREATE notification_reads TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."notification_reads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "notification_log_id" "uuid",
    "announcement_id" "uuid",
    "read_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."notification_reads" OWNER TO "postgres";

ALTER TABLE "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_pkey" PRIMARY KEY ("id");

ALTER TABLE "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_client_id_fkey"
    FOREIGN KEY ("client_id")
    REFERENCES "public"."clients"("id")
    ON DELETE CASCADE;

ALTER TABLE "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_notification_log_id_fkey"
    FOREIGN KEY ("notification_log_id")
    REFERENCES "public"."notification_logs"("id")
    ON DELETE CASCADE;

ALTER TABLE "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_announcement_id_fkey"
    FOREIGN KEY ("announcement_id")
    REFERENCES "public"."announcements"("id")
    ON DELETE CASCADE;

-- Ensure exactly one of notification_log_id or announcement_id is set
ALTER TABLE "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_one_source"
    CHECK (
        ("notification_log_id" IS NOT NULL AND "announcement_id" IS NULL) OR
        ("notification_log_id" IS NULL AND "announcement_id" IS NOT NULL)
    );

-- Unique constraints for each type
ALTER TABLE "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_log_unique"
    UNIQUE ("client_id", "notification_log_id");

ALTER TABLE "public"."notification_reads"
    ADD CONSTRAINT "notification_reads_announcement_unique"
    UNIQUE ("client_id", "announcement_id");

-- Indexes
CREATE INDEX "idx_notification_reads_client"
    ON "public"."notification_reads" ("client_id");
CREATE INDEX "idx_notification_reads_log"
    ON "public"."notification_reads" ("notification_log_id")
    WHERE "notification_log_id" IS NOT NULL;
CREATE INDEX "idx_notification_reads_announcement"
    ON "public"."notification_reads" ("announcement_id")
    WHERE "announcement_id" IS NOT NULL;

-- Enable RLS
ALTER TABLE "public"."notification_reads" ENABLE ROW LEVEL SECURITY;

-- Users can manage their own reads
CREATE POLICY "notification_reads_select_own"
ON "public"."notification_reads" FOR SELECT TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "notification_reads_insert_own"
ON "public"."notification_reads" FOR INSERT TO "authenticated"
WITH CHECK ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "notification_reads_delete_own"
ON "public"."notification_reads" FOR DELETE TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"());

-- Service role full access
CREATE POLICY "notification_reads_service_all"
ON "public"."notification_reads" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- ============================================================================
-- 3. RPC FUNCTIONS
-- ============================================================================

-- Get unread count for notification badge
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
    SELECT COUNT(*) INTO v_unread_logs
    FROM "public"."notification_logs" nl
    WHERE nl.client_id = v_client_id
      AND nl.sent_at > NOW() - INTERVAL '30 days'
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

-- Mark a notification as read
CREATE OR REPLACE FUNCTION "public"."mark_notification_read"(
    "p_notification_log_id" "uuid" DEFAULT NULL,
    "p_announcement_id" "uuid" DEFAULT NULL
)
RETURNS boolean
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_client_id uuid;
BEGIN
    v_client_id := "public"."get_my_client_id"();
    IF v_client_id IS NULL THEN
        RETURN false;
    END IF;

    IF p_notification_log_id IS NOT NULL THEN
        INSERT INTO "public"."notification_reads" (client_id, notification_log_id)
        VALUES (v_client_id, p_notification_log_id)
        ON CONFLICT (client_id, notification_log_id) DO NOTHING;
    ELSIF p_announcement_id IS NOT NULL THEN
        INSERT INTO "public"."notification_reads" (client_id, announcement_id)
        VALUES (v_client_id, p_announcement_id)
        ON CONFLICT (client_id, announcement_id) DO NOTHING;
    ELSE
        RETURN false;
    END IF;

    RETURN true;
END;
$$;

-- Mark all notifications as read
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

    -- Mark all unread notification logs
    INSERT INTO "public"."notification_reads" (client_id, notification_log_id)
    SELECT v_client_id, nl.id
    FROM "public"."notification_logs" nl
    WHERE nl.client_id = v_client_id
      AND nl.sent_at > NOW() - INTERVAL '30 days'
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

-- Grant permissions
GRANT EXECUTE ON FUNCTION "public"."get_unread_notifications_count"() TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."mark_notification_read"("uuid", "uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."mark_all_notifications_read"() TO "authenticated";

-- ============================================================================
-- 4. COMMENTS
-- ============================================================================

COMMENT ON TABLE "public"."announcements" IS
'Comunicazioni broadcast dallo staff (promozioni, nuovi corsi, annunci generali).';

COMMENT ON TABLE "public"."notification_reads" IS
'Traccia quali notifiche/annunci sono stati letti da ogni client.';

COMMENT ON COLUMN "public"."announcements"."category" IS
'Categoria annuncio: general, promotion, course, event';

COMMENT ON COLUMN "public"."announcements"."starts_at" IS
'Quando iniziare a mostrare l''annuncio';

COMMENT ON COLUMN "public"."announcements"."ends_at" IS
'Quando smettere di mostrare l''annuncio (opzionale)';

COMMENT ON FUNCTION "public"."get_unread_notifications_count"() IS
'Conta notifiche non lette (logs ultimi 30gg + annunci attivi). Per badge UI.';

COMMENT ON FUNCTION "public"."mark_notification_read"("uuid", "uuid") IS
'Segna una singola notifica come letta.';

COMMENT ON FUNCTION "public"."mark_all_notifications_read"() IS
'Segna tutte le notifiche come lette. Ritorna il numero segnate.';
