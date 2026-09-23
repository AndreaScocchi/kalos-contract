-- Ricevute: numerazione per anno senza buchi né duplicati, dati congelati, annullamento che non
-- libera il numero. È la regola su cui si regge la contabilità dell'associazione (A5, 2.1–2.3).

BEGIN;
SELECT plan(10);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('12000000-0000-0000-0000-000000000001', 'tesoriere@test.kalos', '{"full_name":"Tesoriere"}', 'authenticated', 'authenticated'),
  ('12000000-0000-0000-0000-000000000002', 'socia@test.kalos', '{"full_name":"Socia Test"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'finance' WHERE id = '12000000-0000-0000-0000-000000000001';

UPDATE public.association_settings
   SET stamp_duty_threshold_cents = 7747, stamp_duty_cents = 200 WHERE id = true;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"12000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(
  (public.staff_register_payment(jsonb_build_object(
     'client_id', (SELECT id FROM public.clients WHERE email = 'socia@test.kalos'),
     'kind', 'membership_fee', 'amount_cents', 2500, 'method', 'cash',
     'source', 'studio', 'issue_receipt', true))
   #>> '{receipt,full_number}'),
  '1/' || EXTRACT(YEAR FROM CURRENT_DATE)::int::text,
  'la prima ricevuta dell''anno è la numero 1'
);

SELECT is(
  (public.staff_register_payment(jsonb_build_object(
     'client_id', (SELECT id FROM public.clients WHERE email = 'socia@test.kalos'),
     'kind', 'subscription', 'amount_cents', 10000, 'method', 'bank_transfer',
     'source', 'studio', 'issue_receipt', true))
   #>> '{receipt,full_number}'),
  '2/' || EXTRACT(YEAR FROM CURRENT_DATE)::int::text,
  'la seconda prende il numero successivo'
);

SELECT is(
  (SELECT stamp_duty_cents FROM public.receipts WHERE number = 2), 200,
  'sopra la soglia si applica la marca da bollo'
);

SELECT is(
  (SELECT stamp_duty_cents FROM public.receipts WHERE number = 1), 0,
  'sotto la soglia no'
);

SELECT is(
  (SELECT count(DISTINCT number)::int FROM public.receipts), 2,
  'non ci sono numeri duplicati'
);

SELECT is(
  (SELECT max(number) - min(number) + 1 FROM public.receipts)::int,
  (SELECT count(*)::int FROM public.receipts),
  'la numerazione non ha buchi'
);

SELECT is(
  (public.issue_receipt((SELECT transaction_id FROM public.receipts WHERE number = 1)))->>'reason',
  'RECEIPT_ALREADY_ISSUED',
  'la stessa transazione non genera due ricevute'
);

SELECT is(
  (public.staff_register_payment(jsonb_build_object(
     'client_id', (SELECT id FROM public.clients WHERE email = 'socia@test.kalos'),
     'kind', 'subscription', 'amount_cents', 6000, 'method', 'cash',
     'source', 'studio', 'status', 'pending', 'issue_receipt', true))
   #>> '{receipt}'),
  NULL,
  'un abbonamento "da saldare" non emette ricevuta'
);

SELECT is(
  (public.void_receipt((SELECT id FROM public.receipts WHERE number = 1), ''))->>'reason',
  'REASON_REQUIRED', 'annullare una ricevuta richiede una motivazione'
);

SELECT ok(
  (public.void_receipt((SELECT id FROM public.receipts WHERE number = 1), 'Importo sbagliato'))
    ->>'ok' = 'true'
  AND (SELECT count(*)::int FROM public.receipts WHERE number = 1) = 1,
  'la ricevuta annullata resta, con il suo numero: annullare non libera il numero'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
