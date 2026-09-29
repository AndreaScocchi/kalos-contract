-- Migration 20260929180000: i piani «a disciplina» collegati alle loro attività
--
-- Un piano vale per le attività di `plan_activities`; se non ne ha, vale per tutte: così
-- `book_lesson`, `staff_book_lesson` e la nuova app. Il gestionale però salvava un piano con la sola
-- `discipline` e nessuna attività, come se coprisse le attività di quella disciplina (lo faceva la
-- webapp, il database no). Nel listino della nuova app quei piani finivano in «Per più attività» con
-- «Tutte le attività», e un abbonamento Mama Moves avrebbe prenotato anche lo yoga.
--
-- Qui ogni piano in listino con una disciplina e senza attività riceve le attività non eliminate
-- della stessa disciplina. I piani fuori listino restano come sono: nessun abbonamento attivo, e
-- la loro disciplina spesso non corrisponde più alle attività di oggi. Da questa versione il
-- gestionale salva sempre le attività del piano.

INSERT INTO "public"."plan_activities" ("plan_id", "activity_id")
SELECT p.id, a.id
FROM "public"."plans" p
JOIN "public"."activities" a
  ON a.discipline = p.discipline
 AND a.deleted_at IS NULL
WHERE p.is_active
  AND p.deleted_at IS NULL
  AND p.discipline IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM "public"."plan_activities" pa WHERE pa.plan_id = p.id
  )
ON CONFLICT DO NOTHING;
