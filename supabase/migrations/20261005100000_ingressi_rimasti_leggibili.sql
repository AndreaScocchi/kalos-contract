-- Migration 20261005100000: la view degli ingressi rimasti è leggibile con il login
--
-- Dal 30/09/2026 il gestionale legge gli ingressi rimasti in blocco da `subscriptions_with_remaining`
-- (Dashboard, Abbonamenti, Clienti, prenotazioni della lezione e dell'evento) invece di fare una
-- richiesta per riga. La view però non ha mai avuto un GRANT esplicito e, con i default privileges
-- del 22/09 («tutto chiuso»), la leggeva solo service_role: quelle pagine ricevevano
-- `permission denied` (42501). Dashboard e Abbonamenti mostravano l'errore, la pagina della lezione
-- nessuna prenotazione.
--
-- È `security_invoker`: valgono le RLS di `subscriptions`, `plans` e `subscription_usages`. Lo staff
-- vede gli ingressi di tutti, ciascun cliente solo i propri, come leggendo `subscriptions`. anon
-- resta fuori.

GRANT SELECT ON TABLE "public"."subscriptions_with_remaining" TO "authenticated";
