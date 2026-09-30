-- Verifica generale del 30/09/2026 (v0.3.10): notifiche che rispettano le preferenze e l'ora
-- italiana, stato di sociə e quote, domanda d'ammissione, note dello staff, registrazione,
-- prenotazioni (abbonamenti eliminati, schede archiviate, lezioni individuali, lista d'attesa),
-- ricevuta sostitutiva, piani e lezioni archiviate dal gestionale.

BEGIN;
SELECT plan(70);

-- ── Persone ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('1c000000-0000-0000-0000-000000000001', 'v30-anna@test.kalos',  '{"full_name":"Anna Trenta"}',  'authenticated', 'authenticated'),
  ('1c000000-0000-0000-0000-000000000002', 'v30-bruno@test.kalos', '{"full_name":"Bruno Trenta"}', 'authenticated', 'authenticated'),
  ('1c000000-0000-0000-0000-000000000003', 'v30-op@test.kalos',    '{"full_name":"Olga Staff"}',   'authenticated', 'authenticated'),
  ('1c000000-0000-0000-0000-000000000004', 'v30-fin@test.kalos',   '{"full_name":"Fabio Tesoriere"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '1c000000-0000-0000-0000-000000000003';
UPDATE public.profiles SET role = 'finance'  WHERE id = '1c000000-0000-0000-0000-000000000004';
UPDATE public.feature_flags SET enabled = false WHERE key IN ('members_only', 'trial_followup');

CREATE TEMP TABLE v30 AS
SELECT (SELECT id FROM public.clients WHERE email = 'v30-anna@test.kalos')  AS anna,
       (SELECT id FROM public.clients WHERE email = 'v30-bruno@test.kalos') AS bruno,
       extract(year FROM internal.rome_today())::int AS yr;
GRANT SELECT ON v30 TO authenticated;

INSERT INTO public.activities (id, name, discipline, duration_minutes, trial_enabled) VALUES
  ('2c000000-0000-0000-0000-000000000001', 'V30 Yoga', 'v30_yoga', 60, true),
  ('2c000000-0000-0000-0000-000000000002', 'V30 Pilates', 'v30_pilates', 60, false);

INSERT INTO public.plans (id, name, price_cents, entries, validity_days) VALUES
  ('4c000000-0000-0000-0000-000000000001', 'V30 Carnet', 8000, 10, 90);
INSERT INTO public.plan_activities (plan_id, activity_id) VALUES
  ('4c000000-0000-0000-0000-000000000001', '2c000000-0000-0000-0000-000000000001');

INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at)
SELECT '5c000000-0000-0000-0000-000000000001'::uuid, anna, '4c000000-0000-0000-0000-000000000001'::uuid, CURRENT_DATE - 30, CURRENT_DATE + 60 FROM v30
UNION ALL
SELECT '5c000000-0000-0000-0000-000000000002'::uuid, anna, '4c000000-0000-0000-0000-000000000001'::uuid, CURRENT_DATE - 30, CURRENT_DATE + 60 FROM v30
UNION ALL
SELECT '5c000000-0000-0000-0000-000000000003'::uuid, bruno, '4c000000-0000-0000-0000-000000000001'::uuid, CURRENT_DATE - 30, CURRENT_DATE + 60 FROM v30;

-- ═════════════════════════════════════════════════════════════════════════════
-- 1. Canale delle notifiche
-- ═════════════════════════════════════════════════════════════════════════════

SELECT is(internal.get_notification_channel((SELECT anna FROM v30), 'birthday'), 'email',
  'senza preferenze e senza dispositivo: email');
INSERT INTO public.notification_preferences (client_id, category, push_enabled, email_enabled)
SELECT anna, 're_engagement'::public.notification_category, false, false FROM v30
UNION ALL SELECT anna, 'birthday'::public.notification_category, false, false FROM v30;
SELECT is(internal.get_notification_channel((SELECT anna FROM v30), 'birthday'), NULL,
  'push ed email spente: nessun canale');
UPDATE public.clients SET email_bounced = true WHERE id = (SELECT bruno FROM v30);
SELECT is(internal.get_notification_channel((SELECT bruno FROM v30), 'birthday'), NULL,
  'un indirizzo che rimbalza non è un canale');
UPDATE public.clients SET email_bounced = false WHERE id = (SELECT bruno FROM v30);

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. «Ci manchi!» una volta per assenza, e mai a chi ha spento tutto
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity) VALUES
  ('3c000000-0000-0000-0000-000000000001', '2c000000-0000-0000-0000-000000000001', now() - interval '10 days', now() - interval '10 days' + interval '1 hour', 10);
INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
SELECT '3c000000-0000-0000-0000-000000000001'::uuid, anna, '5c000000-0000-0000-0000-000000000001'::uuid, 'attended'::public.booking_status FROM v30
UNION ALL
SELECT '3c000000-0000-0000-0000-000000000001'::uuid, bruno, '5c000000-0000-0000-0000-000000000003'::uuid, 'attended'::public.booking_status FROM v30;

SELECT public.queue_re_engagement();
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 're_engagement' AND client_id = (SELECT bruno FROM v30)),
  1, 'Bruno, assente da 10 giorni, riceve «Ci manchi!»');
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 're_engagement' AND client_id = (SELECT anna FROM v30)),
  0, 'Anna ha spento push ed email: niente');
UPDATE public.notification_queue SET status = 'skipped' WHERE category = 're_engagement';
SELECT public.queue_re_engagement();
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 're_engagement' AND client_id = (SELECT bruno FROM v30)),
  1, 'al massimo uno ogni 30 giorni, anche se il precedente è stato saltato');

-- Assente da 100 giorni: «Ci manchi!» ogni mese finché non torna (decisione del 30/09)
UPDATE public.lessons SET starts_at = now() - interval '100 days', ends_at = now() - interval '100 days' + interval '1 hour'
 WHERE id = '3c000000-0000-0000-0000-000000000001';
UPDATE public.notification_queue SET created_at = now() - interval '31 days' WHERE category = 're_engagement';
SELECT public.queue_re_engagement();
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 're_engagement'
             AND client_id = (SELECT bruno FROM v30) AND created_at > now() - interval '1 day'),
  1, 'dopo 30 giorni riparte, anche dopo 100 giorni di assenza');
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 're_engagement'
             AND client_id = (SELECT anna FROM v30)),
  0, 'chi ha spento tutto non lo riceve mai');
DELETE FROM public.bookings WHERE lesson_id = '3c000000-0000-0000-0000-000000000001';

-- ═════════════════════════════════════════════════════════════════════════════
-- 3. Ingressi in esaurimento e compleanno
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.subscription_usages (subscription_id, delta, reason)
SELECT '5c000000-0000-0000-0000-000000000003', -8, 'test' ;
SELECT public.queue_entries_low();
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 'entries_low'
             AND client_id = (SELECT bruno FROM v30)), 1,
  '2 ingressi rimasti: un avviso');
UPDATE public.notification_queue SET status = 'skipped' WHERE category = 'entries_low';
SELECT public.queue_entries_low();
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 'entries_low'
             AND client_id = (SELECT bruno FROM v30)), 1,
  'un avviso saltato non si riaccoda il giorno dopo');

UPDATE public.clients SET birthday = (internal.rome_today() - interval '30 years')::date
 WHERE id IN (SELECT anna FROM v30 UNION ALL SELECT bruno FROM v30);
SELECT public.queue_birthday();
SELECT is((SELECT string_agg(c.email, ',') FROM public.notification_queue q JOIN public.clients c ON c.id = q.client_id
            WHERE q.category = 'birthday' AND c.email LIKE 'v30-%'), 'v30-bruno@test.kalos',
  'auguri a Bruno; Anna li ha spenti');

-- ═════════════════════════════════════════════════════════════════════════════
-- 4. Promemoria: alle 20 italiane, ritirati se la prenotazione non c'è più
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity) VALUES
  ('3c000000-0000-0000-0000-000000000002', '2c000000-0000-0000-0000-000000000001',
   ((internal.rome_today() + 1) + time '18:00') AT TIME ZONE 'Europe/Rome',
   ((internal.rome_today() + 1) + time '19:00') AT TIME ZONE 'Europe/Rome', 10);
INSERT INTO public.bookings (id, lesson_id, client_id, subscription_id, status)
SELECT '6c000000-0000-0000-0000-000000000001', '3c000000-0000-0000-0000-000000000002', bruno, '5c000000-0000-0000-0000-000000000003', 'booked' FROM v30;
SELECT public.queue_lesson_reminders();
SELECT ok(NOT EXISTS (SELECT 1 FROM public.notification_queue
                       WHERE category = 'lesson_reminder' AND data->>'type' = 'evening'
                         AND scheduled_for <> (internal.rome_today() + time '20:00') AT TIME ZONE 'Europe/Rome'),
  'il promemoria della sera è programmato alle 20:00 italiane');
INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
SELECT bruno, 'lesson_reminder', 'email', 'T', 'B',
       jsonb_build_object('booking_id', '6c000000-0000-0000-0000-000000000001', 'lesson_id', '3c000000-0000-0000-0000-000000000002', 'type', 'test'),
       now() + interval '1 day' FROM v30;
UPDATE public.bookings SET status = 'canceled' WHERE id = '6c000000-0000-0000-0000-000000000001';
SELECT is((SELECT count(*)::int FROM public.notification_queue
            WHERE category = 'lesson_reminder' AND status = 'pending'
              AND data->>'booking_id' = '6c000000-0000-0000-0000-000000000001'),
  0, 'disdetta la prenotazione, il promemoria in coda sparisce');

-- ═════════════════════════════════════════════════════════════════════════════
-- 5. Annunci ricorrenti in ora italiana
-- ═════════════════════════════════════════════════════════════════════════════

SELECT is(public.calculate_next_announcement_occurrence('weekly', 1::smallint, NULL, '19:00', '2026-09-30 10:00+00'),
  '2026-10-05 17:00+00'::timestamptz, 'lunedì alle 19 italiane, d''estate');
SELECT is(public.calculate_next_announcement_occurrence('daily', NULL, NULL, '19:00', '2026-12-01 10:00+00'),
  '2026-12-01 18:00+00'::timestamptz, 'ogni giorno alle 19 italiane, d''inverno');
SELECT is(public.calculate_next_announcement_occurrence('monthly', NULL, 31::smallint, '09:00', '2027-02-10 10:00+00'),
  '2027-02-28 08:00+00'::timestamptz, 'il 31 in un mese corto diventa l''ultimo giorno');

-- ═════════════════════════════════════════════════════════════════════════════
-- 6. Richiesta di parere e nuovo evento
-- ═════════════════════════════════════════════════════════════════════════════

SELECT ok(NOT has_function_privilege('authenticated',
  'public.queue_feedback_request(uuid, public.feedback_kind, uuid, timestamptz)', 'EXECUTE'),
  'unə cliente non può accodare richieste di parere');

INSERT INTO public.events (id, name, starts_at, ends_at, is_active) VALUES
  ('7c000000-0000-0000-0000-000000000001', 'V30 Bozza', now() + interval '10 days', now() + interval '10 days 2 hours', false),
  ('7c000000-0000-0000-0000-000000000002', 'V30 Laboratorio', now() + interval '10 days', now() + interval '10 days 2 hours', true);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is((public.queue_new_event('7c000000-0000-0000-0000-000000000001', 'V30 Bozza', now() + interval '10 days', false, true))->>'reason',
  'EVENT_NOT_PUBLISHED', 'una bozza non si annuncia');
SELECT ok(((public.queue_new_event('7c000000-0000-0000-0000-000000000002', 'V30 Laboratorio', now() + interval '10 days', false, true))->>'queued_email')::int > 0,
  'evento pubblicato: parte l''email');
SELECT is((public.queue_new_event('7c000000-0000-0000-0000-000000000002', 'V30 Laboratorio', now() + interval '10 days', false, true))->>'queued_email',
  '0', 'una volta sola per evento');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 7. Stato di sociə e quote
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.association_years (year, fee_cents, fee_due_date, is_open)
VALUES (extract(year FROM internal.rome_today())::int, NULL, internal.rome_today() - 10, true)
ON CONFLICT (year) DO UPDATE SET fee_cents = NULL, fee_due_date = internal.rome_today() - 10, is_open = true;
INSERT INTO public.members (client_id, member_number, admitted_on, status)
SELECT anna, 'V30-0001', internal.rome_today() - 60, 'active' FROM v30;

SELECT is(internal.member_booking_status((SELECT anna FROM v30)), 'fee_due_grace',
  'decadenza passata ma quota senza importo deliberato: non scade');
UPDATE public.association_years SET fee_cents = 3000 WHERE year = extract(year FROM internal.rome_today())::int;
SELECT is(internal.member_booking_status((SELECT anna FROM v30)), 'fee_overdue',
  'con l''importo deliberato e la decadenza passata: quota scaduta');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is((public.staff_set_member_fee((SELECT anna FROM v30), (SELECT yr FROM v30), 'waived'))->>'reason',
  'FINANCE_ONLY', 'un''operatrice non esonera dalla quota');
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000004","role":"authenticated"}';
SELECT is((public.staff_set_member_fee((SELECT anna FROM v30), (SELECT yr FROM v30), 'waived'))->>'ok',
  'true', 'il Tesoriere sì');
RESET ROLE;
SELECT is(internal.member_booking_status((SELECT anna FROM v30)), 'ok', 'quota esonerata: in regola');

-- ═════════════════════════════════════════════════════════════════════════════
-- 8. Domanda d'ammissione: canale, IP e dispositivo solo dall'edge function
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is((public.submit_member_application(jsonb_build_object(
    'first_name', 'Bruno', 'last_name', 'Trenta', 'birth_date', '1990-01-01',
    'accepted_statute', true, 'accepted_privacy', true,
    'channel', 'paper', 'ip', '1.2.3.4', 'user_agent', 'finto')))->>'ok',
  'true', 'la domanda chiamata direttamente si registra');
RESET ROLE;
SELECT is((SELECT channel::text || '|' || COALESCE(host(submitted_ip), '-') || '|' || COALESCE(submitted_user_agent, '-')
             FROM public.member_applications WHERE client_id = (SELECT bruno FROM v30)),
  'app|-|-', '…ma canale, IP e dispositivo inventati non passano');
DELETE FROM public.member_fees WHERE client_id = (SELECT bruno FROM v30);
DELETE FROM public.member_applications WHERE client_id = (SELECT bruno FROM v30);

SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SELECT is((public.submit_member_application(jsonb_build_object(
    'user_id', '1c000000-0000-0000-0000-000000000002',
    'first_name', 'Bruno', 'last_name', 'Trenta', 'birth_date', '1990-01-01',
    'accepted_statute', true, 'accepted_privacy', true,
    'channel', 'site', 'ip', '5.6.7.8', 'user_agent', 'Safari')))->>'ok',
  'true', 'dall''edge function (chiave di sistema) con l''utente del token');
RESET ROLE;
SELECT is((SELECT channel::text || '|' || host(submitted_ip) || '|' || submitted_user_agent
             FROM public.member_applications WHERE client_id = (SELECT bruno FROM v30)),
  'site|5.6.7.8|Safari', 'canale, IP e dispositivo scritti dall''edge function');

-- Domanda su carta per una persona nuova: la scheda nasce solo se la domanda va
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is((public.staff_create_member_application(NULL, jsonb_build_object(
    'year', 1990, 'first_name', 'Carla', 'last_name', 'Carta', 'birth_date', '1980-05-05', 'email', 'v30-carla@test.kalos')))->>'reason',
  'YEAR_NOT_OPEN', 'anno chiuso: domanda rifiutata…');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.clients WHERE email = 'v30-carla@test.kalos'), 0,
  '…e nessuna scheda rimasta');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT ok((public.staff_create_member_application(NULL, jsonb_build_object(
    'first_name', 'Carla', 'last_name', 'Carta', 'birth_date', '1980-05-05', 'email', 'V30-Carla@test.kalos')))->>'client_id' IS NOT NULL,
  'domanda su carta di una persona nuova: la scheda nasce con la domanda');
SELECT is((public.staff_create_member_application(NULL, jsonb_build_object(
    'first_name', 'Carla', 'last_name', 'Carta', 'birth_date', '1980-05-05', 'email', 'v30-carla@test.kalos')))->>'reason',
  'CLIENT_EMAIL_EXISTS', 'la stessa email con le maiuscole diverse non crea un doppione');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 9. Note dello staff
-- ═════════════════════════════════════════════════════════════════════════════

UPDATE public.clients SET notes = 'Paga a fine mese' WHERE id = (SELECT anna FROM v30);
SELECT is((SELECT notes FROM public.client_staff_notes WHERE client_id = (SELECT anna FROM v30)),
  'Paga a fine mese', 'la nota scritta sulla scheda passa fra le note dello staff');
SELECT is((SELECT notes FROM public.clients WHERE id = (SELECT anna FROM v30)), NULL,
  'sulla scheda non resta');
UPDATE public.clients SET notes = '' WHERE id = (SELECT anna FROM v30);
SELECT is((SELECT notes FROM public.client_staff_notes WHERE client_id = (SELECT anna FROM v30)),
  'Paga a fine mese', 'un modulo con le note vuote non le cancella');
SELECT is((SELECT notes FROM public.profiles WHERE id = '1c000000-0000-0000-0000-000000000001'), NULL,
  'il profilo non copia le note');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM public.client_staff_notes), 0, 'la persona non legge le note dello staff');
SELECT is((public.set_my_newsletter_subscription(false))->>'ok', 'true', 'si disiscrive dall''app');
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM public.client_staff_notes WHERE client_id = (SELECT anna FROM v30)), 1,
  'lo staff sì');
RESET ROLE;
SELECT ok(NOT (SELECT newsletter_subscribed FROM public.clients WHERE id = (SELECT anna FROM v30)),
  'newsletter spenta sulla scheda');

-- ═════════════════════════════════════════════════════════════════════════════
-- 10. Registrazione
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.clients (full_name, email) VALUES ('Dora Maiuscola', 'V30-Dora@Test.Kalos');
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('1c000000-0000-0000-0000-000000000005', 'v30-dora@test.kalos',
   '{"full_name":"Dora","newsletter_opt_out":true,"accepted_privacy_at":"x","accepted_terms_at":"x"}', 'authenticated', 'authenticated');
SELECT is((SELECT count(*)::int FROM public.clients WHERE lower(email) = 'v30-dora@test.kalos'), 1,
  'l''email con le maiuscole diverse ritrova la scheda, niente doppione');
SELECT is((SELECT profile_id FROM public.clients WHERE lower(email) = 'v30-dora@test.kalos'),
  '1c000000-0000-0000-0000-000000000005'::uuid, 'scheda collegata all''account');
SELECT ok(NOT (SELECT newsletter_subscribed FROM public.clients WHERE lower(email) = 'v30-dora@test.kalos'),
  '«Non voglio ricevere la newsletter» registrato');
SELECT ok((SELECT accepted_privacy_at IS NOT NULL AND accepted_terms_at IS NOT NULL
             FROM public.profiles WHERE id = '1c000000-0000-0000-0000-000000000005'),
  'privacy e termini accettati nel modulo registrati');

-- ═════════════════════════════════════════════════════════════════════════════
-- 11. Prenotazioni
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity) VALUES
  ('3c000000-0000-0000-0000-000000000003', '2c000000-0000-0000-0000-000000000001', now() + interval '3 days', now() + interval '3 days 1 hour', 1),
  ('3c000000-0000-0000-0000-000000000004', '2c000000-0000-0000-0000-000000000002', now() + interval '3 days', now() + interval '3 days 1 hour', 1);
UPDATE public.subscriptions SET deleted_at = now() WHERE id = '5c000000-0000-0000-0000-000000000002';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is((public.book_lesson('3c000000-0000-0000-0000-000000000003', '5c000000-0000-0000-0000-000000000002'))->>'reason',
  'SUBSCRIPTION_NOT_FOUND_OR_INACTIVE', 'un abbonamento eliminato dallo staff non prenota');
SELECT is((public.book_lesson('3c000000-0000-0000-0000-000000000003', '5c000000-0000-0000-0000-000000000001'))->>'ok',
  'true', 'Anna prenota l''ultimo posto');
-- Bruno: lezione piena di un'attività senza prova e senza abbonamento che la copra
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000002","role":"authenticated"}';
RESET ROLE;
INSERT INTO public.bookings (lesson_id, client_id, status)
SELECT '3c000000-0000-0000-0000-000000000004', anna, 'booked' FROM v30;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is((public.join_waitlist('3c000000-0000-0000-0000-000000000004'))->>'reason',
  'SUBSCRIPTION_REQUIRED', 'in lista d''attesa solo chi poi potrebbe prenotare');
RESET ROLE;

UPDATE public.clients SET deleted_at = now() WHERE id = (SELECT bruno FROM v30);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is((public.book_lesson('3c000000-0000-0000-0000-000000000003', '5c000000-0000-0000-0000-000000000003'))->>'reason',
  'CLIENT_NOT_FOUND', 'una scheda archiviata non prenota dall''app');
RESET ROLE;
UPDATE public.clients SET deleted_at = NULL WHERE id = (SELECT bruno FROM v30);

-- Stato dal gestionale: una disdetta non torna prenotata
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is((public.staff_update_booking_status('6c000000-0000-0000-0000-000000000001', 'booked'))->>'reason',
  'BOOKING_CANCELED', 'una prenotazione disdetta si rifà, non si «riattiva» cambiando lo stato');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 12. Lezioni individuali: cambio di abbonamento e di persona
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at)
SELECT '5c000000-0000-0000-0000-000000000004'::uuid, anna, '4c000000-0000-0000-0000-000000000001'::uuid, CURRENT_DATE - 1, CURRENT_DATE + 60 FROM v30;
INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity, is_individual, assigned_client_id, assigned_subscription_id)
SELECT '3c000000-0000-0000-0000-000000000005', '2c000000-0000-0000-0000-000000000001', now() + interval '5 days', now() + interval '5 days 1 hour', 1,
       true, anna, '5c000000-0000-0000-0000-000000000001' FROM v30;
UPDATE public.lessons SET assigned_client_id = assigned_client_id WHERE id = '3c000000-0000-0000-0000-000000000005';

CREATE TEMP TABLE v30_usage AS
SELECT (SELECT COALESCE(sum(delta), 0) FROM public.subscription_usages WHERE subscription_id = '5c000000-0000-0000-0000-000000000001') AS s1,
       (SELECT COALESCE(sum(delta), 0) FROM public.subscription_usages WHERE subscription_id = '5c000000-0000-0000-0000-000000000004') AS s4;

UPDATE public.lessons SET assigned_subscription_id = '5c000000-0000-0000-0000-000000000004'
 WHERE id = '3c000000-0000-0000-0000-000000000005';
SELECT is((SELECT COALESCE(sum(delta), 0) FROM public.subscription_usages WHERE subscription_id = '5c000000-0000-0000-0000-000000000001')
          - (SELECT s1 FROM v30_usage), 1::bigint,
  'cambiando abbonamento il vecchio riprende l''ingresso (uno, non due)');
SELECT is((SELECT COALESCE(sum(delta), 0) FROM public.subscription_usages WHERE subscription_id = '5c000000-0000-0000-0000-000000000004')
          - (SELECT s4 FROM v30_usage), -1::bigint,
  '…e il nuovo lo consuma');
UPDATE public.lessons SET assigned_subscription_id = '5c000000-0000-0000-0000-000000000001'
 WHERE id = '3c000000-0000-0000-0000-000000000005';
SELECT is((SELECT COALESCE(sum(delta), 0) FROM public.subscription_usages WHERE subscription_id = '5c000000-0000-0000-0000-000000000004')
          - (SELECT s4 FROM v30_usage), 0::bigint,
  'un secondo cambio non va in errore e riporta tutto com''era');
SELECT lives_ok($$ UPDATE public.lessons SET assigned_client_id = (SELECT bruno FROM v30), assigned_subscription_id = '5c000000-0000-0000-0000-000000000003'
                   WHERE id = '3c000000-0000-0000-0000-000000000005' $$,
  'cambiare la persona non va più in errore');
SELECT is((SELECT COALESCE(sum(delta), 0) FROM public.subscription_usages WHERE subscription_id = '5c000000-0000-0000-0000-000000000001')
          - (SELECT s1 FROM v30_usage), 1::bigint,
  'l''ingresso di Anna torna una volta sola');

-- ═════════════════════════════════════════════════════════════════════════════
-- 13. Evento iniziato: dall'app non si disdice più
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.events (id, name, starts_at, ends_at, is_active) VALUES
  ('7c000000-0000-0000-0000-000000000003', 'V30 In corso', now() - interval '1 hour', now() + interval '1 hour', true);
INSERT INTO public.event_bookings (id, event_id, client_id, status)
SELECT '8c000000-0000-0000-0000-000000000001', '7c000000-0000-0000-0000-000000000003', bruno, 'booked' FROM v30;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is((public.cancel_event_booking('8c000000-0000-0000-0000-000000000001'))->>'reason',
  'CANNOT_CANCEL_CONCLUDED', 'un evento iniziato non si disdice dall''app');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 14. Prova non fatta: non diventa il primo ingresso
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.bookings (id, lesson_id, client_id, status, is_trial)
SELECT '6c000000-0000-0000-0000-000000000002', '3c000000-0000-0000-0000-000000000001', bruno, 'no_show', true FROM v30;
INSERT INTO public.trials (client_id, activity_id, lesson_id, booking_id, status)
SELECT bruno, '2c000000-0000-0000-0000-000000000001', '3c000000-0000-0000-0000-000000000001', '6c000000-0000-0000-0000-000000000002', 'no_show' FROM v30;
INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at)
SELECT '5c000000-0000-0000-0000-000000000005'::uuid, bruno, '4c000000-0000-0000-0000-000000000001'::uuid, CURRENT_DATE, CURRENT_DATE + 90 FROM v30;
SELECT is((SELECT status::text FROM public.trials WHERE booking_id = '6c000000-0000-0000-0000-000000000002'), 'no_show',
  'una prova a cui non si è venutə non si converte');

-- ═════════════════════════════════════════════════════════════════════════════
-- 15. Ricevuta annullata e sostituita
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000004","role":"authenticated"}';
SELECT ok((public.staff_register_payment(jsonb_build_object(
    'client_id', (SELECT bruno FROM v30), 'kind', 'event', 'amount_cents', 2000, 'method', 'cash',
    'source', 'studio', 'issue_receipt', true)))->>'ok' = 'true', 'incasso con ricevuta');
CREATE TEMP TABLE v30_tx AS
SELECT t.id AS tx, r.id AS receipt FROM public.transactions t JOIN public.receipts r ON r.transaction_id = t.id
 WHERE t.client_id = (SELECT bruno FROM v30) ORDER BY t.created_at DESC LIMIT 1;
GRANT SELECT ON v30_tx TO authenticated;
SELECT is((public.void_receipt((SELECT receipt FROM v30_tx), 'Importo sbagliato'))->>'ok', 'true', 'ricevuta annullata');
SELECT is((public.issue_receipt((SELECT tx FROM v30_tx), NULL))->>'ok', 'true',
  'si emette la ricevuta sostitutiva per lo stesso incasso');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.receipts WHERE transaction_id = (SELECT tx FROM v30_tx) AND voided_at IS NULL), 1,
  'l''incasso ha una ricevuta valida');
SELECT is((SELECT replaced_transaction_id FROM public.receipts WHERE id = (SELECT receipt FROM v30_tx)), (SELECT tx FROM v30_tx),
  'quella annullata ricorda di quale incasso era');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(jsonb_array_length(public.get_my_receipts()->'items'), 2,
  'la persona vede sia l''annullata sia la nuova');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 16. Gestionale: piano con le attività, lezioni archiviate
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1c000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is((public.staff_save_plan(NULL, '{"name":"V30 Nuovo","price_cents":5000,"validity_days":30,"entries":4}', '{}'))->>'reason',
  'ACTIVITIES_REQUIRED', 'un piano senza attività non si salva (varrebbe per tutte)');
CREATE TEMP TABLE v30_plan AS
SELECT ((public.staff_save_plan(NULL, '{"name":"V30 Nuovo","price_cents":5000,"validity_days":30,"entries":4}',
                                ARRAY['2c000000-0000-0000-0000-000000000002'::uuid]))->>'plan_id')::uuid AS id;
SELECT is((SELECT count(*)::int FROM public.plan_activities WHERE plan_id = (SELECT id FROM v30_plan)),
  1, 'piano e attività nello stesso gesto');

SELECT is((public.staff_archive_lessons(ARRAY['3c000000-0000-0000-0000-000000000003'::uuid], NULL))->>'canceled_bookings',
  '1', 'archiviando una lezione futura la prenotazione si disdice');
RESET ROLE;
SELECT ok((SELECT deleted_at IS NOT NULL FROM public.lessons WHERE id = '3c000000-0000-0000-0000-000000000003'),
  'la lezione è archiviata');
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 'lesson_canceled'
            AND data->>'lesson_id' = '3c000000-0000-0000-0000-000000000003'), 1,
  'e chi era prenotatə riceve «Lezione annullata»');

SELECT ok(NOT has_column_privilege('authenticated', 'public.social_connections', 'access_token', 'SELECT'),
  'il token delle pagine Meta non si legge dall''API');

-- Domande respinte: dopo 12 mesi si cancellano (privacy §7), prima no
INSERT INTO public.member_applications (client_id, year, channel, status, first_name, last_name, birth_date,
                                         accepted_statute_at, accepted_privacy_at, decided_at, rejection_reason)
SELECT bruno, yr, 'paper'::public.member_application_channel, 'rejected'::public.member_application_status, 'Vecchia', 'Respinta', '1990-01-01'::date, now(), now(), now() - interval '13 months', 'Prova' FROM v30
UNION ALL
SELECT bruno, yr, 'paper', 'rejected', 'Recente', 'Respinta', '1990-01-01', now(), now(), now() - interval '2 months', 'Prova' FROM v30;
SELECT internal.purge_rejected_applications();
SELECT is((SELECT string_agg(first_name, ',') FROM public.member_applications
            WHERE client_id = (SELECT bruno FROM v30) AND status = 'rejected'), 'Recente',
  'la domanda respinta da più di 12 mesi è cancellata, quella recente resta');

SELECT * FROM finish();
ROLLBACK;
