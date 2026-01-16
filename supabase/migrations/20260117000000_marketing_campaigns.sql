-- =============================================================================
-- Marketing Campaigns System
-- =============================================================================
-- Centralizes multi-channel marketing campaigns (Push, Newsletter, Social)
-- with AI content generation via Groq and Meta Business API integration.
-- =============================================================================

-- =============================================================================
-- ENUMS
-- =============================================================================

-- Campaign type
CREATE TYPE "public"."campaign_type" AS ENUM (
    'promo',
    'evento',
    'annuncio',
    'corso_nuovo'
);

-- Communication tone
CREATE TYPE "public"."campaign_tone" AS ENUM (
    'formale',
    'amichevole',
    'urgente'
);

-- Campaign workflow status
CREATE TYPE "public"."marketing_campaign_status" AS ENUM (
    'draft',
    'ai_generating',
    'pending_review',
    'scheduled',
    'executing',
    'completed',
    'failed'
);

-- Content type for each channel
CREATE TYPE "public"."campaign_content_type" AS ENUM (
    'brief',
    'push_notification',
    'newsletter',
    'instagram_post',
    'instagram_story',
    'instagram_reel',
    'instagram_carousel',
    'facebook_post'
);

-- Content channel status
CREATE TYPE "public"."content_status" AS ENUM (
    'pending',
    'generated',
    'edited',
    'scheduled',
    'sent',
    'published',
    'failed',
    'skipped'
);

-- Social media platform
CREATE TYPE "public"."social_platform" AS ENUM (
    'instagram',
    'facebook'
);

-- =============================================================================
-- TABLE: campaigns
-- =============================================================================
-- Main marketing campaigns table storing campaign metadata and wizard state

CREATE TABLE IF NOT EXISTS "public"."campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,

    -- Input campagna (Step 1)
    "name" "text" NOT NULL,
    "type" "public"."campaign_type" NOT NULL,
    "target" "jsonb" NOT NULL DEFAULT '{"segment": "tutti"}',
    "message" "text" NOT NULL,
    "event_date" timestamp with time zone,
    "tone" "public"."campaign_tone" NOT NULL DEFAULT 'amichevole',

    -- Wizard state
    "status" "public"."marketing_campaign_status" DEFAULT 'draft' NOT NULL,
    "current_step" integer DEFAULT 1 NOT NULL,
    "skipped_steps" integer[] DEFAULT '{}',

    -- AI metadata
    "ai_prompt_used" "text",
    "ai_model_used" "text",
    "ai_generated_at" timestamp with time zone,

    -- Scheduling
    "scheduled_for" timestamp with time zone,
    "executed_at" timestamp with time zone,

    -- Analytics aggregati
    "total_reach" integer DEFAULT 0,
    "total_engagement" integer DEFAULT 0,

    -- Audit
    "created_by" "uuid" REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,

    CONSTRAINT "campaigns_pkey" PRIMARY KEY ("id")
);

COMMENT ON TABLE "public"."campaigns" IS 'Marketing campaigns with multi-channel content generation';
COMMENT ON COLUMN "public"."campaigns"."target" IS 'JSON object: {segment: string, categories?: string[]}';
COMMENT ON COLUMN "public"."campaigns"."skipped_steps" IS 'Array of step IDs that were skipped in the wizard';

-- Indexes
CREATE INDEX "idx_campaigns_status" ON "public"."campaigns" ("status");
CREATE INDEX "idx_campaigns_type" ON "public"."campaigns" ("type");
CREATE INDEX "idx_campaigns_created_at" ON "public"."campaigns" ("created_at" DESC);
CREATE INDEX "idx_campaigns_scheduled" ON "public"."campaigns" ("scheduled_for")
    WHERE "scheduled_for" IS NOT NULL AND "status" = 'scheduled';
CREATE INDEX "idx_campaigns_not_deleted" ON "public"."campaigns" ("deleted_at")
    WHERE "deleted_at" IS NULL;

-- Trigger updated_at
CREATE TRIGGER "campaigns_updated_at"
    BEFORE UPDATE ON "public"."campaigns"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- =============================================================================
-- TABLE: campaign_contents
-- =============================================================================
-- Stores generated content for each channel (push, newsletter, social)

CREATE TABLE IF NOT EXISTS "public"."campaign_contents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL REFERENCES "public"."campaigns"("id") ON DELETE CASCADE,

    -- Content type
    "content_type" "public"."campaign_content_type" NOT NULL,
    "platform" "public"."social_platform",

    -- Contenuto
    "title" "text",
    "body" "text",
    "hashtags" "text"[],
    "image_suggestions" "text"[],
    "image_url" "text",
    "video_url" "text",
    "link_url" "text",
    "link_label" "text",

    -- AI original (per confronto e audit)
    "ai_generated_title" "text",
    "ai_generated_body" "text",
    "ai_generated_hashtags" "text"[],
    "ai_generated_image_suggestions" "text"[],
    "is_edited" boolean DEFAULT false,

    -- Status & scheduling
    "status" "public"."content_status" DEFAULT 'pending' NOT NULL,
    "scheduled_for" timestamp with time zone,
    "sent_at" timestamp with time zone,
    "published_at" timestamp with time zone,

    -- Integration refs
    "newsletter_campaign_id" "uuid" REFERENCES "public"."newsletter_campaigns"("id") ON DELETE SET NULL,
    "meta_post_id" "text",
    "meta_container_id" "text",

    -- Error tracking
    "error_message" "text",
    "retry_count" integer DEFAULT 0,

    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "campaign_contents_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "campaign_contents_unique" UNIQUE ("campaign_id", "content_type")
);

COMMENT ON TABLE "public"."campaign_contents" IS 'Generated content for each marketing channel';
COMMENT ON COLUMN "public"."campaign_contents"."is_edited" IS 'True if user modified AI-generated content';

-- Indexes
CREATE INDEX "idx_campaign_contents_campaign" ON "public"."campaign_contents" ("campaign_id");
CREATE INDEX "idx_campaign_contents_status" ON "public"."campaign_contents" ("status");
CREATE INDEX "idx_campaign_contents_type" ON "public"."campaign_contents" ("content_type");
CREATE INDEX "idx_campaign_contents_meta_post" ON "public"."campaign_contents" ("meta_post_id")
    WHERE "meta_post_id" IS NOT NULL;

-- Trigger updated_at
CREATE TRIGGER "campaign_contents_updated_at"
    BEFORE UPDATE ON "public"."campaign_contents"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- =============================================================================
-- TABLE: campaign_analytics
-- =============================================================================
-- Stores analytics metrics per channel for each campaign

CREATE TABLE IF NOT EXISTS "public"."campaign_analytics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL REFERENCES "public"."campaigns"("id") ON DELETE CASCADE,
    "content_id" "uuid" REFERENCES "public"."campaign_contents"("id") ON DELETE CASCADE,
    "channel" "text" NOT NULL,

    -- Metriche comuni
    "reach" integer DEFAULT 0,
    "impressions" integer DEFAULT 0,
    "clicks" integer DEFAULT 0,
    "engagement" integer DEFAULT 0,

    -- Newsletter metrics
    "emails_sent" integer DEFAULT 0,
    "emails_delivered" integer DEFAULT 0,
    "emails_opened" integer DEFAULT 0,
    "emails_clicked" integer DEFAULT 0,
    "emails_bounced" integer DEFAULT 0,

    -- Push notification metrics
    "push_sent" integer DEFAULT 0,
    "push_delivered" integer DEFAULT 0,
    "push_clicked" integer DEFAULT 0,

    -- Social metrics
    "likes" integer DEFAULT 0,
    "comments" integer DEFAULT 0,
    "shares" integer DEFAULT 0,
    "saves" integer DEFAULT 0,
    "story_views" integer DEFAULT 0,
    "story_replies" integer DEFAULT 0,

    "last_fetched_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "campaign_analytics_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "campaign_analytics_unique" UNIQUE ("campaign_id", "channel")
);

COMMENT ON TABLE "public"."campaign_analytics" IS 'Analytics metrics per channel for marketing campaigns';

-- Indexes
CREATE INDEX "idx_campaign_analytics_campaign" ON "public"."campaign_analytics" ("campaign_id");
CREATE INDEX "idx_campaign_analytics_channel" ON "public"."campaign_analytics" ("channel");

-- Trigger updated_at
CREATE TRIGGER "campaign_analytics_updated_at"
    BEFORE UPDATE ON "public"."campaign_analytics"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- =============================================================================
-- TABLE: social_connections
-- =============================================================================
-- Stores Meta (Facebook/Instagram) OAuth tokens for social publishing

CREATE TABLE IF NOT EXISTS "public"."social_connections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "operator_id" "uuid" NOT NULL REFERENCES "public"."profiles"("id") ON DELETE CASCADE,
    "platform" "public"."social_platform" NOT NULL,

    -- Account info
    "account_id" "text" NOT NULL,
    "account_name" "text",
    "page_id" "text",
    "page_name" "text",
    "instagram_business_id" "text",
    "instagram_username" "text",

    -- Tokens (encrypted at rest by Supabase)
    "access_token" "text" NOT NULL,
    "token_expires_at" timestamp with time zone,

    -- Permissions granted
    "permissions" "text"[] DEFAULT '{}',

    -- Status
    "is_active" boolean DEFAULT true NOT NULL,
    "last_used_at" timestamp with time zone,
    "last_error" "text",

    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "social_connections_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "social_connections_unique" UNIQUE ("operator_id", "platform")
);

COMMENT ON TABLE "public"."social_connections" IS 'Meta OAuth connections for social media publishing';
COMMENT ON COLUMN "public"."social_connections"."access_token" IS 'Long-lived access token (60 days)';

-- Indexes
CREATE INDEX "idx_social_connections_operator" ON "public"."social_connections" ("operator_id");
CREATE INDEX "idx_social_connections_active" ON "public"."social_connections" ("is_active")
    WHERE "is_active" = true;

-- Trigger updated_at
CREATE TRIGGER "social_connections_updated_at"
    BEFORE UPDATE ON "public"."social_connections"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- =============================================================================
-- RLS POLICIES
-- =============================================================================

ALTER TABLE "public"."campaigns" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."campaign_contents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."campaign_analytics" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."social_connections" ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- Campaigns: Staff full access (excluding soft-deleted)
-- -----------------------------------------------------------------------------

CREATE POLICY "campaigns_staff_select" ON "public"."campaigns"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"() AND "deleted_at" IS NULL);

CREATE POLICY "campaigns_staff_insert" ON "public"."campaigns"
    FOR INSERT TO "authenticated"
    WITH CHECK ("public"."is_staff"());

CREATE POLICY "campaigns_staff_update" ON "public"."campaigns"
    FOR UPDATE TO "authenticated"
    USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

CREATE POLICY "campaigns_staff_delete" ON "public"."campaigns"
    FOR DELETE TO "authenticated"
    USING ("public"."is_staff"());

CREATE POLICY "campaigns_service" ON "public"."campaigns"
    FOR ALL TO "service_role"
    USING (true) WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- Campaign contents: Staff full access
-- -----------------------------------------------------------------------------

CREATE POLICY "campaign_contents_staff_all" ON "public"."campaign_contents"
    FOR ALL TO "authenticated"
    USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

CREATE POLICY "campaign_contents_service" ON "public"."campaign_contents"
    FOR ALL TO "service_role"
    USING (true) WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- Campaign analytics: Staff read, service role write
-- -----------------------------------------------------------------------------

CREATE POLICY "campaign_analytics_staff_select" ON "public"."campaign_analytics"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"());

CREATE POLICY "campaign_analytics_service" ON "public"."campaign_analytics"
    FOR ALL TO "service_role"
    USING (true) WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- Social connections: Staff can view all, manage own
-- -----------------------------------------------------------------------------

CREATE POLICY "social_connections_staff_select" ON "public"."social_connections"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"());

CREATE POLICY "social_connections_staff_insert" ON "public"."social_connections"
    FOR INSERT TO "authenticated"
    WITH CHECK ("public"."is_staff"());

CREATE POLICY "social_connections_own_update" ON "public"."social_connections"
    FOR UPDATE TO "authenticated"
    USING ("public"."is_staff"() AND "operator_id" = "auth"."uid"())
    WITH CHECK ("public"."is_staff"() AND "operator_id" = "auth"."uid"());

CREATE POLICY "social_connections_own_delete" ON "public"."social_connections"
    FOR DELETE TO "authenticated"
    USING ("public"."is_staff"() AND "operator_id" = "auth"."uid"());

CREATE POLICY "social_connections_service" ON "public"."social_connections"
    FOR ALL TO "service_role"
    USING (true) WITH CHECK (true);

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT ALL ON "public"."campaigns" TO "authenticated";
GRANT ALL ON "public"."campaigns" TO "service_role";
GRANT ALL ON "public"."campaign_contents" TO "authenticated";
GRANT ALL ON "public"."campaign_contents" TO "service_role";
GRANT ALL ON "public"."campaign_analytics" TO "authenticated";
GRANT ALL ON "public"."campaign_analytics" TO "service_role";
GRANT ALL ON "public"."social_connections" TO "authenticated";
GRANT ALL ON "public"."social_connections" TO "service_role";
