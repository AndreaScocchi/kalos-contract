-- Add delivery_mode + from_name_override to newsletter_campaigns.
--
-- delivery_mode controls how a newsletter is sent:
--   - 'promotions': brand-heavy HTML template + bulk-sender headers (Feedback-ID,
--     Precedence: bulk). Targets Gmail's "Promotions" tab. Default.
--   - 'primary':    minimal HTML template + neutral headers. Aims for Gmail's
--     "Primary" tab. Best for personal-feeling invites to events.
--
-- from_name_override (used in primary mode) overrides the default sender display
-- name (e.g. "Tommaso da Studio Kalòs"). The email address stays on the verified
-- domain (newsletter@kalosstudio.it) to preserve DKIM alignment.

ALTER TABLE "public"."newsletter_campaigns"
  ADD COLUMN IF NOT EXISTS "delivery_mode" TEXT NOT NULL DEFAULT 'promotions',
  ADD COLUMN IF NOT EXISTS "from_name_override" TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'newsletter_campaigns_delivery_mode_check'
  ) THEN
    ALTER TABLE "public"."newsletter_campaigns"
      ADD CONSTRAINT "newsletter_campaigns_delivery_mode_check"
      CHECK ("delivery_mode" IN ('promotions', 'primary'));
  END IF;
END $$;

COMMENT ON COLUMN "public"."newsletter_campaigns"."delivery_mode" IS
  'Send strategy: ''promotions'' (branded HTML, bulk headers) or ''primary'' (plain HTML, no bulk headers, aiming for Gmail Primary tab).';
COMMENT ON COLUMN "public"."newsletter_campaigns"."from_name_override" IS
  'Optional sender display name override, used in primary mode (e.g. "Tommaso da Studio Kalòs"). Email address stays on the verified domain.';
