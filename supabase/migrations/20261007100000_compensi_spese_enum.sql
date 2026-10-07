-- Migration 20261007100000: spese della lezione nei modelli di compenso (valori dell'enum)
--
-- Richiesta del 07/10 per Yoga e Meditazione: dagli incassi della lezione si tolgono le spese fisse
-- (affitto sala, usura materiali, accoglienza), quello che resta va all'insegnante fino a 40 € e il
-- resto allo Studio. Nel modulo, poi, «Trattenuta sala» stava fra i modi di pagare chi insegna pur
-- essendo una spesa: le spese diventano una famiglia a parte di mattoni, `cost_*`.
--
--   cost_per_lesson, cost_per_hour, cost_per_participant   spese fisse a lezione, all'ora, a persona
--   cost_percent_of_revenue                                 la vecchia `room_fee_percent`, rinominata
--   percent_of_margin                                       compenso: percentuale di quello che resta
--
-- In produzione non c'è ancora nessun modello (verificato il 07/10): rinominare il valore non cambia
-- dati. In un file a parte perché un valore nuovo di un enum non si può usare nella stessa transazione.

ALTER TYPE "public"."compensation_component_kind" ADD VALUE IF NOT EXISTS 'percent_of_margin';
ALTER TYPE "public"."compensation_component_kind" ADD VALUE IF NOT EXISTS 'cost_per_lesson';
ALTER TYPE "public"."compensation_component_kind" ADD VALUE IF NOT EXISTS 'cost_per_hour';
ALTER TYPE "public"."compensation_component_kind" ADD VALUE IF NOT EXISTS 'cost_per_participant';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
         WHERE t.typname = 'compensation_component_kind' AND e.enumlabel = 'room_fee_percent'
    ) THEN
        ALTER TYPE "public"."compensation_component_kind" RENAME VALUE 'room_fee_percent' TO 'cost_percent_of_revenue';
    END IF;
END $$;
