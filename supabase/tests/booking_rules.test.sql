-- Regole di prenotazione: capienza, scadenza, ingressi residui e regola "solo soci".
-- Sono le regole che, se si rompono, fanno entrare qualcunə a una lezione piena o tengono fuori
-- unə sociə in regola. Si lancia con `npm run test:db`.

BEGIN;
SELECT plan(13);

-- ── Dati di prova ────────────────────────────────────────────────────────────
-- Il trigger su auth.users crea profilo e scheda cliente.
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('10000000-0000-0000-0000-000000000001', 'cliente1@test.kalos', '{"full_name":"Cliente Uno"}', 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000002', 'cliente2@test.kalos', '{"full_name":"Cliente Due"}', 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000003', 'operatrice@test.kalos', '{"full_name":"Operatrice"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '10000000-0000-0000-0000-000000000003';

INSERT INTO public.activities (id, name, discipline, duration_minutes)
VALUES ('20000000-0000-0000-0000-000000000001', 'Test Yoga', 'test_yoga', 60);

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity, booking_deadline_minutes) VALUES
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
   now() + interval '3 days', now() + interval '3 days 1 hour', 1, 30),
  -- lezione che comincia fra 10 minuti: la scadenza di 30 minuti è già passata
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001',
   now() + interval '10 minutes', now() + interval '70 minutes', 10, 30);

INSERT INTO public.plans (id, name, price_cents, entries, validity_days)
VALUES ('40000000-0000-0000-0000-000000000001', 'Test 1 ingresso', 1000, 1, 30);
INSERT INTO public.plan_activities (plan_id, activity_id)
VALUES ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001');

-- ── Capienza e scadenza (interruttore "solo soci" spento) ────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(
  (public.book_lesson('30000000-0000-0000-0000-000000000001', NULL))->>'reason', 'BOOKED',
  'con interruttore spento si prenota come prima'
);

SELECT is(
  (public.book_lesson('30000000-0000-0000-0000-000000000001', NULL))->>'reason', 'ALREADY_BOOKED',
  'non ci si prenota due volte alla stessa lezione'
);

SELECT is(
  (public.book_lesson('30000000-0000-0000-0000-000000000002', NULL))->>'reason', 'BOOKING_DEADLINE_PASSED',
  'oltre la scadenza non si prenota più'
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(
  (public.book_lesson('30000000-0000-0000-0000-000000000001', NULL))->>'reason', 'FULL',
  'a capienza esaurita la prenotazione viene rifiutata'
);
RESET ROLE;

-- ── Ingressi residui ─────────────────────────────────────────────────────────
INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at)
SELECT '50000000-0000-0000-0000-000000000001', c.id, '40000000-0000-0000-0000-000000000001',
       CURRENT_DATE, CURRENT_DATE + 30
  FROM public.clients c WHERE c.email = 'cliente2@test.kalos';

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity) VALUES
  ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001',
   now() + interval '4 days', now() + interval '4 days 1 hour', 10),
  ('30000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001',
   now() + interval '5 days', now() + interval '5 days 1 hour', 10);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(
  (public.book_lesson('30000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000001'))->>'reason',
  'BOOKED', 'l''unico ingresso dell''abbonamento si usa'
);
-- Consumato l'ultimo ingresso, un trigger porta l'abbonamento a "completato": il rifiuto arriva
-- quindi come abbonamento non più attivo, non come ingressi finiti. La garanzia che conta è che non
-- si prenoti oltre gli ingressi pagati, e vale in entrambi i casi.
SELECT is(
  (public.book_lesson('30000000-0000-0000-0000-000000000004', '50000000-0000-0000-0000-000000000001'))->>'ok',
  'false', 'finiti gli ingressi non si prenota più con quell''abbonamento'
);
RESET ROLE;

-- ── Regola "solo soci" ───────────────────────────────────────────────────────
UPDATE public.feature_flags SET enabled = true WHERE key = 'members_only';
UPDATE public.association_years SET fee_cents = 2500 WHERE year = EXTRACT(YEAR FROM CURRENT_DATE)::integer;

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity)
VALUES ('30000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000001',
        now() + interval '6 days', now() + interval '6 days 1 hour', 10);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(
  (public.book_lesson('30000000-0000-0000-0000-000000000005', NULL))->>'reason', 'NOT_A_MEMBER',
  'con la regola accesa, chi non ha fatto domanda non prenota'
);

SELECT is(
  (public.submit_member_application(jsonb_build_object(
    'first_name', 'Cliente', 'last_name', 'Uno', 'birth_date', '1990-01-01',
    'accepted_statute', 'true', 'accepted_privacy', 'true')))->>'reason',
  'SUBMITTED', 'la domanda di ammissione si invia'
);

SELECT is(
  (public.book_lesson('30000000-0000-0000-0000-000000000005', NULL))->>'reason', 'MEMBERSHIP_FEE_DUE',
  'domanda inviata ma quota non pagata: ancora no'
);
RESET ROLE;

UPDATE public.member_fees SET status = 'paid', paid_at = now()
 WHERE client_id = (SELECT id FROM public.clients WHERE email = 'cliente1@test.kalos');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(
  (public.book_lesson('30000000-0000-0000-0000-000000000005', NULL))->>'reason', 'BOOKED',
  'quota pagata: si prenota subito, anche prima della delibera del Consiglio Direttivo'
);
RESET ROLE;

-- Partecipare però richiede l'ammissione deliberata
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is(
  (public.staff_update_booking_status(
     (SELECT b.id FROM public.bookings b
       WHERE b.lesson_id = '30000000-0000-0000-0000-000000000005' AND b.status = 'booked'),
     'attended'))->>'reason',
  'MEMBERSHIP_NOT_APPROVED', 'senza delibera non si può segnare "partecipata"'
);

SELECT is(
  (public.staff_decide_member_applications(
     ARRAY(SELECT id FROM public.member_applications WHERE status = 'pending'),
     true, CURRENT_DATE))->>'reason',
  'APPROVED', 'il Consiglio Direttivo delibera l''ammissione'
);
RESET ROLE;

SELECT is(
  (SELECT status::text FROM public.subscriptions WHERE id = '50000000-0000-0000-0000-000000000001'),
  'completed', 'l''abbonamento con zero ingressi residui risulta completato'
);

SELECT * FROM finish();
ROLLBACK;
