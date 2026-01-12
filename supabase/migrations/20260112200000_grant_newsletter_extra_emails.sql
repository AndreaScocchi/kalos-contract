-- Add GRANT permissions for newsletter_extra_emails table
-- This was missing from the original migration

GRANT ALL ON TABLE "public"."newsletter_extra_emails" TO "authenticated";
GRANT ALL ON TABLE "public"."newsletter_extra_emails" TO "service_role";
