-- Seed data per lo sviluppo locale
-- Questo file viene eseguito quando si fa `supabase db reset` o `supabase start`

-- Inserisci qui i dati di seed per il database locale
-- Esempio:
-- INSERT INTO public.profiles (id, full_name) VALUES ('00000000-0000-0000-0000-000000000000', 'Test User');


-- Pagamenti Stripe di prova (livemode = false): in locale scrivono incassi, ricevute e uscite, così
-- si prova il giro completo. Questo interruttore NON esiste in nessuna migrazione, quindi in
-- produzione non c'è: un pagamento di prova non tocca mai il registro vero, né la numerazione delle
-- ricevute. Vedi la migrazione 20260924100000_pagamenti_online.sql e STRIPE_SETUP.md.
INSERT INTO public.feature_flags (key, enabled, description)
VALUES ('stripe_test_ledger', true, 'SOLO IN LOCALE: i pagamenti Stripe di prova scrivono nel registro')
ON CONFLICT (key) DO UPDATE SET enabled = true;
