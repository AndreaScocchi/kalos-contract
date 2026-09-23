-- Migration 20260923160000: nuove categorie di notifica per il modello APS (sessione 3)
--
-- Obiettivo: aggiungere i valori dell'enum `notification_category` che servono ai blocchi successivi
-- di questa sessione:
--   1. `waitlist_promotion`          — si è liberato un posto, la lista d'attesa avanza (H5)
--   2. `member_application_decided`  — il Consiglio Direttivo ha deliberato sulla domanda (A7)
--   3. `membership_fee_due`          — la quota associativa dell'anno è da pagare (A8)
--   4. `trial_followup`              — messaggio dopo la lezione di prova, con link ai piani (F6)
--
-- NB Postgres: `ALTER TYPE … ADD VALUE` non può convivere nella stessa transazione con l'USO del nuovo
-- valore. Per questo i valori stanno qui, ISOLATI, e vengono usati solo dalle migrazioni successive,
-- che girano in transazioni separate a valore già committato. Stesso schema di
-- `20260603100000_add_feedback_request_notification_category.sql`.
--
-- Compatibilità: puramente additiva. Un enum esteso non rompe nessun consumer che legge i valori
-- vecchi; nessuna riga esistente cambia. Vedi docs/PIANO-APS-E-NUOVA-APP.md §4 (sessione 3).

ALTER TYPE "public"."notification_category" ADD VALUE IF NOT EXISTS 'waitlist_promotion';
ALTER TYPE "public"."notification_category" ADD VALUE IF NOT EXISTS 'member_application_decided';
ALTER TYPE "public"."notification_category" ADD VALUE IF NOT EXISTS 'membership_fee_due';
ALTER TYPE "public"."notification_category" ADD VALUE IF NOT EXISTS 'trial_followup';
