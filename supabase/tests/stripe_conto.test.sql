-- Stripe è un conto (v0.3.15): i pagamenti con carta e le commissioni stanno sul conto Stripe finché
-- Stripe non li accredita in banca; l'accredito è un giroconto Stripe → banca scritto solo da
-- `stripe_apply_payout_state`, nel giorno di arrivo, e sparisce se l'accredito fallisce.
--
-- I saldi si controllano come differenza rispetto a quelli di partenza: il test non presuppone un
-- database vuoto. Le date sono nel 2031, lontane da qualunque dato del seed.

BEGIN;
SELECT plan(32);

-- ── Persone ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('17500000-0000-0000-0000-000000000001', 'sc-tesoriere@test.kalos', '{"full_name":"Tesoriere Conto"}', 'authenticated', 'authenticated'),
  ('17500000-0000-0000-0000-000000000002', 'sc-operatrice@test.kalos', '{"full_name":"Operatrice Conto"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'finance'  WHERE id = '17500000-0000-0000-0000-000000000001';
UPDATE public.profiles SET role = 'operator' WHERE id = '17500000-0000-0000-0000-000000000002';

-- ── Il conto di un metodo ────────────────────────────────────────────────────
SELECT is(internal.cash_account_for('cash')::text, 'cash', 'i contanti vanno in cassa');
SELECT is(internal.cash_account_for('bank_transfer')::text, 'bank', 'un bonifico va in banca');
SELECT is(internal.cash_account_for('other')::text, 'bank', '«altro» resta in banca');
SELECT is(internal.cash_account_for('stripe')::text, 'stripe', 'un pagamento con carta va sul conto Stripe');

-- ── Saldi di partenza ────────────────────────────────────────────────────────
SET LOCAL request.jwt.claims = '{"sub":"17500000-0000-0000-0000-000000000001","role":"authenticated"}';
CREATE TEMP TABLE sc_base AS SELECT public.finance_account_balances('2031-03-31') AS b;
GRANT SELECT ON sc_base TO authenticated;

CREATE TEMP VIEW sc_delta AS
SELECT ((n->>'cash_cents')::bigint   - (b->>'cash_cents')::bigint)   AS cash,
       ((n->>'bank_cents')::bigint   - (b->>'bank_cents')::bigint)   AS bank,
       ((n->>'stripe_cents')::bigint - (b->>'stripe_cents')::bigint) AS stripe,
       ((n->>'total_cents')::bigint  - (b->>'total_cents')::bigint)  AS total
  FROM sc_base, LATERAL (SELECT public.finance_account_balances('2031-03-31') AS n) x;
GRANT SELECT ON sc_delta TO authenticated;

-- ── Due pagamenti con carta, le loro commissioni, un bonifico ────────────────
INSERT INTO public.transactions (kind, amount_cents, method, source, status, occurred_on, description) VALUES
  ('donation', 3500, 'stripe',        'site',   'paid', '2031-03-02', 'SC carta 1'),
  ('donation', 5200, 'stripe',        'site',   'paid', '2031-03-03', 'SC carta 2'),
  ('donation', 1000, 'bank_transfer', 'studio', 'paid', '2031-03-03', 'SC bonifico');
INSERT INTO public.expenses (amount_cents, expense_date, category, category_id, source, notes, confirmed_at) VALUES
  (78,  '2031-03-02', 'other', (SELECT id FROM public.expense_categories WHERE slug = 'commissioni'), 'stripe_fee', 'SC commissione 1', now()),
  (103, '2031-03-03', 'other', (SELECT id FROM public.expense_categories WHERE slug = 'commissioni'), 'stripe_fee', 'SC commissione 2', now());

SET LOCAL ROLE authenticated;
SELECT is((SELECT bank FROM sc_delta), 1000::bigint, 'in banca c''è solo il bonifico: la carta non è ancora arrivata');
SELECT is((SELECT stripe FROM sc_delta), 8519::bigint, 'su Stripe i pagamenti con carta meno le commissioni');
SELECT is((SELECT total FROM sc_delta), 9519::bigint, 'il totale comprende il conto Stripe');
SELECT is(
  (SELECT string_agg(account::text, ',' ORDER BY description) FROM public.finance_income_lines('2031-03-01', '2031-03-31')
    WHERE description LIKE 'SC %'),
  'bank,stripe,stripe', 'nelle entrate il conto di un pagamento con carta è Stripe');
RESET ROLE;

-- ── L'accredito ──────────────────────────────────────────────────────────────
-- Stripe accredita 85,19 € (i due pagamenti netti) che arrivano in banca il 10/03
SELECT is(
  public.stripe_apply_payout_state(jsonb_build_object('id', 'po_sc_1', 'status', 'in_transit', 'amount', 8519,
    'currency', 'eur', 'arrival_date', extract(epoch FROM timestamptz '2031-03-10 00:00+00')::bigint, 'livemode', true))->>'action',
  'waiting', 'un accredito in viaggio non è ancora in banca');
SELECT is((SELECT count(*)::int FROM public.account_transfers WHERE stripe_payout_id = 'po_sc_1'), 0,
  'in viaggio non scrive nessun giroconto');

SELECT is(
  public.stripe_apply_payout_state(jsonb_build_object('id', 'po_sc_1', 'status', 'paid', 'amount', 8519,
    'currency', 'eur', 'arrival_date', extract(epoch FROM timestamptz '2031-03-10 00:00+00')::bigint, 'livemode', true))->>'action',
  'recorded', 'arrivato: diventa un giroconto');
SELECT is(
  (SELECT occurred_on || '|' || from_account || '>' || to_account || '|' || amount_cents
     FROM public.account_transfers WHERE stripe_payout_id = 'po_sc_1'),
  '2031-03-10|stripe>bank|8519', 'giroconto Stripe → banca nel giorno di arrivo, con l''importo accreditato');
SELECT is(
  public.stripe_apply_payout_state(jsonb_build_object('id', 'po_sc_1', 'status', 'paid', 'amount', 8519,
    'currency', 'eur', 'arrival_date', extract(epoch FROM timestamptz '2031-03-10 00:00+00')::bigint, 'livemode', true))->>'action',
  'unchanged', 'lo stesso accredito una seconda volta non cambia niente');

SET LOCAL ROLE authenticated;
SELECT is((SELECT bank FROM sc_delta), 9519::bigint, 'dopo l''accredito in banca ci sono anche i pagamenti con carta, netti');
SELECT is((SELECT stripe FROM sc_delta), 0::bigint, 'e su Stripe non resta niente');
SELECT is((SELECT total FROM sc_delta), 9519::bigint, 'un giroconto non cambia il totale');
SELECT is(
  (SELECT (public.finance_account_balances('2031-03-09')->>'stripe_cents')::bigint - (b->>'stripe_cents')::bigint FROM sc_base),
  8519::bigint, 'il giorno prima dell''arrivo i soldi erano ancora su Stripe');
RESET ROLE;

-- Stripe sposta la data di arrivo: il giroconto la segue
SELECT is(
  public.stripe_apply_payout_state(jsonb_build_object('id', 'po_sc_1', 'status', 'paid', 'amount', 8519,
    'currency', 'eur', 'arrival_date', extract(epoch FROM timestamptz '2031-03-11 00:00+00')::bigint, 'livemode', true))->>'action',
  'updated', 'una data di arrivo diversa aggiorna il giroconto');
SELECT is((SELECT occurred_on::text FROM public.account_transfers WHERE stripe_payout_id = 'po_sc_1'), '2031-03-11',
  'il giroconto ha la data nuova');

-- ── Dall'interfaccia ─────────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ DELETE FROM public.account_transfers WHERE stripe_payout_id = 'po_sc_1' $$,
  'P0001', 'AUTOMATIC_TRANSFER', 'un accredito di Stripe non si cancella a mano');
SELECT throws_ok(
  $$ UPDATE public.account_transfers SET amount_cents = 1 WHERE stripe_payout_id = 'po_sc_1' $$,
  'P0001', 'AUTOMATIC_TRANSFER', 'l''importo di un accredito non si cambia a mano');
SELECT lives_ok(
  $$ UPDATE public.account_transfers SET note = 'Accredito di marzo' WHERE stripe_payout_id = 'po_sc_1' $$,
  'la nota di un accredito si può scrivere');
SELECT throws_ok(
  $$ INSERT INTO public.account_transfers (occurred_on, from_account, to_account, amount_cents) VALUES ('2031-03-12', 'stripe', 'bank', 100) $$,
  'P0001', 'AUTOMATIC_TRANSFER', 'un giroconto da Stripe non si scrive a mano');
SELECT throws_ok(
  $$ INSERT INTO public.account_transfers (occurred_on, from_account, to_account, amount_cents, stripe_payout_id) VALUES ('2031-03-12', 'stripe', 'bank', 100, 'po_finto') $$,
  'P0001', 'AUTOMATIC_TRANSFER', 'nemmeno inventando un accredito');
SELECT lives_ok(
  $$ INSERT INTO public.account_transfers (occurred_on, from_account, to_account, amount_cents, note) VALUES ('2031-03-12', 'cash', 'bank', 100, 'SC versamento') $$,
  'i giroconti fra cassa e banca restano a mano');
SELECT throws_ok(
  $$ SELECT public.stripe_apply_payout_state('{"id":"po_x","status":"paid","amount":1,"currency":"eur","arrival_date":0,"livemode":true}') $$,
  '42501', NULL, 'lo stato di un accredito lo scrive solo il servizio, non chi è loggatə');
RESET ROLE;

-- Il vincolo vale anche per chi scrive senza passare dalla funzione
SELECT throws_ok(
  $$ INSERT INTO public.account_transfers (occurred_on, from_account, to_account, amount_cents) VALUES ('2031-03-12', 'stripe', 'bank', 100) $$,
  '23514', NULL, 'un giroconto che tocca Stripe senza accredito viola il vincolo');

-- ── Accredito fallito, di prova, in un'altra valuta ──────────────────────────
SELECT is(
  public.stripe_apply_payout_state(jsonb_build_object('id', 'po_sc_1', 'status', 'failed', 'amount', 8519,
    'currency', 'eur', 'arrival_date', extract(epoch FROM timestamptz '2031-03-11 00:00+00')::bigint, 'livemode', true))->>'action',
  'removed', 'fallito dopo l''arrivo: il giroconto sparisce');

SET LOCAL ROLE authenticated;
SELECT is((SELECT stripe FROM sc_delta), 8519::bigint, 'i soldi sono di nuovo su Stripe');
RESET ROLE;

UPDATE public.feature_flags SET enabled = false WHERE key = 'stripe_test_ledger';
SELECT is(
  public.stripe_apply_payout_state(jsonb_build_object('id', 'po_sc_prova', 'status', 'paid', 'amount', 500,
    'currency', 'eur', 'arrival_date', extract(epoch FROM timestamptz '2031-03-10 00:00+00')::bigint, 'livemode', false))->>'action',
  'ignored', 'un accredito di prova non entra nel registro vero');

SELECT is(
  public.stripe_apply_payout_state(jsonb_build_object('id', 'po_sc_usd', 'status', 'paid', 'amount', 500,
    'currency', 'usd', 'arrival_date', extract(epoch FROM timestamptz '2031-03-10 00:00+00')::bigint, 'livemode', true))->>'reason',
  'UNSUPPORTED_CURRENCY', 'solo euro');

-- Un'operatrice non vede i saldi
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"17500000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT throws_ok($$ SELECT public.finance_account_balances('2031-03-31') $$, '42501', NULL,
  'un''operatrice non legge i saldi');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
