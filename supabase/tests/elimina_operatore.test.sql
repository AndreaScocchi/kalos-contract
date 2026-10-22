-- Eliminare un operatore dal gestionale (migrazione 20261022150000): solo admin; chi ha lezioni o
-- eventi non ancora finiti non si elimina; senza storico la riga sparisce, con uno storico resta
-- solo il nome; la scheda eliminata non torna attiva e non si cancella con un DELETE diretto.

BEGIN;
SELECT plan(31);

-- ── Persone ──────────────────────────────────────────────────────────────────

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('0e200000-0000-0000-0000-000000000001', 'v320-admin@test.kalos', '{"full_name":"Admin 320"}', 'authenticated', 'authenticated'),
  ('0e200000-0000-0000-0000-000000000002', 'v320-operatrice@test.kalos', '{"full_name":"Operatrice 320"}', 'authenticated', 'authenticated'),
  ('0e200000-0000-0000-0000-000000000003', 'v320-tesoriere@test.kalos', '{"full_name":"Tesoriere 320"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'admin'    WHERE id = '0e200000-0000-0000-0000-000000000001';
UPDATE public.profiles SET role = 'operator' WHERE id = '0e200000-0000-0000-0000-000000000002';
UPDATE public.profiles SET role = 'finance'  WHERE id = '0e200000-0000-0000-0000-000000000003';

-- 1 mai lavorato, 2 con lezioni passate, 3 con una lezione domani, 4 con un evento in programma,
-- 5 solo nel registro dei volontari, 6 con una lezione futura archiviata, 7 con la foto della 1
INSERT INTO public.operators (id, name, role, bio, disciplines, image_url, display_order, profile_id, engagement_type) VALUES
  ('0e201000-0000-0000-0000-000000000001', 'V320 Mai lavorato', 'istruttrice', 'Bio', ARRAY['yoga'],
   'https://example.test/storage/v1/object/public/operators/v320-1.jpg', 1, NULL, 'paid'),
  ('0e201000-0000-0000-0000-000000000002', 'V320 Con storico', 'istruttrice', 'Bio lunga', ARRAY['yoga'],
   'https://example.test/storage/v1/object/public/operators/v320-2.jpg', 2, '0e200000-0000-0000-0000-000000000002', 'paid'),
  ('0e201000-0000-0000-0000-000000000003', 'V320 Lezione domani', 'istruttrice', NULL, NULL, NULL, NULL, NULL, 'paid'),
  ('0e201000-0000-0000-0000-000000000004', 'V320 Evento in programma', 'istruttrice', NULL, NULL, NULL, NULL, NULL, 'volunteer'),
  ('0e201000-0000-0000-0000-000000000005', 'V320 Volontaria', 'istruttrice', NULL, NULL, NULL, NULL, NULL, 'volunteer'),
  ('0e201000-0000-0000-0000-000000000006', 'V320 Lezione archiviata', 'istruttrice', NULL, NULL, NULL, NULL, NULL, 'paid'),
  ('0e201000-0000-0000-0000-000000000007', 'V320 Stessa foto', 'istruttrice', NULL, NULL,
   'https://example.test/storage/v1/object/public/operators/v320-7.jpg', NULL, NULL, 'paid');

INSERT INTO public.activities (id, name, discipline, duration_minutes)
VALUES ('0e202000-0000-0000-0000-000000000001', 'V320 Yoga', 'v320_yoga', 60);

INSERT INTO public.lessons (id, activity_id, operator_id, starts_at, ends_at, capacity, deleted_at) VALUES
  ('0e203000-0000-0000-0000-000000000001', '0e202000-0000-0000-0000-000000000001', '0e201000-0000-0000-0000-000000000002',
   now() - interval '10 days', now() - interval '10 days' + interval '1 hour', 10, NULL),
  ('0e203000-0000-0000-0000-000000000002', '0e202000-0000-0000-0000-000000000001', '0e201000-0000-0000-0000-000000000002',
   now() - interval '3 days', now() - interval '3 days' + interval '1 hour', 10, NULL),
  ('0e203000-0000-0000-0000-000000000003', '0e202000-0000-0000-0000-000000000001', '0e201000-0000-0000-0000-000000000003',
   now() + interval '1 day', now() + interval '1 day' + interval '1 hour', 10, NULL),
  ('0e203000-0000-0000-0000-000000000004', '0e202000-0000-0000-0000-000000000001', '0e201000-0000-0000-0000-000000000006',
   now() + interval '2 days', now() + interval '2 days' + interval '1 hour', 10, now());

INSERT INTO public.events (id, name, starts_at, ends_at) VALUES
  ('0e204000-0000-0000-0000-000000000001', 'V320 Laboratorio', now() + interval '5 days', now() + interval '5 days' + interval '2 hours');
INSERT INTO public.event_operators (event_id, operator_id)
VALUES ('0e204000-0000-0000-0000-000000000001', '0e201000-0000-0000-0000-000000000004');

INSERT INTO public.volunteers (full_name, operator_id, started_on)
VALUES ('V320 Volontaria', '0e201000-0000-0000-0000-000000000005', '2026-09-01');

-- Impostazioni dei compensi della persona mai lavorata: se ne vanno con lei
INSERT INTO public.compensation_models (id, name) VALUES ('0e208000-0000-0000-0000-000000000001', 'V320 Modello');
INSERT INTO public.compensation_assignments (operator_id, model_id, valid_from) VALUES
  ('0e201000-0000-0000-0000-000000000001', '0e208000-0000-0000-0000-000000000001', '2026-09-01'),
  ('0e201000-0000-0000-0000-000000000002', '0e208000-0000-0000-0000-000000000001', '2026-09-01');
INSERT INTO public.operator_compensation_settings (operator_id, withholding_percent)
VALUES ('0e201000-0000-0000-0000-000000000001', 20);

-- La persona 7 usa la stessa foto della 2: la foto non si cancella
UPDATE public.operators SET image_url = 'https://example.test/storage/v1/object/public/operators/v320-2.jpg'
 WHERE id = '0e201000-0000-0000-0000-000000000007';

-- ── Chi può eliminare ────────────────────────────────────────────────────────

SET LOCAL ROLE authenticated;

SET LOCAL request.jwt.claims = '{"sub":"0e200000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000001')->>'reason',
  'NOT_ADMIN', 'un''operatrice non elimina le schede dello staff');

SET LOCAL request.jwt.claims = '{"sub":"0e200000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000001')->>'reason',
  'NOT_ADMIN', 'nemmeno il Tesoriere');

SET LOCAL request.jwt.claims = '{"sub":"0e200000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(public.staff_delete_operator('00000000-0000-0000-0000-000000000000')->>'reason',
  'NOT_FOUND', 'una scheda che non c''è risponde NOT_FOUND');

-- ── Quello che non è ancora finito blocca ────────────────────────────────────

SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000003'),
  '{"ok": false, "reason": "UPCOMING", "upcoming_events": 0, "upcoming_lessons": 1}'::jsonb,
  'con una lezione in programma non si elimina, e dice quante');
SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000004', true)->>'reason',
  'UPCOMING', 'nemmeno con un evento in programma, anche solo per chiedere');
SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000004')->'upcoming_events',
  '1'::jsonb, '…e conta gli eventi');

RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.operators WHERE id IN (
    '0e201000-0000-0000-0000-000000000003', '0e201000-0000-0000-0000-000000000004') AND deleted_at IS NULL),
  2, 'chi ha qualcosa in programma resta com''era');
SET LOCAL ROLE authenticated;

-- ── Senza storico: la riga sparisce ──────────────────────────────────────────

SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000001', true),
  '{"ok": true, "reason": "DRY_RUN", "keeps_name": false, "lessons": 0, "events": 0}'::jsonb,
  'la domanda dice che la scheda si cancellerebbe del tutto');

RESET ROLE;
SELECT ok(EXISTS (SELECT 1 FROM public.operators WHERE id = '0e201000-0000-0000-0000-000000000001'),
  '…senza cancellarla');
SET LOCAL ROLE authenticated;

SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000001'),
  jsonb_build_object('ok', true, 'reason', 'DELETED', 'keeps_name', false, 'lessons', 0, 'events', 0,
    'image_url', 'https://example.test/storage/v1/object/public/operators/v320-1.jpg'),
  'senza storico si elimina, e restituisce la foto da togliere dallo storage');

RESET ROLE;
SELECT ok(NOT EXISTS (SELECT 1 FROM public.operators WHERE id = '0e201000-0000-0000-0000-000000000001'),
  'la riga non c''è più');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.compensation_assignments WHERE operator_id = '0e201000-0000-0000-0000-000000000001'),
  'con lei se ne vanno le assegnazioni del modello di compenso');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.operator_compensation_settings WHERE operator_id = '0e201000-0000-0000-0000-000000000001'),
  '…e la ritenuta');
SET LOCAL ROLE authenticated;

-- Una lezione futura archiviata non conta: non è in programma
SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000006')->>'reason',
  'NAME_KEPT', 'una lezione archiviata non blocca, ma è storico: resta il nome');

-- ── Con uno storico: resta solo il nome ──────────────────────────────────────

SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000002', true),
  '{"ok": true, "reason": "DRY_RUN", "keeps_name": true, "lessons": 2, "events": 0}'::jsonb,
  'la domanda dice che resterebbe il nome, per due lezioni');

SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000002'),
  '{"ok": true, "reason": "NAME_KEPT", "keeps_name": true, "lessons": 2, "events": 0, "image_url": null}'::jsonb,
  'con lezioni passate resta il nome; la foto usata anche da un''altra scheda non si cancella');

RESET ROLE;
SELECT is((SELECT name FROM public.operators WHERE id = '0e201000-0000-0000-0000-000000000002'),
  'V320 Con storico', 'il nome resta');
SELECT ok((SELECT deleted_at IS NOT NULL AND NOT is_active AND NOT is_visible_on_site
             FROM public.operators WHERE id = '0e201000-0000-0000-0000-000000000002'),
  'la scheda è eliminata, non attiva e non sul sito');
SELECT ok((SELECT bio IS NULL AND image_url IS NULL AND disciplines IS NULL AND display_order IS NULL AND profile_id IS NULL
             FROM public.operators WHERE id = '0e201000-0000-0000-0000-000000000002'),
  'bio, foto, discipline, ordine sul sito e collegamento all''account si cancellano');
SELECT is((SELECT count(*)::int FROM public.lessons WHERE operator_id = '0e201000-0000-0000-0000-000000000002'),
  2, 'le lezioni passate puntano ancora a lei, quindi ne mostrano il nome');
SELECT is((SELECT count(*)::int FROM public.compensation_assignments WHERE operator_id = '0e201000-0000-0000-0000-000000000002'),
  1, 'le assegnazioni restano per i compensi dei mesi in cui ha lavorato');
SELECT is((SELECT image_url FROM public.operators WHERE id = '0e201000-0000-0000-0000-000000000007'),
  'https://example.test/storage/v1/object/public/operators/v320-2.jpg', 'l''altra scheda tiene la sua foto');
SET LOCAL ROLE authenticated;

SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000002')->>'reason',
  'NOT_FOUND', 'una scheda già eliminata non si elimina di nuovo');

SELECT is(public.staff_delete_operator('0e201000-0000-0000-0000-000000000005')->>'reason',
  'NAME_KEPT', 'chi è nel registro dei volontari ha uno storico');

-- Lo staff continua a leggere il nome; i clienti no, come per le schede non attive
SET LOCAL request.jwt.claims = '{"sub":"0e200000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is((SELECT name FROM public.operators WHERE id = '0e201000-0000-0000-0000-000000000002'),
  'V320 Con storico', 'lo staff legge il nome di chi è stato eliminato');
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims = '{"role":"anon"}';
SELECT is_empty($$ SELECT 1 FROM public.operators WHERE id = '0e201000-0000-0000-0000-000000000002' $$,
  'il sito non vede le schede eliminate');
SELECT is_empty($$ SELECT 1 FROM public.public_site_operators WHERE id = '0e201000-0000-0000-0000-000000000005' $$,
  '…nemmeno nel team');

-- ── Niente scorciatoie ───────────────────────────────────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"0e200000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT throws_ok(
  $$ UPDATE public.operators SET is_active = true WHERE id = '0e201000-0000-0000-0000-000000000002' $$,
  '23514', NULL, 'una scheda eliminata non torna attiva');

SELECT throws_ok(
  $$ DELETE FROM public.operators WHERE id = '0e201000-0000-0000-0000-000000000007' $$,
  '42501', NULL, 'nemmeno l''admin cancella una scheda direttamente');

SELECT lives_ok(
  $$ UPDATE public.operators SET role = 'insegnante' WHERE id = '0e201000-0000-0000-0000-000000000007' $$,
  'l''admin continua a modificare le schede');

RESET ROLE;
SELECT is((SELECT role FROM public.operators WHERE id = '0e201000-0000-0000-0000-000000000007'),
  'insegnante', '…e la modifica arriva');

SELECT * FROM finish();
ROLLBACK;
