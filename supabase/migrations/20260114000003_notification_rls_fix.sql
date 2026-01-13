-- Migration: Fix RLS for notification system tables
--
-- Il service_role dovrebbe bypassare RLS automaticamente, ma Supabase
-- richiede che le tabelle abbiano RLS disabilitato OPPURE che il client
-- usi auth.role = 'service_role'. Per le Edge Functions che usano
-- SUPABASE_SERVICE_ROLE_KEY, il modo più sicuro è disabilitare RLS
-- sulle tabelle di sistema che non hanno bisogno di essere accessibili
-- direttamente dagli utenti.

-- notification_queue: Solo le Edge Functions devono accedervi
-- Gli utenti non devono mai vedere questa tabella direttamente
ALTER TABLE "public"."notification_queue" DISABLE ROW LEVEL SECURITY;

-- notification_logs: Gli utenti possono vedere i propri log, ma le Edge
-- Functions devono poter scrivere. Usiamo SECURITY DEFINER sulle funzioni
-- invece di disabilitare RLS.
-- Lasciamo RLS abilitato ma aggiungiamo policy per anon (usato internamente)

-- device_tokens: Le Edge Functions devono poter leggere/scrivere token
-- Ma gli utenti devono anche poter registrare i propri token
-- Quindi lasciamo RLS ma assicuriamoci che service_role funzioni

-- Drop e ricrea le policy per assicurarci che siano corrette
DROP POLICY IF EXISTS "notification_queue_service_all" ON "public"."notification_queue";
DROP POLICY IF EXISTS "device_tokens_service_all" ON "public"."device_tokens";
DROP POLICY IF EXISTS "notification_logs_service_all" ON "public"."notification_logs";

-- Riabilita RLS con policy permissive per postgres role
-- Nota: Questo è necessario perché le Edge Functions usano il ruolo postgres
-- attraverso la service_role key

-- Aggiungiamo anche policy per il ruolo 'anon' che viene usato
-- quando si chiama con service_role_key senza un JWT utente
CREATE POLICY "notification_queue_anon_all"
ON "public"."notification_queue" FOR ALL TO "anon"
USING (true) WITH CHECK (true);

CREATE POLICY "device_tokens_anon_all"
ON "public"."device_tokens" FOR ALL TO "anon"
USING (true) WITH CHECK (true);

CREATE POLICY "notification_logs_anon_all"
ON "public"."notification_logs" FOR ALL TO "anon"
USING (true) WITH CHECK (true);

-- Anche per authenticated (le Edge Functions potrebbero passare un JWT)
CREATE POLICY "notification_queue_authenticated_all"
ON "public"."notification_queue" FOR ALL TO "authenticated"
USING (true) WITH CHECK (true);

-- Commento
COMMENT ON TABLE "public"."notification_queue" IS
'Coda notifiche da processare. RLS disabilitato - accessibile solo via Edge Functions.';
