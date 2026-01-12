-- Migration: Add recipients column to newsletter_campaigns
-- This stores the selected recipients when saving a draft

-- Add recipients column as JSONB to store the list of recipients
ALTER TABLE "public"."newsletter_campaigns"
  ADD COLUMN IF NOT EXISTS "recipients" JSONB DEFAULT '[]'::jsonb;

-- Add comment
COMMENT ON COLUMN "public"."newsletter_campaigns"."recipients" IS
'Lista dei destinatari selezionati salvati con la bozza. Formato: [{email, name, clientId?}]';
