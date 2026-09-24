#!/usr/bin/env node
/**
 * Finto server Stripe, SOLO per le prove in locale (sessione 5).
 *
 * Risponde alle poche chiamate che fanno le edge function (Checkout, PaymentIntent, rimborsi) con
 * oggetti nella forma di Stripe, tenendo tutto in memoria. Le function lo usano quando
 * STRIPE_API_BASE punta qui, cosa che `_shared/stripe.ts` accetta solo con il Supabase locale e una
 * chiave di prova. Così si prova il giro completo (checkout → pagamento → webhook → registro →
 * rimborso) senza un account Stripe.
 *
 * Oltre all'API finta, `/_control/*` permette al driver (`run-scenarios.mjs`) di fare quello che nella
 * realtà fa la persona o la dashboard: pagare una sessione, far arrivare la commissione più tardi,
 * rimborsare "dalla dashboard", far fallire un rimborso.
 *
 *     node scripts/stripe-local/fake-stripe.mjs            # porta 12111
 */

import http from 'node:http'
import { randomBytes } from 'node:crypto'

const PORT = Number(process.env.FAKE_STRIPE_PORT ?? 12111)

const state = {
  sessions: new Map(),
  paymentIntents: new Map(),
  charges: new Map(),
  refunds: new Map(),
  idempotency: new Map(),
}

const id = (prefix) => `${prefix}_test_${randomBytes(9).toString('hex')}`
const now = () => Math.floor(Date.now() / 1000)

/** Corpo form-urlencoded "alla Stripe" (a[b][0][c]=v) → oggetto. */
function parseForm(body) {
  const out = {}
  for (const [rawKey, value] of new URLSearchParams(body)) {
    const path = rawKey.replace(/\]/g, '').split('[')
    let node = out
    path.forEach((key, i) => {
      const last = i === path.length - 1
      const nextIsIndex = !last && /^\d+$/.test(path[i + 1])
      if (last) node[key] = value
      else node = node[key] ??= nextIsIndex ? [] : {}
    })
  }
  return out
}

function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' })
  res.end(JSON.stringify(body))
}

function stripeError(res, status, message, type = 'invalid_request_error') {
  send(res, status, { error: { type, message } })
}

function chargeView(chargeId) {
  const charge = state.charges.get(chargeId)
  if (!charge) return null
  return {
    ...charge,
    balance_transaction: charge.fee_cents == null
      ? null
      : { id: `txn_${chargeId}`, object: 'balance_transaction', fee: charge.fee_cents, net: charge.amount - charge.fee_cents, currency: 'eur' },
  }
}

function paymentIntentView(pi) {
  return { ...pi, latest_charge: pi.latest_charge ? chargeView(pi.latest_charge) : null }
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = ''
    req.on('data', (chunk) => { data += chunk })
    req.on('end', () => resolve(data))
  })
}

// ── Azioni del driver ────────────────────────────────────────────────────────────────────────

function pay(sessionId, { feeCents = 60, feeLater = false, wallet = null, force = false } = {}) {
  const session = state.sessions.get(sessionId)
  if (!session) throw new Error(`sessione ${sessionId} inesistente`)
  if (session.status !== 'open' && !force) throw new Error(`sessione ${sessionId} è ${session.status}`)
  const piId = id('pi')
  const chargeId = id('ch')
  state.charges.set(chargeId, {
    id: chargeId, object: 'charge', amount: session.amount_total, created: now(), payment_intent: piId,
    livemode: false, fee_cents: feeLater ? null : feeCents, pending_fee_cents: feeCents,
    billing_details: { email: session.customer_email },
    payment_method_details: { type: 'card', card: { wallet: wallet ? { type: wallet } : null } },
  })
  state.paymentIntents.set(piId, {
    id: piId, object: 'payment_intent', status: 'succeeded', amount: session.amount_total,
    amount_received: session.amount_total, currency: 'eur', livemode: false,
    metadata: session.payment_intent_data_metadata ?? {}, latest_charge: chargeId,
    payment_method_types: ['card'], receipt_email: null, last_payment_error: null,
  })
  Object.assign(session, { status: 'complete', payment_status: 'paid', payment_intent: piId })
  return { session, paymentIntentId: piId, chargeId }
}

function createRefund({ payment_intent: piId, amount, metadata = {}, reason = null, status = 'succeeded' }) {
  const pi = state.paymentIntents.get(piId)
  if (!pi) throw new Error(`PaymentIntent ${piId} inesistente`)
  const refunded = [...state.refunds.values()]
    .filter((r) => r.payment_intent === piId && !['failed', 'canceled'].includes(r.status))
    .reduce((sum, r) => sum + r.amount, 0)
  const value = Number(amount ?? pi.amount_received - refunded)
  if (value <= 0 || refunded + value > pi.amount_received) {
    const err = new Error(`Refund amount (€${value / 100}) is greater than unrefunded amount on charge`)
    err.status = 400
    throw err
  }
  const refund = { id: id('re'), object: 'refund', amount: value, payment_intent: piId, charge: pi.latest_charge,
    status, reason, metadata, created: now(), currency: 'eur' }
  state.refunds.set(refund.id, refund)
  return refund
}

// ── Server ───────────────────────────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`)
  const raw = await readBody(req)
  const body = req.headers['content-type']?.includes('json') ? JSON.parse(raw || '{}') : parseForm(raw)
  const parts = url.pathname.split('/').filter(Boolean)

  try {
    // Idempotenza come Stripe: stessa chiave, stessa risposta
    const key = req.headers['idempotency-key']
    if (req.method === 'POST' && key && state.idempotency.has(key)) {
      return send(res, 200, state.idempotency.get(key))
    }
    const remember = (payload) => { if (key) state.idempotency.set(key, payload); return payload }

    // POST /v1/checkout/sessions
    if (req.method === 'POST' && url.pathname === '/v1/checkout/sessions') {
      const sessionId = id('cs')
      const amount = Number(body.line_items?.[0]?.price_data?.unit_amount ?? 0)
      const session = {
        id: sessionId, object: 'checkout.session', mode: body.mode, status: 'open', payment_status: 'unpaid',
        url: `http://localhost:${PORT}/pay/${sessionId}`, amount_total: amount, currency: 'eur',
        client_reference_id: body.client_reference_id ?? null, customer_email: body.customer_email ?? null,
        metadata: body.metadata ?? {}, payment_intent: null, livemode: false,
        success_url: body.success_url, cancel_url: body.cancel_url, expires_at: Number(body.expires_at),
        submit_type: body.submit_type ?? null, payment_method_types: body.payment_method_types ?? [],
        payment_intent_data_metadata: body.payment_intent_data?.metadata ?? {},
      }
      state.sessions.set(sessionId, session)
      return send(res, 200, remember(session))
    }

    // GET /v1/checkout/sessions/:id  —  POST /v1/checkout/sessions/:id/expire
    if (parts[0] === 'v1' && parts[1] === 'checkout' && parts[2] === 'sessions' && parts[3]) {
      const session = state.sessions.get(parts[3])
      if (!session) return stripeError(res, 404, `No such checkout.session: '${parts[3]}'`)
      if (req.method === 'POST' && parts[4] === 'expire') {
        if (session.status !== 'open') return stripeError(res, 400, 'Only Checkout Sessions with a status of `open` can be expired.')
        session.status = 'expired'
        return send(res, 200, remember(session))
      }
      return send(res, 200, session)
    }

    // GET /v1/payment_intents/:id
    if (req.method === 'GET' && parts[0] === 'v1' && parts[1] === 'payment_intents' && parts[2]) {
      const pi = state.paymentIntents.get(parts[2])
      if (!pi) return stripeError(res, 404, `No such payment_intent: '${parts[2]}'`)
      return send(res, 200, paymentIntentView(pi))
    }

    // GET /v1/refunds?payment_intent=…  —  POST /v1/refunds
    if (url.pathname === '/v1/refunds') {
      if (req.method === 'POST') {
        try {
          return send(res, 200, remember(createRefund(body)))
        } catch (err) {
          return stripeError(res, err.status ?? 400, err.message)
        }
      }
      const piId = url.searchParams.get('payment_intent')
      const data = [...state.refunds.values()].filter((r) => r.payment_intent === piId).reverse()
      return send(res, 200, { object: 'list', data, has_more: false, url: '/v1/refunds' })
    }

    // ── Controllo, per il driver ──
    if (url.pathname === '/_control/pay') return send(res, 200, pay(body.session_id, body))
    if (url.pathname === '/_control/fee') {
      const charge = state.charges.get(body.charge_id)
      charge.fee_cents = body.fee_cents ?? charge.pending_fee_cents
      return send(res, 200, chargeView(charge.id))
    }
    if (url.pathname === '/_control/refund') return send(res, 200, createRefund(body))
    if (url.pathname === '/_control/refund-status') {
      const refund = state.refunds.get(body.refund_id)
      refund.status = body.status
      return send(res, 200, refund)
    }
    if (url.pathname === '/_control/object') {
      const kind = body.kind
      const map = { session: state.sessions, payment_intent: state.paymentIntents, charge: state.charges, refund: state.refunds }[kind]
      const object = map?.get(body.id)
      if (!object) return send(res, 404, { error: 'not found' })
      return send(res, 200, kind === 'payment_intent' ? paymentIntentView(object) : kind === 'charge' ? chargeView(object.id) : object)
    }

    return stripeError(res, 404, `Finto Stripe: ${req.method} ${url.pathname} non implementato`)
  } catch (err) {
    return stripeError(res, 500, err.message, 'api_error')
  }
})

server.listen(PORT, () => console.log(`Finto Stripe in ascolto su http://localhost:${PORT}`))
