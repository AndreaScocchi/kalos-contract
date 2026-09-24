-- Sessione 6: prove (disdetta e nuova prova, stato che segue le presenze, conferma dallo staff),
-- lista d'attesa (posto offerto protetto, staff che mette in fila e toglie), promemoria con il
-- luogo, questionario dopo la prova, ricostruzione del sito, view del sito.

BEGIN;
SELECT plan(49);

-- ── Persone ──────────────────────────────────────────────────────────────────
-- Due con l'account (la registrazione crea profilo e scheda), una staff, due solo in anagrafica.
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('16000000-0000-0000-0000-000000000001', 's6-anna@test.kalos',  '{"full_name":"Anna Prova"}',  'authenticated', 'authenticated'),
  ('16000000-0000-0000-0000-000000000002', 's6-bruno@test.kalos', '{"full_name":"Bruno Fila"}',  'authenticated', 'authenticated'),
  ('16000000-0000-0000-0000-000000000009', 's6-staff@test.kalos', '{"full_name":"Staff Sei"}',   'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '16000000-0000-0000-0000-000000000009';

INSERT INTO public.clients (id, full_name, email) VALUES
  ('26000000-0000-0000-0000-000000000003', 'Carla Senza App', 's6-carla@test.kalos'),
  ('26000000-0000-0000-0000-000000000004', 'Dario Senza App', NULL);

CREATE TEMP TABLE s6 AS
SELECT (SELECT id FROM public.clients WHERE email = 's6-anna@test.kalos')  AS anna,
       (SELECT id FROM public.clients WHERE email = 's6-bruno@test.kalos') AS bruno,
       '26000000-0000-0000-0000-000000000003'::uuid AS carla,
       '26000000-0000-0000-0000-000000000004'::uuid AS dario;
GRANT SELECT ON s6 TO authenticated;

-- ── Luogo, attività, lezioni ─────────────────────────────────────────────────
INSERT INTO public.locations (id, slug, name, address_street, city, access_notes) VALUES
  ('36000000-0000-0000-0000-000000000001', 's6-sala-media', 'Sala Media', 'Via della Biblioteca 1', 'Staranzano',
   'Entrata dal cortile.');

INSERT INTO public.activities (id, name, discipline, duration_minutes) VALUES
  ('46000000-0000-0000-0000-000000000001', 'S6 Yoga', 's6_yoga', 60),
  ('46000000-0000-0000-0000-000000000002', 'S6 Meditazione', 's6_meditazione', 45);

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity, location_id) VALUES
  -- prove
  ('56000000-0000-0000-0000-000000000001', '46000000-0000-0000-0000-000000000001', now() + interval '3 days', now() + interval '3 days 1 hour', 10, '36000000-0000-0000-0000-000000000001'),
  ('56000000-0000-0000-0000-000000000002', '46000000-0000-0000-0000-000000000001', now() + interval '4 days', now() + interval '4 days 1 hour', 10, NULL),
  -- lista d'attesa: un posto solo
  ('56000000-0000-0000-0000-000000000003', '46000000-0000-0000-0000-000000000002', now() + interval '5 days', now() + interval '5 days 45 minutes', 1, NULL),
  -- promemoria delle 2 ore
  ('56000000-0000-0000-0000-000000000004', '46000000-0000-0000-0000-000000000002', now() + interval '150 minutes', now() + interval '195 minutes', 10, '36000000-0000-0000-0000-000000000001');

-- La chiamata vera all'edge function passa da pg_net, che in locale non c'è: qui la si sostituisce
-- con una finta che registra la chiamata. Tutto torna com'era col ROLLBACK finale.
CREATE TEMP TABLE edge_calls (name text, body jsonb);
CREATE OR REPLACE FUNCTION internal.call_edge_function(p_function_name text, p_body jsonb DEFAULT '{}'::jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO edge_calls VALUES (p_function_name, p_body);
  RETURN 1;
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 1. Prove
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';

SELECT is((public.staff_book_trial('56000000-0000-0000-0000-000000000001', (SELECT carla FROM s6)))->>'reason',
  'BOOKED', 'lo staff prenota la prova a chi è solo in anagrafica');
RESET ROLE;

SELECT is(
  (SELECT count(*)::int FROM public.notification_queue
    WHERE client_id = (SELECT carla FROM s6) AND category = 'trial_booked' AND channel = 'email'),
  1, 'e parte la conferma via email (F5)');

SELECT ok(
  (SELECT body FROM public.notification_queue
    WHERE client_id = (SELECT carla FROM s6) AND category = 'trial_booked')
    LIKE '%presso Sala Media, Via della Biblioteca 1, Staranzano%registrati con questa email%',
  'la conferma dice dove, e invita all''app chi non ce l''ha');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT is(
  (public.staff_cancel_booking((SELECT booking_id FROM public.trials WHERE client_id = (SELECT carla FROM s6)))) ->> 'reason',
  'CANCELED', 'la prova si può disdire');
RESET ROLE;

SELECT is((SELECT status::text FROM public.trials WHERE client_id = (SELECT carla FROM s6)),
  'canceled', 'la disdetta arriva sulla prova');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT is((public.staff_book_trial('56000000-0000-0000-0000-000000000002', (SELECT carla FROM s6)))->>'reason',
  'BOOKED', 'una prova disdetta non conta come fatta: si riprenota su un''altra data');
RESET ROLE;

SELECT is(
  (SELECT count(*)::int || ':' || min(status::text) || ':' || min(lesson_id::text)
     FROM public.trials WHERE client_id = (SELECT carla FROM s6)),
  '1:booked:56000000-0000-0000-0000-000000000002',
  'resta una sola prova per attività, spostata sulla nuova lezione');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT is(
  (public.staff_update_booking_status((SELECT booking_id FROM public.trials WHERE client_id = (SELECT carla FROM s6)), 'no_show'))->>'reason',
  'UPDATED', 'lo staff segna l''assenza');
RESET ROLE;
SELECT is((SELECT status::text FROM public.trials WHERE client_id = (SELECT carla FROM s6)),
  'no_show', 'l''assenza arriva sulla prova');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT lives_ok(
  $$ SELECT public.staff_update_booking_status((SELECT booking_id FROM public.trials WHERE client_id = (SELECT carla FROM s6)), 'attended') $$,
  'poi la presenza');
RESET ROLE;
SELECT is((SELECT status::text FROM public.trials WHERE client_id = (SELECT carla FROM s6)),
  'attended', 'e la prova risulta fatta');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT is((public.staff_book_trial('56000000-0000-0000-0000-000000000001', (SELECT carla FROM s6)))->>'reason',
  'TRIAL_ALREADY_USED', 'una prova fatta chiude la prova di quell''attività');
RESET ROLE;

-- Scheda nuova al volo: se la prova non va, la scheda non resta come doppione
UPDATE public.activities SET trial_enabled = false WHERE id = '46000000-0000-0000-0000-000000000002';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT is(
  (public.staff_create_client_and_book_trial('56000000-0000-0000-0000-000000000003', 'Elena', 'Nuova', '333', 's6-elena@test.kalos'))->>'reason',
  'TRIAL_NOT_AVAILABLE', 'prova non disponibile per quell''attività');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.clients WHERE email = 's6-elena@test.kalos'), 0,
  'e la scheda creata al volo viene tolta');
UPDATE public.activities SET trial_enabled = true WHERE id = '46000000-0000-0000-0000-000000000002';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT is(
  (public.staff_create_client_and_book_trial('56000000-0000-0000-0000-000000000001', 'Elena', 'Nuova', '333', 'S6-Elena@test.kalos'))->>'client_created',
  'true', 'con la prova disponibile la scheda nasce e la prova è prenotata');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notification_queue q JOIN public.clients c ON c.id = q.client_id
            WHERE c.email = 's6-elena@test.kalos' AND q.category = 'trial_booked'), 1,
  'anche lei riceve la conferma');

-- Chi non ha email né app: nessuna conferma (resterebbe in coda come "saltata")
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT is((public.staff_book_trial('56000000-0000-0000-0000-000000000001', (SELECT dario FROM s6)))->>'reason',
  'BOOKED', 'prova per chi non ha email');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE client_id = (SELECT dario FROM s6)), 0,
  'e nessuna conferma in coda');

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. Questionario dopo la prova
-- ═════════════════════════════════════════════════════════════════════════════

-- Anna prova Yoga dall'app; finché non l'ha fatta, niente questionario
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is((public.book_trial_lesson('56000000-0000-0000-0000-000000000001'))->>'reason', 'BOOKED',
  'la cliente prenota la prova dall''app');
SELECT is(
  (public.submit_trial_feedback((SELECT id FROM public.trials WHERE client_id = (SELECT anna FROM s6)), 5::smallint))->>'reason',
  'NOT_ELIGIBLE', 'prima di farla non si risponde al questionario');
RESET ROLE;

UPDATE public.bookings SET status = 'attended'
 WHERE id = (SELECT booking_id FROM public.trials WHERE client_id = (SELECT anna FROM s6));

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(
  (public.submit_trial_feedback((SELECT id FROM public.trials WHERE client_id = (SELECT anna FROM s6)), 4::smallint,
     '{"accoglienza":"si","livello":"superbo"}'::jsonb))->>'reason',
  'INVALID_ANSWERS', 'una risposta fuori elenco viene rifiutata');
SELECT is(
  (public.submit_trial_feedback((SELECT id FROM public.trials WHERE client_id = (SELECT anna FROM s6)), 4::smallint,
     '{"accoglienza":"si","livello":"giusto","continuare":"forse"}'::jsonb, '  Bella lezione  '))->>'ok',
  'true', 'dopo la prova il questionario si invia');
SELECT is(
  (public.submit_trial_feedback((SELECT id FROM public.trials WHERE client_id = (SELECT anna FROM s6)), 5::smallint,
     '{"continuare":"si"}'::jsonb))->>'ok',
  'true', 'e si può correggere');
RESET ROLE;

SELECT is(
  (SELECT count(*)::int || ':' || min(rating) || ':' || min(metadata->'answers'->>'continuare') || ':' || min(status::text)
     FROM public.feedback WHERE client_id = (SELECT anna FROM s6) AND kind = 'trial'),
  '1:5:si:new', 'resta una risposta sola, aggiornata, e torna da leggere');

SELECT throws_ok(
  $$ INSERT INTO public.feedback (client_id, kind, rating) VALUES ((SELECT anna FROM s6), 'trial', 3) $$,
  '23514', NULL, 'un questionario di prova senza prova non si salva');

-- ═════════════════════════════════════════════════════════════════════════════
-- 3. Lista d'attesa
-- ═════════════════════════════════════════════════════════════════════════════
-- Lezione da un posto (…003). Anna prenota con la prova; Bruno e Carla in fila.

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT is((public.staff_add_to_waitlist('56000000-0000-0000-0000-000000000003', (SELECT bruno FROM s6)))->>'reason',
  'LESSON_NOT_FULL', 'in fila solo se la lezione è piena: altrimenti si prenota');
SELECT is((public.staff_book_trial('56000000-0000-0000-0000-000000000003', (SELECT anna FROM s6)))->>'reason',
  'BOOKED', 'Anna occupa l''unico posto');
SELECT is((public.staff_add_to_waitlist('56000000-0000-0000-0000-000000000003', (SELECT bruno FROM s6)))->>'position',
  '1', 'Bruno è il primo della fila');
SELECT is((public.staff_add_to_waitlist('56000000-0000-0000-0000-000000000003', (SELECT carla FROM s6)))->>'position',
  '2', 'Carla, che non ha l''app, è la seconda');
SELECT is((public.staff_add_to_waitlist('56000000-0000-0000-0000-000000000003', (SELECT carla FROM s6)))->>'reason',
  'ALREADY_IN_WAITLIST', 'niente doppioni in fila');

-- Anna disdice: il posto va a Bruno, per tutti gli altri la lezione resta piena
SELECT is(
  (public.staff_cancel_booking((SELECT id FROM public.bookings
     WHERE lesson_id = '56000000-0000-0000-0000-000000000003' AND client_id = (SELECT anna FROM s6) AND status = 'booked')))->>'reason',
  'CANCELED', 'Anna disdice');
RESET ROLE;

SELECT is(
  (SELECT status::text FROM public.waitlist
    WHERE lesson_id = '56000000-0000-0000-0000-000000000003' AND client_id = (SELECT bruno FROM s6)),
  'offered', 'il posto liberato è offerto al primo della fila');
SELECT is(
  (SELECT count(*)::int FROM public.notification_queue
    WHERE client_id = (SELECT bruno FROM s6) AND category = 'waitlist_promotion'),
  1, 'con una notifica');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT is(
  (public.staff_book_lesson('56000000-0000-0000-0000-000000000003', (SELECT dario FROM s6), NULL))->>'waitlist_offer',
  'true', 'chi non è in fila trova la lezione piena: il posto è tenuto per l''offerta');
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is((public.book_lesson('56000000-0000-0000-0000-000000000003', NULL))->>'reason', 'BOOKED',
  'Bruno, che ha l''offerta, prenota dall''app');
RESET ROLE;
SELECT is(
  (SELECT status::text FROM public.waitlist
    WHERE lesson_id = '56000000-0000-0000-0000-000000000003' AND client_id = (SELECT bruno FROM s6)),
  'booked', 'e prenotando esce dalla fila');

-- Lo staff toglie Carla e la rimette: la riga si riusa (il vecchio vincolo lezione+utente)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"16000000-0000-0000-0000-000000000009","role":"authenticated"}';
SELECT is(
  (public.staff_remove_from_waitlist((SELECT id FROM public.waitlist
     WHERE lesson_id = '56000000-0000-0000-0000-000000000003' AND client_id = (SELECT carla FROM s6))))->>'reason',
  'LEFT', 'lo staff toglie qualcunə dalla fila');
SELECT is((public.staff_add_to_waitlist('56000000-0000-0000-0000-000000000003', (SELECT carla FROM s6)))->>'reason',
  'JOINED', 'e la rimette in fila');
RESET ROLE;
SELECT is(
  (SELECT count(*)::int || ':' || min(status::text) FROM public.waitlist
    WHERE lesson_id = '56000000-0000-0000-0000-000000000003' AND client_id = (SELECT carla FROM s6)),
  '1:waiting', 'sulla stessa riga, in attesa');

-- Un posto in più: va a Carla
UPDATE public.lessons SET capacity = 2 WHERE id = '56000000-0000-0000-0000-000000000003';
SELECT is(
  (SELECT status::text FROM public.waitlist
    WHERE lesson_id = '56000000-0000-0000-0000-000000000003' AND client_id = (SELECT carla FROM s6)),
  'offered', 'aumentando i posti, l''offerta parte da sola');

-- L'offerta scade senza risposta: il job la chiude
UPDATE public.waitlist SET expires_at = now() - interval '1 minute'
 WHERE lesson_id = '56000000-0000-0000-0000-000000000003' AND client_id = (SELECT carla FROM s6);
SELECT is((internal.cron_waitlist())->>'ok', 'true', 'il job della lista d''attesa gira');
SELECT is(
  (SELECT status::text FROM public.waitlist
    WHERE lesson_id = '56000000-0000-0000-0000-000000000003' AND client_id = (SELECT carla FROM s6)),
  'expired', 'e chiude l''offerta scaduta');

-- ═════════════════════════════════════════════════════════════════════════════
-- 4. Promemoria con luogo, e preferenze rispettate
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.bookings (lesson_id, client_id, status, is_trial) VALUES
  ('56000000-0000-0000-0000-000000000004', (SELECT anna FROM s6), 'booked', false),
  ('56000000-0000-0000-0000-000000000004', (SELECT bruno FROM s6), 'booked', false);
INSERT INTO public.notification_preferences (client_id, category, push_enabled, email_enabled)
VALUES ((SELECT bruno FROM s6), 'lesson_reminder', false, false);

SELECT lives_ok($$ SELECT public.queue_lesson_reminders() $$, 'i promemoria si accodano');
SELECT ok(
  (SELECT body FROM public.notification_queue
    WHERE client_id = (SELECT anna FROM s6) AND category = 'lesson_reminder' AND data->>'type' = '2h'
      AND data->>'lesson_id' = '56000000-0000-0000-0000-000000000004')
    LIKE '%presso Sala Media, Via della Biblioteca 1, Staranzano%',
  'il promemoria dice dove');
SELECT is(
  (SELECT count(*)::int FROM public.notification_queue
    WHERE client_id = (SELECT bruno FROM s6) AND category = 'lesson_reminder'),
  0, 'chi ha spento push ed email per i promemoria non li riceve');

-- ═════════════════════════════════════════════════════════════════════════════
-- 5. Ricostruzione del sito
-- ═════════════════════════════════════════════════════════════════════════════

UPDATE public.site_rebuild_state SET requested_at = NULL, triggered_at = NULL WHERE id;
UPDATE public.locations SET access_notes = 'Entrata dal cortile, secondo piano.'
 WHERE id = '36000000-0000-0000-0000-000000000001';
SELECT is((SELECT requested_by FROM public.site_rebuild_state), 'locations',
  'cambiare un luogo chiede di ricostruire il sito');
SELECT is((internal.cron_site_rebuild())->>'reason', 'WAITING_FOR_QUIET',
  'ma si aspetta qualche minuto, per fare una build sola dopo più ritocchi');

UPDATE public.site_rebuild_state SET requested_at = now() - interval '4 minutes' WHERE id;
SELECT is((internal.cron_site_rebuild())->>'reason', 'TRIGGERED', 'passata la quiete, parte');
SELECT is((SELECT count(*)::int FROM edge_calls WHERE name = 'site-rebuild'), 1,
  'chiamando l''edge function site-rebuild una volta');

SELECT * FROM finish();
ROLLBACK;
