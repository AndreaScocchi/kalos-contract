-- Lezioni di prova: una per attività, e la conversione che scala UN solo ingresso e solo da un
-- abbonamento che copre l'attività provata (F2, F3, F4 del piano APS).

BEGIN;
SELECT plan(9);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('11000000-0000-0000-0000-000000000001', 'prova@test.kalos', '{"full_name":"Chi Prova"}', 'authenticated', 'authenticated');

INSERT INTO public.activities (id, name, discipline, duration_minutes) VALUES
  ('21000000-0000-0000-0000-000000000001', 'Test Vinyasa', 'test_vinyasa', 60),
  ('21000000-0000-0000-0000-000000000002', 'Test Meditazione', 'test_meditazione', 45),
  ('21000000-0000-0000-0000-000000000003', 'Test Senza Prova', 'test_senza_prova', 60);
UPDATE public.activities SET trial_enabled = false WHERE id = '21000000-0000-0000-0000-000000000003';

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity) VALUES
  ('31000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', now() + interval '3 days', now() + interval '3 days 1 hour', 10),
  ('31000000-0000-0000-0000-000000000002', '21000000-0000-0000-0000-000000000001', now() + interval '4 days', now() + interval '4 days 1 hour', 10),
  ('31000000-0000-0000-0000-000000000003', '21000000-0000-0000-0000-000000000002', now() + interval '5 days', now() + interval '5 days 45 minutes', 10),
  ('31000000-0000-0000-0000-000000000004', '21000000-0000-0000-0000-000000000003', now() + interval '6 days', now() + interval '6 days 1 hour', 10);

-- Pacchetto che copre SOLO Vinyasa
INSERT INTO public.plans (id, name, price_cents, entries, validity_days)
VALUES ('41000000-0000-0000-0000-000000000001', 'Test 10 Vinyasa', 10000, 10, 90);
INSERT INTO public.plan_activities (plan_id, activity_id)
VALUES ('41000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"11000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is((public.book_trial_lesson('31000000-0000-0000-0000-000000000001'))->>'reason', 'BOOKED',
  'la prima prova di un''attività si prenota');

SELECT is((public.book_trial_lesson('31000000-0000-0000-0000-000000000002'))->>'reason', 'TRIAL_ALREADY_USED',
  'una seconda prova della STESSA attività viene rifiutata, anche su un''altra data');

SELECT is((public.book_trial_lesson('31000000-0000-0000-0000-000000000003'))->>'reason', 'BOOKED',
  'la prova di un''ALTRA attività si può fare');

SELECT is((public.book_trial_lesson('31000000-0000-0000-0000-000000000004'))->>'reason', 'TRIAL_NOT_AVAILABLE',
  'un''attività con la prova disattivata non si prova');
RESET ROLE;

SELECT is(
  (SELECT count(*)::int FROM public.bookings WHERE is_trial = true AND status = 'booked'), 2,
  'le prove risultano prenotazioni di prova, senza abbonamento'
);

-- ── Conversione ──────────────────────────────────────────────────────────────
INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at)
SELECT '51000000-0000-0000-0000-000000000001', c.id, '41000000-0000-0000-0000-000000000001',
       CURRENT_DATE, CURRENT_DATE + 90
  FROM public.clients c WHERE c.email = 'prova@test.kalos';

SELECT is(
  (SELECT status::text FROM public.trials WHERE activity_id = '21000000-0000-0000-0000-000000000001'),
  'converted', 'la prova dell''attività coperta diventa il primo ingresso'
);

SELECT is(
  (SELECT status::text FROM public.trials WHERE activity_id = '21000000-0000-0000-0000-000000000002'),
  'booked', 'la prova di un''attività NON coperta resta a disposizione'
);

SELECT is(
  (SELECT remaining_entries::int FROM public.subscriptions_with_remaining
    WHERE id = '51000000-0000-0000-0000-000000000001'), 9,
  'la conversione scala esattamente un ingresso, non due'
);

SELECT is(
  (SELECT count(*)::int FROM public.subscription_usages
    WHERE subscription_id = '51000000-0000-0000-0000-000000000001' AND reason = 'TRIAL'), 1,
  'e lascia una sola riga di consumo, marcata come prova'
);

SELECT * FROM finish();
ROLLBACK;
