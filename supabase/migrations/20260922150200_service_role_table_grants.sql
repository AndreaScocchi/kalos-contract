-- Migration 20260922150200: permessi standard per service_role, igiene dei default sulle tabelle
--
-- Obiettivo: service_role, la chiave delle edge function, aveva solo SELECT (o nulla) su 12
-- tabelle, fra cui clients, profiles, bookings, event_bookings. Le edge function che scrivono lì
-- fallivano, alcune in silenzio (scoperto nella sessione 1, 2026-09-22):
--   - unsubscribe-newsletter: la disiscrizione dava errore (0 disiscrizioni su 27 newsletter);
--   - ses-webhook / resend-webhook: i bounce permanenti non venivano mai segnati;
--   - delete-account: rispondeva "fatto" ma la scheda cliente restava attiva, con i dati.
-- Si ridanno a service_role i permessi standard di Supabase (SELECT, INSERT, UPDATE, DELETE) su
-- tutte le tabelle di public. service_role è la chiave segreta dei processi di sistema: non sta
-- in nessun client, e ignora comunque le RLS.
--
-- Igiene, stessa logica della migrazione precedente: via MAINTAIN (VACUUM, LOCK, REINDEX…) ad
-- anon e authenticated, che l'API non usa, e default per le tabelle future: service_role le vede,
-- anon e authenticated non ricevono privilegi che l'API non usa. I grant ad anon e authenticated
-- delle tabelle nuove restano espliciti, nella migrazione che le crea (ACCESS_MODEL.md).
--
-- Compatibilità: solo aggiunte per service_role; a anon e authenticated si tolgono privilegi che
-- nessun consumer può usare tramite l'API.
--
-- migration-lint:allow revoke — reason: MAINTAIN e default privileges di anon/authenticated non sono usabili dall'API; nessun consumer ne dipende
-- migration-lint:allow truncate — reason: TRUNCATE compare solo come nome del privilegio nei default privileges, nessun dato viene cancellato

-- 1. service_role: permessi standard sulle tabelle esistenti
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA "public" TO "service_role";

-- 2. MAINTAIN non serve all'API
REVOKE MAINTAIN ON ALL TABLES IN SCHEMA "public" FROM "anon", "authenticated";

-- 3. Tabelle future create da postgres in public
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
  REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLES FROM "anon", "authenticated";
