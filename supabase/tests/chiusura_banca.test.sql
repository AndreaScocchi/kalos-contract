-- Chiusura con l'estratto conto (v0.3.20, 22/10/2026): periodi contigui dall'inizio della
-- contabilità, saldo della banca che passa da una chiusura all'altra, righe abbinate al centesimo
-- con i movimenti del registro (anche più incassi in contanti per un versamento), ogni movimento in
-- una riga sola, righe rimaste aperte riprese dopo, annullo solo dell'ultima. Solo Finanze.
--
-- Le chiusure partono per forza dal 19/08/2026 e finiscono prima di oggi: i movimenti del test sono
-- di agosto e settembre 2026, riconoscibili dalla descrizione «CB …».

BEGIN;
SELECT plan(30);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('17700000-0000-0000-0000-000000000001', 'cb-tesoriere@test.kalos', '{"full_name":"Tesoriere Chiusura"}', 'authenticated', 'authenticated'),
  ('17700000-0000-0000-0000-000000000002', 'cb-operatrice@test.kalos', '{"full_name":"Operatrice Chiusura"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'finance' WHERE id = '17700000-0000-0000-0000-000000000001';
UPDATE public.profiles SET role = 'operator' WHERE id = '17700000-0000-0000-0000-000000000002';

-- Il registro: un bonifico, due quote in contanti versate insieme, un pagamento con carta,
-- una commissione bancaria
INSERT INTO public.transactions (id, kind, amount_cents, method, source, status, occurred_on, description) VALUES
  ('17700000-0000-0000-0000-0000000000a1', 'donation', 10000, 'bank_transfer', 'studio', 'paid', '2026-08-20', 'CB bonifico'),
  ('17700000-0000-0000-0000-0000000000a2', 'donation', 3500, 'cash', 'studio', 'paid', '2026-09-05', 'CB contanti 1'),
  ('17700000-0000-0000-0000-0000000000a3', 'donation', 3500, 'cash', 'studio', 'paid', '2026-09-05', 'CB contanti 2'),
  ('17700000-0000-0000-0000-0000000000a4', 'donation', 2000, 'stripe', 'studio', 'paid', '2026-09-06', 'CB carta');
INSERT INTO public.expenses (id, amount_cents, expense_date, category_id, payment_method, notes, confirmed_at) VALUES
  ('17700000-0000-0000-0000-0000000000e1', 250, '2026-08-31', (SELECT id FROM public.expense_categories WHERE slug = 'materiali'),
   'bank_transfer', 'CB commissione', now());

-- ── Chi può ──────────────────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"17700000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(
  public.finance_save_bank_closing('{"period_from":"2026-08-19","period_to":"2026-08-31","lines":[]}')->>'reason',
  'NOT_FINANCE', 'un''operatrice non chiude');
SELECT throws_ok(
  $$ INSERT INTO public.bank_rules (match_causale, category_id) VALUES ('Commissioni', (SELECT id FROM public.expense_categories LIMIT 1)) $$,
  '42501', NULL, 'un''operatrice non scrive le regole');

SET LOCAL request.jwt.claims = '{"sub":"17700000-0000-0000-0000-000000000001","role":"authenticated"}';

-- ── Il periodo ───────────────────────────────────────────────────────────────
SELECT is(
  public.finance_save_bank_closing('{"period_from":"2026-08-20","period_to":"2026-08-31","lines":[]}')->>'expected_from',
  (SELECT ledger_start_date::text FROM public.association_settings),
  'la prima chiusura parte dall''inizio della contabilità');
SELECT is(
  public.finance_save_bank_closing(jsonb_build_object('period_from', '2026-08-19', 'period_to', (now() AT TIME ZONE 'Europe/Rome')::date))->>'reason',
  'PERIOD_NOT_OVER', 'si chiude solo fino a ieri');
SELECT is(
  public.finance_save_bank_closing('{"period_from":"2026-08-19","period_to":"2026-08-31","lines":[{"booked_on":"2026-09-01","amount_cents":100}]}')->>'reason',
  'LINE_OUTSIDE_PERIOD', 'una riga fuori dal periodo non entra');
SELECT is(
  public.finance_save_bank_closing('{"period_from":"2026-08-19","period_to":"2026-08-31","lines":[{"booked_on":"2026-08-25","amount_cents":"dieci"}]}')->>'reason',
  'INVALID_LINE', 'un importo che non è un numero');

-- ── Gli abbinamenti ──────────────────────────────────────────────────────────
SELECT is(
  public.finance_save_bank_closing('{"period_from":"2026-08-19","period_to":"2026-08-31","lines":[
     {"booked_on":"2026-08-21","amount_cents":9000,"links":[{"transaction_id":"17700000-0000-0000-0000-0000000000a1"}]}]}')->>'reason',
  'LINK_AMOUNT_MISMATCH', 'una riga abbinata deve tornare al centesimo');
SELECT is((SELECT count(*)::int FROM public.bank_closings), 0, 'un errore non lascia niente di scritto');
SELECT is(
  public.finance_save_bank_closing('{"period_from":"2026-08-19","period_to":"2026-08-31","lines":[
     {"booked_on":"2026-08-21","amount_cents":2000,"links":[{"transaction_id":"17700000-0000-0000-0000-0000000000a4"}]}]}')->>'reason',
  'LINK_NOT_BANK', 'un pagamento con carta non è un movimento della banca');
SELECT is(
  public.finance_save_bank_closing('{"period_from":"2026-08-19","period_to":"2026-08-31","lines":[
     {"booked_on":"2026-08-21","amount_cents":10000,"links":[{"transaction_id":"17700000-0000-0000-0000-0000000000a1"}]},
     {"booked_on":"2026-08-22","amount_cents":10000,"links":[{"transaction_id":"17700000-0000-0000-0000-0000000000a1"}]}]}')->>'reason',
  'ALREADY_LINKED', 'un movimento del registro sta in una riga sola');

-- ── Prima chiusura: agosto ───────────────────────────────────────────────────
CREATE TEMP TABLE cb_first AS
SELECT public.finance_save_bank_closing('{"period_from":"2026-08-19","period_to":"2026-08-31",
   "account_ref":"Z0000000000000000000001","printed_on":"2026-10-21","file_path":"2026/agosto.pdf","note":"CB prima",
   "lines":[
     {"booked_on":"2026-08-21","value_on":"2026-08-20","amount_cents":10000,"causale":"Bonifico a Vostro favore","description":"CB",
      "links":[{"transaction_id":"17700000-0000-0000-0000-0000000000a1"}]},
     {"booked_on":"2026-08-31","amount_cents":-250,"causale":"Commissioni","links":[{"expense_id":"17700000-0000-0000-0000-0000000000e1"}]},
     {"booked_on":"2026-08-31","amount_cents":-100,"causale":"Imposte e tasse","note":"bollo da registrare"}]}') AS r;
SELECT is((SELECT r->>'reason' FROM cb_first), 'SAVED', 'la prima chiusura si salva');
SELECT is(
  (SELECT (r->>'closing_cents')::bigint - (r->>'opening_cents')::bigint FROM cb_first),
  9650::bigint, 'saldo a fine periodo = saldo iniziale + movimenti del PDF');
SELECT is(
  (SELECT opening_cents FROM public.bank_closings WHERE period_from = '2026-08-19'),
  (SELECT opening_bank_cents FROM public.association_settings), 'la prima parte dal saldo iniziale del conto');
SELECT is(
  (SELECT ledger_cents::bigint FROM public.bank_closings WHERE period_from = '2026-08-19'),
  (public.finance_account_balances('2026-08-31')->>'bank_cents')::bigint, 'resta il saldo del gestionale a fine periodo');
SELECT is((SELECT count(*)::int FROM public.bank_statement_lines l JOIN public.bank_closings c ON c.id = l.closing_id WHERE c.note = 'CB prima'),
  3, 'le righe del PDF restano');
SELECT is(
  (SELECT closed_by FROM public.bank_closings WHERE period_from = '2026-08-19'),
  '17700000-0000-0000-0000-000000000001'::uuid, 'resta chi ha chiuso');
SET LOCAL request.jwt.claims = '{"sub":"17700000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM public.bank_closings), 0, 'un''operatrice non legge le chiusure');
SET LOCAL request.jwt.claims = '{"sub":"17700000-0000-0000-0000-000000000001","role":"authenticated"}';

-- ── Seconda chiusura: settembre ──────────────────────────────────────────────
SELECT is(
  public.finance_save_bank_closing('{"period_from":"2026-09-02","period_to":"2026-09-30","lines":[]}')->>'expected_from',
  '2026-09-01', 'la chiusura dopo parte dal giorno dopo');
SELECT is(
  public.finance_save_bank_closing('{"period_from":"2026-09-01","period_to":"2026-09-30","account_ref":"Z9","lines":[]}')->>'reason',
  'ACCOUNT_MISMATCH', 'lo stesso conto da una chiusura all''altra');

-- Il bollo rimasto aperto ad agosto si registra adesso e si abbina nella chiusura di settembre
RESET ROLE;
INSERT INTO public.expenses (id, amount_cents, expense_date, category_id, payment_method, notes, confirmed_at) VALUES
  ('17700000-0000-0000-0000-0000000000e2', 100, '2026-08-31', (SELECT id FROM public.expense_categories WHERE slug = 'materiali'),
   'bank_transfer', 'CB bollo', now());
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"17700000-0000-0000-0000-000000000001","role":"authenticated"}';

CREATE TEMP TABLE cb_second AS
SELECT public.finance_save_bank_closing(jsonb_build_object(
   'period_from', '2026-09-01', 'period_to', '2026-09-30', 'account_ref', 'Z0000000000000000000001', 'note', 'CB seconda',
   'lines', '[{"booked_on":"2026-09-08","amount_cents":7000,"causale":"Versamento di contante","links":[
               {"transaction_id":"17700000-0000-0000-0000-0000000000a2"},{"transaction_id":"17700000-0000-0000-0000-0000000000a3"}]}]'::jsonb,
   'carry_links', jsonb_build_array(jsonb_build_object(
       'line_id', (SELECT l.id FROM public.bank_statement_lines l JOIN public.bank_closings c ON c.id = l.closing_id
                    WHERE c.note = 'CB prima' AND l.amount_cents = -100),
       'expense_id', '17700000-0000-0000-0000-0000000000e2')))) AS r;
SELECT is((SELECT r->>'reason' FROM cb_second), 'SAVED', 'un versamento di contanti si abbina a più incassi');
SELECT is(
  (SELECT (r->>'opening_cents')::bigint FROM cb_second),
  (SELECT closing_cents::bigint FROM public.bank_closings WHERE period_from = '2026-08-19'),
  'il saldo iniziale è quello della chiusura prima');
SELECT is(
  (SELECT count(*)::int FROM public.bank_line_links k JOIN public.bank_statement_lines l ON l.id = k.line_id
    WHERE l.amount_cents = -100 AND k.closing_id = (SELECT (r->>'closing_id')::uuid FROM cb_second)),
  1, 'una riga rimasta aperta si abbina nella chiusura dopo');

-- ── Annullare ────────────────────────────────────────────────────────────────
SELECT is(
  public.finance_delete_bank_closing((SELECT id FROM public.bank_closings WHERE period_from = '2026-08-19'))->>'reason',
  'LAST_ONLY', 'si annulla solo l''ultima chiusura');
SELECT is(
  public.finance_delete_bank_closing((SELECT (r->>'closing_id')::uuid FROM cb_second))->>'reason',
  'DELETED', 'l''ultima si annulla');
SELECT is(
  (SELECT count(*)::int FROM public.bank_line_links k JOIN public.bank_statement_lines l ON l.id = k.line_id WHERE l.amount_cents = -100),
  0, 'con lei se ne va l''abbinamento fatto su una riga di prima, che torna aperta');
SELECT is(
  (SELECT count(*)::int FROM public.transactions WHERE id IN ('17700000-0000-0000-0000-0000000000a2', '17700000-0000-0000-0000-0000000000a3')),
  2, 'i movimenti del registro restano');

-- ── Un movimento cancellato libera la riga ───────────────────────────────────
RESET ROLE;
DELETE FROM public.expenses WHERE id = '17700000-0000-0000-0000-0000000000e1';
SELECT is(
  (SELECT count(*)::int FROM public.bank_line_links WHERE expense_id = '17700000-0000-0000-0000-0000000000e1'),
  0, 'se l''uscita si cancella, la riga dell''estratto torna da sistemare');

-- ── Regole e scritture dirette ───────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"17700000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT lives_ok(
  $$ INSERT INTO public.bank_rules (match_causale, category_id, vendor) VALUES ('Commissioni', (SELECT id FROM public.expense_categories LIMIT 1), 'BCC') $$,
  'le Finanze ricordano una spesa ricorrente');
SELECT throws_ok(
  $$ INSERT INTO public.bank_rules (match_causale, category_id) VALUES (' commissioni ', (SELECT id FROM public.expense_categories LIMIT 1)) $$,
  '23505', NULL, 'la stessa regola una volta sola');
SELECT throws_ok(
  $$ INSERT INTO public.bank_closings (period_from, period_to, opening_cents, movements_cents, closing_cents, ledger_cents)
     VALUES ('2026-09-01', '2026-09-30', 0, 0, 0, 0) $$,
  '42501', NULL, 'le chiusure si scrivono solo con la funzione');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
