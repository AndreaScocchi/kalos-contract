-- Categorizzazione servizi in 4 fasce (Fase 4 della nuova app, item E).
-- Classifica ogni attività in una delle 4 fasce di servizio: Comunità / Partners / Core / Esperienze.
-- Modifica ADDITIVA: nuovo enum + nuova colonna NOT NULL con DEFAULT 'core' (backfill automatico delle
-- righe esistenti → tutte 'core'; lo staff ricategorizza dal gestionale). Impatto zero sui consumer
-- esistenti (website, gestionale, PWA): l'INSERT che omette la colonna riceve il default.
-- Vedi docs/NEW_APP_PLAN.md §5 (item E) e §3 (disciplina additiva).

CREATE TYPE "public"."activity_category" AS ENUM (
    'comunita',
    'partners',
    'core',
    'esperienze'
);

ALTER TABLE "public"."activities"
    ADD COLUMN "category" "public"."activity_category" NOT NULL DEFAULT 'core';

COMMENT ON COLUMN "public"."activities"."category" IS '4 fasce di servizio: comunita, partners, core (default), esperienze. Vedi NEW_APP_PLAN.md item E.';
