-- Migration 20260928120000: valore nuovo per la sessione 9 (avviso allo staff per le prove dall'app)
--
-- Un valore enum, in un file a parte: Postgres non permette di usare un valore aggiunto con
-- ADD VALUE nella stessa transazione in cui lo si crea, e la migrazione `…120200_pagamenti_app.sql`
-- lo usa.
--
--   `notification_category.trial_booked_staff` — qualcunə ha prenotato una lezione di prova dall'app:
--   lo sanno gli admin e l'operatrice della lezione (F6). Le prove inserite dallo staff non lo mandano.
--
-- Compatibilità: solo ADD VALUE, nessun valore esistente cambia.

ALTER TYPE "public"."notification_category" ADD VALUE IF NOT EXISTS 'trial_booked_staff';
