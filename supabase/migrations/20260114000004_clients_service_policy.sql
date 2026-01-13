-- Migration: Add service role policy for clients table
--
-- La Edge Function process-notification-queue fa un JOIN con clients
-- per ottenere email e full_name. Serve una policy che permetta
-- l'accesso al service role.

-- Aggiungi policy per anon (usato quando si chiama con service_role_key)
CREATE POLICY "clients_anon_select"
ON "public"."clients" FOR SELECT TO "anon"
USING (true);

-- Questo permette alle Edge Functions di leggere i dati dei clienti
-- per inviare notifiche email.
