-- Gestionale soci e incassi (sessione 4): saldare un "da saldare", incassare la quota in un gesto
-- solo, leggere lo stato di iscrizione di più persone. Le operatrici registrano e saldano, ma non
-- vedono le Finanze (E3): per questo i test girano con il ruolo `operator`, non admin.

BEGIN;
SELECT plan(18);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('14000000-0000-0000-0000-000000000001', 'operatrice@test.kalos', '{"full_name":"Operatrice Test"}', 'authenticated', 'authenticated'),
  ('14000000-0000-0000-0000-000000000002', 'nuova@test.kalos', '{"full_name":"Nuova Socia"}', 'authenticated', 'authenticated'),
  ('14000000-0000-0000-0000-000000000003', 'cliente@test.kalos', '{"full_name":"Cliente Qualunque"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '14000000-0000-0000-0000-000000000001';

-- Quota 2026 deliberata a 25 €, 2027 ancora da deliberare (NULL)
UPDATE public.association_years SET fee_cents = 2500 WHERE year = 2026;
UPDATE public.association_years SET fee_cents = NULL WHERE year = 2027;

-- ─────────────────────────────────────────────────────────────────────────────
-- Chi non è staff non passa
-- ─────────────────────────────────────────────────────────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"14000000-0000-0000-0000-000000000003","role":"authenticated"}';

SELECT is(
  public.staff_pay_member_fee((SELECT id FROM public.clients WHERE email = 'cliente@test.kalos'), 2026)->>'reason',
  'NOT_STAFF', 'un cliente non può incassare quote'
);
SELECT is(
  public.staff_settle_transaction('00000000-0000-0000-0000-000000000000'::uuid)->>'reason',
  'NOT_STAFF', 'un cliente non può saldare incassi'
);
SELECT is(
  public.staff_get_member_statuses(ARRAY[(SELECT id FROM public.clients WHERE email = 'cliente@test.kalos')])->>'reason',
  'NOT_STAFF', 'un cliente non legge lo stato di iscrizione degli altri'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Stato di iscrizione e quota
-- ─────────────────────────────────────────────────────────────────────────────

SET LOCAL request.jwt.claims = '{"sub":"14000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(
  public.staff_get_member_statuses(ARRAY[(SELECT id FROM public.clients WHERE email = 'nuova@test.kalos')])
    #>> ARRAY['statuses', (SELECT id FROM public.clients WHERE email = 'nuova@test.kalos')::text],
  'no_application', 'senza domanda lo stato è no_application'
);

SELECT is(
  public.staff_create_member_application(
    (SELECT id FROM public.clients WHERE email = 'nuova@test.kalos'),
    jsonb_build_object('year', 2026, 'first_name', 'Nuova', 'last_name', 'Socia', 'birth_date', '1990-05-01',
                       'fiscal_code', 'nvssci90e41f356x', 'address_street', 'Via Roma 1', 'address_zip', '34077',
                       'address_city', 'Ronchi dei Legionari', 'address_province', 'GO')
  )->>'ok',
  'true', 'l''operatrice inserisce una domanda su carta'
);

SELECT is(
  public.staff_get_member_statuses(ARRAY[(SELECT id FROM public.clients WHERE email = 'nuova@test.kalos')])
    #>> ARRAY['statuses', (SELECT id FROM public.clients WHERE email = 'nuova@test.kalos')::text],
  'fee_unpaid', 'con la domanda ma senza quota lo stato è fee_unpaid'
);

SELECT is(
  public.staff_pay_member_fee((SELECT id FROM public.clients WHERE email = 'nuova@test.kalos'), 2027)->>'reason',
  'FEE_AMOUNT_NOT_SET', 'senza importo deliberato e senza importo a mano non si incassa'
);

SELECT ok(
  (public.staff_pay_member_fee((SELECT id FROM public.clients WHERE email = 'nuova@test.kalos'), 2026,
     NULL, 'cash'::public.payment_method, NULL, true) #>> '{receipt,full_number}') IS NOT NULL,
  'la quota si incassa con l''importo dell''anno e la ricevuta'
);

SELECT is(
  (SELECT r.recipient_fiscal_code || ' | ' || r.recipient_address FROM public.receipts r
     JOIN public.transactions t ON t.id = r.transaction_id
    WHERE t.client_id = (SELECT id FROM public.clients WHERE email = 'nuova@test.kalos')
      AND t.kind = 'membership_fee'),
  'NVSSCI90E41F356X | Via Roma 1, 34077 Ronchi dei Legionari (GO)',
  'la ricevuta della quota, pagata prima della delibera, ha già codice fiscale e indirizzo della domanda'
);

SELECT is(
  (SELECT status::text || ':' || amount_cents::text FROM public.member_fees
    WHERE client_id = (SELECT id FROM public.clients WHERE email = 'nuova@test.kalos') AND year = 2026),
  'paid:2500', 'la quota risulta pagata, con l''importo deliberato'
);

SELECT is(
  (SELECT count(*)::int FROM public.transactions t
     JOIN public.member_fees f ON f.transaction_id = t.id
    WHERE f.client_id = (SELECT id FROM public.clients WHERE email = 'nuova@test.kalos')
      AND t.kind = 'membership_fee' AND t.status = 'paid' AND t.amount_cents = 2500),
  1, 'la quota è collegata al suo incasso'
);

SELECT is(
  public.staff_pay_member_fee((SELECT id FROM public.clients WHERE email = 'nuova@test.kalos'), 2026)->>'reason',
  'FEE_ALREADY_PAID', 'la stessa quota non si incassa due volte'
);

SELECT is(
  public.staff_get_member_statuses(ARRAY[(SELECT id FROM public.clients WHERE email = 'nuova@test.kalos')])
    #>> ARRAY['statuses', (SELECT id FROM public.clients WHERE email = 'nuova@test.kalos')::text],
  'pending_admission', 'con la quota pagata e la domanda aperta lo stato è pending_admission'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- "Da saldare"
-- ─────────────────────────────────────────────────────────────────────────────

SELECT is(
  public.staff_register_payment(jsonb_build_object(
    'client_id', (SELECT id FROM public.clients WHERE email = 'cliente@test.kalos'),
    'kind', 'subscription', 'amount_cents', 9000, 'method', 'cash', 'status', 'pending',
    'occurred_on', (CURRENT_DATE - 10)::text, 'description', 'Abbonamento da saldare'))->>'ok',
  'true', 'l''operatrice registra un abbonamento da saldare'
);

SELECT ok(
  (public.staff_settle_transaction(
     (SELECT id FROM public.transactions WHERE description = 'Abbonamento da saldare'),
     'bank_transfer'::public.payment_method, CURRENT_DATE, true) #>> '{receipt,full_number}') IS NOT NULL,
  'l''operatrice lo salda ed emette la ricevuta'
);

SELECT is(
  (SELECT status::text || ':' || method::text || ':' || (occurred_on = CURRENT_DATE)::text
     FROM public.transactions WHERE description = 'Abbonamento da saldare'),
  'paid:bank_transfer:true', 'saldato: stato, metodo e data sono quelli dell''incasso vero'
);

SELECT is(
  public.staff_settle_transaction(
    (SELECT id FROM public.transactions WHERE description = 'Abbonamento da saldare'))->>'reason',
  'NOT_PENDING', 'un incasso già saldato non si salda di nuovo'
);

SELECT is(
  public.staff_get_member_statuses(ARRAY[NULL::uuid])->'statuses',
  '{}'::jsonb, 'gli id nulli si ignorano'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
