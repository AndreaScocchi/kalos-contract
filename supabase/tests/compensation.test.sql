-- Compensi a mattoni: le spese della lezione, ogni mattone, il minimo garantito, i tetti (a lezione e
-- orario), gli scaglioni, quello che resta allo Studio, e il fatto che ai volontari non si calcola
-- nulla (art. 23 dello statuto, E6 del piano APS).

BEGIN;
SELECT plan(27);

-- Modello "storico": tutto quello che resta dopo il 15% di sala, con il tetto di 40 €/h
INSERT INTO public.compensation_models (id, name, max_hourly_cents)
VALUES ('60000000-0000-0000-0000-000000000001', 'Test storico', 4000);
INSERT INTO public.compensation_components (model_id, kind, value_percent, display_order) VALUES
  ('60000000-0000-0000-0000-000000000001', 'cost_percent_of_revenue', 15, 10),
  ('60000000-0000-0000-0000-000000000001', 'percent_of_margin',      100, 20);

-- Modello "a mattoni": 15 € fissi + 2 € a partecipante, minimo 25 €, +10 € da 8 persone in su
INSERT INTO public.compensation_models (id, name, min_guaranteed_cents)
VALUES ('60000000-0000-0000-0000-000000000002', 'Test mattoni', 2500);
INSERT INTO public.compensation_components (model_id, kind, value_cents, display_order) VALUES
  ('60000000-0000-0000-0000-000000000002', 'fixed_per_lesson', 1500, 10),
  ('60000000-0000-0000-0000-000000000002', 'per_participant',   200, 20);
INSERT INTO public.compensation_tiers (model_id, min_participants, max_participants, amount_cents)
VALUES ('60000000-0000-0000-0000-000000000002', 8, NULL, 1000);

-- Modello a ore
INSERT INTO public.compensation_models (id, name) VALUES
  ('60000000-0000-0000-0000-000000000003', 'Test a ore');
INSERT INTO public.compensation_components (model_id, kind, value_cents)
VALUES ('60000000-0000-0000-0000-000000000003', 'fixed_per_hour', 3000);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000001', 60, 5, 10000))->>'amount_cents',
  '4000', 'storico: 100 € di incassi meno il 15% di sala lascia 85 €, ma il tetto orario lo porta a 40 €'
);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000001', 90, 9, 20000))->>'amount_cents',
  '6000', 'il tetto orario si riproporziona sulla durata: 90 minuti valgono 60 €'
);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000001', 60, 2, 2000))->>'amount_cents',
  '1700', 'sotto il tetto vale il conto vero: 20 € meno il 15% di sala'
);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000002', 60, 3, 0))->>'amount_cents',
  '2500', 'mattoni: 15 € + 6 € starebbero sotto il minimo garantito, che vince'
);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000002', 60, 5, 0))->>'amount_cents',
  '2500', 'mattoni: 15 € + 10 € fa esattamente il minimo'
);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000002', 60, 8, 0))->>'amount_cents',
  '4100', 'mattoni: da 8 persone si aggiunge lo scaglione'
);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000003', 90, 0, 0))->>'amount_cents',
  '4500', 'a ore: 30 €/h per 90 minuti fa 45 €'
);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000003', 30, 0, 0))->>'amount_cents',
  '1500', 'a ore: mezz''ora vale metà'
);

-- ── Spese della lezione: il foglio di Yoga e Meditazione ─────────────────────
-- Incassi − affitto sala 4 € − usura materiali 3 € − accoglienza 1 € = quello che resta;
-- all'insegnante quello che resta fino a 40 € a lezione, il resto allo Studio
INSERT INTO public.compensation_models (id, name, max_per_lesson_cents)
VALUES ('60000000-0000-0000-0000-000000000005', 'Test Yoga e Meditazione', 4000);
INSERT INTO public.compensation_components (model_id, kind, value_cents, value_percent, display_order, note) VALUES
  ('60000000-0000-0000-0000-000000000005', 'cost_per_lesson',   400, NULL, 10, 'Affitto sala'),
  ('60000000-0000-0000-0000-000000000005', 'cost_per_lesson',   300, NULL, 20, 'Usura materiali'),
  ('60000000-0000-0000-0000-000000000005', 'cost_per_lesson',   100, NULL, 30, 'Accoglienza'),
  ('60000000-0000-0000-0000-000000000005', 'percent_of_margin', NULL, 100, 40, NULL);

SELECT is(
  (SELECT r->>'costs_cents' || '|' || (r->>'margin_cents') || '|' || (r->>'amount_cents') || '|' || (r->>'studio_cents')
     FROM internal.compute_compensation('60000000-0000-0000-0000-000000000005', 60, 4, 5200) r),
  '800|4400|4000|400', 'Yoga: 52 € − 8 € di spese = 44 €; 40 € all''insegnante, 4 € allo Studio'
);

SELECT is(
  (SELECT string_agg(c->>'note' || ' ' || (c->>'amount_cents'), ', ' ORDER BY ord)
     FROM jsonb_array_elements(internal.compute_compensation('60000000-0000-0000-0000-000000000005', 60, 4, 5200)->'costs')
          WITH ORDINALITY AS x(c, ord)),
  'Affitto sala 400, Usura materiali 300, Accoglienza 100', 'il dettaglio elenca ogni spesa col suo nome, nell''ordine del modello'
);

SELECT is(
  (SELECT (r->>'amount_cents') || '|' || (r->>'studio_cents')
     FROM internal.compute_compensation('60000000-0000-0000-0000-000000000005', 60, 3, 3900) r),
  '3100|0', 'Yoga: con 39 € di incassi restano 31 €, tutti all''insegnante, niente allo Studio'
);

SELECT is(
  (SELECT (r->>'amount_cents') || '|' || (r->>'studio_cents')
     FROM internal.compute_compensation('60000000-0000-0000-0000-000000000005', 60, 1, 500) r),
  '0|-300', 'Yoga: se le spese superano gli incassi il compenso è zero e lo Studio ci rimette la differenza'
);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000005', 75, 6, 7800))->>'amount_cents',
  '4000', 'il tetto a lezione non cresce con la durata: 75 minuti restano 40 €'
);

SELECT is(
  (SELECT c->>'kind' || ' ' || (c->>'amount_cents')
     FROM jsonb_array_elements(internal.compute_compensation('60000000-0000-0000-0000-000000000005', 60, 4, 5200)->'components') c
    WHERE c->>'kind' = 'max_lesson_cap'),
  'max_lesson_cap -400', 'il dettaglio dice quanto ha tolto il tetto a lezione'
);

-- Spese all'ora e a persona; un compenso fisso non lo toccano: pesano solo su quello che resta allo Studio
INSERT INTO public.compensation_models (id, name) VALUES
  ('60000000-0000-0000-0000-000000000006', 'Test spese e fisso');
INSERT INTO public.compensation_components (model_id, kind, value_cents, display_order, note) VALUES
  ('60000000-0000-0000-0000-000000000006', 'cost_per_hour',         400, 10, 'Affitto orario'),
  ('60000000-0000-0000-0000-000000000006', 'cost_per_participant',  100, 20, 'Tisane'),
  ('60000000-0000-0000-0000-000000000006', 'fixed_per_lesson',     2000, 30, NULL);

SELECT is(
  (SELECT r->>'costs_cents' || '|' || (r->>'amount_cents') || '|' || (r->>'studio_cents')
     FROM internal.compute_compensation('60000000-0000-0000-0000-000000000006', 90, 5, 6000) r),
  '1100|2000|2900', 'spese 6 € (90 minuti a 4 €/h) + 5 € (5 persone): il fisso resta 20 €, allo Studio 29 €'
);

-- La percentuale di quello che resta non va sotto zero e non mangia gli altri mattoni
INSERT INTO public.compensation_models (id, name) VALUES
  ('60000000-0000-0000-0000-000000000004', 'Test spese oltre gli incassi');
INSERT INTO public.compensation_components (model_id, kind, value_cents, value_percent, display_order) VALUES
  ('60000000-0000-0000-0000-000000000004', 'cost_per_lesson',   2000, NULL, 10),
  ('60000000-0000-0000-0000-000000000004', 'fixed_per_lesson',  1000, NULL, 20),
  ('60000000-0000-0000-0000-000000000004', 'percent_of_margin', NULL,   50, 30);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000004', 60, 1, 1500))->>'amount_cents',
  '1000', 'se le spese superano gli incassi la percentuale di quello che resta vale zero, il fisso resta'
);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000004', 60, 5, 6000))->>'amount_cents',
  '3000', 'con 60 € di incassi e 20 € di spese: 10 € fissi + metà dei 40 € che restano'
);

-- Con tutti e due i tetti vale il più basso
INSERT INTO public.compensation_models (id, name, max_per_lesson_cents, max_hourly_cents) VALUES
  ('60000000-0000-0000-0000-000000000007', 'Test due tetti', 4000, 3000);
INSERT INTO public.compensation_components (model_id, kind, value_percent)
VALUES ('60000000-0000-0000-0000-000000000007', 'percent_of_revenue', 100);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000007', 60, 8, 10000))->>'amount_cents',
  '3000', 'un''ora: il tetto orario (30 €) è più basso di quello a lezione (40 €) e vince'
);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000007', 120, 8, 10000))->>'amount_cents',
  '4000', 'due ore: il tetto orario sarebbe 60 €, quello a lezione (40 €) è più basso e vince'
);

-- Il vincolo sul tipo di valore vale anche per le spese
SELECT throws_ok(
  $$INSERT INTO public.compensation_components (model_id, kind, value_percent)
    VALUES ('60000000-0000-0000-0000-000000000007', 'cost_per_lesson', 10)$$,
  '23514', NULL, 'una spesa a lezione vuole un importo, non una percentuale'
);

SELECT throws_ok(
  $$INSERT INTO public.compensation_components (model_id, kind, value_cents)
    VALUES ('60000000-0000-0000-0000-000000000007', 'percent_of_margin', 1000)$$,
  '23514', NULL, 'la percentuale di quello che resta vuole una percentuale, non un importo'
);

-- ── Volontari esclusi ────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('13000000-0000-0000-0000-000000000001', 'tesoriera2@test.kalos', '{"full_name":"Tesoriera"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'finance' WHERE id = '13000000-0000-0000-0000-000000000001';

INSERT INTO public.operators (id, name, role, engagement_type) VALUES
  ('70000000-0000-0000-0000-000000000001', 'Retribuita Test', 'istruttrice', 'paid'),
  ('70000000-0000-0000-0000-000000000002', 'Volontaria Test', 'istruttrice', 'volunteer');
INSERT INTO public.activities (id, name, discipline, duration_minutes)
VALUES ('22000000-0000-0000-0000-000000000001', 'Test Compensi', 'test_compensi', 60);
INSERT INTO public.lessons (id, activity_id, operator_id, starts_at, ends_at, capacity) VALUES
  ('32000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001',
   '70000000-0000-0000-0000-000000000001', date_trunc('month', now()) + interval '2 days',
   date_trunc('month', now()) + interval '2 days 1 hour', 10),
  ('32000000-0000-0000-0000-000000000002', '22000000-0000-0000-0000-000000000001',
   '70000000-0000-0000-0000-000000000002', date_trunc('month', now()) + interval '3 days',
   date_trunc('month', now()) + interval '3 days 1 hour', 10);
INSERT INTO public.compensation_assignments (operator_id, model_id, valid_from) VALUES
  ('70000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000002', CURRENT_DATE - 30),
  ('70000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000002', CURRENT_DATE - 30);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"13000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(
  (SELECT count(*)::int FROM public.calculate_compensation_v2(
     date_trunc('month', CURRENT_DATE)::date,
     (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date)
    WHERE operator_id = '70000000-0000-0000-0000-000000000002'),
  0, 'a chi è volontariə non si calcola nessun compenso'
);

SELECT is(
  (SELECT count(*)::int FROM public.calculate_compensation_v2(
     date_trunc('month', CURRENT_DATE)::date,
     (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date)
    WHERE operator_id = '70000000-0000-0000-0000-000000000001'),
  1, 'a chi è retribuitə sì'
);
RESET ROLE;

-- ── Salvataggio dal gestionale: spese col loro nome e tetto a lezione ───────
-- (come postgres con l'identità della Tesoriera, per tenere l'id in una tabella temporanea)
CREATE TEMP TABLE yoga_model AS
SELECT public.staff_save_compensation_model(jsonb_build_object(
    'name', 'Yoga e Meditazione',
    'max_per_lesson_cents', 4000,
    'components', jsonb_build_array(
       jsonb_build_object('kind', 'cost_per_lesson', 'value_cents', 400, 'note', 'Affitto sala'),
       jsonb_build_object('kind', 'cost_per_lesson', 'value_cents', 300, 'note', ' Usura materiali '),
       jsonb_build_object('kind', 'cost_per_lesson', 'value_cents', 100, 'note', 'Accoglienza'),
       jsonb_build_object('kind', 'percent_of_margin', 'value_percent', 100)))) AS r;

SELECT is((SELECT r->>'ok' FROM yoga_model), 'true', 'un modello con le spese si salva in un colpo solo');

SELECT is(
  (SELECT string_agg(c.note, ', ' ORDER BY c.display_order) || '|' || m.max_per_lesson_cents
     FROM yoga_model y
     JOIN public.compensation_models m ON m.id = (y.r->>'model_id')::uuid
     JOIN public.compensation_components c ON c.model_id = m.id AND c.kind = 'cost_per_lesson'
    GROUP BY m.max_per_lesson_cents),
  'Affitto sala, Usura materiali, Accoglienza|4000', 'restano i nomi delle spese (senza spazi in più) e il tetto a lezione'
);

SELECT is(
  (SELECT p->>'amount_cents' || '|' || (p->>'studio_cents')
     FROM yoga_model y, public.preview_compensation((y.r->>'model_id')::uuid, 60, 4, 5200) p),
  '4000|400', 'la prova del modello dà anche quello che resta allo Studio'
);

SELECT is(
  public.staff_save_compensation_model(jsonb_build_object(
    'name', 'Spesa sbagliata',
    'components', jsonb_build_array(jsonb_build_object('kind', 'cost_per_lesson', 'value_percent', 10))))->>'reason',
  'INVALID_MODEL', 'una spesa scritta male fa rifiutare il modello'
);

SELECT * FROM finish();
ROLLBACK;
