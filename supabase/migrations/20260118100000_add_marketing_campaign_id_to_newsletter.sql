-- =============================================================================
-- Add marketing_campaign_id to newsletter_campaigns
-- =============================================================================
-- This migration adds a reference from newsletter_campaigns back to the
-- marketing campaign that generated them, allowing the newsletter list
-- to show which campaign the newsletter originated from.
-- =============================================================================

-- Add column to newsletter_campaigns
ALTER TABLE "public"."newsletter_campaigns"
ADD COLUMN IF NOT EXISTS "marketing_campaign_id" uuid REFERENCES "public"."campaigns"("id") ON DELETE SET NULL;

-- Create index for efficient lookups
CREATE INDEX IF NOT EXISTS "idx_newsletter_campaigns_marketing_campaign"
ON "public"."newsletter_campaigns" ("marketing_campaign_id")
WHERE "marketing_campaign_id" IS NOT NULL;

-- Add comment
COMMENT ON COLUMN "public"."newsletter_campaigns"."marketing_campaign_id"
IS 'Reference to the marketing campaign that generated this newsletter (null if created manually)';
