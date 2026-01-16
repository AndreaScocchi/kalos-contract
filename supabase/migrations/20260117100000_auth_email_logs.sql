-- Migration: Create auth email logs table
--
-- Obiettivo: Tracciare le email di conferma auth (signup, resend)
-- per debugging e monitoring del delivery.

-- ============================================================================
-- 1. CREATE auth_email_logs TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."auth_email_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "email_type" "text" NOT NULL, -- 'signup', 'resend', 'password_reset', etc.
    "source" "text" NOT NULL, -- 'supabase_auth', 'resend_custom', 'edge_function'
    "resend_id" "text", -- ID from Resend if sent via custom email
    "status" "text" DEFAULT 'sent' NOT NULL, -- 'sent', 'delivered', 'bounced', 'failed'
    "error_message" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."auth_email_logs" OWNER TO "postgres";

ALTER TABLE "public"."auth_email_logs"
    ADD CONSTRAINT "auth_email_logs_pkey" PRIMARY KEY ("id");

-- Indexes for efficient querying
CREATE INDEX "idx_auth_email_logs_user_id" ON "public"."auth_email_logs" ("user_id");
CREATE INDEX "idx_auth_email_logs_email" ON "public"."auth_email_logs" ("email");
CREATE INDEX "idx_auth_email_logs_created_at" ON "public"."auth_email_logs" ("created_at" DESC);
CREATE INDEX "idx_auth_email_logs_status" ON "public"."auth_email_logs" ("status");
CREATE INDEX "idx_auth_email_logs_resend_id" ON "public"."auth_email_logs" ("resend_id") WHERE "resend_id" IS NOT NULL;

-- ============================================================================
-- 2. ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE "public"."auth_email_logs" ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 3. RLS POLICIES
-- ============================================================================

-- Staff can view all logs
CREATE POLICY "auth_email_logs_staff_select"
ON "public"."auth_email_logs" FOR SELECT TO "authenticated"
USING ("public"."is_staff"());

-- Service role full access (for edge functions)
CREATE POLICY "auth_email_logs_service_all"
ON "public"."auth_email_logs" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- ============================================================================
-- 4. TRIGGER FOR updated_at
-- ============================================================================

CREATE TRIGGER "auth_email_logs_updated_at"
    BEFORE UPDATE ON "public"."auth_email_logs"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ============================================================================
-- 5. GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT ON "public"."auth_email_logs" TO "authenticated";
GRANT ALL ON "public"."auth_email_logs" TO "service_role";

-- ============================================================================
-- 6. RPC FUNCTION: Get auth email stats for a user
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."get_auth_email_stats"("p_user_id" "uuid")
RETURNS TABLE (
    "total_sent" bigint,
    "last_sent_at" timestamp with time zone,
    "last_status" "text",
    "failed_count" bigint,
    "bounced_count" bigint
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    -- Only staff can access
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN QUERY
    SELECT
        COUNT(*)::bigint AS total_sent,
        MAX(ael.created_at) AS last_sent_at,
        (SELECT status FROM public.auth_email_logs WHERE user_id = p_user_id ORDER BY created_at DESC LIMIT 1) AS last_status,
        COUNT(*) FILTER (WHERE ael.status = 'failed')::bigint AS failed_count,
        COUNT(*) FILTER (WHERE ael.status = 'bounced')::bigint AS bounced_count
    FROM public.auth_email_logs ael
    WHERE ael.user_id = p_user_id;
END;
$$;

ALTER FUNCTION "public"."get_auth_email_stats"("uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."get_auth_email_stats"("uuid") TO "authenticated";
