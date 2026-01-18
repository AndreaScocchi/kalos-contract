-- =============================================================================
-- Add social_connection_id to campaign_contents
-- =============================================================================
-- Allows selecting which social account to use for publishing each content.
-- This enables the selection of specific Instagram/Facebook accounts
-- when multiple are connected.
-- =============================================================================

-- Add social_connection_id column with foreign key
ALTER TABLE "public"."campaign_contents"
ADD COLUMN IF NOT EXISTS "social_connection_id" uuid
REFERENCES "public"."social_connections"("id") ON DELETE SET NULL;

-- Index for looking up contents by connection
CREATE INDEX IF NOT EXISTS "idx_campaign_contents_social_connection"
ON "public"."campaign_contents" ("social_connection_id")
WHERE "social_connection_id" IS NOT NULL;

-- Comment
COMMENT ON COLUMN "public"."campaign_contents"."social_connection_id" IS 'Selected social account for publishing (allows choosing between multiple connected accounts)';
