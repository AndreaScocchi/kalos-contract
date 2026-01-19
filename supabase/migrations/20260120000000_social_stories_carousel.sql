-- =============================================================================
-- Social Stories & Carousel Support
-- =============================================================================
-- Adds support for:
-- 1. Instagram carousel posts (multiple slides)
-- 2. Multiple Instagram stories per campaign (3 stories with temporal logic)
-- 3. Story text overlays
-- =============================================================================

-- Add new columns to campaign_contents
ALTER TABLE "public"."campaign_contents"
ADD COLUMN IF NOT EXISTS "slides" jsonb DEFAULT '[]',
ADD COLUMN IF NOT EXISTS "story_text_overlays" text[],
ADD COLUMN IF NOT EXISTS "scheduled_offset_days" integer,
ADD COLUMN IF NOT EXISTS "sequence_index" integer DEFAULT 0;

COMMENT ON COLUMN "public"."campaign_contents"."slides" IS 'JSON array of carousel slides: [{image_url?: string, image_suggestion: string}]';
COMMENT ON COLUMN "public"."campaign_contents"."story_text_overlays" IS 'Array of text overlays to display on story images';
COMMENT ON COLUMN "public"."campaign_contents"."scheduled_offset_days" IS 'Days offset from event_date for story scheduling (-7, -3, -1, 0)';
COMMENT ON COLUMN "public"."campaign_contents"."sequence_index" IS 'Index for multiple contents of same type (e.g., story 0, 1, 2)';

-- Drop existing unique constraint
ALTER TABLE "public"."campaign_contents"
DROP CONSTRAINT IF EXISTS "campaign_contents_unique";

-- Create new unique constraint that includes sequence_index
ALTER TABLE "public"."campaign_contents"
ADD CONSTRAINT "campaign_contents_unique"
UNIQUE ("campaign_id", "content_type", "sequence_index");

-- Add index for efficient querying of stories
CREATE INDEX IF NOT EXISTS "idx_campaign_contents_sequence"
ON "public"."campaign_contents" ("campaign_id", "content_type", "sequence_index");
