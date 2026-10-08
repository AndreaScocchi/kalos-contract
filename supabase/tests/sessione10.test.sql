-- Sessione 10: le proprie ricevute nell'app, l'interruttore della Pratica a casa. La Bussola dei
-- soci, che stava qui, è stata tolta il 07/10/2026 (migrazione 20261007190000_via_bussola).

BEGIN;
SELECT plan(9);

-- ── Persone ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('1a000000-0000-0000-0000-000000000001', 's10-anna@test.kalos',  '{"full_name":"Anna Dieci"}',  'authenticated', 'authenticated'),
  ('1a000000-0000-0000-0000-000000000002', 's10-bruno@test.kalos', '{"full_name":"Bruno Dieci"}', 'authenticated', 'authenticated'),
  ('1a000000-0000-0000-0000-000000000005', 's10-ope@test.kalos',   '{"full_name":"Operatrice Dieci"}', 'authenticated', 'authenticated'),
  ('1a000000-0000-0000-0000-000000000006', 's10-senza@test.kalos', '{"full_name":"Senza Scheda"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '1a000000-0000-0000-0000-000000000005';
-- Un account senza scheda cliente
DELETE FROM public.clients WHERE email = 's10-senza@test.kalos';

CREATE TEMP TABLE s10 AS
SELECT (SELECT id FROM public.clients WHERE email = 's10-anna@test.kalos')  AS anna,
       (SELECT id FROM public.clients WHERE email = 's10-bruno@test.kalos') AS bruno;
GRANT SELECT ON s10 TO authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- 1. Le proprie ricevute
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000005","role":"authenticated"}';
SELECT is(public.staff_register_payment(jsonb_build_object(
    'client_id', (SELECT anna FROM s10), 'kind', 'subscription', 'amount_cents', 6000, 'method', 'bank_transfer',
    'description', 'S10 Carnet', 'note', 'nota interna dello staff', 'issue_receipt', true))->>'ok',
  'true', 'un incasso di Anna con ricevuta');
SELECT is(public.staff_register_payment(jsonb_build_object(
    'client_id', (SELECT bruno FROM s10), 'kind', 'donation', 'amount_cents', 2000,
    'description', 'S10 Donazione', 'issue_receipt', true))->>'ok',
  'true', 'uno di Bruno');
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(
  (SELECT string_agg((i->>'amount_cents') || ' ' || (i->>'method') || ' ' || (i->>'kind'), ', ')
     FROM jsonb_array_elements(public.get_my_receipts()->'items') i),
  '6000 bank_transfer subscription', 'Anna vede solo la sua ricevuta, con metodo e tipo');
SELECT ok(NOT (public.get_my_receipts()::text LIKE '%nota interna%'),
  'le note dello staff sull''incasso non escono');
SELECT is(
  public.get_my_receipt((SELECT (public.get_my_receipts()->'items'->0->>'id')::uuid))
    #>> '{receipt,transaction,method}',
  'bank_transfer', 'i dati del PDF della propria ricevuta, col metodo di pagamento');
SELECT is((SELECT count(*)::int FROM public.receipts), 0,
  'dalla tabella il cliente non legge nessuna ricevuta, nemmeno la sua');
RESET ROLE;

-- La ricevuta di Bruno, chiesta da Anna
SELECT set_config('s10.receipt_bruno', (SELECT r.id::text FROM public.receipts r
                                          JOIN public.transactions t ON t.id = r.transaction_id
                                         WHERE t.description = 'S10 Donazione'), true);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.get_my_receipt(current_setting('s10.receipt_bruno')::uuid)->>'reason', 'RECEIPT_NOT_FOUND',
  'la ricevuta di un''altra persona risponde come una inesistente');

SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000006","role":"authenticated"}';
SELECT is(public.get_my_receipts()->'items', '[]'::jsonb, 'senza scheda, nessuna ricevuta');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. L'interruttore della Pratica a casa
-- ═════════════════════════════════════════════════════════════════════════════

SELECT is((SELECT enabled FROM public.feature_flags WHERE key = 'home_practice'), false,
  'la Pratica a casa nasce spenta');

SELECT * FROM finish();
ROLLBACK;
