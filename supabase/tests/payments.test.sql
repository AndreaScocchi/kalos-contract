-- Pagamenti: idempotenza del webhook, commissione che diventa un'uscita, rimborsi che non superano
-- l'incasso e registro che torna. Sono i punti che il piano elenca come rischio (§5): un pagamento
-- online deve creare gli stessi record di uno registrato in studio, senza doppi conteggi.

BEGIN;
SELECT plan(9);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('14000000-0000-0000-0000-000000000001', 'tesoreria@test.kalos', '{"full_name":"Tesoreria"}', 'authenticated', 'authenticated'),
  ('14000000-0000-0000-0000-000000000002', 'pagante@test.kalos', '{"full_name":"Chi Paga"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'finance' WHERE id = '14000000-0000-0000-0000-000000000001';

-- ── Idempotenza del webhook ──────────────────────────────────────────────────
INSERT INTO public.stripe_events (id, type, payload)
VALUES ('evt_test_1', 'payment_intent.succeeded', '{}'::jsonb);

SELECT throws_ok(
  $$ INSERT INTO public.stripe_events (id, type, payload)
     VALUES ('evt_test_1', 'payment_intent.succeeded', '{}'::jsonb) $$,
  '23505', NULL,
  'lo stesso evento consegnato due volte non si registra due volte'
);

-- ── Commissione → uscita ─────────────────────────────────────────────────────
INSERT INTO public.stripe_payments (
  id, payment_intent_id, client_id, purpose, amount_cents, fee_cents, net_cents,
  status, succeeded_at
)
SELECT '80000000-0000-0000-0000-000000000001', 'pi_test_1', c.id, 'subscription',
       10000, 174, 9826, 'succeeded', now()
  FROM public.clients c WHERE c.email = 'pagante@test.kalos';

SELECT is(
  (SELECT count(*)::int FROM public.expenses
    WHERE source = 'stripe_fee' AND amount_cents = 174),
  1, 'la commissione di Stripe diventa un''uscita da sola'
);

SELECT is(
  (SELECT ec.slug FROM public.expenses e
     JOIN public.expense_categories ec ON ec.id = e.category_id
    WHERE e.source = 'stripe_fee'),
  'commissioni', 'e finisce nella categoria commissioni'
);

SELECT isnt(
  (SELECT fee_expense_id FROM public.stripe_payments WHERE id = '80000000-0000-0000-0000-000000000001'),
  NULL, 'il pagamento tiene il riferimento all''uscita generata'
);

-- Un aggiornamento successivo non deve creare una seconda uscita per la stessa commissione
UPDATE public.stripe_payments SET status = 'succeeded'
 WHERE id = '80000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*)::int FROM public.expenses WHERE source = 'stripe_fee'),
  1, 'un secondo aggiornamento non duplica l''uscita della commissione'
);

-- ── Registro e rimborsi ──────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"14000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT ok(
  (public.staff_register_payment(jsonb_build_object(
     'client_id', (SELECT id FROM public.clients WHERE email = 'pagante@test.kalos'),
     'kind', 'subscription', 'amount_cents', 10000, 'method', 'stripe',
     'source', 'app')))->>'ok' = 'true',
  'un incasso online si registra nello stesso registro di quelli in studio'
);

SELECT is(
  (public.staff_refund_transaction(
     (SELECT id FROM public.transactions WHERE amount_cents = 10000), 15000, 'Troppo'))->>'reason',
  'INVALID_AMOUNT', 'non si rimborsa più di quanto incassato'
);

SELECT is(
  (public.staff_refund_transaction(
     (SELECT id FROM public.transactions WHERE amount_cents = 10000), 4000, 'Parziale'))->>'status',
  'partially_refunded', 'un rimborso parziale lascia la transazione parzialmente rimborsata'
);

SELECT is(
  (SELECT sum(amount_cents)::int FROM public.transactions WHERE status <> 'pending'),
  6000, 'il registro torna: sommando le righe si ottiene il saldo, rimborso compreso'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
