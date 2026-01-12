-- Fix newsletter RLS policies - simplify to debug permission issues

-- Drop existing policies
DROP POLICY IF EXISTS "newsletter_campaigns_select_staff" ON "public"."newsletter_campaigns";
DROP POLICY IF EXISTS "newsletter_campaigns_insert_staff" ON "public"."newsletter_campaigns";
DROP POLICY IF EXISTS "newsletter_campaigns_update_staff" ON "public"."newsletter_campaigns";
DROP POLICY IF EXISTS "newsletter_campaigns_delete_staff" ON "public"."newsletter_campaigns";

DROP POLICY IF EXISTS "newsletter_templates_select_staff" ON "public"."newsletter_templates";
DROP POLICY IF EXISTS "newsletter_templates_all_admin" ON "public"."newsletter_templates";

DROP POLICY IF EXISTS "newsletter_emails_select_staff" ON "public"."newsletter_emails";
DROP POLICY IF EXISTS "newsletter_emails_insert_service" ON "public"."newsletter_emails";
DROP POLICY IF EXISTS "newsletter_emails_update_service" ON "public"."newsletter_emails";

DROP POLICY IF EXISTS "newsletter_tracking_events_select_staff" ON "public"."newsletter_tracking_events";
DROP POLICY IF EXISTS "newsletter_tracking_events_insert_service" ON "public"."newsletter_tracking_events";

-- Recreate simplified policies for campaigns
CREATE POLICY "newsletter_campaigns_select_staff" ON "public"."newsletter_campaigns"
FOR SELECT TO "authenticated"
USING (is_staff());

CREATE POLICY "newsletter_campaigns_insert_staff" ON "public"."newsletter_campaigns"
FOR INSERT TO "authenticated"
WITH CHECK (is_staff());

CREATE POLICY "newsletter_campaigns_update_staff" ON "public"."newsletter_campaigns"
FOR UPDATE TO "authenticated"
USING (is_staff())
WITH CHECK (is_staff());

CREATE POLICY "newsletter_campaigns_delete_staff" ON "public"."newsletter_campaigns"
FOR DELETE TO "authenticated"
USING (is_staff());

-- Templates: all staff can read and manage
CREATE POLICY "newsletter_templates_all_staff" ON "public"."newsletter_templates"
FOR ALL TO "authenticated"
USING (is_staff())
WITH CHECK (is_staff());

-- Emails: staff can read, service role can write
CREATE POLICY "newsletter_emails_select_staff" ON "public"."newsletter_emails"
FOR SELECT TO "authenticated"
USING (is_staff());

CREATE POLICY "newsletter_emails_all_service" ON "public"."newsletter_emails"
FOR ALL TO "service_role"
USING (true)
WITH CHECK (true);

-- Tracking events: staff can read, service role can write
CREATE POLICY "newsletter_tracking_events_select_staff" ON "public"."newsletter_tracking_events"
FOR SELECT TO "authenticated"
USING (is_staff());

CREATE POLICY "newsletter_tracking_events_all_service" ON "public"."newsletter_tracking_events"
FOR ALL TO "service_role"
USING (true)
WITH CHECK (true);
