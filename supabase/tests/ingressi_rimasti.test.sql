-- Ingressi rimasti (v0.3.12): `subscriptions_with_remaining` si legge con il login, con le RLS delle
-- tabelle sotto. Lo staff vede tutti, ciascun cliente solo i propri abbonamenti, anon nessuno.

BEGIN;
SELECT plan(7);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('1d000000-0000-0000-0000-000000000001', 'ir-anna@test.kalos',  '{"full_name":"Anna Ingressi"}',  'authenticated', 'authenticated'),
  ('1d000000-0000-0000-0000-000000000002', 'ir-bruno@test.kalos', '{"full_name":"Bruno Ingressi"}', 'authenticated', 'authenticated'),
  ('1d000000-0000-0000-0000-000000000003', 'ir-op@test.kalos',    '{"full_name":"Olga Ingressi"}',  'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '1d000000-0000-0000-0000-000000000003';

INSERT INTO public.plans (id, name, price_cents, entries, validity_days) VALUES
  ('4d000000-0000-0000-0000-000000000001', 'IR Carnet', 5000, 4, 30);

INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at)
SELECT '5d000000-0000-0000-0000-000000000001'::uuid, c.id, '4d000000-0000-0000-0000-000000000001'::uuid,
       CURRENT_DATE, CURRENT_DATE + 30
  FROM public.clients c WHERE c.email = 'ir-anna@test.kalos'
UNION ALL
SELECT '5d000000-0000-0000-0000-000000000002'::uuid, c.id, '4d000000-0000-0000-0000-000000000001'::uuid,
       CURRENT_DATE, CURRENT_DATE + 30
  FROM public.clients c WHERE c.email = 'ir-bruno@test.kalos';

INSERT INTO public.subscription_usages (subscription_id, delta, reason)
VALUES ('5d000000-0000-0000-0000-000000000001', -1, 'BOOK');

SELECT ok((SELECT 'security_invoker=true' = ANY (reloptions) FROM pg_class
           WHERE oid = 'public.subscriptions_with_remaining'::regclass),
  'la view applica le RLS di chi legge');

SELECT ok(NOT has_table_privilege('anon', 'public.subscriptions_with_remaining', 'SELECT'),
  'anon non legge gli ingressi rimasti');

-- Staff: le richieste del gestionale (Dashboard, Abbonamenti, prenotazioni della lezione)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1d000000-0000-0000-0000-000000000003","role":"authenticated"}';

SELECT lives_ok(
  $$ SELECT id, remaining_entries FROM public.subscriptions_with_remaining LIMIT 1 $$,
  'lo staff legge la view senza permission denied');
SELECT is(
  (SELECT count(*)::int FROM public.subscriptions_with_remaining
    WHERE id IN ('5d000000-0000-0000-0000-000000000001', '5d000000-0000-0000-0000-000000000002')),
  2, 'lo staff vede gli abbonamenti di tuttə');
SELECT is(
  (SELECT remaining_entries::int FROM public.subscriptions_with_remaining
    WHERE id = '5d000000-0000-0000-0000-000000000001'),
  3, 'ingressi rimasti = ingressi del piano + movimenti');

-- Cliente: solo i propri
SET LOCAL request.jwt.claims = '{"sub":"1d000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(
  (SELECT count(*)::int FROM public.subscriptions_with_remaining
    WHERE id IN ('5d000000-0000-0000-0000-000000000001', '5d000000-0000-0000-0000-000000000002')),
  1, 'un cliente vede solo i propri abbonamenti');
SELECT is(
  (SELECT id FROM public.subscriptions_with_remaining
    WHERE id IN ('5d000000-0000-0000-0000-000000000001', '5d000000-0000-0000-0000-000000000002')),
  '5d000000-0000-0000-0000-000000000001'::uuid, 'ed è il suo');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
