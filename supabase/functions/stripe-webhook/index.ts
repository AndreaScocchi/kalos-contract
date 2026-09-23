// Webhook di Stripe.
//
// Stripe chiama questo indirizzo a ogni evento. Non c'è un JWT (`verify_jwt = false` in config.toml):
// la sicurezza è la FIRMA, verificata sul corpo grezzo con STRIPE_WEBHOOK_SECRET. Una richiesta senza
// firma valida riceve 400 e non tocca nulla.
//
// Gli eventi sono un campanello, non dati: ognuno che riguarda un pagamento fa rileggere da Stripe lo
// stato completo (`reconcilePaymentIntent`) e lo riporta nel database con `stripe_apply_payment_state`.
// Quindi l'ordine in cui arrivano, i doppioni e le consegne in parallelo non cambiano il risultato.
//
// Risposte:
//   200  elaborato, già elaborato, di un'altra modalità (test/live) o di un tipo che non ci interessa
//   400  firma mancante o non valida
//   500  errore durante l'elaborazione: Stripe riprova (fino a 3 giorni in live), l'errore resta in
//        `stripe_events.error_message` e ops-health manda l'avviso se l'evento resta indietro
//   503  Stripe non configurato
// Le email delle ricevute partono DOPO la risposta: un'email non riuscita non fa mai rispondere 500.

import { adminClient, jsonResponse, runAfterResponse } from '../_shared/http.ts'
import { sendReceiptEmail } from '../_shared/receiptEmail.ts'
import { getStripe, reconcilePaymentIntent, verifyStripeEvent, type ApplyResult, type Stripe } from '../_shared/stripe.ts'

type Handled = { receiptIds: string[]; note: string }

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') return jsonResponse({ ok: false, reason: 'METHOD_NOT_ALLOWED' }, 405)

  const signature = req.headers.get('stripe-signature')
  if (!signature) return jsonResponse({ ok: false, reason: 'MISSING_SIGNATURE' }, 400)

  const configured = getStripe()
  if (!configured) return jsonResponse({ ok: false, reason: 'STRIPE_NOT_CONFIGURED' }, 503)
  const { stripe, mode } = configured

  const rawBody = await req.text()
  let event: Stripe.Event
  try {
    event = await verifyStripeEvent(stripe, rawBody, signature)
  } catch (err) {
    console.error('[stripe-webhook] firma non valida:', err instanceof Error ? err.message : err)
    return jsonResponse({ ok: false, reason: 'INVALID_SIGNATURE' }, 400)
  }

  // Un evento di prova con la chiave live (o viceversa) non si può rileggere con questa chiave: si
  // ignora con un 200, altrimenti Stripe continuerebbe a riprovare per giorni.
  if (event.livemode !== (mode === 'live')) {
    return jsonResponse({ ok: true, ignored: 'MODE_MISMATCH' })
  }

  const admin = adminClient()
  const object = event.data.object as { id?: string }
  const { data: received, error: receivedError } = await admin.rpc('stripe_event_received', {
    p_event_id: event.id,
    p_type: event.type,
    p_livemode: event.livemode,
    p_object_id: object?.id ?? null,
  })
  if (receivedError) {
    console.error('[stripe-webhook] stripe_event_received:', receivedError.message)
    return jsonResponse({ ok: false, reason: 'DB_UNAVAILABLE' }, 500)
  }
  if (received?.already_processed) return jsonResponse({ ok: true, duplicate: true })

  let handled: Handled
  try {
    handled = await handleEvent(event, stripe)
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error(`[stripe-webhook] ${event.type} ${event.id}:`, message)
    await admin.rpc('stripe_event_done', { p_event_id: event.id, p_error: message.slice(0, 1000) })
    return jsonResponse({ ok: false, reason: 'PROCESSING_FAILED' }, 500)
  }

  await admin.rpc('stripe_event_done', { p_event_id: event.id, p_error: null })

  if (handled.receiptIds.length > 0) {
    runAfterResponse(sendReceipts(handled.receiptIds))
  }

  return jsonResponse({ ok: true, handled: handled.note })
})

async function handleEvent(event: Stripe.Event, stripe: Stripe): Promise<Handled> {
  const admin = adminClient()
  const receipts = (result: ApplyResult): string[] => {
    if (!result.ok) throw new Error(`stato non applicato: ${result.reason}`)
    return result.receipt_ids ?? []
  }

  switch (event.type) {
    // Checkout: la persona ha finito sulla pagina di Stripe
    case 'checkout.session.completed':
    case 'checkout.session.async_payment_succeeded':
    case 'checkout.session.async_payment_failed': {
      const session = event.data.object as Stripe.Checkout.Session
      if (session.mode !== 'payment' || typeof session.payment_intent !== 'string') {
        return { receiptIds: [], note: 'senza pagamento' }
      }
      const result = await reconcilePaymentIntent(stripe, admin, session.payment_intent, {
        stripePaymentId: session.client_reference_id ?? session.metadata?.kalos_payment_id ?? null,
        checkoutSessionId: session.id,
      })
      return { receiptIds: receipts(result), note: `pagamento ${result.status}` }
    }

    case 'checkout.session.expired': {
      const session = event.data.object as Stripe.Checkout.Session
      const { error } = await admin.rpc('stripe_checkout_expired', { p_checkout_session_id: session.id })
      if (error) throw new Error(`stripe_checkout_expired: ${error.message}`)
      return { receiptIds: [], note: 'sessione scaduta' }
    }

    // Pagamenti che non passano dal Checkout (l'app, dalla sessione 9) e stati successivi
    case 'payment_intent.succeeded':
    case 'payment_intent.processing':
    case 'payment_intent.payment_failed':
    case 'payment_intent.canceled': {
      const pi = event.data.object as Stripe.PaymentIntent
      const result = await reconcilePaymentIntent(stripe, admin, pi.id)
      return { receiptIds: receipts(result), note: `pagamento ${result.status}` }
    }

    // Commissione arrivata dopo, rimborsi (anche quelli fatti dalla dashboard di Stripe)
    case 'charge.succeeded':
    case 'charge.updated':
    case 'charge.refunded': {
      const charge = event.data.object as Stripe.Charge
      if (typeof charge.payment_intent !== 'string') return { receiptIds: [], note: 'addebito senza PaymentIntent' }
      const result = await reconcilePaymentIntent(stripe, admin, charge.payment_intent)
      return { receiptIds: receipts(result), note: `pagamento ${result.status}` }
    }

    case 'refund.created':
    case 'refund.updated':
    case 'refund.failed': {
      const refund = event.data.object as Stripe.Refund
      if (typeof refund.payment_intent !== 'string') return { receiptIds: [], note: 'rimborso senza PaymentIntent' }
      const result = await reconcilePaymentIntent(stripe, admin, refund.payment_intent)
      return { receiptIds: receipts(result), note: `pagamento ${result.status}` }
    }

    // Contestazioni: nessuna scrittura automatica nel registro. L'evento resta in `stripe_events`
    // e ops-health manda l'avviso: se ne occupa chi segue le Finanze, dalla dashboard di Stripe.
    case 'charge.dispute.created':
    case 'charge.dispute.updated':
    case 'charge.dispute.closed':
      return { receiptIds: [], note: 'contestazione registrata' }

    default:
      return { receiptIds: [], note: 'tipo non gestito' }
  }
}

async function sendReceipts(receiptIds: string[]): Promise<void> {
  const admin = adminClient()
  for (const id of receiptIds) {
    const result = await sendReceiptEmail(admin, id)
    if (!result.ok && result.reason !== 'ALREADY_SENT' && result.reason !== 'SEND_IN_PROGRESS') {
      console.error('[stripe-webhook] ricevuta non inviata', id, result.reason, result.message ?? '')
    }
  }
}
