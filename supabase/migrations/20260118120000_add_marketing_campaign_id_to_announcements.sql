-- =============================================================================
-- Add marketing_campaign_id to announcements
-- =============================================================================
-- This migration adds a reference from announcements back to the marketing
-- campaign that generated them, allowing the announcements list to show
-- which campaign the announcement originated from.
-- =============================================================================

-- Add column to announcements
ALTER TABLE "public"."announcements"
ADD COLUMN IF NOT EXISTS "marketing_campaign_id" uuid REFERENCES "public"."campaigns"("id") ON DELETE SET NULL;

-- Create index for efficient lookups
CREATE INDEX IF NOT EXISTS "idx_announcements_marketing_campaign"
ON "public"."announcements" ("marketing_campaign_id")
WHERE "marketing_campaign_id" IS NOT NULL;

-- Add comment
COMMENT ON COLUMN "public"."announcements"."marketing_campaign_id"
IS 'Reference to the marketing campaign that generated this announcement (null if created manually)';

-- =============================================================================
-- Backfill marketing_campaign_id for existing announcements
-- =============================================================================
-- Use the data field in notification_queue to find the campaign_id for
-- announcements created from marketing campaigns.
-- The edge function stores campaign_id in the data JSON field.

-- Update announcements with the marketing campaign reference
-- by looking up the relationship through notification_queue data
UPDATE "public"."announcements" a
SET "marketing_campaign_id" = (nq.data->>'campaign_id')::uuid
FROM "public"."notification_queue" nq
WHERE (nq.data->>'announcement_id')::uuid = a.id
  AND nq.data->>'campaign_id' IS NOT NULL
  AND a.marketing_campaign_id IS NULL;

-- Also check notification_logs for already processed notifications
UPDATE "public"."announcements" a
SET "marketing_campaign_id" = (nl.data->>'campaign_id')::uuid
FROM "public"."notification_logs" nl
WHERE (nl.data->>'announcement_id')::uuid = a.id
  AND nl.data->>'campaign_id' IS NOT NULL
  AND a.marketing_campaign_id IS NULL;
