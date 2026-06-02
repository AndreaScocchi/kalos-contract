-- Categoria notifica `feedback_request` (Fase 5 della nuova app, item D — raccolta automatica feedback).
-- Modifica ADDITIVA: aggiunge SOLO un valore all'enum `notification_category`. Impatto zero sui consumer
-- esistenti (website, gestionale, PWA): un enum esteso non rompe nessun codice che legge i valori vecchi.
--
-- NB Postgres: `ALTER TYPE … ADD VALUE` non può convivere nella stessa transazione con l'USO del nuovo
-- valore. Per questo la categoria viene aggiunta qui, ISOLATA, e usata solo dalla migrazione successiva
-- (`…_create_feedback.sql`), che gira in una transazione separata a valore già committato.
-- Vedi docs/NEW_APP_PLAN.md §5 (item D) e §3 (disciplina additiva).

ALTER TYPE "public"."notification_category" ADD VALUE IF NOT EXISTS 'feedback_request';
