-- Add email_bounced tracking to clients table
-- This allows automatic exclusion of clients with bounced emails from newsletter sends

ALTER TABLE "public"."clients"
  ADD COLUMN IF NOT EXISTS "email_bounced" BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS "email_bounced_at" TIMESTAMPTZ;

-- Create index for efficient filtering of non-bounced clients
CREATE INDEX IF NOT EXISTS "idx_clients_email_bounced" ON "public"."clients" ("email_bounced") WHERE email_bounced = FALSE;

COMMENT ON COLUMN "public"."clients"."email_bounced" IS 'True if email has hard bounced, excluding client from newsletter sends';
COMMENT ON COLUMN "public"."clients"."email_bounced_at" IS 'Timestamp of when the email bounced';
