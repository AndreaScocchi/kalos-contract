-- Niente cassa (v0.3.19, 22/10/2026): l'associazione non ha una cassa fisica e i contanti si versano
-- subito sul conto. Contano in banca dal giorno dell'incasso, il saldo iniziale è solo del conto e
-- nessun giroconto tocca la cassa, nemmeno scritto senza passare dall'API.
--
-- I saldi si controllano come differenza rispetto a quelli di partenza: il test non presuppone un
-- database vuoto. Le date sono nel 2032, lontane da qualunque dato del seed.

BEGIN;
SELECT plan(9);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('17600000-0000-0000-0000-000000000001', 'nc-tesoriere@test.kalos', '{"full_name":"Tesoriere Senza Cassa"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'finance' WHERE id = '17600000-0000-0000-0000-000000000001';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"17600000-0000-0000-0000-000000000001","role":"authenticated"}';
CREATE TEMP TABLE nc_base AS SELECT public.finance_account_balances('2032-05-31') AS b;

-- ── Una quota in contanti e un'uscita in contanti ────────────────────────────
RESET ROLE;
INSERT INTO public.transactions (kind, amount_cents, method, source, status, occurred_on, description) VALUES
  ('donation', 3500, 'cash', 'studio', 'paid', '2032-05-07', 'NC contanti');
INSERT INTO public.expenses (amount_cents, expense_date, category_id, payment_method, notes, confirmed_at)
VALUES (500, '2032-05-08', (SELECT id FROM public.expense_categories WHERE slug = 'materiali'), 'cash', 'NC uscita', now());

SET LOCAL ROLE authenticated;
SELECT is(
  (SELECT account::text FROM public.finance_income_lines('2032-05-01', '2032-05-31') WHERE description = 'NC contanti'),
  'bank', 'un incasso in contanti è in banca dal giorno dell''incasso');
SELECT is(
  (SELECT (n->>'bank_cents')::bigint - (b->>'bank_cents')::bigint
     FROM nc_base, LATERAL (SELECT public.finance_account_balances('2032-05-31') AS n) x),
  3000::bigint, 'in banca entrano i contanti ed esce l''uscita in contanti');
SELECT is((public.finance_account_balances('2032-05-31')->>'cash_cents')::bigint, 0::bigint, 'la cassa è sempre a zero');
SELECT is(
  (SELECT (n->>'total_cents')::bigint - (b->>'total_cents')::bigint
     FROM nc_base, LATERAL (SELECT public.finance_account_balances('2032-05-31') AS n) x),
  3000::bigint, 'il totale è la banca più Stripe');

-- ── Dall'API ─────────────────────────────────────────────────────────────────
SELECT throws_ok(
  $$ INSERT INTO public.account_transfers (occurred_on, from_account, to_account, amount_cents) VALUES ('2032-05-09', 'bank', 'cash', 100) $$,
  'P0001', 'NO_CASH_ACCOUNT', 'nessun prelievo verso una cassa che non c''è');
SELECT is(public.finance_set_opening_balances(100, 0)->>'reason', 'NO_CASH_ACCOUNT', 'nessun saldo iniziale di cassa');
SELECT is(public.finance_set_opening_balances(NULL, (SELECT opening_bank_cents FROM public.association_settings))->>'ok', 'true',
  'il saldo del conto si imposta anche senza dire niente della cassa');
RESET ROLE;

-- ── I vincoli valgono anche fuori dall'API ───────────────────────────────────
SELECT throws_ok(
  $$ INSERT INTO public.account_transfers (occurred_on, from_account, to_account, amount_cents) VALUES ('2032-05-09', 'cash', 'bank', 100) $$,
  '23514', NULL, 'un giroconto con la cassa viola il vincolo');
SELECT throws_ok(
  $$ UPDATE public.association_settings SET opening_cash_cents = 100 WHERE id = true $$,
  '23514', NULL, 'un saldo iniziale di cassa viola il vincolo');

SELECT * FROM finish();
ROLLBACK;
