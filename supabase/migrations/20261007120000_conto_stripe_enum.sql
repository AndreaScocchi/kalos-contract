-- Migration 20261007120000: Stripe diventa un conto (valore dell'enum)
--
-- In un file a parte perché un valore nuovo di un enum non si può usare nella stessa transazione in
-- cui lo si aggiunge: lo usano la migrazione successiva (`20261007120100_conto_stripe.sql`) e il suo
-- vincolo su `account_transfers`.

ALTER TYPE "public"."cash_account" ADD VALUE IF NOT EXISTS 'stripe';

COMMENT ON TYPE "public"."cash_account" IS
    'I conti dell''associazione: cassa (contanti), banca (conto corrente) e stripe (i pagamenti con carta incassati e non ancora accreditati sul conto). Nel rendiconto il saldo di Stripe sta con i depositi bancari.';
