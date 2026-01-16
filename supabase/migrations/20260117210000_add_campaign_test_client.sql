-- =============================================================================
-- Add test_client_id to campaigns for testing
-- =============================================================================
-- Allows campaigns to be sent to a specific client for testing purposes.
-- When test_client_id is set, the campaign will only be sent to that client.
-- =============================================================================

-- Add test_client_id column
ALTER TABLE "public"."campaigns"
ADD COLUMN IF NOT EXISTS "test_client_id" "uuid" REFERENCES "public"."clients"("id") ON DELETE SET NULL;

-- Add comment
COMMENT ON COLUMN "public"."campaigns"."test_client_id" IS 'When set, campaign is sent only to this client (for testing)';

-- Add index for lookups
CREATE INDEX IF NOT EXISTS "idx_campaigns_test_client" ON "public"."campaigns" ("test_client_id")
WHERE "test_client_id" IS NOT NULL;
