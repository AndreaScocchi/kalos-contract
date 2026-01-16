-- Add preview_text to newsletter_campaigns table
-- This is the preheader text shown after the subject in email clients

ALTER TABLE "public"."newsletter_campaigns"
  ADD COLUMN IF NOT EXISTS "preview_text" TEXT;

COMMENT ON COLUMN "public"."newsletter_campaigns"."preview_text" IS 'Preview text (preheader) shown after the subject line in email clients';
