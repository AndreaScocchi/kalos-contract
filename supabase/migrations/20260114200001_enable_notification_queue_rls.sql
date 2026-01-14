-- Migration: Enable RLS on notification_queue
--
-- La tabella notification_queue deve avere RLS abilitato per soddisfare il linter.
-- La tabella è accessibile solo via Edge Functions con service_role key,
-- che bypassa RLS automaticamente. Quindi abilitiamo RLS senza policy
-- per bloccare completamente l'accesso da anon/authenticated.

ALTER TABLE "public"."notification_queue" ENABLE ROW LEVEL SECURITY;

-- Nessuna policy = nessun accesso per anon/authenticated
-- service_role bypassa RLS automaticamente
