-- Migration: Fix notification center permissions
-- Grant table permissions for announcements and notification_reads

-- Grant permissions on announcements
GRANT SELECT ON "public"."announcements" TO "authenticated";
GRANT SELECT ON "public"."announcements" TO "anon";
GRANT ALL ON "public"."announcements" TO "service_role";

-- Grant permissions on notification_reads
GRANT SELECT, INSERT, DELETE ON "public"."notification_reads" TO "authenticated";
GRANT ALL ON "public"."notification_reads" TO "service_role";
