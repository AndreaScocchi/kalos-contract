-- Sessione 11: dove porta una notifica, il messaggio dopo la prova, i propri dati, privacy e termini
-- accettati, l'eliminazione dell'account e il ritorno con la stessa email.

BEGIN;
SELECT plan(50);

-- ── Persone ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('1b000000-0000-0000-0000-000000000001', 's11-elena@test.kalos',  '{"full_name":"Elena Undici"}',  'authenticated', 'authenticated'),
  ('1b000000-0000-0000-0000-000000000002', 's11-franco@test.kalos', '{"full_name":"Franco Undici"}', 'authenticated', 'authenticated'),
  ('1b000000-0000-0000-0000-000000000003', 's11-gina@test.kalos',   '{"full_name":"Gina Staff"}',    'authenticated', 'authenticated'),
  ('1b000000-0000-0000-0000-000000000004', 's11-ivo@test.kalos',    '{"full_name":"Ivo Undici"}',    'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '1b000000-0000-0000-0000-000000000003';
UPDATE public.feature_flags SET enabled = false WHERE key IN ('members_only', 'trial_followup');

CREATE TEMP TABLE s11 AS
SELECT (SELECT id FROM public.clients WHERE email = 's11-elena@test.kalos')  AS elena,
       (SELECT id FROM public.clients WHERE email = 's11-franco@test.kalos') AS franco,
       (SELECT id FROM public.clients WHERE email = 's11-ivo@test.kalos')    AS ivo;
GRANT SELECT ON s11 TO authenticated;

INSERT INTO public.activities (id, name, discipline, duration_minutes) VALUES
  ('2b000000-0000-0000-0000-000000000001', 'S11 Yoga', 's11_yoga', 60),
  ('2b000000-0000-0000-0000-000000000002', 'S11 Pilates', 's11_pilates', 60),
  ('2b000000-0000-0000-0000-000000000003', 'S11 Respiro', 's11_respiro', 60);

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity) VALUES
  -- L1: futura, un posto (lo prende Franco, Ivo aspetta)
  ('3b000000-0000-0000-0000-000000000001', '2b000000-0000-0000-0000-000000000001', now() + interval '3 days', now() + interval '3 days 1 hour', 1),
  -- L2: passata, prenotazione di Franco mai segnata
  ('3b000000-0000-0000-0000-000000000002', '2b000000-0000-0000-0000-000000000001', now() - interval '2 days', now() - interval '2 days' + interval '1 hour', 10),
  -- L3 e L4: le prove di Elena
  ('3b000000-0000-0000-0000-000000000003', '2b000000-0000-0000-0000-000000000002', now() + interval '2 days', now() + interval '2 days 1 hour', 10),
  ('3b000000-0000-0000-0000-000000000004', '2b000000-0000-0000-0000-000000000003', now() + interval '2 days', now() + interval '2 days 1 hour', 10),
  -- L5: piena (Ivo), Franco in lista d'attesa
  ('3b000000-0000-0000-0000-000000000005', '2b000000-0000-0000-0000-000000000001', now() + interval '4 days', now() + interval '4 days 1 hour', 1);

INSERT INTO public.plans (id, name, price_cents, entries, validity_days)
VALUES ('4b000000-0000-0000-0000-000000000001', 'S11 Carnet Yoga', 8000, 8, 90);
INSERT INTO public.plan_activities (plan_id, activity_id)
VALUES ('4b000000-0000-0000-0000-000000000001', '2b000000-0000-0000-0000-000000000001');
INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at)
SELECT '5b000000-0000-0000-0000-000000000001'::uuid, franco, '4b000000-0000-0000-0000-000000000001'::uuid,
       CURRENT_DATE - 10, CURRENT_DATE + 80 FROM s11
UNION ALL
SELECT '5b000000-0000-0000-0000-000000000002'::uuid, ivo, '4b000000-0000-0000-0000-000000000001'::uuid,
       CURRENT_DATE - 10, CURRENT_DATE + 80 FROM s11;

-- ═════════════════════════════════════════════════════════════════════════════
-- 1. Dove porta una notifica
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
SELECT elena, c.category::public.notification_category, 'email', 'T', 'B', c.data::jsonb, now() + interval '1 year'
  FROM s11, (VALUES
    ('lesson_reminder',     '{"lesson_id":"3b000000-0000-0000-0000-000000000001","booking_id":"x","tag":"a"}'),
    ('subscription_expiry', '{"subscription_id":"5b000000-0000-0000-0000-000000000001","tag":"b"}'),
    ('birthday',            '{"url":"https://esempio.it/truffa","tag":"c"}'),
    ('re_engagement',       '{"url":"//esempio.it","tag":"d"}'),
    ('feedback_request',    '{"kind":"onboarding","tag":"e"}'),
    ('journal_reminder',    '{"url":"/journal/new","tag":"f"}'),
    ('announcement',        '{"announcement_id":"6b000000-0000-0000-0000-000000000001","tag":"g"}'),
    ('practice_resume',     '{"practice_id":"7b000000-0000-0000-0000-000000000001","tag":"h"}')
  ) AS c(category, data);

SELECT is((SELECT data->>'url' FROM public.notification_queue WHERE data->>'tag' = 'a'),
  '/lesson/3b000000-0000-0000-0000-000000000001', 'un promemoria porta alla lezione');
SELECT is((SELECT data->>'url' FROM public.notification_queue WHERE data->>'tag' = 'b'),
  '/subscriptions', 'la scadenza porta agli abbonamenti');
SELECT is((SELECT data->>'url' FROM public.notification_queue WHERE data->>'tag' = 'c'),
  '/journey', 'un indirizzo esterno non passa: resta la pagina della categoria');
SELECT is((SELECT data->>'url' FROM public.notification_queue WHERE data->>'tag' = 'd'),
  '/calendar', 'nemmeno un «//dominio»');
SELECT ok((SELECT NOT (data ? 'url') FROM public.notification_queue WHERE data->>'tag' = 'e'),
  'senza una pagina dedicata niente url (l''app apre il centro notifiche)');
SELECT is((SELECT data->>'url' FROM public.notification_queue WHERE data->>'tag' = 'f'),
  '/journal/new', 'un percorso dell''app già scritto resta com''è');
SELECT is((SELECT data->>'url' FROM public.notification_queue WHERE data->>'tag' = 'g'),
  '/announcement/6b000000-0000-0000-0000-000000000001', 'un annuncio porta alla sua pagina');
SELECT is((SELECT data->>'url' FROM public.notification_queue WHERE data->>'tag' = 'h'),
  '/practice/7b000000-0000-0000-0000-000000000001', 'riprendi la pratica porta alla pratica');
DELETE FROM public.notification_queue WHERE client_id = (SELECT elena FROM s11);

-- Il centro notifiche: `path` anche per i log scritti prima della sessione 11
INSERT INTO public.notification_logs (client_id, category, channel, title, body, data, status)
SELECT elena, 'entries_low', 'push', 'Ingressi', 'Ti restano 2 ingressi', '{"subscription_id":"5b000000-0000-0000-0000-000000000001"}', 'sent' FROM s11;
INSERT INTO public.announcements (id, title, body, category, is_active, starts_at)
VALUES ('6b000000-0000-0000-0000-000000000002', 'S11 Annuncio', 'Corpo', 'general', true, now() - interval '1 hour');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1b000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is((SELECT i->>'path' FROM jsonb_array_elements(public.get_my_notifications(50, 0)->'items') i
            WHERE i->>'type' = 'push'),
  '/subscriptions', 'il feed dà il percorso di un log di prima, dalla categoria');
SELECT is((SELECT i->>'path' FROM jsonb_array_elements(public.get_my_notifications(50, 0)->'items') i
            WHERE i->>'id' = '6b000000-0000-0000-0000-000000000002'),
  '/announcement/6b000000-0000-0000-0000-000000000002', 'e quello dell''annuncio');
SELECT is((SELECT i->>'route' FROM jsonb_array_elements(public.get_my_notifications(50, 0)->'items') i
            WHERE i->>'type' = 'push'),
  'kalos://profile', 'la vecchia `route` resta com''era');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. Il messaggio dopo la prova
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1b000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.book_trial_lesson('3b000000-0000-0000-0000-000000000003')->>'reason', 'BOOKED', 'Elena prenota la prova di Pilates');
SELECT is(public.book_trial_lesson('3b000000-0000-0000-0000-000000000004')->>'reason', 'BOOKED', 'e quella di Respiro');
RESET ROLE;

-- Le lezioni sono finite da tre ore
UPDATE public.lessons SET starts_at = now() - interval '4 hours', ends_at = now() - interval '3 hours'
 WHERE id IN ('3b000000-0000-0000-0000-000000000003', '3b000000-0000-0000-0000-000000000004');

-- Interruttore spento: la presenza non manda nulla
UPDATE public.bookings SET status = 'attended'
 WHERE is_trial AND lesson_id = '3b000000-0000-0000-0000-000000000003';
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 'trial_followup'), 0,
  'con l''interruttore spento nessun messaggio dopo la prova');

UPDATE public.feature_flags SET enabled = true WHERE key = 'trial_followup';
UPDATE public.bookings SET status = 'attended'
 WHERE is_trial AND lesson_id = '3b000000-0000-0000-0000-000000000004';
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 'trial_followup'), 1,
  'acceso, la presenza alla prova accoda il messaggio');
SELECT is((SELECT data->>'url' FROM public.notification_queue WHERE category = 'trial_followup'),
  '/feedback/trial/' || (SELECT id FROM public.trials WHERE lesson_id = '3b000000-0000-0000-0000-000000000004'),
  'che porta al questionario di quella prova');
SELECT ok((SELECT scheduled_for >= now() - interval '1 second'
                  AND extract(hour FROM scheduled_for AT TIME ZONE 'Europe/Rome') BETWEEN 9 AND 20
             FROM public.notification_queue WHERE category = 'trial_followup'),
  'non prima di adesso e mai di sera o di notte');
SELECT ok((SELECT body LIKE '%abbonamenti%' AND body NOT LIKE '%primo ingresso%' AND title = 'Com''è andata la prova di S11 Respiro?'
             FROM public.notification_queue WHERE category = 'trial_followup'),
  'col nome dell''attività e l''invito ai piani (la prova resta gratuita)');

UPDATE public.bookings SET status = 'no_show' WHERE is_trial AND lesson_id = '3b000000-0000-0000-0000-000000000004';
UPDATE public.bookings SET status = 'attended' WHERE is_trial AND lesson_id = '3b000000-0000-0000-0000-000000000004';
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 'trial_followup'), 1,
  'segnare di nuovo la presenza non manda un secondo messaggio');

-- Chi ha già risposto al questionario non lo riceve
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1b000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.submit_trial_feedback(
    (SELECT id FROM public.trials WHERE lesson_id = '3b000000-0000-0000-0000-000000000003'), 5::smallint,
    '{"accoglienza":"si","livello":"giusto","continuare":"forse"}'::jsonb, NULL)->>'ok',
  'true', 'Elena risponde al questionario della prova di Pilates');
RESET ROLE;
UPDATE public.bookings SET status = 'no_show' WHERE is_trial AND lesson_id = '3b000000-0000-0000-0000-000000000003';
UPDATE public.bookings SET status = 'attended' WHERE is_trial AND lesson_id = '3b000000-0000-0000-0000-000000000003';
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 'trial_followup'), 1,
  'a chi ha già risposto il messaggio non arriva');

-- ═════════════════════════════════════════════════════════════════════════════
-- 3. I propri dati, privacy e termini
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1b000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.update_my_profile('E', NULL, NULL)->>'reason', 'INVALID_NAME', 'un nome di una lettera non passa');
SELECT is(public.update_my_profile('Elena Undici', 'chiamami', NULL)->>'reason', 'INVALID_PHONE', 'nemmeno un telefono di lettere');
SELECT is(public.update_my_profile('Elena Undici', NULL, CURRENT_DATE + 1)->>'reason', 'INVALID_BIRTHDAY', 'né un compleanno nel futuro');
SELECT is(public.update_my_profile('  Elena   Maria Undici ', ' +39 333 123 4567 ', DATE '1990-04-12')->>'ok', 'true',
  'Elena cambia nome, telefono e compleanno');
SELECT is((SELECT full_name || ' | ' || phone || ' | ' || birthday FROM public.clients WHERE id = (SELECT elena FROM s11)),
  'Elena Maria Undici | +39 333 123 4567 | 1990-04-12', 'la scheda dello staff li riceve, ripuliti');
SELECT is((SELECT full_name FROM public.profiles WHERE id = auth.uid()), 'Elena Maria Undici', 'e anche il profilo');

SELECT is(public.accept_my_legal_documents()->>'ok', 'true', 'Elena accetta privacy e termini in vigore');
SELECT ok((SELECT accepted_terms_at IS NOT NULL AND accepted_terms_at = accepted_privacy_at
             FROM public.profiles WHERE id = auth.uid()),
  'col momento registrato dal server, per entrambi');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 4. Eliminazione dell'account
-- ═════════════════════════════════════════════════════════════════════════════

-- Franco: sociə con la quota, note dello staff, prenotazioni future e passate, lista d'attesa,
-- diario, dispositivo, notifiche, una segnalazione, eventi (uno pagato), una vecchia iscrizione
-- legata all'utente.
UPDATE public.clients SET notes = 'Nota dello staff', phone = '3331112222', birthday = DATE '1985-01-01'
 WHERE id = (SELECT franco FROM s11);
INSERT INTO public.members (client_id, member_number, admitted_on) SELECT franco, 'S11-0001', CURRENT_DATE - 20 FROM s11;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1b000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.book_lesson('3b000000-0000-0000-0000-000000000001', '5b000000-0000-0000-0000-000000000001')->>'ok', 'true',
  'Franco prenota l''ultimo posto di una lezione futura');
SET LOCAL request.jwt.claims = '{"sub":"1b000000-0000-0000-0000-000000000004","role":"authenticated"}';
SELECT is(public.book_lesson('3b000000-0000-0000-0000-000000000005', '5b000000-0000-0000-0000-000000000002')->>'ok', 'true',
  'Ivo prende l''unico posto di un''altra');
SELECT is(public.join_waitlist('3b000000-0000-0000-0000-000000000001')->>'ok', 'true', 'e aspetta quella di Franco');
SET LOCAL request.jwt.claims = '{"sub":"1b000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.join_waitlist('3b000000-0000-0000-0000-000000000005')->>'ok', 'true', 'Franco aspetta quella di Ivo');
RESET ROLE;

INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
SELECT '3b000000-0000-0000-0000-000000000002', franco, '5b000000-0000-0000-0000-000000000001', 'booked' FROM s11;
INSERT INTO public.journal_entries (client_id, body) SELECT franco, 'Pensieri' FROM s11;
INSERT INTO public.device_tokens (client_id, expo_push_token, platform) SELECT franco, 'ExponentPushToken[s11franco]', 'ios' FROM s11;
INSERT INTO public.notification_preferences (client_id, category, push_enabled, email_enabled)
SELECT franco, 'lesson_reminder', false, true FROM s11;
INSERT INTO public.notification_logs (client_id, category, channel, title, body, status)
SELECT franco, 'birthday', 'email', 'Auguri', 'Tanti auguri', 'sent' FROM s11;
INSERT INTO public.bug_reports (title, description, created_by_user_id)
VALUES ('Non si apre', 'La pagina resta bianca', '1b000000-0000-0000-0000-000000000002');
INSERT INTO public.events (id, name, starts_at) VALUES
  ('8b000000-0000-0000-0000-000000000001', 'S11 Evento libero', now() + interval '10 days'),
  ('8b000000-0000-0000-0000-000000000002', 'S11 Evento pagato', now() + interval '12 days'),
  ('8b000000-0000-0000-0000-000000000003', 'S11 Evento vecchio', now() - interval '200 days');
INSERT INTO public.event_bookings (id, event_id, client_id, status)
SELECT '9b000000-0000-0000-0000-000000000001'::uuid, '8b000000-0000-0000-0000-000000000001'::uuid, franco, 'booked'::public.booking_status FROM s11
UNION ALL
SELECT '9b000000-0000-0000-0000-000000000002'::uuid, '8b000000-0000-0000-0000-000000000002'::uuid, franco, 'booked'::public.booking_status FROM s11;
INSERT INTO public.event_bookings (id, event_id, user_id, status)
VALUES ('9b000000-0000-0000-0000-000000000003', '8b000000-0000-0000-0000-000000000003', '1b000000-0000-0000-0000-000000000002', 'attended');
INSERT INTO public.transactions (client_id, kind, amount_cents, method, source, status, event_booking_id)
SELECT franco, 'event', 1500, 'cash', 'studio', 'paid', '9b000000-0000-0000-0000-000000000002' FROM s11;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1b000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT throws_ok($$ SELECT public.delete_account_data('1b000000-0000-0000-0000-000000000002') $$, '42501', NULL,
  'dall''app la funzione non si chiama: solo l''edge function, col service role');
RESET ROLE;

SELECT is(public.delete_account_data('1b000000-0000-0000-0000-000000000003')->>'reason', 'STAFF_ACCOUNT',
  'l''account di chi è staff non si elimina dall''app');
SELECT is(public.delete_account_data('1b000000-0000-0000-0000-000000000002')->>'ok', 'true', 'quello di Franco sì');

SELECT is((SELECT status::text FROM public.bookings WHERE lesson_id = '3b000000-0000-0000-0000-000000000001'
             AND client_id = (SELECT franco FROM s11)), 'canceled', 'la prenotazione futura è disdetta');
SELECT is((SELECT count(*)::int FROM public.subscription_usages su JOIN public.bookings b ON b.id = su.booking_id
            WHERE b.lesson_id = '3b000000-0000-0000-0000-000000000001' AND su.delta = 1), 1,
  'e l''ingresso torna all''abbonamento');
SELECT is((SELECT status::text FROM public.waitlist WHERE lesson_id = '3b000000-0000-0000-0000-000000000001'
             AND client_id = (SELECT ivo FROM s11)), 'offered', 'il posto liberato va a chi aspettava');
SELECT is((SELECT status::text FROM public.bookings WHERE lesson_id = '3b000000-0000-0000-0000-000000000002'),
  'booked', 'la prenotazione passata resta com''era (presenze e Finanze)');
SELECT is((SELECT status::text FROM public.waitlist WHERE client_id = (SELECT franco FROM s11)), 'left',
  'Franco esce dalla lista d''attesa');
SELECT is((SELECT string_agg(status::text, ',' ORDER BY id) FROM public.event_bookings
            WHERE id IN ('9b000000-0000-0000-0000-000000000001', '9b000000-0000-0000-0000-000000000002')),
  'canceled,booked', 'l''evento non pagato si disdice, quello pagato lo decide lo staff');
SELECT is((SELECT (SELECT count(*) FROM public.journal_entries WHERE client_id = franco)
                + (SELECT count(*) FROM public.device_tokens WHERE client_id = franco)
                + (SELECT count(*) FROM public.notification_preferences WHERE client_id = franco)
                + (SELECT count(*) FROM public.notification_logs WHERE client_id = franco)
             FROM s11)::int, 0, 'diario, dispositivi e notifiche sono cancellati');
SELECT ok((SELECT deleted_at IS NOT NULL AND NOT is_active AND phone IS NULL AND birthday IS NULL
                  AND NOT newsletter_subscribed
                  AND notes IS NULL
                  AND (SELECT n.notes FROM public.client_staff_notes n WHERE n.client_id = clients.id)
                      LIKE 'Nota dello staff' || E'\n' || 'Account dell''app eliminato dalla persona il %'
             FROM public.clients WHERE id = (SELECT franco FROM s11)),
  'la scheda resta disattivata, senza telefono né compleanno, con le note dello staff intatte');
SELECT is((SELECT status::text FROM public.members WHERE client_id = (SELECT franco FROM s11)), 'active',
  'l''iscrizione all''associazione non cambia');

SELECT lives_ok($$ DELETE FROM auth.users WHERE id = '1b000000-0000-0000-0000-000000000002' $$,
  'poi l''utente di Supabase Auth si cancella senza intoppi');
SELECT ok((SELECT created_by_client_id = (SELECT franco FROM s11) FROM public.bug_reports WHERE title = 'Non si apre')
          AND (SELECT client_id = (SELECT franco FROM s11) FROM public.event_bookings WHERE id = '9b000000-0000-0000-0000-000000000003'),
  'la segnalazione e la vecchia iscrizione restano, intestate alla scheda');

-- Franco torna con la stessa email
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('1b000000-0000-0000-0000-000000000012', 's11-franco@test.kalos', '{"full_name":"Franco Di Nuovo"}', 'authenticated', 'authenticated');
SELECT ok((SELECT profile_id = '1b000000-0000-0000-0000-000000000012' AND deleted_at IS NULL AND is_active
             FROM public.clients WHERE id = (SELECT franco FROM s11)),
  'registrandosi di nuovo ritrova la sua scheda, riattivata');
SELECT is((SELECT count(*)::int FROM public.clients WHERE email = 's11-franco@test.kalos'), 1,
  'senza una seconda scheda');
SELECT is((SELECT member_number FROM public.members m JOIN public.clients c ON c.id = m.client_id
            WHERE c.profile_id = '1b000000-0000-0000-0000-000000000012'),
  'S11-0001', 'e con la sua tessera di sociə');

SELECT * FROM finish();
ROLLBACK;
