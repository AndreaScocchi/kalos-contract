// Rimborso sulla carta di un incasso online, deciso dallo staff (D4: mai automatico).
//
// POST { transaction_id, amount_cents, reason, request_id } con il token di chi è loggato.
//   1. `staff_prepare_stripe_refund` col token: solo Finanze (admin e Tesoriere), importo entro il
//      rimborsabile, incasso davvero online;
//   2. rimborso su Stripe, con motivo e autore nei metadata e una chiave di idempotenza: un doppio clic
//      non restituisce il denaro due volte;
//   3. `reconcilePaymentIntent`: lo stesso percorso del webhook scrive la riga negativa. Quando poi
//      arriva l'evento del rimborso, trova tutto già fatto.
//
// Risponde { ok: true, status, refund_status } oppure { ok: false, reason }.

import { corsHeaders } from '../_shared/cors.ts'
import { adminClient, jsonResponse, UUID_RE, userClient } from '../_shared/http.ts'
import { getStripe, reconcilePaymentIntent } from '../_shared/stripe.ts'

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return jsonResponse({ ok: false, reason: 'METHOD_NOT_ALLOWED' }, 405)

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return jsonResponse({ ok: false, reason: 'INVALID_BODY' }, 400)
  }

  const transactionId = typeof body.transaction_id === 'string' ? body.transaction_id : ''
  const amount = Number(body.amount_cents)
  const reason = typeof body.reason === 'string' ? body.reason.trim() : ''
  const requestId = typeof body.request_id === 'string' ? body.request_id : ''
  if (!UUID_RE.test(transactionId)) return jsonResponse({ ok: false, reason: 'TRANSACTION_NOT_FOUND' }, 400)
  if (!reason) return jsonResponse({ ok: false, reason: 'REASON_REQUIRED' })
  if (!UUID_RE.test(requestId)) return jsonResponse({ ok: false, reason: 'MISSING_REQUEST_ID' }, 400)

  const user = userClient(authHeader)
  const { data: userData } = await user.auth.getUser()
  if (!userData?.user) return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)

  const { data: prepared, error } = await user.rpc('staff_prepare_stripe_refund', {
    p_transaction_id: transactionId,
    p_amount_cents: Number.isInteger(amount) ? amount : null,
  })
  if (error) {
    console.error('[stripe-refund] staff_prepare_stripe_refund:', error.message)
    return jsonResponse({ ok: false, reason: 'PREPARE_FAILED' }, 500)
  }
  if (!prepared?.ok) return jsonResponse({ ok: false, reason: prepared?.reason, refundable_cents: prepared?.refundable_cents })

  const configured = getStripe()
  if (!configured) return jsonResponse({ ok: false, reason: 'STRIPE_NOT_CONFIGURED' }, 503)
  const { stripe, mode } = configured
  // Un pagamento di prova non si rimborsa con la chiave live, né il contrario
  if (prepared.livemode !== (mode === 'live')) return jsonResponse({ ok: false, reason: 'STRIPE_MODE_MISMATCH' }, 409)

  let refundStatus: string | null = null
  try {
    const refund = await stripe.refunds.create(
      {
        payment_intent: prepared.payment_intent_id,
        amount,
        reason: 'requested_by_customer',
        metadata: {
          kalos_transaction_id: transactionId,
          reason: reason.slice(0, 480),
          created_by: userData.user.id,
        },
      },
      { idempotencyKey: `refund-${transactionId}-${requestId}` },
    )
    refundStatus = refund.status
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error('[stripe-refund] Stripe ha rifiutato il rimborso:', message)
    return jsonResponse({ ok: false, reason: 'STRIPE_REFUND_FAILED', message: message.slice(0, 300) }, 502)
  }

  // Il rimborso è partito: lo si registra subito. Se questo passo fallisse, lo farebbe il webhook.
  try {
    const result = await reconcilePaymentIntent(stripe, adminClient(), prepared.payment_intent_id, {
      stripePaymentId: prepared.stripe_payment_id,
    })
    return jsonResponse({ ok: true, status: result.status, refund_status: refundStatus })
  } catch (err) {
    console.error('[stripe-refund] registrazione del rimborso rimandata al webhook:', err)
    return jsonResponse({ ok: true, status: null, refund_status: refundStatus, recorded: false })
  }
})
