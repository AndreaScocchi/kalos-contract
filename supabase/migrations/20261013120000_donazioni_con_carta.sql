-- Migration 20261013120000: interruttore `card_donations`, donazioni con carta spente
--
-- Il 05/10/2026 Stripe ha fermato gli accrediti sul conto: secondo la sua verifica l'associazione è
-- un ente benefico senza registrazione (per l'Italia, il RUNTS), categoria che i suoi termini
-- vietano. I pagamenti con carta si fermano il 04/11 se non si risponde. Dal 01/10 su Stripe sono
-- arrivate solo quote e abbonamenti, nessuna donazione: il 13/10 l'utente ha deciso di togliere la
-- donazione con carta finché l'iscrizione al RUNTS non è perfezionata. Resta il bonifico.
--
-- Prima la donazione con carta seguiva solo `payments`, che però regge anche quota, abbonamenti ed
-- eventi. Da qui ha un interruttore suo, letto dal sito (`/donazioni` nasconde il modulo) e da
-- `stripe-checkout` (lo scopo `donation` risponde DONATIONS_DISABLED). Si riaccende dopo il RUNTS
-- e dopo averlo comunicato a Stripe.

INSERT INTO "public"."feature_flags" ("key", "enabled", "description") VALUES
    ('card_donations', false,
     'Donazioni con carta su /donazioni (Stripe), oltre a `payments`. Spente dal 13/10/2026 su richiesta di Stripe (ente non ancora iscritto al RUNTS): da riaccendere dopo l''iscrizione e dopo averla comunicata a Stripe.')
ON CONFLICT ("key") DO NOTHING;
