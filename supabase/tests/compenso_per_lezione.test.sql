-- Il compenso di una singola lezione si può modificare (migrazione 20261102100000): modello, incassi,
-- spese e compenso scritto a mano, con il motivo. Ciò che non si cambia resta dal vivo; le modifiche si
-- congelano col mese, restano se il mese si riapre e non toccano le righe congelate o pagate. Il
-- modello di prova è la ricetta di Yoga e Meditazione: 4 + 3 + 1 € di spese, il resto fino a 40 €.

BEGIN;
SELECT plan(64);

-- ── Persone, modelli, lezioni ed eventi del mese scorso ──────────────────────

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('0e020000-0000-0000-0000-000000000001', 'v1102-tesoriere@test.kalos', '{"full_name":"Tesoriere 1102"}', 'authenticated', 'authenticated'),
  ('0e020000-0000-0000-0000-000000000002', 'v1102-operatrice@test.kalos', '{"full_name":"Operatrice 1102"}', 'authenticated', 'authenticated'),
  ('0e020000-0000-0000-0000-000000000003', 'v1102-cliente@test.kalos', '{"full_name":"Cliente 1102"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'finance'  WHERE id = '0e020000-0000-0000-0000-000000000001';
UPDATE public.profiles SET role = 'operator' WHERE id = '0e020000-0000-0000-0000-000000000002';

-- Il test non presuppone un database senza predefinito
UPDATE public.compensation_models SET is_default = false WHERE is_default;

INSERT INTO public.operators (id, name, role, engagement_type) VALUES
  ('0e021000-0000-0000-0000-000000000001', 'V1102 Assegnata', 'istruttrice', 'paid'),
  ('0e021000-0000-0000-0000-000000000002', 'V1102 Volontaria', 'istruttrice', 'volunteer'),
  ('0e021000-0000-0000-0000-000000000003', 'V1102 Senza modello', 'istruttrice', 'paid');

INSERT INTO public.compensation_models (id, name, max_per_lesson_cents) VALUES
  ('0e028000-0000-0000-0000-000000000001', 'V1102 Base', 4000);
INSERT INTO public.compensation_components (model_id, kind, value_cents, value_percent, display_order, note) VALUES
  ('0e028000-0000-0000-0000-000000000001', 'cost_per_lesson',   400, NULL, 10, 'Affitto sala'),
  ('0e028000-0000-0000-0000-000000000001', 'cost_per_lesson',   300, NULL, 20, 'Usura materiali'),
  ('0e028000-0000-0000-0000-000000000001', 'cost_per_lesson',   100, NULL, 30, 'Accoglienza'),
  ('0e028000-0000-0000-0000-000000000001', 'percent_of_margin', NULL, 100, 40, NULL);
INSERT INTO public.compensation_models (id, name) VALUES
  ('0e028000-0000-0000-0000-000000000002', 'V1102 Fisso 30');
INSERT INTO public.compensation_components (model_id, kind, value_cents)
VALUES ('0e028000-0000-0000-0000-000000000002', 'fixed_per_lesson', 3000);
INSERT INTO public.compensation_models (id, name, is_active) VALUES
  ('0e028000-0000-0000-0000-000000000003', 'V1102 Disattivato', false);

INSERT INTO public.compensation_assignments (operator_id, activity_id, model_id, valid_from) VALUES
  ('0e021000-0000-0000-0000-000000000001', NULL, '0e028000-0000-0000-0000-000000000001', '2020-01-01');

INSERT INTO public.activities (id, name, discipline, duration_minutes)
VALUES ('0e022000-0000-0000-0000-000000000001', 'V1102 Yoga', 'v1102_yoga', 60);
INSERT INTO public.plans (id, name, price_cents, entries, validity_days)
VALUES ('0e023000-0000-0000-0000-000000000001', 'V1102 Ingresso', 5200, 1, 90);
INSERT INTO public.clients (id, full_name, email) VALUES
  ('0e024000-0000-0000-0000-000000000001', 'Cliente A 1102', 'v1102-a@test.kalos'),
  ('0e024000-0000-0000-0000-000000000002', 'Cliente B 1102', 'v1102-b@test.kalos');
INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at)
SELECT v.id, v.client_id, '0e023000-0000-0000-0000-000000000001',
       (date_trunc('month', now()) - interval '2 months')::date, (date_trunc('month', now()) + interval '2 months')::date
  FROM (VALUES
    ('0e025000-0000-0000-0000-000000000001'::uuid, '0e024000-0000-0000-0000-000000000001'::uuid),
    ('0e025000-0000-0000-0000-000000000002'::uuid, '0e024000-0000-0000-0000-000000000002'::uuid)
  ) AS v(id, client_id);

INSERT INTO public.lessons (id, activity_id, operator_id, starts_at, ends_at, capacity)
SELECT v.id, '0e022000-0000-0000-0000-000000000001', v.operator_id,
       date_trunc('month', now()) - interval '1 month' + v.offs,
       date_trunc('month', now()) - interval '1 month' + v.offs + interval '1 hour', 10
  FROM (VALUES
    ('0e026000-0000-0000-0000-000000000001'::uuid, '0e021000-0000-0000-0000-000000000001'::uuid, interval '5 days 16 hours'),
    ('0e026000-0000-0000-0000-000000000002'::uuid, '0e021000-0000-0000-0000-000000000002'::uuid, interval '6 days 16 hours'),
    ('0e026000-0000-0000-0000-000000000003'::uuid, '0e021000-0000-0000-0000-000000000003'::uuid, interval '7 days 16 hours')
  ) AS v(id, operator_id, offs);
INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status) VALUES
  ('0e026000-0000-0000-0000-000000000001', '0e024000-0000-0000-0000-000000000001', '0e025000-0000-0000-0000-000000000001', 'attended');

-- Un evento con il modello suo: resta la base da cui parte la modifica
INSERT INTO public.events (id, name, starts_at, ends_at, price_cents) VALUES
  ('0e027000-0000-0000-0000-000000000001', 'V1102 Laboratorio',
   date_trunc('month', now()) - interval '1 month' + interval '12 days 15 hours',
   date_trunc('month', now()) - interval '1 month' + interval '12 days 17 hours', 2000);
INSERT INTO public.event_operators (event_id, operator_id, model_id) VALUES
  ('0e027000-0000-0000-0000-000000000001', '0e021000-0000-0000-0000-000000000001', '0e028000-0000-0000-0000-000000000002');

CREATE TEMP TABLE v1102_month AS
SELECT (date_trunc('month', now()) - interval '1 month')::date AS m_start,
       (date_trunc('month', now()) - interval '1 day')::date AS m_end;
GRANT SELECT ON v1102_month TO authenticated;

-- La riga del mese, con le colonne del calcolo accanto al dettaglio
CREATE FUNCTION pg_temp.line(p_lesson uuid, p_event uuid DEFAULT NULL) RETURNS jsonb
  LANGUAGE sql AS $$
  SELECT c.breakdown || jsonb_build_object('row_amount', c.amount_cents, 'row_revenue', c.revenue_cents,
                                           'row_model', c.model_name, 'row_participants', c.participants)
    FROM v1102_month, public.calculate_compensation_v2(m_start, m_end, NULL) c
   WHERE c.lesson_id = p_lesson OR c.event_id = p_event
$$;

-- La riga giusta è sempre la stessa: lezione della persona assegnata, con un motivo
CREATE FUNCTION pg_temp.save(p jsonb) RETURNS text
  LANGUAGE sql AS $$
  SELECT public.staff_save_compensation_override(
    jsonb_build_object('operator_id', '0e021000-0000-0000-0000-000000000001',
                       'lesson_id', '0e026000-0000-0000-0000-000000000001',
                       'note', 'Sala gratis') || p)->>'reason'
$$;

GRANT EXECUTE ON FUNCTION pg_temp.line(uuid, uuid), pg_temp.save(jsonb) TO authenticated;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"0e020000-0000-0000-0000-000000000001","role":"authenticated"}';

-- ── Senza modifiche, tutto come prima ────────────────────────────────────────

SELECT is((SELECT r->>'row_amount' || '|' || (r->>'costs_cents') || '|' || (r->>'studio_cents') FROM pg_temp.line('0e026000-0000-0000-0000-000000000001') r),
  '4000|800|400', 'senza modifiche: 52 € − 8 € di spese, 40 € all''insegnante, 4 € allo Studio');
SELECT ok(NOT (pg_temp.line('0e026000-0000-0000-0000-000000000001') ? 'override'), '…e nel dettaglio non c''è nessuna modifica');

-- ── Le spese ─────────────────────────────────────────────────────────────────

SELECT is(pg_temp.save('{"costs":[{"note":"Usura materiali","amount_cents":300},{"note":"Accoglienza","amount_cents":100}]}'),
  'SAVED', 'una lezione senza affitto: le spese si riscrivono');
SELECT is((SELECT r->>'row_amount' || '|' || (r->>'costs_cents') || '|' || (r->>'margin_cents') || '|' || (r->>'studio_cents') FROM pg_temp.line('0e026000-0000-0000-0000-000000000001') r),
  '4000|400|4800|800', 'il tetto del modello vale ancora: 40 € all''insegnante, il risparmio resta allo Studio');
SELECT is(pg_temp.line('0e026000-0000-0000-0000-000000000001')->'costs'->0->>'note', 'Usura materiali', 'il dettaglio nomina le spese scritte');
SELECT is(pg_temp.line('0e026000-0000-0000-0000-000000000001')->'costs'->0->>'kind', 'custom', '…che si riconoscono da quelle del modello');
SELECT is(pg_temp.line('0e026000-0000-0000-0000-000000000001')->'override'->>'note', 'Sala gratis', 'il dettaglio porta il motivo');
SELECT is(pg_temp.line('0e026000-0000-0000-0000-000000000001')->'override'->'base'->>'amount_cents', '4000', '…e quanto dava il modello');
SELECT is(pg_temp.line('0e026000-0000-0000-0000-000000000001')->'override'->'base'->>'revenue_cents', '5200', '…sugli incassi delle prenotazioni');

-- Quello che non si è cambiato segue le prenotazioni
RESET ROLE;
INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status) VALUES
  ('0e026000-0000-0000-0000-000000000001', '0e024000-0000-0000-0000-000000000002', '0e025000-0000-0000-0000-000000000002', 'attended');
SET LOCAL ROLE authenticated;
SELECT is((SELECT r->>'row_participants' || '|' || (r->>'row_revenue') || '|' || (r->>'costs_cents') FROM pg_temp.line('0e026000-0000-0000-0000-000000000001') r),
  '2|10400|400', 'una presenza in più: incassi dal vivo, spese come scritte');
RESET ROLE;
DELETE FROM public.bookings WHERE client_id = '0e024000-0000-0000-0000-000000000002';
SET LOCAL ROLE authenticated;

SELECT is(pg_temp.save('{"costs":[]}'), 'SAVED', 'una lezione senza nessuna spesa');
SELECT is((SELECT r->>'costs_cents' || '|' || (r->>'margin_cents') FROM pg_temp.line('0e026000-0000-0000-0000-000000000001') r),
  '0|5200', '…e tutti gli incassi restano');
SELECT is((SELECT count(*)::text FROM public.compensation_line_overrides WHERE lesson_id = '0e026000-0000-0000-0000-000000000001'),
  '1', 'salvare di nuovo non crea una seconda modifica');

-- ── Gli incassi ──────────────────────────────────────────────────────────────

SELECT is(pg_temp.save('{"revenue_cents":2000}'), 'SAVED', 'gli incassi si correggono');
SELECT is((SELECT r->>'row_revenue' || '|' || (r->>'costs_cents') || '|' || (r->>'row_amount') || '|' || (r->>'studio_cents') FROM pg_temp.line('0e026000-0000-0000-0000-000000000001') r),
  '2000|800|1200|0', '20 € − 8 € del modello = 12 €: una nuova modifica sostituisce quella di prima');

-- Il gestionale manda sempre tutti i campi, con null per quello che non si cambia
SELECT is(pg_temp.save('{"event_id":null,"model_id":null,"revenue_cents":null,"costs":null,"amount_cents":1500}'), 'SAVED', 'i campi a null restano «come da calcolo»');
SELECT is((SELECT (r->>'row_amount') || '|' || (r->>'row_revenue') || '|' || (r->>'costs_cents') || '|' || (r->'override'->>'costs' IS NULL)::text FROM pg_temp.line('0e026000-0000-0000-0000-000000000001') r),
  '1500|5200|800|true', '…e le spese null non diventano un elenco vuoto');
SELECT is((SELECT r->>'costs_cents' FROM public.preview_compensation_override('0e028000-0000-0000-0000-000000000001', 60, 1, 5200, NULL, NULL) r),
  '800', 'anche nella prova');

-- ── Il compenso scritto a mano ───────────────────────────────────────────────

SELECT is(pg_temp.save('{"amount_cents":5000}'), 'SAVED', 'il compenso si scrive a mano');
SELECT is((SELECT r->>'row_amount' || '|' || (r->>'margin_cents') || '|' || (r->>'studio_cents') FROM pg_temp.line('0e026000-0000-0000-0000-000000000001') r),
  '5000|4400|-600', 'vale anche sopra il tetto, e allo Studio si legge la differenza');
SELECT is(pg_temp.line('0e026000-0000-0000-0000-000000000001')->'components', '[{"kind":"manual","amount_cents":5000}]'::jsonb,
  'il dettaglio non finge un calcolo che non c''è stato');
SELECT is(pg_temp.save('{"amount_cents":0}'), 'SAVED', 'zero è un compenso valido');
SELECT is(pg_temp.line('0e026000-0000-0000-0000-000000000001')->>'row_amount', '0', '…non vuol dire «come da modello»');

-- ── Il modello ───────────────────────────────────────────────────────────────

SELECT is(pg_temp.save('{"model_id":"0e028000-0000-0000-0000-000000000002"}'), 'SAVED', 'un altro modello solo per questa lezione');
SELECT is((SELECT r->>'row_model' || '|' || (r->>'row_amount') FROM pg_temp.line('0e026000-0000-0000-0000-000000000001') r),
  'V1102 Fisso 30|3000', 'il calcolo segue quel modello');
SELECT is(pg_temp.line('0e026000-0000-0000-0000-000000000001')->'override'->'base'->>'model_name', 'V1102 Base', '…e il dettaglio ricorda quello di partenza');
SELECT is(pg_temp.save('{"model_id":"0e028000-0000-0000-0000-000000000003"}'), 'MODEL_DISABLED', 'un modello disattivato non si sceglie');
SELECT is(pg_temp.save('{"model_id":"0e028000-0000-0000-0000-00000000dead"}'), 'MODEL_NOT_FOUND', 'un modello che non esiste nemmeno');

-- ── Richieste sbagliate ──────────────────────────────────────────────────────

SELECT is(pg_temp.save('{"note":"  ","amount_cents":100}'), 'REASON_REQUIRED', 'senza motivo non si salva');
SELECT is(pg_temp.save('{}'), 'NO_CHANGES', 'senza cambiare niente non si salva');
SELECT is(pg_temp.save('{"amount_cents":-1}'), 'INVALID_OVERRIDE', 'un compenso negativo no');
SELECT is(pg_temp.save('{"revenue_cents":-1}'), 'INVALID_OVERRIDE', 'incassi negativi no');
SELECT is(pg_temp.save('{"amount_cents":"tanti"}'), 'INVALID_OVERRIDE', 'un importo che non è un numero no');
SELECT is(pg_temp.save('{"costs":[{"note":"Affitto","amount_cents":-100}]}'), 'INVALID_OVERRIDE', 'una spesa negativa no');
SELECT is(pg_temp.save('{"costs":[{"note":" ","amount_cents":100}]}'), 'INVALID_OVERRIDE', 'una spesa senza nome no');
SELECT is(pg_temp.save('{"costs":[{"note":"Affitto","amount_cents":10.5}]}'), 'INVALID_OVERRIDE', 'una spesa con frazioni di centesimo no');
SELECT is(pg_temp.save('{"costs":{"note":"Affitto"}}'), 'INVALID_OVERRIDE', 'le spese sono un elenco');
SELECT is(pg_temp.save('{"lesson_id":"0e026000-0000-0000-0000-000000000002","amount_cents":100}'),
  'LINE_NOT_FOUND', 'la lezione di un''altra persona no');
SELECT is(public.staff_save_compensation_override(
    '{"operator_id":"0e021000-0000-0000-0000-000000000002","lesson_id":"0e026000-0000-0000-0000-000000000002","note":"x","amount_cents":100}')->>'reason',
  'LINE_NOT_FOUND', 'chi è volontariə non ha compensi da modificare');
SELECT is(public.staff_save_compensation_override(
    '{"operator_id":"0e021000-0000-0000-0000-000000000003","lesson_id":"0e026000-0000-0000-0000-000000000003","note":"x","amount_cents":100}')->>'reason',
  'MODEL_REQUIRED', 'senza un modello la riga non si potrebbe chiudere: ne serve uno anche col compenso a mano');
SELECT is(public.staff_save_compensation_override(
    '{"operator_id":"0e021000-0000-0000-0000-000000000003","lesson_id":"0e026000-0000-0000-0000-000000000003","note":"x","model_id":"0e028000-0000-0000-0000-000000000002"}')->>'reason',
  'SAVED', 'scegliere un modello sistema una lezione senza modello');

-- ── L'evento ─────────────────────────────────────────────────────────────────

SELECT is(public.staff_save_compensation_override(
    '{"operator_id":"0e021000-0000-0000-0000-000000000001","event_id":"0e027000-0000-0000-0000-000000000001","note":"Accordo a parte","amount_cents":10000}')->>'reason',
  'SAVED', 'anche un evento si modifica');
SELECT is((SELECT r->>'row_amount' || '|' || (r->'override'->'base'->>'model_name') FROM pg_temp.line(NULL, '0e027000-0000-0000-0000-000000000001') r),
  '10000|V1102 Fisso 30', 'il modello scelto per l''evento resta la base');

-- ── Congelare, riaprire, pagare ──────────────────────────────────────────────

SELECT is(pg_temp.save('{"costs":[{"note":"Usura materiali","amount_cents":300}]}'), 'SAVED', 'la modifica prima di chiudere');
SELECT is((SELECT public.staff_freeze_compensation(m_start, m_end, '0e021000-0000-0000-0000-000000000001')->>'inserted' FROM v1102_month),
  '2', 'si chiude il mese');
SELECT is((SELECT amount_cents || '|' || (breakdown->>'costs_cents') || '|' || (breakdown->'override'->>'note')
             FROM public.compensation_entries WHERE lesson_id = '0e026000-0000-0000-0000-000000000001'),
  '4000|300|Sala gratis', 'il compenso congelato ha la modifica e il suo motivo');
SELECT is(pg_temp.save('{"amount_cents":100}'), 'LINE_FROZEN', 'una riga congelata non si modifica');
SELECT is(public.staff_delete_compensation_override('0e021000-0000-0000-0000-000000000001', '0e026000-0000-0000-0000-000000000001')->>'reason',
  'LINE_FROZEN', '…e non si riporta al modello');
SELECT is((SELECT public.staff_unfreeze_compensation(m_start, '0e021000-0000-0000-0000-000000000001')->>'deleted' FROM v1102_month),
  '2', 'si riapre il mese');
SELECT is(pg_temp.line('0e026000-0000-0000-0000-000000000001')->>'costs_cents', '300', 'la modifica resta dopo la riapertura');
SELECT is(pg_temp.save('{"costs":[{"note":"Usura materiali","amount_cents":300}],"amount_cents":3500}'), 'SAVED', 'riaperto, si modifica di nuovo');
SELECT is((SELECT public.staff_freeze_compensation(m_start, m_end, '0e021000-0000-0000-0000-000000000001')->>'inserted' FROM v1102_month),
  '2', 'si richiude');
SELECT is((SELECT public.staff_pay_compensation('0e021000-0000-0000-0000-000000000001', m_start)->>'gross_cents' FROM v1102_month),
  '13500', 'il pagamento somma gli importi modificati: 35 € + 100 €');
SELECT is(pg_temp.save('{"amount_cents":100}'), 'LINE_PAID', 'una riga pagata non si modifica');

-- ── Tornare al modello ───────────────────────────────────────────────────────

SELECT is((SELECT public.staff_undo_compensation_payment(id)->>'reason' FROM public.compensation_payments WHERE operator_id = '0e021000-0000-0000-0000-000000000001'),
  'UNDONE', 'si annulla il pagamento');
SELECT is((SELECT public.staff_unfreeze_compensation(m_start, '0e021000-0000-0000-0000-000000000001')->>'deleted' FROM v1102_month),
  '2', 'si riapre il mese');
SELECT is(public.staff_delete_compensation_override('0e021000-0000-0000-0000-000000000001', '0e026000-0000-0000-0000-000000000001')->>'reason',
  'RESET', 'la lezione torna al modello');
SELECT is((SELECT r->>'row_amount' || '|' || (r->>'costs_cents') || '|' || (r ? 'override')::text FROM pg_temp.line('0e026000-0000-0000-0000-000000000001') r),
  '4000|800|false', 'come se non fosse successo niente');

-- ── La prova mentre si scrive ────────────────────────────────────────────────

SELECT is((SELECT r->>'amount_cents' || '|' || (r->>'costs_cents') || '|' || (r->>'studio_cents')
             FROM public.preview_compensation_override('0e028000-0000-0000-0000-000000000001', 60, 4, 5200, '[{"note":"Accoglienza","amount_cents":100}]', NULL) r),
  '4000|100|1100', 'la prova usa lo stesso calcolo e non scrive niente');

-- ── Chi può ──────────────────────────────────────────────────────────────────

SET LOCAL request.jwt.claims = '{"sub":"0e020000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(pg_temp.save('{"amount_cents":100}'), 'SAVED', 'dal 22/10 le Finanze sono di tutto lo staff: anche un''operatrice modifica');

-- Le righe si scrivono solo con le funzioni, anche per lo staff
SELECT throws_ok($$ INSERT INTO public.compensation_line_overrides (operator_id, lesson_id, note)
                    VALUES ('0e021000-0000-0000-0000-000000000003', '0e026000-0000-0000-0000-000000000003', 'x') $$,
  '42501', NULL, 'nessuna scrittura diretta nella tabella');
SELECT throws_ok($$ DELETE FROM public.compensation_line_overrides $$, '42501', NULL, 'nessuna cancellazione diretta');

SET LOCAL request.jwt.claims = '{"sub":"0e020000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is(pg_temp.save('{"amount_cents":100}'), 'NOT_FINANCE', 'unə cliente no');

SELECT is((SELECT count(*)::text FROM public.compensation_line_overrides), '0', 'unə cliente non legge le modifiche');

SELECT * FROM finish();
ROLLBACK;
