-- Pagamenti online (sessione 5): quota dal sito, donazioni, rimborsi da Stripe.
--
-- Il webhook non usa gli eventi come dati: rilegge da Stripe lo stato del pagamento e lo passa a
-- `stripe_apply_payment_state`. Qui si prova quella funzione con gli stati che Stripe può raccontare,
-- anche due volte, anche fuori ordine, e le regole che non devono mai saltare: un incasso per
-- pagamento, niente ricevuta sui doppioni, niente pagamenti di prova nel registro vero.

BEGIN;
SELECT plan(48);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('15000000-0000-0000-0000-000000000001', 'socia@test.kalos', '{"full_name":"Socia Online"}', 'authenticated', 'authenticated'),
  ('15000000-0000-0000-0000-000000000002', 'tesoriere@test.kalos', '{"full_name":"Tesoriere"}', 'authenticated', 'authenticated'),
  ('15000000-0000-0000-0000-000000000003', 'operatrice@test.kalos', '{"full_name":"Operatrice"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'finance'  WHERE id = '15000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET role = 'operator' WHERE id = '15000000-0000-0000-0000-000000000003';

UPDATE public.feature_flags SET enabled = false WHERE key = 'payments';
INSERT INTO public.feature_flags (key, enabled) VALUES ('stripe_test_ledger', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
UPDATE public.association_years SET fee_cents = 2500, is_open = true WHERE year = 2026;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Prima del checkout: prepare_my_fee_payment
-- ─────────────────────────────────────────────────────────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(public.prepare_my_fee_payment(2026)->>'reason', 'PAYMENTS_DISABLED',
  'con i pagamenti spenti non si apre nessun checkout');

RESET ROLE;
UPDATE public.feature_flags SET enabled = true WHERE key = 'payments';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(public.prepare_my_fee_payment(2026)->>'reason', 'NO_APPLICATION',
  'senza domanda di ammissione la quota non si paga');

SELECT is(
  public.submit_member_application(jsonb_build_object(
    'year', 2026, 'channel', 'site', 'first_name', 'Socia', 'last_name', 'Online',
    'birth_date', '1988-03-12', 'fiscal_code', 'snlsco88c52f356k',
    'address_street', 'Via Roma 3', 'address_zip', '34074', 'address_city', 'Monfalcone',
    'address_province', 'GO', 'email', 'socia@test.kalos',
    'accepted_statute', true, 'accepted_privacy', true))->>'ok',
  'true', 'la domanda dal sito si invia');

RESET ROLE;
UPDATE public.association_years SET fee_cents = NULL WHERE year = 2026;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(public.prepare_my_fee_payment(2026)->>'reason', 'FEE_AMOUNT_NOT_SET',
  'finché il Consiglio Direttivo non delibera l''importo, online non si paga');

RESET ROLE;
UPDATE public.association_years SET fee_cents = 2500 WHERE year = 2026;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is((public.prepare_my_fee_payment(2026)->>'amount_cents')::int, 2500,
  'con la domanda e l''importo deliberato il checkout si prepara, con l''importo deciso dal database');

SELECT is(public.issue_receipt((SELECT id FROM public.transactions LIMIT 1))->>'reason', 'NOT_STAFF',
  'emettere ricevute resta cosa dello staff');

RESET ROLE;

-- Il checkout aperto dall'edge function (riga "created")
INSERT INTO public.stripe_payments (id, checkout_session_id, client_id, purpose, target_id, amount_cents,
                                    source, metadata, livemode, receipt_email)
SELECT '90000000-0000-0000-0000-000000000001', 'cs_test_quota', f.client_id, 'membership_fee', f.id, 2500,
       'site', jsonb_build_object('year', 2026), false, 'socia@test.kalos'
  FROM public.member_fees f
  JOIN public.clients c ON c.id = f.client_id
 WHERE c.email = 'socia@test.kalos' AND f.year = 2026;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Il pagamento della quota
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TEMP TABLE quota_state AS
SELECT jsonb_build_object(
  'stripe_payment_id', '90000000-0000-0000-0000-000000000001',
  'checkout_session_id', 'cs_test_quota',
  'payment_intent', jsonb_build_object(
    'id', 'pi_test_quota', 'status', 'succeeded', 'amount_received', 2500, 'currency', 'eur',
    'livemode', false, 'payment_method_type', 'card', 'receipt_email', 'socia@test.kalos',
    'charge', jsonb_build_object('created', extract(epoch from now())::bigint, 'fee_cents', 60, 'net_cents', 2440)),
  'refunds', '[]'::jsonb) AS payload;

SELECT is(public.stripe_apply_payment_state((SELECT payload FROM quota_state))->>'ok', 'true',
  'lo stato "pagato" si applica');

SELECT is(
  (SELECT status::text FROM public.member_fees f JOIN public.clients c ON c.id = f.client_id
    WHERE c.email = 'socia@test.kalos' AND f.year = 2026),
  'paid', 'la quota risulta pagata');

SELECT is(
  (SELECT r.causale || ' | ' || r.recipient_fiscal_code FROM public.receipts r
     JOIN public.transactions t ON t.id = r.transaction_id
    WHERE t.stripe_payment_id = '90000000-0000-0000-0000-000000000001'),
  'Quota associativa 2026 | SNLSCO88C52F356K',
  'la ricevuta nasce da sola, con la causale dell''anno e il codice fiscale della domanda');

SELECT is(
  (SELECT method::text || ' | ' || source::text FROM public.transactions
    WHERE stripe_payment_id = '90000000-0000-0000-0000-000000000001'),
  'stripe | site', 'l''incasso dice come e da dove è arrivato');

-- Stripe consegna di nuovo lo stesso stato
SELECT is(
  jsonb_array_length(public.stripe_apply_payment_state((SELECT payload FROM quota_state))->'receipt_ids'),
  1, 'riapplicato, restituisce la stessa ricevuta ancora da inviare');

SELECT is(
  (SELECT count(*)::int FROM public.transactions WHERE stripe_payment_id = '90000000-0000-0000-0000-000000000001'),
  1, 'lo stesso pagamento applicato due volte fa un incasso solo');

SELECT is(
  (SELECT count(*)::int FROM public.receipts r JOIN public.transactions t ON t.id = r.transaction_id
    WHERE t.stripe_payment_id = '90000000-0000-0000-0000-000000000001'),
  1, 'e una ricevuta sola');

SELECT is(
  (SELECT count(*)::int FROM public.expenses WHERE source = 'stripe_fee' AND notes LIKE '%pi_test_quota%'),
  1, 'la commissione diventa un''uscita, una volta sola');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT is(public.prepare_my_fee_payment(2026)->>'reason', 'FEE_ALREADY_PAID',
  'una quota pagata non si paga di nuovo');
RESET ROLE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. La stessa quota pagata due volte (due schede del browser)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.stripe_payments (id, checkout_session_id, client_id, purpose, target_id, amount_cents, source, livemode)
SELECT '90000000-0000-0000-0000-000000000002', 'cs_test_doppio', client_id, 'membership_fee', target_id, 2500, 'site', false
  FROM public.stripe_payments WHERE id = '90000000-0000-0000-0000-000000000001';

SELECT is(
  public.stripe_apply_payment_state(jsonb_build_object(
    'stripe_payment_id', '90000000-0000-0000-0000-000000000002',
    'payment_intent', jsonb_build_object('id', 'pi_test_doppio', 'status', 'succeeded', 'amount_received', 2500,
      'currency', 'eur', 'livemode', false,
      'charge', jsonb_build_object('created', extract(epoch from now())::bigint, 'fee_cents', 60, 'net_cents', 2440))
  ))->>'is_duplicate',
  'true', 'il secondo pagamento della stessa quota è segnato come doppione');

SELECT ok(
  EXISTS (SELECT 1 FROM public.transactions WHERE stripe_payment_id = '90000000-0000-0000-0000-000000000002'
           AND member_fee_id IS NULL AND (metadata->>'duplicate')::boolean),
  'il denaro arrivato si registra comunque, senza toccare la quota');

SELECT is(
  (SELECT count(*)::int FROM public.receipts r JOIN public.transactions t ON t.id = r.transaction_id
    WHERE t.stripe_payment_id = '90000000-0000-0000-0000-000000000002'),
  0, 'nessuna ricevuta sul doppione: niente numero bruciato su soldi da restituire');

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Una donazione dal sito, pagata alle 23:30 del 31 dicembre
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.stripe_payments (id, checkout_session_id, purpose, amount_cents, source, livemode, metadata)
VALUES ('90000000-0000-0000-0000-000000000003', 'cs_test_dono', 'donation', 5000, 'site', false,
        jsonb_build_object('payer', jsonb_build_object('name', 'Maria Rossi', 'email', 'maria@test.kalos',
                                                       'fiscal_code', 'rssmra80a41f205x')));

SELECT is(
  public.stripe_apply_payment_state(jsonb_build_object(
    'stripe_payment_id', '90000000-0000-0000-0000-000000000003',
    'payment_intent', jsonb_build_object('id', 'pi_test_dono', 'status', 'succeeded', 'amount_received', 5000,
      'currency', 'eur', 'livemode', false,
      'charge', jsonb_build_object('created', extract(epoch from timestamptz '2026-12-31 22:30:00+00')::bigint,
                                   'fee_cents', 100, 'net_cents', 4900))
  ))->>'ok',
  'true', 'la donazione si registra');

SELECT is(
  (SELECT r.recipient_name || ' | ' || r.recipient_fiscal_code || ' | ' || r.causale || ' | ' || r.year
     FROM public.receipts r JOIN public.transactions t ON t.id = r.transaction_id
    WHERE t.stripe_payment_id = '90000000-0000-0000-0000-000000000003'),
  'Maria Rossi | RSSMRA80A41F205X | Erogazione liberale | 2026',
  'la ricevuta è intestata a chi ha donato, e il 31/12 alle 23:30 in Italia resta nel 2026');

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Un pagamento di prova dove l'interruttore locale non c'è (cioè in produzione)
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.feature_flags SET enabled = false WHERE key = 'stripe_test_ledger';

INSERT INTO public.stripe_payments (id, checkout_session_id, purpose, amount_cents, source, livemode, metadata)
VALUES ('90000000-0000-0000-0000-000000000004', 'cs_test_prova', 'donation', 1000, 'site', false,
        jsonb_build_object('payer', jsonb_build_object('name', 'Prova', 'email', 'prova@test.kalos')));

SELECT is(
  public.stripe_apply_payment_state(jsonb_build_object(
    'stripe_payment_id', '90000000-0000-0000-0000-000000000004',
    'payment_intent', jsonb_build_object('id', 'pi_test_prova', 'status', 'succeeded', 'amount_received', 1000,
      'currency', 'eur', 'livemode', false,
      'charge', jsonb_build_object('created', extract(epoch from now())::bigint, 'fee_cents', 40, 'net_cents', 960))
  ))->>'ledger',
  'false', 'un pagamento di prova in produzione non può scrivere nel registro');

SELECT is(
  (SELECT count(*)::int FROM public.transactions WHERE stripe_payment_id = '90000000-0000-0000-0000-000000000004')
  + (SELECT count(*)::int FROM public.expenses WHERE notes LIKE '%pi_test_prova%'),
  0, 'né incasso, né ricevuta, né uscita per la commissione');

SELECT is(
  (SELECT status::text FROM public.stripe_payments WHERE id = '90000000-0000-0000-0000-000000000004'),
  'succeeded', 'resta solo la riga del pagamento, per capire cosa è successo');

UPDATE public.feature_flags SET enabled = true WHERE key = 'stripe_test_ledger';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Rimborsi
-- ─────────────────────────────────────────────────────────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"15000000-0000-0000-0000-000000000002","role":"authenticated"}';

SELECT is(
  public.staff_refund_transaction(
    (SELECT id FROM public.transactions WHERE stripe_payment_id = '90000000-0000-0000-0000-000000000001'),
    500, 'A mano')->>'reason',
  'USE_STRIPE_REFUND', 'un incasso online non si rimborsa a mano: i soldi sono sulla carta');

SELECT is(
  public.staff_prepare_stripe_refund(
    (SELECT id FROM public.transactions WHERE stripe_payment_id = '90000000-0000-0000-0000-000000000001'),
    3000)->>'reason',
  'INVALID_AMOUNT', 'non si rimborsa più di quanto incassato');

SELECT is(
  public.staff_prepare_stripe_refund(
    (SELECT id FROM public.transactions WHERE stripe_payment_id = '90000000-0000-0000-0000-000000000001'),
    1000)->>'payment_intent_id',
  'pi_test_quota', 'il Tesoriere prepara il rimborso sulla carta');

SET LOCAL request.jwt.claims = '{"sub":"15000000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is(
  public.staff_prepare_stripe_refund(
    (SELECT id FROM public.transactions WHERE stripe_payment_id = '90000000-0000-0000-0000-000000000001'),
    1000)->>'reason',
  'NOT_FINANCE', 'un''operatrice no');
RESET ROLE;

-- Stripe racconta un rimborso parziale, due volte
CREATE TEMP TABLE rimborso_parziale AS
SELECT (SELECT payload FROM quota_state) || jsonb_build_object('refunds', jsonb_build_array(
  jsonb_build_object('id', 're_test_1', 'amount', 1000, 'status', 'succeeded',
                     'created', extract(epoch from now())::bigint,
                     'metadata', jsonb_build_object('reason', 'Lezione annullata',
                                                    'created_by', '15000000-0000-0000-0000-000000000002'))
)) AS payload;

SELECT is(public.stripe_apply_payment_state((SELECT payload FROM rimborso_parziale))->>'status',
  'partially_refunded', 'un rimborso parziale lascia il pagamento parzialmente rimborsato');
SELECT is(public.stripe_apply_payment_state((SELECT payload FROM rimborso_parziale))->>'status',
  'partially_refunded', 'raccontato due volte, non cambia nulla');

SELECT is(
  (SELECT count(*)::int || ' | ' || sum(amount_cents)::text || ' | ' || min(note) || ' | ' || min(created_by::text)
     FROM public.transactions
    WHERE refund_of_id = (SELECT id FROM public.transactions WHERE stripe_payment_id = '90000000-0000-0000-0000-000000000001')),
  '1 | -1000 | Lezione annullata | 15000000-0000-0000-0000-000000000002',
  'una riga negativa sola, con il motivo e chi l''ha deciso');

-- Poi un secondo rimborso che chiude il conto: la quota risulta rimborsata
SELECT is(
  public.stripe_apply_payment_state((SELECT payload FROM rimborso_parziale)
    || jsonb_build_object('refunds', (SELECT payload->'refunds' FROM rimborso_parziale) || jsonb_build_array(
         jsonb_build_object('id', 're_test_2', 'amount', 1500, 'status', 'pending', 'reason', 'requested_by_customer'))))
    ->>'status',
  'refunded', 'il secondo rimborso completa la restituzione');

SELECT is(
  (SELECT f.status::text || ' | ' || t.note FROM public.member_fees f
     JOIN public.transactions t ON t.refund_of_id = f.transaction_id AND t.amount_cents = -1500
    WHERE f.id = (SELECT target_id FROM public.stripe_payments WHERE id = '90000000-0000-0000-0000-000000000001')),
  'refunded | Rimborso da dashboard Stripe (requested_by_customer)',
  'quota rimborsata; il rimborso fatto dalla dashboard si registra col suo motivo');

-- Il secondo rimborso fallisce: la riga si annulla e la quota torna pagata
SELECT is(
  public.stripe_apply_payment_state((SELECT payload FROM rimborso_parziale)
    || jsonb_build_object('refunds', (SELECT payload->'refunds' FROM rimborso_parziale) || jsonb_build_array(
         jsonb_build_object('id', 're_test_2', 'amount', 1500, 'status', 'failed'))))
    ->>'status',
  'partially_refunded', 'un rimborso non riuscito non conta');

SELECT is(
  (SELECT f.status::text FROM public.member_fees f
    WHERE f.id = (SELECT target_id FROM public.stripe_payments WHERE id = '90000000-0000-0000-0000-000000000001')),
  'paid', 'e la quota torna pagata');

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Fuori ordine: rimborso raccontato insieme al pagamento, commissione arrivata dopo
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.stripe_payments (id, checkout_session_id, purpose, amount_cents, source, livemode, metadata)
VALUES ('90000000-0000-0000-0000-000000000005', 'cs_test_ordine', 'donation', 2000, 'site', false,
        jsonb_build_object('payer', jsonb_build_object('name', 'Luca Bianchi', 'email', 'luca@test.kalos')));

SELECT is(
  public.stripe_apply_payment_state(jsonb_build_object(
    'checkout_session_id', 'cs_test_ordine',
    'payment_intent', jsonb_build_object('id', 'pi_test_ordine', 'status', 'succeeded', 'amount_received', 2000,
      'currency', 'eur', 'livemode', false,
      'charge', jsonb_build_object('created', extract(epoch from now())::bigint)),
    'refunds', jsonb_build_array(jsonb_build_object('id', 're_test_3', 'amount', 2000, 'status', 'succeeded'))
  ))->>'status',
  'refunded', 'pagamento e rimborso nello stesso passaggio: prima l''incasso, poi il rimborso');

SELECT is(
  (public.stripe_apply_payment_state(jsonb_build_object(
    'checkout_session_id', 'cs_test_ordine',
    'payment_intent', jsonb_build_object('id', 'pi_test_ordine', 'status', 'succeeded', 'amount_received', 2000,
      'currency', 'eur', 'livemode', false,
      'charge', jsonb_build_object('created', extract(epoch from now())::bigint, 'fee_cents', 55, 'net_cents', 1945)),
    'refunds', jsonb_build_array(jsonb_build_object('id', 're_test_3', 'amount', 2000, 'status', 'succeeded'))
  ))->>'ok'),
  'true', 'la commissione arriva dopo il rimborso');

SELECT is((SELECT count(*)::int FROM public.expenses WHERE notes LIKE '%pi_test_ordine%'), 1,
  'e diventa comunque un''uscita, perché Stripe non la restituisce');

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Sessioni scadute, memoria del webhook, invio delle ricevute, limite per IP
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.stripe_payments (id, checkout_session_id, purpose, amount_cents, source, livemode, receipt_email, metadata)
VALUES ('90000000-0000-0000-0000-000000000006', 'cs_test_scaduta', 'donation', 1000, 'site', false, 'x@test.kalos',
        jsonb_build_object('payer', jsonb_build_object('name', 'Chi Ci Ripensa', 'email', 'x@test.kalos')));
SELECT ok((public.stripe_checkout_expired('cs_test_scaduta')->>'changed')::boolean,
  'la sessione scaduta si annulla');

SELECT is(
  (SELECT status::text || ' | ' || (metadata ? 'payer')::text || ' | ' || COALESCE(receipt_email, '-')
     FROM public.stripe_payments WHERE id = '90000000-0000-0000-0000-000000000006'),
  'canceled | false | -', 'una donazione non pagata si annulla e i dati di chi voleva donare si cancellano');

SELECT is(public.stripe_event_received('evt_test_a', 'checkout.session.completed', false, 'cs_x')->>'already_processed',
  'false', 'il webhook registra un evento nuovo');
SELECT lives_ok($$ SELECT public.stripe_event_done('evt_test_a') $$, 'e lo segna come elaborato');
SELECT is(public.stripe_event_received('evt_test_a', 'checkout.session.completed', false, 'cs_x')->>'already_processed',
  'true', 'alla seconda consegna lo riconosce');

SELECT is(
  (SELECT public.receipt_claim_send(r.id)->>'ok' FROM public.receipts r
     JOIN public.transactions t ON t.id = r.transaction_id
    WHERE t.stripe_payment_id = '90000000-0000-0000-0000-000000000003'),
  'true', 'l''invio della ricevuta si prenota');

SELECT is(
  (SELECT public.receipt_claim_send(r.id)->>'reason' FROM public.receipts r
     JOIN public.transactions t ON t.id = r.transaction_id
    WHERE t.stripe_payment_id = '90000000-0000-0000-0000-000000000003'),
  'SEND_IN_PROGRESS', 'una seconda consegna nello stesso momento non manda una seconda email');

SELECT ok(public.stripe_register_checkout_attempt('ip-test', 'donation', 2, 60), 'primo checkout dallo stesso IP');
SELECT ok(public.stripe_register_checkout_attempt('ip-test', 'donation', 2, 60), 'secondo checkout dallo stesso IP');
SELECT ok(NOT public.stripe_register_checkout_attempt('ip-test', 'donation', 2, 60),
  'oltre il limite orario per IP il checkout delle donazioni si ferma');

SELECT ok(
  NOT has_function_privilege('authenticated', 'public.stripe_apply_payment_state(jsonb)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.stripe_apply_payment_state(jsonb)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.receipt_claim_send(uuid, boolean)', 'EXECUTE'),
  'le funzioni del webhook non sono raggiungibili da app e sito');

SELECT * FROM finish();
ROLLBACK;
