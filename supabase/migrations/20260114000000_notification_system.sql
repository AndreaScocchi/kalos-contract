-- Migration: Create notification system tables
--
-- Obiettivo: Sistema completo di notifiche push + email fallback
-- con preferenze utente, coda di invio e tracking.

-- ============================================================================
-- 1. CREATE ENUMS
-- ============================================================================

CREATE TYPE "public"."notification_category" AS ENUM (
    'lesson_reminder',        -- Promemoria lezione
    'subscription_expiry',    -- Scadenza abbonamento
    'entries_low',            -- Ingressi quasi esauriti
    're_engagement',          -- Re-engagement (torna a trovarci)
    'first_lesson',           -- Prima lezione completata
    'milestone',              -- Traguardi (10, 25, 50, 100 lezioni)
    'birthday',               -- Compleanno
    'new_event'               -- Nuovo evento pubblicato
);
ALTER TYPE "public"."notification_category" OWNER TO "postgres";

CREATE TYPE "public"."notification_channel" AS ENUM (
    'push',
    'email'
);
ALTER TYPE "public"."notification_channel" OWNER TO "postgres";

CREATE TYPE "public"."notification_status" AS ENUM (
    'pending',
    'sent',
    'delivered',
    'failed',
    'skipped'
);
ALTER TYPE "public"."notification_status" OWNER TO "postgres";

-- ============================================================================
-- 2. ADD BIRTHDAY TO CLIENTS TABLE
-- ============================================================================

ALTER TABLE "public"."clients" ADD COLUMN IF NOT EXISTS "birthday" DATE;

COMMENT ON COLUMN "public"."clients"."birthday" IS
'Data di nascita del cliente per invio auguri di compleanno';

-- ============================================================================
-- 3. CREATE device_tokens TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."device_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "expo_push_token" "text" NOT NULL,
    "device_id" "text",
    "platform" "text",
    "app_version" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_used_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."device_tokens" OWNER TO "postgres";

ALTER TABLE "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_pkey" PRIMARY KEY ("id");

ALTER TABLE "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_expo_push_token_unique" UNIQUE ("expo_push_token");

ALTER TABLE "public"."device_tokens"
    ADD CONSTRAINT "device_tokens_client_id_fkey"
    FOREIGN KEY ("client_id")
    REFERENCES "public"."clients"("id")
    ON DELETE CASCADE;

-- Indexes
CREATE INDEX "idx_device_tokens_client_id" ON "public"."device_tokens" ("client_id");
CREATE INDEX "idx_device_tokens_is_active" ON "public"."device_tokens" ("is_active") WHERE "is_active" = true;

-- ============================================================================
-- 4. CREATE notification_preferences TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."notification_preferences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "category" "public"."notification_category" NOT NULL,
    "push_enabled" boolean DEFAULT true NOT NULL,
    "email_enabled" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."notification_preferences" OWNER TO "postgres";

ALTER TABLE "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_pkey" PRIMARY KEY ("id");

ALTER TABLE "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_client_category_unique"
    UNIQUE ("client_id", "category");

ALTER TABLE "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_client_id_fkey"
    FOREIGN KEY ("client_id")
    REFERENCES "public"."clients"("id")
    ON DELETE CASCADE;

-- Index
CREATE INDEX "idx_notification_preferences_client_id" ON "public"."notification_preferences" ("client_id");

-- ============================================================================
-- 5. CREATE notification_queue TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."notification_queue" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "category" "public"."notification_category" NOT NULL,
    "channel" "public"."notification_channel" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "data" "jsonb" DEFAULT '{}'::"jsonb",
    "scheduled_for" timestamp with time zone NOT NULL,
    "status" "public"."notification_status" DEFAULT 'pending'::"public"."notification_status" NOT NULL,
    "attempts" integer DEFAULT 0 NOT NULL,
    "last_attempt_at" timestamp with time zone,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone
);
ALTER TABLE "public"."notification_queue" OWNER TO "postgres";

ALTER TABLE "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_pkey" PRIMARY KEY ("id");

ALTER TABLE "public"."notification_queue"
    ADD CONSTRAINT "notification_queue_client_id_fkey"
    FOREIGN KEY ("client_id")
    REFERENCES "public"."clients"("id")
    ON DELETE CASCADE;

-- Indexes for efficient queue processing
CREATE INDEX "idx_notification_queue_pending"
    ON "public"."notification_queue" ("scheduled_for", "status")
    WHERE "status" = 'pending';
CREATE INDEX "idx_notification_queue_client_id" ON "public"."notification_queue" ("client_id");
CREATE INDEX "idx_notification_queue_category" ON "public"."notification_queue" ("category");

-- ============================================================================
-- 6. CREATE notification_logs TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."notification_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "category" "public"."notification_category" NOT NULL,
    "channel" "public"."notification_channel" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text",
    "data" "jsonb" DEFAULT '{}'::"jsonb",
    "expo_receipt_id" "text",
    "resend_id" "text",
    "status" "public"."notification_status" DEFAULT 'sent'::"public"."notification_status" NOT NULL,
    "sent_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "delivered_at" timestamp with time zone,
    "error_message" "text"
);
ALTER TABLE "public"."notification_logs" OWNER TO "postgres";

ALTER TABLE "public"."notification_logs"
    ADD CONSTRAINT "notification_logs_pkey" PRIMARY KEY ("id");

ALTER TABLE "public"."notification_logs"
    ADD CONSTRAINT "notification_logs_client_id_fkey"
    FOREIGN KEY ("client_id")
    REFERENCES "public"."clients"("id")
    ON DELETE CASCADE;

-- Indexes
CREATE INDEX "idx_notification_logs_client_id" ON "public"."notification_logs" ("client_id");
CREATE INDEX "idx_notification_logs_category" ON "public"."notification_logs" ("category");
CREATE INDEX "idx_notification_logs_sent_at" ON "public"."notification_logs" ("sent_at" DESC);
CREATE INDEX "idx_notification_logs_client_category_sent"
    ON "public"."notification_logs" ("client_id", "category", "sent_at" DESC);

-- ============================================================================
-- 7. TRIGGERS FOR updated_at
-- ============================================================================

CREATE TRIGGER "device_tokens_updated_at"
    BEFORE UPDATE ON "public"."device_tokens"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."update_updated_at_column"();

CREATE TRIGGER "notification_preferences_updated_at"
    BEFORE UPDATE ON "public"."notification_preferences"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ============================================================================
-- 8. ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE "public"."device_tokens" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."notification_preferences" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."notification_queue" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."notification_logs" ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 9. RLS POLICIES
-- ============================================================================

-- device_tokens: Users can manage their own tokens
CREATE POLICY "device_tokens_select_own"
ON "public"."device_tokens" FOR SELECT TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "device_tokens_insert_own"
ON "public"."device_tokens" FOR INSERT TO "authenticated"
WITH CHECK ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "device_tokens_update_own"
ON "public"."device_tokens" FOR UPDATE TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"())
WITH CHECK ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "device_tokens_delete_own"
ON "public"."device_tokens" FOR DELETE TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"());

-- device_tokens: Service role full access
CREATE POLICY "device_tokens_service_all"
ON "public"."device_tokens" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- notification_preferences: Users can manage their own preferences
CREATE POLICY "notification_preferences_select_own"
ON "public"."notification_preferences" FOR SELECT TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "notification_preferences_insert_own"
ON "public"."notification_preferences" FOR INSERT TO "authenticated"
WITH CHECK ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "notification_preferences_update_own"
ON "public"."notification_preferences" FOR UPDATE TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"())
WITH CHECK ("client_id" = "public"."get_my_client_id"());

-- notification_preferences: Service role full access
CREATE POLICY "notification_preferences_service_all"
ON "public"."notification_preferences" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- notification_queue: Only service role can access
CREATE POLICY "notification_queue_service_all"
ON "public"."notification_queue" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- notification_logs: Users can see their own logs, staff can see all
CREATE POLICY "notification_logs_select_own"
ON "public"."notification_logs" FOR SELECT TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "notification_logs_select_staff"
ON "public"."notification_logs" FOR SELECT TO "authenticated"
USING ("public"."is_staff"());

-- notification_logs: Service role full access
CREATE POLICY "notification_logs_service_all"
ON "public"."notification_logs" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- ============================================================================
-- 10. HELPER FUNCTIONS
-- ============================================================================

-- Check if client has active push tokens
CREATE OR REPLACE FUNCTION "public"."client_has_active_push_tokens"("p_client_id" "uuid")
RETURNS boolean
LANGUAGE "plpgsql"
SECURITY DEFINER
STABLE
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM "public"."device_tokens"
        WHERE "client_id" = p_client_id AND "is_active" = true
    );
END;
$$;

-- Get client's preferred notification channel for a category
CREATE OR REPLACE FUNCTION "public"."get_notification_channel"(
    "p_client_id" "uuid",
    "p_category" "public"."notification_category"
)
RETURNS "public"."notification_channel"
LANGUAGE "plpgsql"
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_pref RECORD;
    v_has_push boolean;
BEGIN
    -- Get preferences
    SELECT push_enabled, email_enabled INTO v_pref
    FROM "public"."notification_preferences"
    WHERE client_id = p_client_id AND category = p_category;

    -- Default to all enabled if no preference set
    IF NOT FOUND THEN
        v_pref.push_enabled := true;
        v_pref.email_enabled := true;
    END IF;

    -- Check if user has active push tokens
    v_has_push := "public"."client_has_active_push_tokens"(p_client_id);

    -- Prefer push if enabled and available
    IF v_pref.push_enabled AND v_has_push THEN
        RETURN 'push'::"public"."notification_channel";
    ELSIF v_pref.email_enabled THEN
        RETURN 'email'::"public"."notification_channel";
    ELSE
        -- Both disabled, return null (will skip notification)
        RETURN NULL;
    END IF;
END;
$$;

-- Check if re-engagement notification can be sent
-- p_days: 4 for first reminder (push only), 7 for second reminder (push+email)
CREATE OR REPLACE FUNCTION "public"."can_send_re_engagement"(
    "p_client_id" "uuid",
    "p_days" integer DEFAULT 7
)
RETURNS boolean
LANGUAGE "plpgsql"
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_last_re_engagement timestamp with time zone;
    v_has_upcoming_booking boolean;
    v_days_since_last_booking integer;
BEGIN
    -- Check if this specific re-engagement (4d or 7d) was already sent
    SELECT sent_at INTO v_last_re_engagement
    FROM "public"."notification_logs"
    WHERE client_id = p_client_id
      AND category = 're_engagement'
      AND (data->>'days')::int = p_days
      AND sent_at > NOW() - INTERVAL '30 days'
    ORDER BY sent_at DESC
    LIMIT 1;

    IF v_last_re_engagement IS NOT NULL THEN
        RETURN false; -- Already sent this type recently
    END IF;

    -- Check if user has upcoming booking (don't send if they're already coming)
    SELECT EXISTS (
        SELECT 1 FROM "public"."bookings" b
        JOIN "public"."lessons" l ON b.lesson_id = l.id
        WHERE b.client_id = p_client_id
          AND b.status = 'booked'
          AND l.starts_at > NOW()
    ) INTO v_has_upcoming_booking;

    IF v_has_upcoming_booking THEN
        RETURN false; -- Has upcoming booking, no need to re-engage
    END IF;

    -- Check days since last booking
    SELECT EXTRACT(DAY FROM NOW() - MAX(l.starts_at))::integer
    INTO v_days_since_last_booking
    FROM "public"."bookings" b
    JOIN "public"."lessons" l ON b.lesson_id = l.id
    WHERE b.client_id = p_client_id
      AND b.status IN ('booked', 'attended')
      AND l.starts_at < NOW();

    -- Can send if days since last booking matches the threshold
    RETURN v_days_since_last_booking IS NOT NULL AND v_days_since_last_booking >= p_days;
END;
$$;

-- Count total attended lessons for a client (for milestones)
CREATE OR REPLACE FUNCTION "public"."count_attended_lessons"("p_client_id" "uuid")
RETURNS integer
LANGUAGE "sql"
SECURITY DEFINER
STABLE
AS $$
    SELECT COALESCE(COUNT(*)::integer, 0)
    FROM "public"."bookings"
    WHERE client_id = p_client_id AND status = 'attended';
$$;

-- Check if milestone notification was already sent
CREATE OR REPLACE FUNCTION "public"."milestone_already_sent"(
    "p_client_id" "uuid",
    "p_milestone" integer
)
RETURNS boolean
LANGUAGE "sql"
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM "public"."notification_logs"
        WHERE client_id = p_client_id
          AND category = 'milestone'
          AND (data->>'milestone')::int = p_milestone
    );
$$;

-- ============================================================================
-- 11. COMMENTS
-- ============================================================================

COMMENT ON TABLE "public"."device_tokens" IS
'Token push Expo per ogni dispositivo registrato. Un client puo avere piu dispositivi.';

COMMENT ON TABLE "public"."notification_preferences" IS
'Preferenze notifiche per ogni client e categoria. Permette di abilitare/disabilitare push ed email separatamente.';

COMMENT ON TABLE "public"."notification_queue" IS
'Coda notifiche da processare. I job pg_cron accodano qui, il processor le invia.';

COMMENT ON TABLE "public"."notification_logs" IS
'Storico notifiche inviate con stato di delivery. Usato per analytics e anti-spam.';

COMMENT ON COLUMN "public"."device_tokens"."expo_push_token" IS
'Token Expo Push nel formato ExponentPushToken[xxx] o per web push';

COMMENT ON COLUMN "public"."device_tokens"."platform" IS
'Piattaforma: ios, android, web';

COMMENT ON COLUMN "public"."notification_queue"."data" IS
'Dati aggiuntivi come lesson_id, subscription_id, etc. per deep linking';

COMMENT ON COLUMN "public"."notification_queue"."scheduled_for" IS
'Quando la notifica deve essere inviata. Il processor legge solo quelle con scheduled_for <= NOW()';

COMMENT ON COLUMN "public"."notification_logs"."expo_receipt_id" IS
'ID ricevuta Expo per verificare delivery push';

COMMENT ON COLUMN "public"."notification_logs"."resend_id" IS
'ID email Resend per tracking delivery email';
