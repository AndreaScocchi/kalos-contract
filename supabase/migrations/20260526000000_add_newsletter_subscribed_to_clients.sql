-- Add newsletter_subscribed flag to clients table.
-- Already referenced by the unsubscribe-newsletter edge function; this migration
-- guarantees the column exists in every environment and adds an index used by the
-- send-newsletter recipient filter.

ALTER TABLE "public"."clients"
  ADD COLUMN IF NOT EXISTS "newsletter_subscribed" BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS "idx_clients_newsletter_subscribed"
  ON "public"."clients" ("newsletter_subscribed")
  WHERE newsletter_subscribed = TRUE;

COMMENT ON COLUMN "public"."clients"."newsletter_subscribed" IS
  'False when the client has opted out via the one-click unsubscribe link. Newsletter sends must exclude these clients.';
