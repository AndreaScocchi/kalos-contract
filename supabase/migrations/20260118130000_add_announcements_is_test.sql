-- Migration: Add is_test column to announcements
--
-- Allows announcements to be created in test mode from marketing campaigns
-- Test announcements are visible in the management panel but can be filtered

-- Add is_test column with default false
ALTER TABLE "public"."announcements"
ADD COLUMN IF NOT EXISTS "is_test" boolean DEFAULT false NOT NULL;

-- Add index for filtering test announcements
CREATE INDEX IF NOT EXISTS "idx_announcements_is_test"
ON "public"."announcements" ("is_test");

-- Add comment
COMMENT ON COLUMN "public"."announcements"."is_test" IS 'True if announcement was created from a test campaign execution';
