-- Il modello di compenso predefinito (migrazione 20261007160000): vale per chi non ha un modello
-- assegnato (lezioni ed eventi), le assegnazioni e il modello dell'evento vincono, i volontari restano
-- esclusi, il predefinito si cambia solo dalle Finanze e resta uno solo e sempre attivo. Il modello di
-- prova è quello della richiesta: affitto sala 4 €, usura materiali 3 €, accoglienza 1 €, il resto
-- all'insegnante fino a 40 € a lezione.

BEGIN;
SELECT plan(26);

-- ── Persone, lezioni ed eventi del mese scorso ───────────────────────────────

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('0d160000-0000-0000-0000-000000000001', 'v316-tesoriere@test.kalos', '{"full_name":"Tesoriere 316"}', 'authenticated', 'authenticated'),
  ('0d160000-0000-0000-0000-000000000002', 'v316-operatrice@test.kalos', '{"full_name":"Operatrice 316"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'finance'  WHERE id = '0d160000-0000-0000-0000-000000000001';
UPDATE public.profiles SET role = 'operator' WHERE id = '0d160000-0000-0000-0000-000000000002';

INSERT INTO public.operators (id, name, role, engagement_type) VALUES
  ('0d161000-0000-0000-0000-000000000001', 'V316 Senza assegnazione', 'istruttrice', 'paid'),
  ('0d161000-0000-0000-0000-000000000002', 'V316 Assegnata', 'istruttrice', 'paid'),
  ('0d161000-0000-0000-0000-000000000003', 'V316 Volontaria', 'istruttrice', 'volunteer'),
  ('0d161000-0000-0000-0000-000000000004', 'V316 Per attività', 'istruttrice', 'paid');

-- Il test non presuppone un database senza predefinito
UPDATE public.compensation_models SET is_default = false WHERE is_default;

INSERT INTO public.compensation_models (id, name, max_per_lesson_cents) VALUES
  ('0d168000-0000-0000-0000-000000000003', 'V316 Base', 4000);
INSERT INTO public.compensation_components (model_id, kind, value_cents, value_percent, display_order, note) VALUES
  ('0d168000-0000-0000-0000-000000000003', 'cost_per_lesson',   400, NULL, 10, 'Affitto sala'),
  ('0d168000-0000-0000-0000-000000000003', 'cost_per_lesson',   300, NULL, 20, 'Usura materiali'),
  ('0d168000-0000-0000-0000-000000000003', 'cost_per_lesson',   100, NULL, 30, 'Accoglienza'),
  ('0d168000-0000-0000-0000-000000000003', 'percent_of_margin', NULL, 100, 40, NULL);
INSERT INTO public.compensation_models (id, name) VALUES
  ('0d168000-0000-0000-0000-000000000001', 'V316 Fisso 30');
INSERT INTO public.compensation_components (model_id, kind, value_cents)
VALUES ('0d168000-0000-0000-0000-000000000001', 'fixed_per_lesson', 3000);
INSERT INTO public.compensation_models (id, name, is_active) VALUES
  ('0d168000-0000-0000-0000-000000000002', 'V316 Disattivato', false);

INSERT INTO public.activities (id, name, discipline, duration_minutes) VALUES
  ('0d162000-0000-0000-0000-000000000001', 'V316 Yoga', 'v316_yoga', 60),
  ('0d162000-0000-0000-0000-000000000002', 'V316 Meditazione', 'v316_meditazione', 60);
INSERT INTO public.plans (id, name, price_cents, entries, validity_days)
VALUES ('0d163000-0000-0000-0000-000000000001', 'V316 Ingresso', 5200, 1, 90);
INSERT INTO public.clients (id, full_name, email)
VALUES ('0d164000-0000-0000-0000-000000000001', 'Cliente 316', 'v316-cliente@test.kalos');
INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at) VALUES
  ('0d165000-0000-0000-0000-000000000001', '0d164000-0000-0000-0000-000000000001', '0d163000-0000-0000-0000-000000000001',
   (date_trunc('month', now()) - interval '2 months')::date, (date_trunc('month', now()) + interval '2 months')::date);

-- L'operatrice per attività ha il fisso solo per la Meditazione: per lo Yoga vale il predefinito
INSERT INTO public.compensation_assignments (operator_id, activity_id, model_id, valid_from) VALUES
  ('0d161000-0000-0000-0000-000000000002', NULL, '0d168000-0000-0000-0000-000000000001', '2020-01-01'),
  ('0d161000-0000-0000-0000-000000000004', '0d162000-0000-0000-0000-000000000002', '0d168000-0000-0000-0000-000000000001', '2020-01-01');

INSERT INTO public.lessons (id, activity_id, operator_id, starts_at, ends_at, capacity)
SELECT v.id, v.activity_id, v.operator_id,
       date_trunc('month', now()) - interval '1 month' + v.offs,
       date_trunc('month', now()) - interval '1 month' + v.offs + interval '1 hour', 10
  FROM (VALUES
    ('0d166000-0000-0000-0000-000000000001'::uuid, '0d162000-0000-0000-0000-000000000001'::uuid, '0d161000-0000-0000-0000-000000000001'::uuid, interval '5 days 16 hours'),
    ('0d166000-0000-0000-0000-000000000002'::uuid, '0d162000-0000-0000-0000-000000000001'::uuid, '0d161000-0000-0000-0000-000000000002'::uuid, interval '6 days 16 hours'),
    ('0d166000-0000-0000-0000-000000000003'::uuid, '0d162000-0000-0000-0000-000000000001'::uuid, '0d161000-0000-0000-0000-000000000003'::uuid, interval '7 days 16 hours'),
    ('0d166000-0000-0000-0000-000000000004'::uuid, '0d162000-0000-0000-0000-000000000001'::uuid, '0d161000-0000-0000-0000-000000000004'::uuid, interval '8 days 16 hours'),
    ('0d166000-0000-0000-0000-000000000005'::uuid, '0d162000-0000-0000-0000-000000000002'::uuid, '0d161000-0000-0000-0000-000000000004'::uuid, interval '9 days 16 hours')
  ) AS v(id, activity_id, operator_id, offs);
INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status) VALUES
  ('0d166000-0000-0000-0000-000000000001', '0d164000-0000-0000-0000-000000000001', '0d165000-0000-0000-0000-000000000001', 'attended');

-- Due eventi della persona senza assegnazione: uno senza modello suo, uno con il fisso
INSERT INTO public.events (id, name, starts_at, ends_at, price_cents) VALUES
  ('0d167000-0000-0000-0000-000000000001', 'V316 Laboratorio',
   date_trunc('month', now()) - interval '1 month' + interval '12 days 15 hours',
   date_trunc('month', now()) - interval '1 month' + interval '12 days 17 hours', 2000),
  ('0d167000-0000-0000-0000-000000000002', 'V316 Ritiro',
   date_trunc('month', now()) - interval '1 month' + interval '13 days 15 hours',
   date_trunc('month', now()) - interval '1 month' + interval '13 days 17 hours', 2000);
INSERT INTO public.event_bookings (event_id, client_id) VALUES
  ('0d167000-0000-0000-0000-000000000001', '0d164000-0000-0000-0000-000000000001');
INSERT INTO public.event_operators (event_id, operator_id, model_id) VALUES
  ('0d167000-0000-0000-0000-000000000001', '0d161000-0000-0000-0000-000000000001', NULL),
  ('0d167000-0000-0000-0000-000000000002', '0d161000-0000-0000-0000-000000000001', '0d168000-0000-0000-0000-000000000001');

CREATE TEMP TABLE v316_month AS
SELECT (date_trunc('month', now()) - interval '1 month')::date AS m_start,
       (date_trunc('month', now()) - interval '1 day')::date AS m_end;
GRANT SELECT ON v316_month TO authenticated;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"0d160000-0000-0000-0000-000000000001","role":"authenticated"}';

-- ── Senza predefinito come prima, poi il predefinito ─────────────────────────

SELECT is(
  (SELECT (model_id IS NULL) || '|' || amount_cents || '|' || (breakdown->>'reason')
     FROM v316_month, public.calculate_compensation_v2(m_start, m_end, '0d161000-0000-0000-0000-000000000001')
    WHERE lesson_id = '0d166000-0000-0000-0000-000000000001'),
  'true|0|NO_MODEL', 'senza predefinito, chi non ha un modello assegnato resta «senza modello» come prima');

SELECT is(
  public.staff_set_default_compensation_model('0d168000-0000-0000-0000-000000000003')->>'reason',
  'SAVED', 'le Finanze scelgono il modello predefinito');

SELECT is(
  (SELECT string_agg(name, ', ') FROM public.compensation_models WHERE is_default),
  'V316 Base', '…ed è l''unico predefinito');

SELECT is(
  (SELECT r->>'costs_cents' || '|' || (r->>'margin_cents') || '|' || (r->>'amount_cents') || '|' || (r->>'studio_cents')
     FROM public.preview_compensation('0d168000-0000-0000-0000-000000000003', 60, 4, 5200) r),
  '800|4400|4000|400', '52 € di incassi: 8 € di spese, restano 44 €; 40 € all''insegnante, 4 € all''Associazione');

SELECT is(
  (SELECT (r->>'amount_cents') || '|' || (r->>'studio_cents')
     FROM public.preview_compensation('0d168000-0000-0000-0000-000000000003', 75, 3, 3900) r),
  '3100|0', 'sotto il tetto va tutto all''insegnante, anche in una lezione da 75 minuti');

-- ── Quale modello vale ───────────────────────────────────────────────────────

SELECT is(
  (SELECT model_name || '|' || amount_cents || '|' || (breakdown->>'studio_cents')
     FROM v316_month, public.calculate_compensation_v2(m_start, m_end, '0d161000-0000-0000-0000-000000000001')
    WHERE lesson_id = '0d166000-0000-0000-0000-000000000001'),
  'V316 Base|4000|400', 'senza assegnazione vale il predefinito: 52 € di incassi, 40 € all''insegnante');

SELECT is(
  (SELECT model_name || '|' || amount_cents
     FROM v316_month, public.calculate_compensation_v2(m_start, m_end, '0d161000-0000-0000-0000-000000000002')
    WHERE lesson_id = '0d166000-0000-0000-0000-000000000002'),
  'V316 Fisso 30|3000', 'un modello assegnato alla persona vince sul predefinito');

SELECT is(
  (SELECT string_agg(title || ':' || model_name, ', ' ORDER BY occurred_at)
     FROM v316_month, public.calculate_compensation_v2(m_start, m_end, '0d161000-0000-0000-0000-000000000004')),
  'V316 Yoga:V316 Base, V316 Meditazione:V316 Fisso 30',
  'con un modello solo per un''attività, le altre attività usano il predefinito');

SELECT is(
  (SELECT count(*)::int
     FROM v316_month, public.calculate_compensation_v2(m_start, m_end, '0d161000-0000-0000-0000-000000000003')),
  0, 'a chi è volontariə il predefinito non dà nessun compenso');

SELECT is(
  (SELECT model_name || '|' || amount_cents
     FROM v316_month, public.calculate_compensation_v2(m_start, m_end, '0d161000-0000-0000-0000-000000000001')
    WHERE event_id = '0d167000-0000-0000-0000-000000000001'),
  'V316 Base|1200', 'anche un evento senza modello suo usa il predefinito: 20 € − 8 € di spese');

SELECT is(
  (SELECT model_name || '|' || amount_cents
     FROM v316_month, public.calculate_compensation_v2(m_start, m_end, '0d161000-0000-0000-0000-000000000001')
    WHERE event_id = '0d167000-0000-0000-0000-000000000002'),
  'V316 Fisso 30|3000', 'il modello scelto per un evento vince sul predefinito');

SELECT is(
  (SELECT r->>'inserted' || '|' || (r->>'no_model')
     FROM (SELECT public.staff_freeze_compensation(m_start, m_end, '0d161000-0000-0000-0000-000000000001') AS r FROM v316_month) x),
  '3|0', 'con il predefinito non resta niente «senza modello»: si congelano la lezione e i due eventi');

-- ── Cambiare il predefinito ──────────────────────────────────────────────────

SELECT is(
  public.staff_set_default_compensation_model('0d168000-0000-0000-0000-000000000001')->>'reason',
  'SAVED', 'il predefinito si cambia con un altro modello');

SELECT is(
  (SELECT string_agg(name, ', ') FROM public.compensation_models WHERE is_default),
  'V316 Fisso 30', '…e il predefinito resta uno solo');

SELECT is(
  (SELECT model_name || '|' || amount_cents
     FROM v316_month, public.calculate_compensation_v2(m_start, m_end, '0d161000-0000-0000-0000-000000000004')
    WHERE lesson_id = '0d166000-0000-0000-0000-000000000004'),
  'V316 Fisso 30|3000', 'il calcolo dal vivo segue il predefinito nuovo');

SELECT is(
  (SELECT m.name || '|' || e.amount_cents
     FROM public.compensation_entries e JOIN public.compensation_models m ON m.id = e.model_id
    WHERE e.lesson_id = '0d166000-0000-0000-0000-000000000001'),
  'V316 Base|4000', 'un compenso già congelato non cambia');

SELECT is(
  public.staff_set_default_compensation_model('0d168000-0000-0000-0000-000000000002')->>'reason',
  'MODEL_INACTIVE', 'un modello disattivato non può essere il predefinito');

SELECT is(
  public.staff_set_default_compensation_model('00000000-0000-0000-0000-000000000000')->>'reason',
  'MODEL_NOT_FOUND', 'un modello che non esiste nemmeno');

SELECT is(
  public.staff_save_compensation_model(jsonb_build_object(
    'id', '0d168000-0000-0000-0000-000000000001', 'name', 'V316 Fisso 30', 'is_active', false,
    'components', jsonb_build_array(jsonb_build_object('kind', 'fixed_per_lesson', 'value_cents', 3000))))->>'reason',
  'DEFAULT_MODEL_ACTIVE', 'il predefinito non si disattiva dal modulo');

SELECT is(
  public.staff_save_compensation_model(jsonb_build_object(
    'id', '0d168000-0000-0000-0000-000000000001', 'name', 'V316 Fisso 35',
    'components', jsonb_build_array(jsonb_build_object('kind', 'fixed_per_lesson', 'value_cents', 3500))))->>'reason',
  'SAVED', 'il predefinito si modifica come gli altri modelli');

SELECT is(
  (SELECT name || '|' || is_default || '|' || is_active FROM public.compensation_models WHERE id = '0d168000-0000-0000-0000-000000000001'),
  'V316 Fisso 35|true|true', '…e resta predefinito e attivo');

SELECT throws_ok(
  $$ INSERT INTO public.compensation_models (name, is_default) VALUES ('V316 Secondo predefinito', true) $$,
  '23505', NULL, 'due modelli predefiniti non possono esserci');

SELECT throws_ok(
  $$ UPDATE public.compensation_models SET is_active = false WHERE is_default $$,
  '23514', NULL, 'il predefinito non si disattiva nemmeno scrivendo nella tabella');

SELECT is(
  public.staff_set_default_compensation_model('0d168000-0000-0000-0000-000000000003')->>'reason',
  'SAVED', 'si torna al modello di prima');

SELECT is(
  (SELECT string_agg(name, ', ') FROM public.compensation_models WHERE is_default),
  'V316 Base', '…e l''altro non è più predefinito');

-- Chi non è delle Finanze non cambia il predefinito
SET LOCAL request.jwt.claims = '{"sub":"0d160000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(
  public.staff_set_default_compensation_model('00000000-0000-0000-0000-000000000000')->>'reason',
  'NOT_FINANCE', 'un''operatrice non cambia il modello predefinito');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
