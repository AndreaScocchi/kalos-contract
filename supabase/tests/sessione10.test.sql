-- Sessione 10: la Bussola dei soci (D6), le proprie ricevute nell'app, l'interruttore della Pratica
-- a casa.

BEGIN;
SELECT plan(24);

-- ── Persone ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('1a000000-0000-0000-0000-000000000001', 's10-anna@test.kalos',  '{"full_name":"Anna Dieci"}',  'authenticated', 'authenticated'),
  ('1a000000-0000-0000-0000-000000000002', 's10-bruno@test.kalos', '{"full_name":"Bruno Dieci"}', 'authenticated', 'authenticated'),
  ('1a000000-0000-0000-0000-000000000003', 's10-carla@test.kalos', '{"full_name":"Carla Dieci"}', 'authenticated', 'authenticated'),
  ('1a000000-0000-0000-0000-000000000004', 's10-dario@test.kalos', '{"full_name":"Dario Dieci"}', 'authenticated', 'authenticated'),
  ('1a000000-0000-0000-0000-000000000005', 's10-ope@test.kalos',   '{"full_name":"Operatrice Dieci"}', 'authenticated', 'authenticated'),
  ('1a000000-0000-0000-0000-000000000006', 's10-senza@test.kalos', '{"full_name":"Senza Scheda"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '1a000000-0000-0000-0000-000000000005';
-- Un account senza scheda cliente
DELETE FROM public.clients WHERE email = 's10-senza@test.kalos';

-- La Bussola non dipende da «solo soci»
UPDATE public.feature_flags SET enabled = false WHERE key = 'members_only';

CREATE TEMP TABLE s10 AS
SELECT (SELECT id FROM public.clients WHERE email = 's10-anna@test.kalos')  AS anna,
       (SELECT id FROM public.clients WHERE email = 's10-bruno@test.kalos') AS bruno,
       (SELECT id FROM public.clients WHERE email = 's10-carla@test.kalos') AS carla,
       (SELECT id FROM public.clients WHERE email = 's10-dario@test.kalos') AS dario,
       EXTRACT(YEAR FROM CURRENT_DATE)::int AS year;
GRANT SELECT ON s10 TO authenticated;

INSERT INTO public.association_years (year, fee_cents) VALUES ((SELECT year FROM s10), 2500)
ON CONFLICT (year) DO UPDATE SET fee_cents = 2500, fee_due_date = NULL;

-- Anna: sociə con la quota versata. Dario: sociə, quota ancora da versare. Carla: domanda in
-- attesa con la quota versata. Bruno: nessuna domanda.
INSERT INTO public.members (client_id, member_number, admitted_on)
SELECT anna, 'S10-0001', CURRENT_DATE - 30 FROM s10
UNION ALL SELECT dario, 'S10-0002', CURRENT_DATE - 30 FROM s10;
INSERT INTO public.member_fees (client_id, year, amount_cents, status, paid_at)
SELECT anna, year, 2500, 'paid'::public.member_fee_status, now() FROM s10
UNION ALL SELECT carla, year, 2500, 'paid', now() FROM s10
UNION ALL SELECT dario, year, 2500, 'due', NULL FROM s10;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000005","role":"authenticated"}';
SELECT is(
  public.staff_create_member_application((SELECT carla FROM s10),
    jsonb_build_object('year', (SELECT year FROM s10), 'first_name', 'Carla', 'last_name', 'Dieci',
                       'birth_date', '1990-05-01', 'fiscal_code', 'dcicrl90e41f356x',
                       'address_street', 'Via Roma 1', 'address_zip', '34077',
                       'address_city', 'Ronchi dei Legionari', 'address_province', 'GO'))->>'ok',
  'true', 'Carla ha una domanda in attesa');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 1. La Bussola
-- ═════════════════════════════════════════════════════════════════════════════

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.request_bussola(NULL, NULL)->>'reason', 'NOT_A_MEMBER',
  'chi non è sociə non chiede la Bussola, anche con «solo soci» spenta');

SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000006","role":"authenticated"}';
SELECT is(public.request_bussola(NULL, NULL)->>'reason', 'NOT_A_MEMBER',
  'nemmeno chi non ha ancora una scheda');

SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is(public.request_bussola(NULL, NULL)->>'reason', 'PENDING_ADMISSION',
  'con la domanda in attesa si aspetta l''ammissione');

SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000004","role":"authenticated"}';
SELECT is(public.request_bussola(NULL, NULL)->>'ok', 'true',
  'unə sociə con la quota ancora nei tempi la chiede');
RESET ROLE;

UPDATE public.association_years SET fee_due_date = CURRENT_DATE - 1 WHERE year = (SELECT year FROM s10);
UPDATE public.bussola_requests SET status = 'cancelled' WHERE client_id = (SELECT dario FROM s10);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000004","role":"authenticated"}';
SELECT is(public.request_bussola(NULL, NULL)->>'reason', 'MEMBERSHIP_FEE_DUE',
  'passata la data di decadenza senza quota, prima serve la quota');

SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.request_bussola(NULL, repeat('a', 1001))->>'reason', 'NOTE_TOO_LONG',
  'una nota oltre i mille caratteri non passa');
SELECT is(public.request_bussola(NULL, '  Vorrei capire da dove cominciare  ')->>'ok', 'true',
  'Anna, sociə in regola, chiede la Bussola');
SELECT is(public.request_bussola(NULL, NULL)->>'reason', 'ALREADY_OPEN',
  'una richiesta aperta alla volta');
SELECT is((SELECT note || ' | ' || status || ' | ' || (metadata->>'channel') FROM public.bussola_requests
            WHERE client_id = (SELECT anna FROM s10)),
  'Vorrei capire da dove cominciare | pending | app', 'la richiesta la legge solo lei, con la nota ripulita');
RESET ROLE;

SELECT set_config('s10.request_anna', (SELECT id::text FROM public.bussola_requests
                                          WHERE client_id = (SELECT anna FROM s10) AND status = 'pending'), true);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.cancel_bussola_request(current_setting('s10.request_anna')::uuid)->>'reason',
  'NOT_FOUND', 'Bruno non ritira la richiesta di Anna (e non scopre che esiste)');
RESET ROLE;

UPDATE public.bussola_requests SET status = 'scheduled' WHERE client_id = (SELECT anna FROM s10);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.cancel_bussola_request((SELECT id FROM public.bussola_requests
                                          WHERE client_id = (SELECT anna FROM s10) AND status = 'scheduled'))->>'reason',
  'ALREADY_SCHEDULED', 'una Bussola già fissata non si ritira dall''app');

SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000005","role":"authenticated"}';
SELECT is(public.cancel_bussola_request((SELECT id FROM public.bussola_requests
                                          WHERE client_id = (SELECT anna FROM s10) AND status = 'scheduled'))->>'ok',
  'true', 'lo staff la annulla anche fissata');

SET LOCAL request.jwt.claims = '{"sub":"1a000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.request_bussola(NULL, NULL)->>'ok', 'true', 'annullata, Anna ne chiede un''altra');
SELECT is(public.cancel_bussola_request((SELECT id FROM public.bussola_requests
                                          WHERE client_id = (SELECT anna FROM s10) AND status = 'pending'))->>'ok',
  'true', 'e la ritira finché è da fissare');
RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. Le proprie ricevute
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
-- 3. L'interruttore della Pratica a casa
-- ═════════════════════════════════════════════════════════════════════════════

SELECT is((SELECT enabled FROM public.feature_flags WHERE key = 'home_practice'), false,
  'la Pratica a casa nasce spenta');

SELECT * FROM finish();
ROLLBACK;
