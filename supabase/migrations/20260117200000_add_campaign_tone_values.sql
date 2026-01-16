-- =============================================================================
-- Add new campaign tone values
-- =============================================================================
-- Adds additional tone of voice options for marketing campaigns:
-- entusiasta, professionale, empatico, diretto, esclusivo
-- =============================================================================

-- Add new values to the campaign_tone enum
ALTER TYPE "public"."campaign_tone" ADD VALUE IF NOT EXISTS 'entusiasta';
ALTER TYPE "public"."campaign_tone" ADD VALUE IF NOT EXISTS 'professionale';
ALTER TYPE "public"."campaign_tone" ADD VALUE IF NOT EXISTS 'empatico';
ALTER TYPE "public"."campaign_tone" ADD VALUE IF NOT EXISTS 'diretto';
ALTER TYPE "public"."campaign_tone" ADD VALUE IF NOT EXISTS 'esclusivo';
