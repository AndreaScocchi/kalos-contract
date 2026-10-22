-- Le operatrici in tutte le sezioni del gestionale (migrazione 20261022170000, richiesta dell'utente
-- del 22/10/2026): Finanze, azioni sui soldi e Segnalazioni come admin e Tesoriere. Restano
-- all'admin le schede dello staff, i ruoli, la quota dell'anno e gli interruttori. Chi non è staff
-- resta fuori da tutto.

BEGIN;
SELECT plan(17);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('0f220000-0000-0000-0000-000000000001', 'ots-operatrice@test.kalos', '{"full_name":"Operatrice Sezioni"}', 'authenticated', 'authenticated'),
  ('0f220000-0000-0000-0000-000000000002', 'ots-cliente@test.kalos', '{"full_name":"Cliente Sezioni"}', 'authenticated', 'authenticated'),
  ('0f220000-0000-0000-0000-000000000003', 'ots-altra@test.kalos', '{"full_name":"Altra Cliente"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '0f220000-0000-0000-0000-000000000001';

INSERT INTO public.expenses (id, amount_cents, expense_date, category_id, payment_method, notes, confirmed_at) VALUES
  ('0f220000-0000-0000-0000-0000000000e1', 1200, '2026-09-10', (SELECT id FROM public.expense_categories WHERE slug = 'materiali'),
   'bank_transfer', 'OTS uscita', now());
INSERT INTO public.bug_reports (id, title, description, created_by_user_id) VALUES
  ('0f220000-0000-0000-0000-0000000000b1', 'OTS mia', 'della cliente', '0f220000-0000-0000-0000-000000000002'),
  ('0f220000-0000-0000-0000-0000000000b2', 'OTS altra', 'di un''altra persona', '0f220000-0000-0000-0000-000000000003');

-- ── Operatrice: le Finanze ───────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"0f220000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT ok(public.can_access_finance(), 'un''operatrice entra nelle Finanze');
SELECT lives_ok($$ SELECT * FROM public.finance_income_lines('2026-09-01', '2026-09-30') $$,
  'un''operatrice legge le entrate delle Finanze');
SELECT lives_ok($$ SELECT public.finance_account_balances('2026-09-30') $$,
  'un''operatrice legge i saldi di banca e Stripe');
SELECT is((SELECT count(*)::int FROM public.expenses WHERE id = '0f220000-0000-0000-0000-0000000000e1'), 1,
  'un''operatrice vede le uscite');
SELECT isnt(public.staff_set_default_compensation_model('00000000-0000-0000-0000-000000000000')->>'reason',
  'NOT_FINANCE', 'un''operatrice arriva ai modelli di compenso');
SELECT is(
  public.staff_register_payment(jsonb_build_object('kind', 'other', 'amount_cents', 100, 'method', 'bank_transfer',
    'rendiconto_voce', 'E-A8', 'description', 'OTS entrata'))->>'ok',
  'true', 'un''operatrice registra un''entrata con la voce del rendiconto');

-- ── Operatrice: le Segnalazioni ──────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM public.bug_reports WHERE title LIKE 'OTS %'), 2,
  'un''operatrice vede le segnalazioni di tuttə');
UPDATE public.bug_reports SET status = 'resolved' WHERE id = '0f220000-0000-0000-0000-0000000000b2';
DELETE FROM public.bug_reports WHERE id = '0f220000-0000-0000-0000-0000000000b1';

-- ── Operatrice: quello che resta all'admin ───────────────────────────────────
SELECT throws_ok($$ UPDATE public.profiles SET role = 'admin' WHERE id = auth.uid() $$, '42501', NULL,
  'un''operatrice non cambia i ruoli');
SELECT throws_ok($$ INSERT INTO public.operators (name, role) VALUES ('OTS scheda', 'Insegnante') $$, '42501', NULL,
  'un''operatrice non crea schede dello staff');
SELECT is(public.staff_delete_operator('00000000-0000-0000-0000-000000000000', true)->>'reason', 'NOT_ADMIN',
  'un''operatrice non elimina schede dello staff');
SELECT throws_ok($$ INSERT INTO public.association_years (year, fee_cents) VALUES (2099, 100) $$, '42501', NULL,
  'un''operatrice non decide la quota dell''anno');
SELECT throws_ok($$ INSERT INTO public.feature_flags (key, enabled) VALUES ('ots_prova', true) $$, '42501', NULL,
  'un''operatrice non tocca gli interruttori');

RESET ROLE;
SELECT is((SELECT status::text FROM public.bug_reports WHERE id = '0f220000-0000-0000-0000-0000000000b2'), 'resolved',
  'un''operatrice cambia lo stato di una segnalazione');
SELECT is((SELECT count(*)::int FROM public.bug_reports WHERE id = '0f220000-0000-0000-0000-0000000000b1'), 0,
  'un''operatrice cancella una segnalazione');
INSERT INTO public.bug_reports (id, title, description, created_by_user_id) VALUES
  ('0f220000-0000-0000-0000-0000000000b1', 'OTS mia', 'della cliente', '0f220000-0000-0000-0000-000000000002');

-- ── Chi non è staff resta fuori ──────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"0f220000-0000-0000-0000-000000000002","role":"authenticated"}';

SELECT ok(NOT public.can_access_finance(), 'un cliente non entra nelle Finanze');
SELECT is((SELECT count(*)::int FROM public.expenses), 0, 'un cliente non vede le uscite');
SELECT is((SELECT string_agg(title, ', ') FROM public.bug_reports WHERE title LIKE 'OTS %'), 'OTS mia',
  'un cliente vede solo le proprie segnalazioni');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
