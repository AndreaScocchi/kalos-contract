-- Migration: Simplify newsletter system
-- Remove templates, switch to plain text, support manual email recipients

-- ============================================================================
-- 1. DROP NEWSLETTER_TEMPLATES TABLE (no longer used)
-- ============================================================================

-- First drop the foreign key from campaigns
ALTER TABLE "public"."newsletter_campaigns"
  DROP CONSTRAINT IF EXISTS "newsletter_campaigns_template_id_fkey";

-- Drop RLS policies
DROP POLICY IF EXISTS "newsletter_templates_select_staff" ON "public"."newsletter_templates";
DROP POLICY IF EXISTS "newsletter_templates_all_admin" ON "public"."newsletter_templates";
DROP POLICY IF EXISTS "newsletter_templates_all_staff" ON "public"."newsletter_templates";

-- Drop the table
DROP TABLE IF EXISTS "public"."newsletter_templates";

-- ============================================================================
-- 2. MODIFY NEWSLETTER_CAMPAIGNS TABLE
-- ============================================================================

-- Remove template_id column
ALTER TABLE "public"."newsletter_campaigns"
  DROP COLUMN IF EXISTS "template_id";

-- Rename content_html to content (plain text now)
ALTER TABLE "public"."newsletter_campaigns"
  RENAME COLUMN "content_html" TO "content";

-- Drop content_text column (no longer needed, content is plain text)
ALTER TABLE "public"."newsletter_campaigns"
  DROP COLUMN IF EXISTS "content_text";

-- ============================================================================
-- 3. MODIFY NEWSLETTER_EMAILS TABLE
-- ============================================================================

-- Make client_id nullable (for manual email addresses not linked to clients)
ALTER TABLE "public"."newsletter_emails"
  ALTER COLUMN "client_id" DROP NOT NULL;

-- Drop the old unique constraint on (campaign_id, client_id)
ALTER TABLE "public"."newsletter_emails"
  DROP CONSTRAINT IF EXISTS "newsletter_emails_campaign_client_unique";

-- Add new unique constraint on (campaign_id, email_address)
-- This prevents sending duplicate emails to the same address in a campaign
ALTER TABLE "public"."newsletter_emails"
  ADD CONSTRAINT "newsletter_emails_campaign_email_unique"
  UNIQUE ("campaign_id", "email_address");

-- ============================================================================
-- 4. UPDATE COMMENTS
-- ============================================================================

COMMENT ON TABLE "public"."newsletter_campaigns" IS
'Campagne newsletter. Il contenuto e in testo semplice. Supporta {{nome}} come placeholder per il nome del destinatario.';

COMMENT ON COLUMN "public"."newsletter_campaigns"."content" IS
'Contenuto della newsletter in testo semplice. Supporta {{nome}} come placeholder.';

COMMENT ON COLUMN "public"."newsletter_emails"."client_id" IS
'ID del cliente destinatario. NULL per email manuali non associate a un cliente.';
