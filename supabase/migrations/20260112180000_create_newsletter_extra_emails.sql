-- Create table for extra newsletter recipients (non-clients)
CREATE TABLE IF NOT EXISTS "public"."newsletter_extra_emails" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "email" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ,
  CONSTRAINT "newsletter_extra_emails_email_unique" UNIQUE ("email")
);

-- Enable RLS
ALTER TABLE "public"."newsletter_extra_emails" ENABLE ROW LEVEL SECURITY;

-- Staff can view all extra emails
CREATE POLICY "Staff can view extra emails"
  ON "public"."newsletter_extra_emails"
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('operator', 'admin', 'finance')
    )
  );

-- Staff can insert extra emails
CREATE POLICY "Staff can insert extra emails"
  ON "public"."newsletter_extra_emails"
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('operator', 'admin', 'finance')
    )
  );

-- Staff can update extra emails
CREATE POLICY "Staff can update extra emails"
  ON "public"."newsletter_extra_emails"
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('operator', 'admin', 'finance')
    )
  );

-- Staff can delete extra emails
CREATE POLICY "Staff can delete extra emails"
  ON "public"."newsletter_extra_emails"
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('operator', 'admin', 'finance')
    )
  );

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS "idx_newsletter_extra_emails_deleted_at"
  ON "public"."newsletter_extra_emails" ("deleted_at");

-- Comment
COMMENT ON TABLE "public"."newsletter_extra_emails" IS 'Extra email addresses for newsletter recipients (non-clients)';