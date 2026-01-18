-- =============================================================================
-- Backfill marketing_campaign_id in newsletter_campaigns
-- =============================================================================
-- This migration populates marketing_campaign_id for existing newsletter_campaigns
-- that were created from marketing campaigns, using the existing link in
-- campaign_contents.newsletter_campaign_id.
-- =============================================================================

-- Update newsletter_campaigns with the marketing campaign reference
-- by looking up the relationship through campaign_contents
UPDATE "public"."newsletter_campaigns" nc
SET "marketing_campaign_id" = cc.campaign_id
FROM "public"."campaign_contents" cc
WHERE cc.newsletter_campaign_id = nc.id
  AND cc.content_type = 'newsletter'
  AND nc.marketing_campaign_id IS NULL;
