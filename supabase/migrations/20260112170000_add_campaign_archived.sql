-- Add archived column to newsletter_campaigns
ALTER TABLE "public"."newsletter_campaigns"
  ADD COLUMN IF NOT EXISTS "archived" BOOLEAN NOT NULL DEFAULT FALSE;

-- Create index for faster filtering
CREATE INDEX IF NOT EXISTS "idx_newsletter_campaigns_archived"
  ON "public"."newsletter_campaigns" ("archived");

-- Comment
COMMENT ON COLUMN "public"."newsletter_campaigns"."archived" IS 'Whether the campaign is archived (hidden from default list view)';
