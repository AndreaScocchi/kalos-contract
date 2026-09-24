-- Finanze (sessione 7): voci del rendiconto per cassa e distinzione fra associatə e terzi, entrate
-- divise per attività in base alle prenotazioni, saldi di cassa e banca, uscite automatiche
-- protette, ricorrenze che recuperano i mesi, compensi congelati solo se già avvenuti, pagati con
-- la ritenuta d'acconto e annullabili, modelli salvati tutto o niente.
--
-- I saldi si controllano come differenza rispetto a quelli di partenza: il test non presuppone un
-- database vuoto.

BEGIN;
SELECT plan(66);

-- ── Persone ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('17000000-0000-0000-0000-000000000001', 's7-tesoriere@test.kalos', '{"full_name":"Tesoriere Sette"}', 'authenticated', 'authenticated'),
  ('17000000-0000-0000-0000-000000000002', 's7-operatrice@test.kalos', '{"full_name":"Operatrice Sette"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'finance'  WHERE id = '17000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET role = 'operator' WHERE id = '17000000-0000-0000-0000-000000000002';

INSERT INTO public.clients (id, full_name, email) VALUES
  ('27000000-0000-0000-0000-000000000001', 'Socia Sette', 's7-socia@test.kalos'),
  ('27000000-0000-0000-0000-000000000002', 'Terzo Sette', 's7-terzo@test.kalos');
INSERT INTO public.members (client_id, member_number, admitted_on)
VALUES ('27000000-0000-0000-0000-000000000001', '2026-9701', '2026-08-19');

-- ── Attività, abbonamenti, prenotazioni, evento ──────────────────────────────
INSERT INTO public.activities (id, name, discipline, duration_minutes, group_id) VALUES
  ('47000000-0000-0000-0000-000000000001', 'S7 Yin', 's7_yin', 60, (SELECT id FROM public.activity_groups WHERE slug = 'benessere')),
  ('47000000-0000-0000-0000-000000000002', 'S7 Vinyasa', 's7_vinyasa', 60, (SELECT id FROM public.activity_groups WHERE slug = 'benessere'));
INSERT INTO public.plans (id, name, price_cents, entries, validity_days)
VALUES ('48000000-0000-0000-0000-000000000001', 'S7 Yoga 10', 1000, 10, 90);
INSERT INTO public.plan_activities (plan_id, activity_id) VALUES
  ('48000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000001'),
  ('48000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000002');
INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at) VALUES
  ('49000000-0000-0000-0000-000000000001', '27000000-0000-0000-0000-000000000001', '48000000-0000-0000-0000-000000000001', '2026-09-10', '2026-12-10'),
  ('49000000-0000-0000-0000-000000000002', '27000000-0000-0000-0000-000000000002', '48000000-0000-0000-0000-000000000001', '2026-09-11', '2026-12-11');

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity) VALUES
  ('4b000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000001', '2026-09-14 16:00+00', '2026-09-14 17:00+00', 10),
  ('4b000000-0000-0000-0000-000000000002', '47000000-0000-0000-0000-000000000001', '2026-09-21 16:00+00', '2026-09-21 17:00+00', 10),
  ('4b000000-0000-0000-0000-000000000003', '47000000-0000-0000-0000-000000000002', '2026-09-15 16:00+00', '2026-09-15 17:00+00', 10),
  ('4b000000-0000-0000-0000-000000000004', '47000000-0000-0000-0000-000000000002', '2026-09-22 16:00+00', '2026-09-22 17:00+00', 10);
-- Con l'abbonamento della socia: due Yin (presente, prenotata), un Vinyasa assente, un Vinyasa
-- disdetto che non conta
INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status) VALUES
  ('4b000000-0000-0000-0000-000000000001', '27000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000001', 'attended'),
  ('4b000000-0000-0000-0000-000000000002', '27000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000001', 'booked'),
  ('4b000000-0000-0000-0000-000000000003', '27000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000001', 'no_show'),
  ('4b000000-0000-0000-0000-000000000004', '27000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000001', 'canceled');

INSERT INTO public.events (id, name, starts_at, price_cents)
VALUES ('4a000000-0000-0000-0000-000000000001', 'S7 Laboratorio', '2026-09-26 15:00+00', 1500);
INSERT INTO public.event_bookings (id, event_id, client_id)
VALUES ('4c000000-0000-0000-0000-000000000001', '4a000000-0000-0000-0000-000000000001', '27000000-0000-0000-0000-000000000002');

-- ── Saldi di partenza, prima di qualunque movimento del test ─────────────────
SET LOCAL request.jwt.claims = '{"sub":"17000000-0000-0000-0000-000000000001","role":"authenticated"}';
CREATE TEMP TABLE s7_base AS
SELECT public.finance_account_balances('2026-09-30') AS b,
       (SELECT opening_cash_cents FROM public.association_settings) AS oc,
       (SELECT opening_bank_cents FROM public.association_settings) AS ob;
GRANT SELECT ON s7_base TO authenticated;

-- ── Incassi ──────────────────────────────────────────────────────────────────
INSERT INTO public.transactions (id, client_id, kind, amount_cents, method, source, status, occurred_on, subscription_id, event_booking_id, refund_of_id, description) VALUES
  ('aa000000-0000-0000-0000-000000000001', '27000000-0000-0000-0000-000000000001', 'subscription',   1000, 'cash',          'studio', 'partially_refunded', '2026-09-10', '49000000-0000-0000-0000-000000000001', NULL, NULL, NULL),
  ('aa000000-0000-0000-0000-000000000002', '27000000-0000-0000-0000-000000000002', 'subscription',   2000, 'bank_transfer', 'studio', 'partially_refunded', '2026-09-11', '49000000-0000-0000-0000-000000000002', NULL, NULL, NULL),
  ('aa000000-0000-0000-0000-000000000003', '27000000-0000-0000-0000-000000000001', 'membership_fee', 2500, 'cash',          'studio', 'paid',     '2026-09-10', NULL, NULL, NULL, NULL),
  ('aa000000-0000-0000-0000-000000000004', NULL,                                   'donation',       5000, 'stripe',        'site',   'paid',     '2026-09-12', NULL, NULL, NULL, 'Donazione online'),
  ('aa000000-0000-0000-0000-000000000005', '27000000-0000-0000-0000-000000000002', 'subscription',   4000, 'bank_transfer', 'studio', 'pending',  '2026-09-12', NULL, NULL, NULL, NULL),
  ('aa000000-0000-0000-0000-000000000006', '27000000-0000-0000-0000-000000000002', 'other',          1000, 'cash',          'studio', 'void',     '2026-09-12', NULL, NULL, NULL, NULL),
  ('aa000000-0000-0000-0000-000000000008', '27000000-0000-0000-0000-000000000002', 'other',           700, 'cash',          'studio', 'paid',     '2026-08-01', NULL, NULL, NULL, 'Gestione precedente'),
  ('aa000000-0000-0000-0000-000000000011', '27000000-0000-0000-0000-000000000002', 'event',          1500, 'bank_transfer', 'studio', 'paid',     '2026-09-26', NULL, '4c000000-0000-0000-0000-000000000001', NULL, NULL),
  ('aa000000-0000-0000-0000-000000000012', '27000000-0000-0000-0000-000000000002', 'subscription',    800, 'cash',          'studio', 'paid',     '2026-09-27', NULL, NULL, NULL, 'Abbonamento senza collegamento');
INSERT INTO public.transactions (id, client_id, kind, amount_cents, method, source, status, occurred_on, refund_of_id, description) VALUES
  ('aa000000-0000-0000-0000-000000000007', '27000000-0000-0000-0000-000000000002', 'subscription', -500, 'bank_transfer', 'studio', 'paid', '2026-09-15', 'aa000000-0000-0000-0000-000000000002', 'Rimborso'),
  ('aa000000-0000-0000-0000-000000000010', '27000000-0000-0000-0000-000000000001', 'subscription', -100, 'cash',          'studio', 'paid', '2026-09-20', 'aa000000-0000-0000-0000-000000000001', 'Rimborso');

-- ─────────────────────────────────────────────────────────────────────────────
-- Chi non è delle Finanze non passa
-- ─────────────────────────────────────────────────────────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"17000000-0000-0000-0000-000000000002","role":"authenticated"}';

SELECT throws_ok($$ SELECT * FROM public.finance_income_lines('2026-09-01', '2026-09-30') $$, '42501', NULL,
  'un''operatrice non legge le entrate delle Finanze');
SELECT throws_ok($$ SELECT * FROM public.finance_income_allocations('2026-09-01', '2026-09-30') $$, '42501', NULL,
  'un''operatrice non legge le entrate per attività');
SELECT is(public.finance_set_opening_balances(1, 1)->>'reason', 'NOT_FINANCE',
  'un''operatrice non imposta i saldi iniziali');
SELECT is(public.staff_pay_compensation('00000000-0000-0000-0000-000000000000'::uuid, '2026-09-01')->>'reason', 'NOT_FINANCE',
  'un''operatrice non paga compensi');
SELECT is(
  public.staff_register_payment(jsonb_build_object('kind', 'other', 'amount_cents', 100, 'rendiconto_voce', 'E-A8'))->>'reason',
  'NOT_FINANCE', 'un''operatrice registra incassi ma non sceglie la voce del rendiconto');
SELECT is((SELECT count(*)::int FROM public.expenses), 0, 'un''operatrice non vede le uscite');
SELECT throws_ok(
  $$ INSERT INTO public.account_transfers (from_account, to_account, amount_cents) VALUES ('cash', 'bank', 100) $$,
  '42501', NULL, 'un''operatrice non registra giroconti');

RESET ROLE;

-- ─────────────────────────────────────────────────────────────────────────────
-- Entrate e voci del rendiconto
-- ─────────────────────────────────────────────────────────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"17000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(
  public.staff_register_payment(jsonb_build_object(
    'kind', 'other', 'amount_cents', 10000, 'method', 'bank_transfer', 'occurred_on', '2026-09-18',
    'description', 'S7 Contributo del Comune', 'rendiconto_voce', 'E-A8'))->>'ok',
  'true', 'il Tesoriere registra un contributo pubblico senza persona, con la sua voce');

SELECT is(
  public.staff_register_payment(jsonb_build_object('kind', 'other', 'amount_cents', 100, 'rendiconto_voce', 'U-A1'))->>'reason',
  'INVALID_VOCE', 'una voce di uscita non si mette su un incasso');

SELECT is(
  (SELECT string_agg(l.voce || ':' || l.amount_cents, ', ' ORDER BY l.transaction_id)
     FROM public.finance_income_lines('2026-09-01', '2026-09-30') l
    WHERE l.transaction_id::text LIKE 'aa000000%'),
  'E-A3:1000, E-A7:2000, E-A1:2500, E-A4:5000, E-A7:-500, E-A3:-100, E-A7:1500, E-A7:800',
  'voci: contributo di una socia A3, di un terzo A7, quota A1, donazione A4; i rimborsi seguono l''incasso; esclusi da saldare, annullati e gestione precedente'
);

SELECT is(
  (SELECT voce || '|' || account::text FROM public.finance_income_lines('2026-09-01', '2026-09-30')
    WHERE description = 'S7 Contributo del Comune'),
  'E-A8|bank', 'la voce scelta a mano vince, e un bonifico va in banca');

SELECT is(
  (SELECT string_agg(l.is_member::text || '/' || l.account::text, ', ' ORDER BY l.transaction_id)
     FROM public.finance_income_lines('2026-09-01', '2026-09-30') l
    WHERE l.transaction_id IN ('aa000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000002',
                               'aa000000-0000-0000-0000-000000000004')),
  'true/cash, false/bank, false/bank',
  'stato di sociə alla data e conto: contanti in cassa, bonifico e carta in banca'
);

SELECT is(
  (SELECT sum(amount_cents)::int FROM public.finance_income_lines('2026-09-01', '2026-09-30')
    WHERE transaction_id::text LIKE 'aa000000%' OR description = 'S7 Contributo del Comune'),
  22200, 'il totale di settembre torna, rimborsi compresi'
);

SELECT throws_ok(
  $$ UPDATE public.transactions SET rendiconto_voce = 'U-A2' WHERE id = 'aa000000-0000-0000-0000-000000000003' $$,
  'P0001', 'RENDICONTO_VOCE_KIND_MISMATCH', 'nemmeno correggendo a mano si mette una voce di uscita su un incasso');

-- ─────────────────────────────────────────────────────────────────────────────
-- Entrate per attività
-- ─────────────────────────────────────────────────────────────────────────────

SELECT is(
  (SELECT string_agg(a.activity_name || ':' || a.amount_cents, ', ' ORDER BY a.activity_name)
     FROM public.finance_income_allocations('2026-09-01', '2026-09-30') a
    WHERE a.transaction_id = 'aa000000-0000-0000-0000-000000000001'),
  'S7 Vinyasa:333, S7 Yin:667',
  'l''abbonamento si divide sulle lezioni prenotate (2 Yin, 1 Vinyasa; la disdetta no), il centesimo avanzato alla quota col resto più alto'
);

SELECT is(
  (SELECT string_agg(a.activity_name || ':' || a.amount_cents, ', ' ORDER BY a.activity_name)
     FROM public.finance_income_allocations('2026-09-01', '2026-09-30') a
    WHERE a.transaction_id = 'aa000000-0000-0000-0000-000000000010'),
  'S7 Vinyasa:-33, S7 Yin:-67', 'il rimborso si divide come l''incasso che restituisce'
);

SELECT is(
  (SELECT string_agg(a.bucket || ':' || a.amount_cents, ', ' ORDER BY a.transaction_id)
     FROM public.finance_income_allocations('2026-09-01', '2026-09-30') a
    WHERE a.transaction_id IN ('aa000000-0000-0000-0000-000000000002', 'aa000000-0000-0000-0000-000000000007',
                               'aa000000-0000-0000-0000-000000000012')),
  'unused:2000, unused:-500, unlinked:800',
  'un abbonamento senza prenotazioni resta "non ancora usato"; un incasso senza collegamento resta da parte'
);

SELECT is(
  (SELECT a.bucket || '|' || a.event_name || '|' || a.group_name FROM public.finance_income_allocations('2026-09-01', '2026-09-30') a
    WHERE a.transaction_id = 'aa000000-0000-0000-0000-000000000011'),
  'event|S7 Laboratorio|Laboratori e Eventi', 'un evento va all''evento, nel gruppo dei laboratori');

SELECT is(
  (SELECT sum(amount_cents)::int FROM public.finance_income_allocations('2026-09-01', '2026-09-30')
    WHERE transaction_id::text LIKE 'aa000000%'),
  (SELECT sum(amount_cents)::int FROM public.finance_income_lines('2026-09-01', '2026-09-30')
    WHERE transaction_id::text LIKE 'aa000000%' AND kind IN ('subscription', 'event', 'trial')),
  'la ripartizione non perde né inventa centesimi'
);

SELECT is(
  (SELECT sum(amount_cents)::int FROM public.finance_income_allocations('2026-09-01', '2026-09-30')
    WHERE transaction_id::text LIKE 'aa000000%' AND group_name = 'Kalòs x Benessere'),
  900, 'per gruppo: la socia ha dato 10 € al gruppo Benessere, meno 1 € rimborsato'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Uscite: categoria allineata, uscite automatiche protette
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.expenses (amount_cents, expense_date, category_id, payment_method, notes)
VALUES (1200, '2026-09-13', (SELECT id FROM public.expense_categories WHERE slug = 'materiali'), 'cash', 'S7 materiali');

SELECT is(
  (SELECT category || '|' || (confirmed_at IS NOT NULL)::text || '|' || source::text FROM public.expenses WHERE notes = 'S7 materiali'),
  'materials|true|manual', 'un''uscita a mano: la vecchia categoria si allinea da sola ed è già confermata');

SELECT throws_ok(
  $$ INSERT INTO public.expenses (amount_cents, expense_date, category_id, source, notes)
     VALUES (100, '2026-09-13', (SELECT id FROM public.expense_categories WHERE slug = 'compensi'), 'payout', 'S7 finto compenso') $$,
  'P0001', 'AUTOMATIC_EXPENSE', 'dall''interfaccia non si inventano uscite automatiche');

SELECT throws_ok(
  $$ UPDATE public.expenses SET rendiconto_voce = 'E-A1' WHERE notes = 'S7 materiali' $$,
  'P0001', 'RENDICONTO_VOCE_KIND_MISMATCH', 'una voce di entrata non si mette su un''uscita');

RESET ROLE;
-- Una commissione Stripe, come la scrive il trigger dei pagamenti
INSERT INTO public.expenses (amount_cents, expense_date, category, category_id, source, payment_method, notes, confirmed_at)
VALUES (150, '2026-09-12', 'other', (SELECT id FROM public.expense_categories WHERE slug = 'commissioni'),
        'stripe_fee', 'cash', 'S7 commissione', now());

SELECT is((SELECT payment_method::text FROM public.expenses WHERE notes = 'S7 commissione'), 'stripe',
  'una commissione esce sempre da Stripe, qualunque metodo le si passi');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"17000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT throws_ok($$ DELETE FROM public.expenses WHERE notes = 'S7 commissione' $$, 'P0001', 'AUTOMATIC_EXPENSE',
  'una commissione non si cancella dall''interfaccia');
SELECT throws_ok($$ UPDATE public.expenses SET amount_cents = 1 WHERE notes = 'S7 commissione' $$, 'P0001', 'AUTOMATIC_EXPENSE',
  'l''importo di una commissione non si cambia dall''interfaccia');
SELECT lives_ok($$ UPDATE public.expenses SET notes = 'S7 commissione', vendor = 'Stripe' WHERE notes = 'S7 commissione' $$,
  'di un''uscita automatica si possono cambiare note e fornitore');

INSERT INTO public.expenses (amount_cents, expense_date, category_id, notes)
VALUES (999, '2026-09-13', (SELECT id FROM public.expense_categories WHERE slug = 'altro'), 'S7 da cancellare');
DELETE FROM public.expenses WHERE notes = 'S7 da cancellare';
SELECT is((SELECT count(*)::int FROM public.expenses WHERE notes = 'S7 da cancellare'), 0,
  'il Tesoriere cancella un''uscita scritta a mano per errore');

-- ─────────────────────────────────────────────────────────────────────────────
-- Spese ricorrenti
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.recurring_expenses (id, category_id, label, amount_cents, day_of_month, starts_on, payment_method) VALUES
  ('4d000000-0000-0000-0000-000000000001', (SELECT id FROM public.expense_categories WHERE slug = 'utenze'), 'S7 luce', 3000, 5,
   (date_trunc('month', CURRENT_DATE) - interval '2 months')::date, 'cash'),
  -- parte il 20 del primo mese: la scadenza del 10 di quel mese non gli appartiene
  ('4d000000-0000-0000-0000-000000000002', (SELECT id FROM public.expense_categories WHERE slug = 'software'), 'S7 software', 1000, 10,
   (date_trunc('month', CURRENT_DATE) - interval '2 months' + interval '19 days')::date, 'bank_transfer');
INSERT INTO public.recurring_expenses (id, category_id, label, amount_cents, day_of_month, starts_on, is_active, last_generated_month) VALUES
  ('4d000000-0000-0000-0000-000000000003', (SELECT id FROM public.expense_categories WHERE slug = 'altro'), 'S7 sospesa', 500, 1,
   (date_trunc('month', CURRENT_DATE) - interval '6 months')::date, false,
   (date_trunc('month', CURRENT_DATE) - interval '3 months')::date);
UPDATE public.recurring_expenses SET is_active = true WHERE id = '4d000000-0000-0000-0000-000000000003';

SELECT is(
  (SELECT last_generated_month FROM public.recurring_expenses WHERE id = '4d000000-0000-0000-0000-000000000003'),
  (date_trunc('month', CURRENT_DATE) - interval '1 month')::date,
  'una spesa riattivata riparte dal mese in corso: i mesi di sospensione non si recuperano');

SELECT ok(
  (public.generate_recurring_expenses((date_trunc('month', CURRENT_DATE) + interval '2 months')::date)->>'ok')::boolean,
  'le ricorrenze si generano anche chiedendo un mese futuro');

SELECT is(
  (SELECT string_agg(r.label || ':' || (SELECT count(*) FROM public.expenses e WHERE e.recurring_expense_id = r.id), ', ' ORDER BY r.label)
     FROM public.recurring_expenses r WHERE r.id::text LIKE '4d000000%'),
  'S7 luce:3, S7 software:2, S7 sospesa:1',
  'recuperati i mesi mancanti fino a quello in corso; la scadenza prima dell''inizio e i mesi di sospensione no'
);

SELECT is(
  (SELECT count(*)::int FROM public.expenses e JOIN public.recurring_expenses r ON r.id = e.recurring_expense_id
    WHERE r.id::text LIKE '4d000000%'
      AND (e.expense_date >= (date_trunc('month', CURRENT_DATE) + interval '1 month')::date OR e.confirmed_at IS NOT NULL)),
  0, 'mai oltre il mese in corso, e tutte da confermare');

SELECT is(public.generate_recurring_expenses()->>'created', '0', 'ogni mese nasce una volta sola');

SELECT is(
  public.confirm_expense(
    (SELECT id FROM public.expenses WHERE recurring_expense_id = '4d000000-0000-0000-0000-000000000001' ORDER BY expense_date LIMIT 1),
    3100, '2026-06-07', 'bank_transfer')->>'ok',
  'true', 'la conferma corregge importo, data e metodo');

SELECT is(
  (SELECT amount_cents || '|' || expense_date || '|' || payment_method::text || '|' || category
     FROM public.expenses WHERE recurring_expense_id = '4d000000-0000-0000-0000-000000000001' AND confirmed_at IS NOT NULL),
  '3100|2026-06-07|bank_transfer|utilities', 'l''uscita confermata ha i valori corretti e la categoria allineata');

SELECT is(
  public.confirm_expense(
    (SELECT id FROM public.expenses WHERE recurring_expense_id = '4d000000-0000-0000-0000-000000000001' AND confirmed_at IS NOT NULL))->>'reason',
  'EXPENSE_NOT_FOUND_OR_ALREADY_CONFIRMED', 'una conferma sola');

-- ─────────────────────────────────────────────────────────────────────────────
-- Compensi
-- ─────────────────────────────────────────────────────────────────────────────

RESET ROLE;
INSERT INTO public.operators (id, name, role, engagement_type) VALUES
  ('7a000000-0000-0000-0000-000000000001', 'S7 Occasionale', 'istruttrice', 'paid'),
  ('7a000000-0000-0000-0000-000000000002', 'S7 Forfettaria', 'istruttrice', 'paid');
-- Una lezione passata e una futura per la prima, in due mesi diversi
INSERT INTO public.lessons (id, activity_id, operator_id, starts_at, ends_at, capacity) VALUES
  ('4b000000-0000-0000-0000-000000000011', '47000000-0000-0000-0000-000000000001', '7a000000-0000-0000-0000-000000000001',
   date_trunc('month', now()) - interval '1 month' + interval '10 days 16 hours',
   date_trunc('month', now()) - interval '1 month' + interval '10 days 17 hours', 10),
  ('4b000000-0000-0000-0000-000000000012', '47000000-0000-0000-0000-000000000001', '7a000000-0000-0000-0000-000000000001',
   date_trunc('month', now()) + interval '1 month' + interval '10 days 16 hours',
   date_trunc('month', now()) + interval '1 month' + interval '10 days 17 hours', 10),
  -- Per la seconda: alle 00:30 del primo ottobre in Italia (22:30 UTC del 30 settembre), e una
  -- lezione di 90 minuti di un'attività che dura di solito 60
  ('4b000000-0000-0000-0000-000000000013', '47000000-0000-0000-0000-000000000001', '7a000000-0000-0000-0000-000000000002',
   '2025-09-30 22:30+00', '2025-09-30 23:30+00', 10),
  ('4b000000-0000-0000-0000-000000000014', '47000000-0000-0000-0000-000000000002', '7a000000-0000-0000-0000-000000000002',
   '2025-10-10 16:00+00', '2025-10-10 17:30+00', 10);

-- I modelli si creano con la funzione, come farà il gestionale (qui come postgres con l'identità
-- del Tesoriere, per poter tenere gli id in una tabella temporanea)
SET LOCAL request.jwt.claims = '{"sub":"17000000-0000-0000-0000-000000000001","role":"authenticated"}';
CREATE TEMP TABLE s7_models (name text, id uuid);
GRANT SELECT ON s7_models TO authenticated;
INSERT INTO s7_models
SELECT 'fisso', (public.staff_save_compensation_model(jsonb_build_object(
    'name', 'S7 Fisso 30',
    'components', jsonb_build_array(jsonb_build_object('kind', 'fixed_per_lesson', 'value_cents', 3000)))) ->> 'model_id')::uuid;
INSERT INTO s7_models
SELECT 'ora', (public.staff_save_compensation_model(jsonb_build_object(
    'name', 'S7 A ora 20',
    'components', jsonb_build_array(jsonb_build_object('kind', 'fixed_per_hour', 'value_cents', 2000)))) ->> 'model_id')::uuid;

SET LOCAL ROLE authenticated;

INSERT INTO public.compensation_assignments (operator_id, activity_id, model_id, valid_from) VALUES
  ('7a000000-0000-0000-0000-000000000001', NULL, (SELECT id FROM s7_models WHERE name = 'fisso'), '2020-01-01'),
  ('7a000000-0000-0000-0000-000000000002', NULL, (SELECT id FROM s7_models WHERE name = 'fisso'), '2020-01-01'),
  ('7a000000-0000-0000-0000-000000000002', '47000000-0000-0000-0000-000000000002', (SELECT id FROM s7_models WHERE name = 'ora'), '2020-01-01');
INSERT INTO public.operator_compensation_settings (operator_id, withholding_percent)
VALUES ('7a000000-0000-0000-0000-000000000001', 20);

SELECT is(
  (SELECT string_agg(to_char(occurred_at AT TIME ZONE 'Europe/Rome', 'DD/MM HH24:MI'), ', ')
     FROM public.calculate_compensation_v2('2025-10-01', '2025-10-31', '7a000000-0000-0000-0000-000000000002')
    WHERE lesson_id = '4b000000-0000-0000-0000-000000000013'),
  '01/10 00:30', 'il mese si conta in ora italiana: le 00:30 del primo ottobre sono di ottobre');
SELECT is(
  (SELECT count(*)::int FROM public.calculate_compensation_v2('2025-09-01', '2025-09-30', '7a000000-0000-0000-0000-000000000002')
    WHERE lesson_id = '4b000000-0000-0000-0000-000000000013'),
  0, '…e non di settembre');
SELECT is(
  (SELECT duration_minutes || '|' || amount_cents || '|' || model_name
     FROM public.calculate_compensation_v2('2025-10-01', '2025-10-31', '7a000000-0000-0000-0000-000000000002')
    WHERE lesson_id = '4b000000-0000-0000-0000-000000000014'),
  '90|3000|S7 A ora 20', 'vale la durata vera della lezione, e il modello dell''attività batte quello generale');

-- Congelamento: dal mese scorso a quello prossimo, per vedere che la lezione futura resta fuori
SELECT is(
  (SELECT r->>'inserted' || '|' || (r->>'future') FROM (
     SELECT public.staff_freeze_compensation(
       (date_trunc('month', now()) - interval '1 month')::date,
       (date_trunc('month', now()) + interval '2 months' - interval '1 day')::date,
       '7a000000-0000-0000-0000-000000000001') AS r) x),
  '1|1', 'si congela solo la lezione già fatta; quella futura resta fuori');

SELECT is(
  public.staff_freeze_compensation(
    (date_trunc('month', now()) - interval '1 month')::date,
    (date_trunc('month', now()) - interval '1 day')::date,
    '7a000000-0000-0000-0000-000000000001')->>'inserted',
  '0', 'congelare di nuovo non duplica');

SELECT is(
  public.staff_unfreeze_compensation((date_trunc('month', now()) - interval '1 month')::date,
                                     '7a000000-0000-0000-0000-000000000001')->>'deleted',
  '1', 'un mese congelato e non pagato si riapre');

SELECT is(
  public.staff_freeze_compensation(
    (date_trunc('month', now()) - interval '1 month')::date,
    (date_trunc('month', now()) - interval '1 day')::date,
    '7a000000-0000-0000-0000-000000000001')->>'inserted',
  '1', '…e si ricongela');

SELECT throws_ok(
  $$ INSERT INTO public.compensation_entries (operator_id, period_month, lesson_id, occurred_at, duration_minutes, amount_cents)
     VALUES ('7a000000-0000-0000-0000-000000000001', '2026-01-01', '4b000000-0000-0000-0000-000000000012', now(), 60, 1) $$,
  '42501', NULL, 'i compensi congelati si scrivono solo con le funzioni');

RESET ROLE;
CREATE TEMP TABLE s7_pay AS
SELECT public.staff_pay_compensation(
  '7a000000-0000-0000-0000-000000000001', (date_trunc('month', now()) - interval '1 month')::date,
  '2026-10-05', 'bank_transfer') AS r;
GRANT SELECT ON s7_pay TO authenticated;
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT r->>'gross_cents' || '|' || (r->>'withholding_cents') || '|' || (r->>'net_cents') || '|' || (r->>'f24_due_on') FROM s7_pay),
  '3000|600|2400|2026-11-16', 'pagamento: lordo 30 €, ritenuta del 20% presa dalle impostazioni, netto 24 €, F24 entro il 16 del mese dopo');

SELECT is(
  (SELECT e.amount_cents || '|' || e.expense_date || '|' || e.payment_method::text || '|' || e.source::text || '|' || (e.confirmed_at IS NOT NULL)::text || '|' || e.category
     FROM public.expenses e WHERE e.id = (SELECT (r->>'net_expense_id')::uuid FROM s7_pay)),
  '2400|2026-10-05|bank_transfer|payout|true|staff_compensation', 'il netto è un''uscita del giorno del pagamento');

SELECT is(
  (SELECT e.amount_cents || '|' || e.expense_date || '|' || (e.confirmed_at IS NULL)::text
     FROM public.expenses e WHERE e.id = (SELECT (r->>'withholding_expense_id')::uuid FROM s7_pay)),
  '600|2026-11-16|true', 'la ritenuta è un''uscita da confermare quando si paga l''F24');

SELECT is(
  (SELECT string_agg(DISTINCT status::text || '/' || (payment_id = (SELECT (r->>'payment_id')::uuid FROM s7_pay))::text, ',')
     FROM public.compensation_entries WHERE operator_id = '7a000000-0000-0000-0000-000000000001'),
  'paid/true', 'i compensi del mese risultano pagati con quel pagamento');

SELECT is(
  public.staff_pay_compensation('7a000000-0000-0000-0000-000000000001', (date_trunc('month', now()) - interval '1 month')::date)->>'reason',
  'NOTHING_TO_PAY', 'lo stesso mese non si paga due volte');

SELECT is(
  public.staff_unfreeze_compensation((date_trunc('month', now()) - interval '1 month')::date,
                                     '7a000000-0000-0000-0000-000000000001')->>'deleted',
  '0', 'un compenso pagato non si riapre');

SELECT is(
  public.confirm_expense((SELECT (r->>'withholding_expense_id')::uuid FROM s7_pay), 1)->>'reason',
  'AMOUNT_LOCKED', 'l''importo della ritenuta non si cambia alla conferma');

SELECT throws_ok(
  format('DELETE FROM public.expenses WHERE id = %L', (SELECT r->>'net_expense_id' FROM s7_pay)),
  'P0001', 'AUTOMATIC_EXPENSE', 'l''uscita di un compenso non si cancella dall''interfaccia');

SELECT is(public.staff_undo_compensation_payment((SELECT (r->>'payment_id')::uuid FROM s7_pay))->>'ok', 'true',
  'un pagamento sbagliato si annulla');

SELECT is(
  (SELECT (SELECT count(*) FROM public.expenses
            WHERE id IN ((SELECT (r->>'net_expense_id')::uuid FROM s7_pay), (SELECT (r->>'withholding_expense_id')::uuid FROM s7_pay)))
          || '|' || string_agg(DISTINCT status::text || '/' || (payment_id IS NULL)::text, ',')
     FROM public.compensation_entries WHERE operator_id = '7a000000-0000-0000-0000-000000000001'),
  '0|pending/true', 'annullato: le uscite spariscono e i compensi tornano da pagare');

SELECT is(
  public.staff_pay_compensation('7a000000-0000-0000-0000-000000000001', (date_trunc('month', now()) - interval '1 month')::date,
                                '2026-10-06', 'cash', 0, 3200)->>'reason',
  'REASON_REQUIRED', 'un lordo diverso dal calcolato vuole la motivazione');

SELECT is(
  (SELECT r->>'net_cents' || '|' || (r->>'withholding_cents') FROM (
     SELECT public.staff_pay_compensation('7a000000-0000-0000-0000-000000000001', (date_trunc('month', now()) - interval '1 month')::date,
                                          '2026-10-06', 'cash', 0, 3200, 'Bollo della fattura') AS r) x),
  '3200|0', 'con la motivazione si paga il lordo concordato, e senza ritenuta il netto è tutto');

-- ── Modelli ──────────────────────────────────────────────────────────────────

SELECT is(
  (SELECT (r->>'ok') FROM (SELECT public.staff_save_compensation_model(jsonb_build_object(
     'id', (SELECT id FROM s7_models WHERE name = 'ora'), 'name', 'S7 A ora 20', 'min_guaranteed_cents', 2500,
     'components', jsonb_build_array(
        jsonb_build_object('kind', 'fixed_per_lesson', 'value_cents', 1500),
        jsonb_build_object('kind', 'per_participant', 'value_cents', 200)),
     'tiers', jsonb_build_array(jsonb_build_object('min_participants', 8, 'amount_cents', 1000)))) AS r) x),
  'true', 'un modello si riscrive con i suoi mattoni e scaglioni');

SELECT is(
  (SELECT (SELECT count(*) FROM public.compensation_components WHERE model_id = m.id) || '|'
       || (SELECT count(*) FROM public.compensation_tiers WHERE model_id = m.id) || '|' || m.min_guaranteed_cents
     FROM s7_models s JOIN public.compensation_models m ON m.id = s.id WHERE s.name = 'ora'),
  '2|1|2500', 'i mattoni vecchi sono sostituiti, non aggiunti');

SELECT is(
  public.staff_save_compensation_model(jsonb_build_object(
    'name', 'S7 Rotto',
    'components', jsonb_build_array(
       jsonb_build_object('kind', 'fixed_per_lesson', 'value_cents', 1000),
       jsonb_build_object('kind', 'percent_of_revenue', 'value_cents', 100))))->>'reason',
  'INVALID_MODEL', 'un mattone scritto male fa rifiutare tutto il modello');

SELECT is((SELECT count(*)::int FROM public.compensation_models WHERE name = 'S7 Rotto'), 0,
  '…e del modello rifiutato non resta niente');

SELECT is(
  public.preview_compensation((SELECT id FROM s7_models WHERE name = 'ora'), 60, 9, 0)->>'amount_cents',
  '4300', 'la prova del modello: 15 € + 9 × 2 € + 10 € di scaglione');

-- ─────────────────────────────────────────────────────────────────────────────
-- Rimborso a unə volontariə, cassa e banca
-- ─────────────────────────────────────────────────────────────────────────────

RESET ROLE;
INSERT INTO public.volunteers (id, full_name, started_on) VALUES ('7b000000-0000-0000-0000-000000000001', 'S7 Volontaria', '2026-08-19');
INSERT INTO public.volunteer_reimbursements (id, volunteer_id, spent_on, amount_cents, description, attachment_path, status, approved_at)
VALUES ('7c000000-0000-0000-0000-000000000001', '7b000000-0000-0000-0000-000000000001', '2026-09-02', 400, 'Tappetini',
        'rimborsi/s7/scontrino.pdf', 'approved', now());

SET LOCAL request.jwt.claims = '{"sub":"17000000-0000-0000-0000-000000000001","role":"authenticated"}';
CREATE TEMP TABLE s7_reimb AS
SELECT public.staff_pay_volunteer_reimbursement('7c000000-0000-0000-0000-000000000001', '2026-09-20', 'cash') AS r;
GRANT SELECT ON s7_reimb TO authenticated;

SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT e.expense_date || '|' || e.payment_method::text || '|' || e.amount_cents FROM public.expenses e
    WHERE e.id = (SELECT (r->>'expense_id')::uuid FROM s7_reimb)),
  '2026-09-20|cash|400', 'il rimborso esce il giorno in cui lo si paga, non quello dello scontrino');

SELECT is(public.finance_set_opening_balances(10000, 50000)->>'ok', 'true', 'il Tesoriere imposta i saldi iniziali');

INSERT INTO public.account_transfers (occurred_on, from_account, to_account, amount_cents, note)
VALUES ('2026-09-14', 'cash', 'bank', 2000, 'S7 versamento');

-- Movimenti del test fino al 30/09: in cassa 10 + 25 − 1 + 8 (entrate) − 12 (materiali) − 20
-- (versamento) − 4 (rimborso) = 6 €; in banca 20 + 50 − 5 + 15 + 100 (entrate) − 1,50
-- (commissione) + 20 (versamento) = 198,50 €. I compensi sono pagati in ottobre.
SELECT is(
  (SELECT (public.finance_account_balances('2026-09-30')->>'cash_cents')::bigint
          - ((b->>'cash_cents')::bigint - oc + 10000) FROM s7_base),
  600::bigint, 'saldo di cassa: saldo iniziale più i movimenti in contanti, meno quello che è andato in banca');

SELECT is(
  (SELECT (public.finance_account_balances('2026-09-30')->>'bank_cents')::bigint
          - ((b->>'bank_cents')::bigint - ob + 50000) FROM s7_base),
  19850::bigint, 'saldo di banca: bonifici, carta e versamento, meno la commissione di Stripe');

SELECT is(
  (SELECT r->>'cash_cents' || '|' || (r->>'bank_cents') || '|' || (r->>'before_ledger')
     FROM (SELECT public.finance_account_balances('2026-08-01') AS r) x),
  '10000|50000|true', 'prima dell''inizio della contabilità valgono i saldi iniziali');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
