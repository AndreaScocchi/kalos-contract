-- Migration 20260924150000: valori nuovi per la sessione 6 (prove e questionario)
--
-- Due valori enum, in un file a parte: Postgres non permette di usare un valore aggiunto con
-- ADD VALUE nella stessa transazione in cui lo si crea, e la migrazione successiva
-- (`…150100_gruppi_luoghi_prove.sql`) li usa in funzioni e vincoli.
--
--   1. `notification_category.trial_booked` — conferma della lezione di prova inserita dallo staff,
--      con l'invito all'app (F5).
--   2. `feedback_kind.trial` — il questionario dopo la prova (F6). Le risposte si raccolgono
--      dall'app nella sessione 11; il gestionale le mostra da subito.
--
-- Compatibilità: solo ADD VALUE, nessun valore esistente cambia.

ALTER TYPE "public"."notification_category" ADD VALUE IF NOT EXISTS 'trial_booked';
ALTER TYPE "public"."feedback_kind" ADD VALUE IF NOT EXISTS 'trial';
