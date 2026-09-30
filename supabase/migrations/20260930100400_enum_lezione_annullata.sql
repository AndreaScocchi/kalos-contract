-- Migration 20260930100400: categoria di notifica «lezione annullata»
--
-- Serve a `staff_archive_lessons` (migrazione successiva): quando lo staff archivia una lezione
-- futura con delle prenotazioni, chi era prenotatə riceve «Lezione annullata» e l'ingresso torna
-- all'abbonamento. È un messaggio di servizio: arriva sempre (push o email), come le conferme.
-- In un file a parte perché un valore nuovo di un enum non si può usare nella stessa transazione.

ALTER TYPE "public"."notification_category" ADD VALUE IF NOT EXISTS 'lesson_canceled';
