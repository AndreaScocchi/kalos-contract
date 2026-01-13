-- Migration: Grant explicit permissions for notification tables
--
-- Il service_role in Supabase usa internamente il ruolo 'anon' o 'authenticated'.
-- Dobbiamo concedere esplicitamente i permessi GRANT sui tavoli.

-- Grant ALL permissions on notification tables to anon role
GRANT ALL ON "public"."notification_queue" TO "anon";
GRANT ALL ON "public"."notification_logs" TO "anon";
GRANT ALL ON "public"."device_tokens" TO "anon";
GRANT ALL ON "public"."notification_preferences" TO "anon";

-- Grant SELECT on clients to anon (needed for JOIN)
GRANT SELECT ON "public"."clients" TO "anon";

-- Grant to authenticated as well (for app access)
GRANT ALL ON "public"."notification_queue" TO "authenticated";
GRANT ALL ON "public"."notification_logs" TO "authenticated";
GRANT ALL ON "public"."device_tokens" TO "authenticated";
GRANT ALL ON "public"."notification_preferences" TO "authenticated";

-- Grant to service_role explicitly
GRANT ALL ON "public"."notification_queue" TO "service_role";
GRANT ALL ON "public"."notification_logs" TO "service_role";
GRANT ALL ON "public"."device_tokens" TO "service_role";
GRANT ALL ON "public"."notification_preferences" TO "service_role";
GRANT SELECT ON "public"."clients" TO "service_role";
