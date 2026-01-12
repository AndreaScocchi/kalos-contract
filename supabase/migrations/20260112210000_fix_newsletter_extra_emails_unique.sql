-- Fix unique constraint to only apply to non-deleted records
-- This allows re-adding an email after soft-deleting it

-- Drop the old unique constraint
ALTER TABLE "public"."newsletter_extra_emails"
  DROP CONSTRAINT IF EXISTS "newsletter_extra_emails_email_unique";

-- Create a partial unique index that only applies to non-deleted records
CREATE UNIQUE INDEX "newsletter_extra_emails_email_unique"
  ON "public"."newsletter_extra_emails" ("email")
  WHERE "deleted_at" IS NULL;
