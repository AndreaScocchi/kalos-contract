-- Sessione 9: acquisti dall'app, abbonamenti che partono dal primo ingresso (D5), eventi pagati,
-- "da saldare" saldati con carta, avviso allo staff per le prove dall'app, piani archiviati.
--
-- Il webhook passa sempre da `stripe_apply_payment_state`: qui la si chiama con gli stati che Stripe
-- racconta, dopo aver creato la riga del pagamento come la crea `stripe-checkout`.

BEGIN;
SELECT plan(56);

-- ── Persone ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('19000000-0000-0000-0000-000000000001', 's9-anna@test.kalos',  '{"full_name":"Anna Nove"}',  'authenticated', 'authenticated'),
  ('19000000-0000-0000-0000-000000000002', 's9-bruno@test.kalos', '{"full_name":"Bruno Nove"}', 'authenticated', 'authenticated'),
  ('19000000-0000-0000-0000-000000000003', 's9-admin@test.kalos', '{"full_name":"Admin Nove"}', 'authenticated', 'authenticated'),
  ('19000000-0000-0000-0000-000000000004', 's9-ope@test.kalos',   '{"full_name":"Operatrice Nove"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'admin'    WHERE id = '19000000-0000-0000-0000-000000000003';
UPDATE public.profiles SET role = 'operator' WHERE id = '19000000-0000-0000-0000-000000000004';

UPDATE public.feature_flags SET enabled = false WHERE key IN ('payments', 'members_only');
INSERT INTO public.feature_flags (key, enabled) VALUES ('stripe_test_ledger', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;

CREATE TEMP TABLE s9 AS
SELECT (SELECT id FROM public.clients WHERE email = 's9-anna@test.kalos')  AS anna,
       (SELECT id FROM public.clients WHERE email = 's9-bruno@test.kalos') AS bruno,
       (now() AT TIME ZONE 'Europe/Rome')::date AS today;
GRANT SELECT ON s9 TO authenticated;

-- Un giorno alle 18 (ora italiana), a `n` giorni da oggi
CREATE FUNCTION pg_temp.at(n integer) RETURNS timestamptz LANGUAGE sql AS $$
  SELECT (((SELECT today FROM s9) + n)::timestamp + time '18:00') AT TIME ZONE 'Europe/Rome'
$$;

-- Lo stato "pagato" come lo rilegge il webhook
CREATE FUNCTION pg_temp.paid(p_sp uuid, p_pi text, p_amount integer) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'stripe_payment_id', p_sp,
    'payment_intent', jsonb_build_object(
      'id', p_pi, 'status', 'succeeded', 'amount_received', p_amount, 'currency', 'eur',
      'livemode', false, 'payment_method_type', 'card',
      'charge', jsonb_build_object('created', extract(epoch from now())::bigint,
                                   'fee_cents', 50, 'net_cents', p_amount - 50)),
    'refunds', '[]'::jsonb)
$$;

-- ── Offerta ──────────────────────────────────────────────────────────────────
INSERT INTO public.activities (id, name, discipline, duration_minutes) VALUES
  ('29000000-0000-0000-0000-000000000001', 'S9 Yoga', 's9_yoga', 60);

INSERT INTO public.operators (id, name, role, profile_id) VALUES
  ('39000000-0000-0000-0000-000000000001', 'S9 Operatrice', 'Insegnante', '19000000-0000-0000-0000-000000000004');

INSERT INTO public.plans (id, name, price_cents, entries, validity_days, discount_percent) VALUES
  ('49000000-0000-0000-0000-000000000001', 'S9 Carnet 10', 8000, 10, 90, 10);
INSERT INTO public.plan_activities (plan_id, activity_id) VALUES
  ('49000000-0000-0000-0000-000000000001', '29000000-0000-0000-0000-000000000001');

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity, operator_id) VALUES
  ('59000000-0000-0000-0000-000000000001', '29000000-0000-0000-0000-000000000001', pg_temp.at(10),  pg_temp.at(10)  + interval '1 hour', 10, NULL),
  ('59000000-0000-0000-0000-000000000002', '29000000-0000-0000-0000-000000000001', pg_temp.at(5),   pg_temp.at(5)   + interval '1 hour', 10, NULL),
  ('59000000-0000-0000-0000-000000000003', '29000000-0000-0000-0000-000000000001', pg_temp.at(100), pg_temp.at(100) + interval '1 hour', 10, NULL),
  ('59000000-0000-0000-0000-000000000004', '29000000-0000-0000-0000-000000000001', pg_temp.at(20),  pg_temp.at(20)  + interval '1 hour', 10, NULL),
  ('59000000-0000-0000-0000-000000000005', '29000000-0000-0000-0000-000000000001', pg_temp.at(3),   pg_temp.at(3)   + interval '1 hour', 10, '39000000-0000-0000-0000-000000000001'),
  ('59000000-0000-0000-0000-000000000006', '29000000-0000-0000-0000-000000000001', pg_temp.at(4),   pg_temp.at(4)   + interval '1 hour', 10, '39000000-0000-0000-0000-000000000001'),
  ('59000000-0000-0000-0000-000000000007', '29000000-0000-0000-0000-000000000001', pg_temp.at(15),  pg_temp.at(15)  + interval '1 hour', 10, NULL);

INSERT INTO public.events (id, name, starts_at, ends_at, price_cents, capacity) VALUES
  ('69000000-0000-0000-0000-000000000001', 'S9 Laboratorio', pg_temp.at(7),  pg_temp.at(7)  + interval '2 hours', 1500, 1),
  ('69000000-0000-0000-0000-000000000002', 'S9 Passato',     pg_temp.at(-2), pg_temp.at(-2) + interval '2 hours', 1000, NULL),
  ('69000000-0000-0000-0000-000000000003', 'S9 Incontro',    pg_temp.at(8),  pg_temp.at(8)  + interval '2 hours', 1000, NULL),
  ('69000000-0000-0000-0000-000000000004', 'S9 Piccolo',     pg_temp.at(9),  pg_temp.at(9)  + interval '2 hours', 0, 1);

-- ═════════════════════════════════════════════════════════════════════════════
-- 1. Si può comprare il piano?
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.prepare_my_plan_purchase('49000000-0000-0000-0000-000000000001')->>'reason', 'PAYMENTS_DISABLED',
  'con i pagamenti spenti non si compra nulla');
RESET ROLE;

UPDATE public.feature_flags SET enabled = true WHERE key = 'payments';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.prepare_my_plan_purchase('49000000-0000-0000-0000-000000000001')->>'reason', 'PLAN_NOT_SOLD_IN_APP',
  'un piano non messo in vendita nell''app non si compra');
RESET ROLE;

UPDATE public.plans SET sold_in_app = true WHERE id = '49000000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is((public.prepare_my_plan_purchase('49000000-0000-0000-0000-000000000001')->>'amount_cents')::int, 7200,
  'l''importo lo decide il database, con lo sconto del piano (80 € meno 10%)');
SELECT is(public.prepare_my_plan_purchase('49000000-0000-0000-0000-000000000001')->'plan'->>'validity_days', '90',
  'la fotografia del piano viaggia col pagamento');
RESET ROLE;

UPDATE public.feature_flags SET enabled = true WHERE key = 'members_only';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.prepare_my_plan_purchase('49000000-0000-0000-0000-000000000001')->>'reason', 'NOT_A_MEMBER',
  'con «solo soci» accesa, chi non è sociə non compra abbonamenti');
RESET ROLE;
UPDATE public.feature_flags SET enabled = false WHERE key = 'members_only';

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. Il pagamento crea l'abbonamento
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.stripe_payments (id, checkout_session_id, client_id, purpose, target_id, amount_cents, source, metadata, livemode)
SELECT '99000000-0000-0000-0000-000000000001', 'cs_test_s9_piano', anna, 'subscription',
       '49000000-0000-0000-0000-000000000001', 7200, 'app',
       jsonb_build_object('kind', 'new_subscription', 'title', 'Abbonamento S9 Carnet 10',
         'plan', jsonb_build_object('plan_id', '49000000-0000-0000-0000-000000000001', 'name', 'S9 Carnet 10',
                                    'entries', 10, 'validity_days', 90, 'price_cents', 8000)),
       false
  FROM s9;

SELECT is(public.stripe_apply_payment_state(pg_temp.paid('99000000-0000-0000-0000-000000000001', 'pi_s9_piano', 7200))->>'ok',
  'true', 'il pagamento dell''abbonamento si applica');

SELECT is(
  (SELECT concat_ws(' | ', s.started_at - d.today, s.activation_deadline - d.today, s.expires_at - d.today,
                    s.starts_on_first_entry, COALESCE(s.first_entry_on::text, 'nessun ingresso'))
     FROM public.subscriptions s, s9 d WHERE s.client_id = d.anna),
  '0 | 60 | 150 | t | nessun ingresso',
  'D5: parte dal primo ingresso, entro 60 giorni; scadenza provvisoria = 60 + 90 giorni');

SELECT is(
  (SELECT concat_ws(' | ', t.kind, t.source, t.subscription_id IS NOT NULL, t.amount_cents)
     FROM public.transactions t WHERE t.stripe_payment_id = '99000000-0000-0000-0000-000000000001'),
  'subscription | app | t | 7200', 'l''incasso è collegato all''abbonamento e viene dall''app');

SELECT is(
  (SELECT count(*)::int FROM public.receipts r JOIN public.transactions t ON t.id = r.transaction_id
    WHERE t.stripe_payment_id = '99000000-0000-0000-0000-000000000001'),
  1, 'con la sua ricevuta');

SELECT public.stripe_apply_payment_state(pg_temp.paid('99000000-0000-0000-0000-000000000001', 'pi_s9_piano', 7200));
SELECT is((SELECT count(*)::int FROM public.subscriptions s, s9 WHERE s.client_id = s9.anna), 1,
  'Stripe che riconsegna lo stesso pagamento non crea un secondo abbonamento');

-- Un pagamento di prova dove il registro non è ammesso (come in produzione) non crea abbonamenti
UPDATE public.feature_flags SET enabled = false WHERE key = 'stripe_test_ledger';
INSERT INTO public.stripe_payments (id, client_id, purpose, target_id, amount_cents, source, metadata, livemode)
SELECT '99000000-0000-0000-0000-000000000002', bruno, 'subscription', '49000000-0000-0000-0000-000000000001', 7200, 'app',
       jsonb_build_object('kind', 'new_subscription', 'plan', jsonb_build_object('plan_id', '49000000-0000-0000-0000-000000000001', 'validity_days', 90, 'entries', 10)),
       false
  FROM s9;
SELECT public.stripe_apply_payment_state(pg_temp.paid('99000000-0000-0000-0000-000000000002', 'pi_s9_prova', 7200));
SELECT is(
  (SELECT count(*)::int FROM public.subscriptions s, s9 WHERE s.client_id = s9.bruno),
  0, 'un pagamento di prova senza registro non crea l''abbonamento');
UPDATE public.feature_flags SET enabled = true WHERE key = 'stripe_test_ledger';

CREATE TEMP TABLE sub AS SELECT s.id FROM public.subscriptions s, s9 WHERE s.client_id = s9.anna;
GRANT SELECT ON sub TO authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- 3. Il primo ingresso
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.book_lesson('59000000-0000-0000-0000-000000000001', (SELECT id FROM sub))->>'reason', 'BOOKED',
  'si prenota con l''abbonamento appena comprato');
RESET ROLE;

SELECT is(
  (SELECT concat_ws(' | ', s.first_entry_on - d.today, s.expires_at - d.today) FROM public.subscriptions s, s9 d
    WHERE s.id = (SELECT id FROM sub)),
  '10 | 100', 'la prima lezione fissa l''inizio: scadenza = primo ingresso + 90 giorni');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.book_lesson('59000000-0000-0000-0000-000000000002', (SELECT id FROM sub))->>'reason', 'BOOKED',
  'una lezione più vicina si prenota');
RESET ROLE;

SELECT is(
  (SELECT concat_ws(' | ', s.first_entry_on - d.today, s.expires_at - d.today) FROM public.subscriptions s, s9 d
    WHERE s.id = (SELECT id FROM sub)),
  '5 | 95', 'e diventa il nuovo primo ingresso');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(
  public.cancel_booking((SELECT id FROM public.bookings WHERE lesson_id = '59000000-0000-0000-0000-000000000002'
                            AND status = 'booked' AND client_id = (SELECT anna FROM s9)))->>'ok',
  'true', 'la lezione più vicina si disdice');
RESET ROLE;

SELECT is(
  (SELECT concat_ws(' | ', s.first_entry_on - d.today, s.expires_at - d.today) FROM public.subscriptions s, s9 d
    WHERE s.id = (SELECT id FROM sub)),
  '10 | 100', 'disdetta, il primo ingresso torna quello di prima');

UPDATE public.lessons SET starts_at = starts_at + interval '2 days', ends_at = ends_at + interval '2 days'
 WHERE id = '59000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT concat_ws(' | ', s.first_entry_on - d.today, s.expires_at - d.today) FROM public.subscriptions s, s9 d
    WHERE s.id = (SELECT id FROM sub)),
  '12 | 102', 'la lezione spostata sposta il primo ingresso');

UPDATE public.bookings SET status = 'no_show'
 WHERE lesson_id = '59000000-0000-0000-0000-000000000001' AND client_id = (SELECT anna FROM s9);
SELECT is(
  (SELECT (s.first_entry_on - d.today)::text FROM public.subscriptions s, s9 d WHERE s.id = (SELECT id FROM sub)),
  '12', 'un''assenza ha consumato l''ingresso: resta il primo');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.book_lesson('59000000-0000-0000-0000-000000000003', (SELECT id FROM sub))->>'reason', 'BOOKED',
  'una lezione lontana ma dentro la validità si prenota');
SELECT is(public.book_lesson('59000000-0000-0000-0000-000000000002', (SELECT id FROM sub))->>'reason',
  'OUTSIDE_SUBSCRIPTION_WINDOW',
  'una lezione più vicina che lascerebbe fuori quella lontana viene rifiutata, con le date');
RESET ROLE;

-- Nessun ingresso entro i 60 giorni: l'abbonamento è partito comunque
INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, activation_deadline, expires_at,
                                  custom_validity_days, starts_on_first_entry)
SELECT '79000000-0000-0000-0000-000000000001', bruno, '49000000-0000-0000-0000-000000000001',
       today - 70, today - 10, today + 80, 90, true
  FROM s9;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.book_lesson('59000000-0000-0000-0000-000000000007', '79000000-0000-0000-0000-000000000001')->>'reason',
  'BOOKED', 'dopo i 60 giorni si prenota come sempre');
RESET ROLE;
SELECT is(
  (SELECT concat_ws(' | ', s.first_entry_on - d.today, s.expires_at - d.today) FROM public.subscriptions s, s9 d
    WHERE s.id = '79000000-0000-0000-0000-000000000001'),
  '15 | 80', 'oltre i 60 giorni la validità parte dalla scadenza di attivazione, non dal primo ingresso');

-- ═════════════════════════════════════════════════════════════════════════════
-- 4. La prova: avviso allo staff, e convertita non accorcia
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.book_trial_lesson('59000000-0000-0000-0000-000000000005')->>'reason', 'BOOKED',
  'Bruno prenota una prova dall''app');
RESET ROLE;

SELECT is(
  (SELECT string_agg(c.email, ', ' ORDER BY c.email) FROM public.notification_queue q
     JOIN public.clients c ON c.id = q.client_id WHERE q.category = 'trial_booked_staff'),
  's9-admin@test.kalos, s9-ope@test.kalos',
  'lo sanno l''admin e l''operatrice della lezione, una volta ciascunə');

SELECT is(
  (SELECT channel::text || ' | ' || (body LIKE 'Bruno Nove ha prenotato dall''app una lezione di prova%')::text
     FROM public.notification_queue q JOIN public.clients c ON c.id = q.client_id
    WHERE q.category = 'trial_booked_staff' AND c.email = 's9-ope@test.kalos'),
  'email | true', 'senza app, per email, con chi e quando');

INSERT INTO public.stripe_payments (id, client_id, purpose, target_id, amount_cents, source, metadata, livemode)
SELECT '99000000-0000-0000-0000-000000000003', bruno, 'subscription', '49000000-0000-0000-0000-000000000001', 7200, 'app',
       jsonb_build_object('kind', 'new_subscription', 'plan', jsonb_build_object('plan_id', '49000000-0000-0000-0000-000000000001', 'validity_days', 90, 'entries', 10)),
       false
  FROM s9;
SELECT public.stripe_apply_payment_state(pg_temp.paid('99000000-0000-0000-0000-000000000003', 'pi_s9_bruno', 7200));

SELECT is(
  (SELECT t.status::text FROM public.trials t, s9 WHERE t.client_id = s9.bruno),
  'converted', 'comprando l''abbonamento, la prova diventa il primo ingresso (F2)');

SELECT is(
  (SELECT concat_ws(' | ', COALESCE(s.first_entry_on::text, 'nessun ingresso'), s.expires_at - d.today,
                    (SELECT sum(delta) FROM public.subscription_usages u WHERE u.subscription_id = s.id))
     FROM public.subscriptions s, s9 d
    WHERE s.id = (SELECT t.id FROM public.transactions x JOIN public.subscriptions t ON t.id = x.subscription_id
                   WHERE x.stripe_payment_id = '99000000-0000-0000-0000-000000000003')),
  'nessun ingresso | 150 | -1', 'la prova scala un ingresso ma non fa partire la validità');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is(public.staff_book_trial('59000000-0000-0000-0000-000000000006', (SELECT anna FROM s9))->>'ok', 'true',
  'lo staff inserisce una prova');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notification_queue WHERE category = 'trial_booked_staff'), 2,
  'una prova inserita dallo staff non avvisa lo staff');

-- ═════════════════════════════════════════════════════════════════════════════
-- 5. Eventi con contributo: prima il posto, poi il pagamento
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.book_event('69000000-0000-0000-0000-000000000001')->>'reason', 'BOOKED', 'Anna si iscrive al laboratorio');
RESET ROLE;

CREATE TEMP TABLE eb AS
SELECT id FROM public.event_bookings WHERE event_id = '69000000-0000-0000-0000-000000000001' AND client_id = (SELECT anna FROM s9);
GRANT SELECT ON eb TO authenticated;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.book_event('69000000-0000-0000-0000-000000000001')->>'reason', 'FULL', 'il posto è suo: per Bruno è pieno');
SELECT is(public.book_event('69000000-0000-0000-0000-000000000002')->>'reason', 'EVENT_CONCLUDED',
  'a un evento finito non ci si iscrive');
SELECT is(public.prepare_my_event_payment((SELECT id FROM eb))->>'reason', 'BOOKING_NOT_FOUND',
  'l''iscrizione di un''altra persona non si paga');
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(
  (SELECT r->>'kind' || ' | ' || (r->>'amount_cents') FROM (SELECT public.prepare_my_event_payment((SELECT id FROM eb)) r) x),
  'event_booking | 1500', 'il contributo si paga dopo l''iscrizione, con l''importo dell''evento');
SELECT is(
  (SELECT count(*)::int FROM jsonb_array_elements(public.get_my_open_payments()->'items') i
    WHERE i->>'type' = 'event_booking' AND i->>'event_booking_id' = (SELECT id FROM eb)::text),
  1, 'ed è tra le cose da pagare');
RESET ROLE;

INSERT INTO public.stripe_payments (id, client_id, purpose, target_id, amount_cents, source, metadata, livemode)
SELECT '99000000-0000-0000-0000-000000000004', anna, 'event', (SELECT id FROM eb), 1500, 'app',
       jsonb_build_object('kind', 'event_booking', 'title', 'Contributo — S9 Laboratorio'), false
  FROM s9;
SELECT public.stripe_apply_payment_state(pg_temp.paid('99000000-0000-0000-0000-000000000004', 'pi_s9_evento', 1500));

SELECT is(
  (SELECT concat_ws(' | ', t.kind, t.event_booking_id = (SELECT id FROM eb),
                    (SELECT count(*) FROM public.receipts r WHERE r.transaction_id = t.id))
     FROM public.transactions t WHERE t.stripe_payment_id = '99000000-0000-0000-0000-000000000004'),
  'event | t | 1', 'pagato: incasso collegato all''iscrizione, con ricevuta');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.prepare_my_event_payment((SELECT id FROM eb))->>'reason', 'ALREADY_PAID', 'non si paga due volte');
SELECT is(public.cancel_event_booking((SELECT id FROM eb))->>'reason', 'PAID_CONTACT_STUDIO',
  'un''iscrizione pagata si disdice parlando con lo studio');
SELECT is(
  (SELECT count(*)::int FROM jsonb_array_elements(public.get_my_open_payments()->'items') i
    WHERE i->>'event_booking_id' = (SELECT id FROM eb)::text),
  0, 'e non è più tra le cose da pagare');
RESET ROLE;

-- Iscrizione disdetta mentre si pagava: il denaro è arrivato, ma va restituito
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT public.book_event('69000000-0000-0000-0000-000000000003');
RESET ROLE;
INSERT INTO public.stripe_payments (id, client_id, purpose, target_id, amount_cents, source, metadata, livemode)
SELECT '99000000-0000-0000-0000-000000000005', bruno, 'event',
       (SELECT id FROM public.event_bookings WHERE event_id = '69000000-0000-0000-0000-000000000003' AND client_id = s9.bruno),
       1000, 'app', jsonb_build_object('kind', 'event_booking'), false
  FROM s9;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT public.cancel_event_booking((SELECT id FROM public.event_bookings
                                     WHERE event_id = '69000000-0000-0000-0000-000000000003' AND client_id = (SELECT bruno FROM s9)));
RESET ROLE;
SELECT public.stripe_apply_payment_state(pg_temp.paid('99000000-0000-0000-0000-000000000005', 'pi_s9_disdetta', 1000));
SELECT is(
  (SELECT concat_ws(' | ', sp.is_duplicate, t.event_booking_id IS NULL,
                    (SELECT count(*) FROM public.receipts r WHERE r.transaction_id = t.id))
     FROM public.stripe_payments sp JOIN public.transactions t ON t.id = sp.transaction_id
    WHERE sp.id = '99000000-0000-0000-0000-000000000005'),
  't | t | 0', 'iscrizione disdetta prima del pagamento: doppione da rimborsare, senza ricevuta né collegamento');

-- Riattivare un'iscrizione disdetta non scavalca più la capienza
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT public.book_event('69000000-0000-0000-0000-000000000004');
SELECT public.cancel_event_booking((SELECT id FROM public.event_bookings
                                     WHERE event_id = '69000000-0000-0000-0000-000000000004' AND client_id = (SELECT anna FROM s9)));
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT public.book_event('69000000-0000-0000-0000-000000000004');
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.book_event('69000000-0000-0000-0000-000000000004')->>'reason', 'FULL',
  'riattivando un''iscrizione disdetta, se il posto è stato preso l''evento è pieno');
RESET ROLE;

-- Evento passato, iscrizione mai segnata: non resta un debito per sempre
INSERT INTO public.event_bookings (id, event_id, client_id, status)
SELECT '89000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000002', anna, 'booked' FROM s9;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.prepare_my_event_payment('89000000-0000-0000-0000-000000000001')->>'reason', 'EVENT_CONCLUDED',
  'dopo l''evento si paga solo se c''eri');
SELECT is(
  (SELECT count(*)::int FROM jsonb_array_elements(public.get_my_open_payments()->'items') i
    WHERE i->>'event_booking_id' = '89000000-0000-0000-0000-000000000001'),
  0, 'e non compare tra le cose da pagare');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 6. "Da saldare" pagato con carta
-- ═════════════════════════════════════════════════════════════════════════════

INSERT INTO public.transactions (id, client_id, kind, amount_cents, method, source, status, occurred_on, subscription_id, description)
SELECT '88000000-0000-0000-0000-000000000001', anna, 'subscription', 5000, 'cash', 'studio', 'pending',
       today - 3, (SELECT id FROM sub), 'Abbonamento in studio'
  FROM s9;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is((public.prepare_my_settlement('88000000-0000-0000-0000-000000000001')->>'amount_cents')::int, 5000,
  'il proprio «da saldare» si può pagare dall''app');
SELECT is(
  (SELECT count(*)::int FROM jsonb_array_elements(public.get_my_open_payments()->'items') i
    WHERE i->>'type' = 'settlement' AND i->>'transaction_id' = '88000000-0000-0000-0000-000000000001'),
  1, 'ed è tra le cose da pagare');
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.prepare_my_settlement('88000000-0000-0000-0000-000000000001')->>'reason', 'TRANSACTION_NOT_FOUND',
  'quello di un''altra persona no');
RESET ROLE;

INSERT INTO public.stripe_payments (id, client_id, purpose, target_id, amount_cents, source, metadata, livemode)
SELECT '99000000-0000-0000-0000-000000000006', anna, 'subscription', '88000000-0000-0000-0000-000000000001', 5000, 'app',
       jsonb_build_object('kind', 'settlement'), false
  FROM s9;
SELECT public.stripe_apply_payment_state(pg_temp.paid('99000000-0000-0000-0000-000000000006', 'pi_s9_saldo', 5000));

SELECT is(
  (SELECT concat_ws(' | ', status, method, source, stripe_payment_id = '99000000-0000-0000-0000-000000000006',
                    occurred_on = (SELECT today FROM s9))
     FROM public.transactions WHERE id = '88000000-0000-0000-0000-000000000001'),
  'paid | stripe | app | t | t', 'la stessa riga diventa pagata con carta, con la data del pagamento');

SELECT is(
  (SELECT count(*)::int FROM public.transactions WHERE stripe_payment_id = '99000000-0000-0000-0000-000000000006')
  + (SELECT count(*)::int FROM public.receipts WHERE transaction_id = '88000000-0000-0000-0000-000000000001') * 10,
  11, 'nessun incasso in più, e la ricevuta');

INSERT INTO public.stripe_payments (id, client_id, purpose, target_id, amount_cents, source, metadata, livemode)
SELECT '99000000-0000-0000-0000-000000000007', anna, 'subscription', '88000000-0000-0000-0000-000000000001', 5000, 'app',
       jsonb_build_object('kind', 'settlement'), false
  FROM s9;
SELECT public.stripe_apply_payment_state(pg_temp.paid('99000000-0000-0000-0000-000000000007', 'pi_s9_saldo2', 5000));
SELECT is((SELECT is_duplicate FROM public.stripe_payments WHERE id = '99000000-0000-0000-0000-000000000007'), true,
  'un secondo saldo dello stesso «da saldare» è un doppione');

-- Un evento registrato in studio come «da saldare» si salda dalla sua iscrizione
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT public.book_event('69000000-0000-0000-0000-000000000003');
RESET ROLE;
INSERT INTO public.transactions (client_id, kind, amount_cents, method, source, status, event_booking_id, description)
SELECT bruno, 'event', 1000, 'cash', 'studio', 'pending',
       (SELECT id FROM public.event_bookings WHERE event_id = '69000000-0000-0000-0000-000000000003' AND client_id = s9.bruno),
       'Iscrizione in studio'
  FROM s9;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(
  public.prepare_my_event_payment((SELECT id FROM public.event_bookings
                                    WHERE event_id = '69000000-0000-0000-0000-000000000003' AND client_id = (SELECT bruno FROM s9)))->>'kind',
  'settlement', 'se lo staff l''ha registrata come «da saldare», si salda quella');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 7. Com'è andato il pagamento (pagina di ritorno dell'app)
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(
  (SELECT concat_ws(' | ', r->>'status', r->>'recorded', (r->>'subscription_id') IS NOT NULL, (r->>'receipt_number') IS NOT NULL)
     FROM (SELECT public.get_my_payment_status('99000000-0000-0000-0000-000000000001') r) x),
  'succeeded | true | t | t', 'chi ha pagato vede esito, abbonamento e ricevuta');
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.get_my_payment_status('99000000-0000-0000-0000-000000000001')->>'reason', 'PAYMENT_NOT_FOUND',
  'il pagamento di un''altra persona non si vede');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 8. Piano archiviato, modifica a mano
-- ═════════════════════════════════════════════════════════════════════════════

UPDATE public.plans SET deleted_at = now(), is_active = false WHERE id = '49000000-0000-0000-0000-000000000001';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"19000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.book_lesson('59000000-0000-0000-0000-000000000004', (SELECT id FROM sub))->>'reason', 'BOOKED',
  'col piano archiviato, l''abbonamento già comprato resta valido');
SELECT is((SELECT count(*)::int FROM public.plans WHERE id = '49000000-0000-0000-0000-000000000001'), 1,
  'e chi ce l''ha continua a leggere il piano');
RESET ROLE;

UPDATE public.subscriptions SET expires_at = (SELECT today FROM s9) + 30 WHERE id = (SELECT id FROM sub);
SELECT is((SELECT starts_on_first_entry FROM public.subscriptions WHERE id = (SELECT id FROM sub)), false,
  'lo staff che cambia le date a mano decide lui: il primo ingresso non comanda più');

SELECT * FROM finish();
ROLLBACK;
