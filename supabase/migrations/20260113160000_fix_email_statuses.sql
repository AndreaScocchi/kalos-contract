-- Fix email statuses for emails that were sent before the webhook fix
-- Emails with 'sent' status and sent_at timestamp should be marked as 'delivered'
UPDATE "public"."newsletter_emails"
SET status = 'delivered',
    delivered_at = sent_at
WHERE status = 'sent'
  AND sent_at IS NOT NULL;

-- Recalculate campaign stats based on actual email statuses
UPDATE "public"."newsletter_campaigns" c
SET
  delivered_count = (
    SELECT COUNT(*) FROM "public"."newsletter_emails" e
    WHERE e.campaign_id = c.id
    AND e.status IN ('delivered', 'opened', 'clicked')
  ),
  opened_count = (
    SELECT COUNT(*) FROM "public"."newsletter_emails" e
    WHERE e.campaign_id = c.id
    AND e.status IN ('opened', 'clicked')
  ),
  clicked_count = (
    SELECT COUNT(*) FROM "public"."newsletter_emails" e
    WHERE e.campaign_id = c.id
    AND e.status = 'clicked'
  ),
  bounced_count = (
    SELECT COUNT(*) FROM "public"."newsletter_emails" e
    WHERE e.campaign_id = c.id
    AND e.status IN ('bounced', 'complained')
  )
WHERE c.status = 'sent';
