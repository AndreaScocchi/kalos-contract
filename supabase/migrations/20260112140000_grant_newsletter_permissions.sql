-- Grant permissions on newsletter tables to authenticated and anon roles
-- This is required for PostgREST to access the tables

-- Grant permissions to authenticated role
GRANT ALL ON "public"."newsletter_campaigns" TO "authenticated";
GRANT ALL ON "public"."newsletter_templates" TO "authenticated";
GRANT ALL ON "public"."newsletter_emails" TO "authenticated";
GRANT ALL ON "public"."newsletter_tracking_events" TO "authenticated";

-- Grant permissions to anon role (read-only for templates)
GRANT SELECT ON "public"."newsletter_templates" TO "anon";

-- Grant permissions to service_role
GRANT ALL ON "public"."newsletter_campaigns" TO "service_role";
GRANT ALL ON "public"."newsletter_templates" TO "service_role";
GRANT ALL ON "public"."newsletter_emails" TO "service_role";
GRANT ALL ON "public"."newsletter_tracking_events" TO "service_role";

-- Re-enable RLS with proper policies
ALTER TABLE "public"."newsletter_campaigns" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."newsletter_templates" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."newsletter_emails" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."newsletter_tracking_events" ENABLE ROW LEVEL SECURITY;
