-- =============================================================================
-- Add is_test flag to social_connections
-- =============================================================================
-- Allows connecting separate Meta accounts for test and production environments.
-- When a campaign is executed in test mode (with a specific test client),
-- the system will use the test social connection; otherwise, it uses production.
-- =============================================================================

-- Add is_test column
ALTER TABLE "public"."social_connections"
ADD COLUMN IF NOT EXISTS "is_test" boolean DEFAULT false NOT NULL;

-- Drop old unique constraint (operator_id, platform)
ALTER TABLE "public"."social_connections"
DROP CONSTRAINT IF EXISTS "social_connections_unique";

-- Create new unique constraint that includes is_test
-- This allows same operator to have both test and prod connections per platform
ALTER TABLE "public"."social_connections"
ADD CONSTRAINT "social_connections_unique"
UNIQUE ("operator_id", "platform", "is_test");

-- Index for filtering by is_test
CREATE INDEX IF NOT EXISTS "idx_social_connections_is_test"
ON "public"."social_connections" ("is_test");

-- Comment
COMMENT ON COLUMN "public"."social_connections"."is_test" IS 'True for test accounts, false for production accounts';
