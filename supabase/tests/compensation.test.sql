-- Compensi a mattoni: ogni mattone, il minimo garantito, il tetto orario, gli scaglioni, e il fatto
-- che ai volontari non si calcola nulla (art. 23 dello statuto, E6 del piano APS).

BEGIN;
SELECT plan(11);

-- Modello "storico": tutto l'incasso meno il 15% di sala, con il tetto di 40 €/h
INSERT INTO public.compensation_models (id, name, max_hourly_cents)
VALUES ('60000000-0000-0000-0000-000000000001', 'Test storico', 4000);
INSERT INTO public.compensation_components (model_id, kind, value_percent, display_order) VALUES
  ('60000000-0000-0000-0000-000000000001', 'percent_of_revenue', 100, 10),
  ('60000000-0000-0000-0000-000000000001', 'room_fee_percent',    15, 20);

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
  '4000', 'storico: 100 € di incassi meno il 15% di sala fa 85 €, ma il tetto orario lo porta a 40 €'
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

-- Un compenso non può essere negativo nemmeno se le trattenute superano tutto il resto
INSERT INTO public.compensation_models (id, name) VALUES
  ('60000000-0000-0000-0000-000000000004', 'Test solo trattenuta');
INSERT INTO public.compensation_components (model_id, kind, value_percent)
VALUES ('60000000-0000-0000-0000-000000000004', 'room_fee_percent', 20);

SELECT is(
  (internal.compute_compensation('60000000-0000-0000-0000-000000000004', 60, 5, 10000))->>'amount_cents',
  '0', 'se le trattenute superano il resto, il compenso è zero e non un debito'
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

SELECT * FROM finish();
ROLLBACK;
