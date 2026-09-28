// Apre un pagamento con Stripe Checkout (pagina di pagamento ospitata da Stripe) e restituisce
// l'indirizzo a cui mandare la persona.
//
// POST, questi casi:
//   { purpose: 'membership_fee', year? }                    quota associativa, con il token di chi è loggato
//   { purpose: 'donation', amount_cents, name, email, fiscal_code? }   donazione dal sito, anche senza login
//   { purpose: 'subscription', plan_id }                    abbonamento dall'app (sessione 9)
//   { purpose: 'event', event_booking_id }                  contributo di un evento a cui si è iscrittə (sessione 9)
//   { purpose: 'settlement', transaction_id }               un "da saldare" registrato in studio (sessione 9)
//
// Dall'app si aggiunge `client: 'app'` (e `platform: 'ios' | 'android' | 'web'`): la fonte diventa
// "app" e si torna alla pagina `/payment/return` dell'app invece che al sito. Senza `client` tutto è
// come nella sessione 5 (il sito non cambia).
//
// Gli importi li decide il database (`prepare_my_*`), mai il browser. Solo carta, Apple Pay e Google
// Pay (D2): `payment_method_types: ['card']` li comprende tutti e tre e nient'altro. Nessun rinnovo
// automatico: sempre `mode: 'payment'`.
//
// La riga in `stripe_payments` nasce qui, prima della sessione, così l'id va nei metadata e il webhook
// ritrova il pagamento senza ambiguità.
//
// Risponde { ok: true, url, payment_id } oppure { ok: false, reason }.

import { corsHeaders } from '../_shared/cors.ts'
import { adminClient, clientIp, EMAIL_RE, jsonResponse, sha256Hex, userClient } from '../_shared/http.ts'
import {
  checkStripeMode, getStripe, paymentsEnabled, reconcilePaymentIntent, type Stripe,
} from '../_shared/stripe.ts'

const DONATION_MIN_CENTS = 500
const DONATION_MAX_CENTS = 100_000
const DONATIONS_PER_IP_PER_HOUR = 10
const APP_CHECKOUTS_PER_PERSON_PER_HOUR = 20
const SESSION_LIFETIME_SECONDS = 60 * 60

// Dove si può tornare dopo il pagamento. In produzione il sito; in locale il server di sviluppo.
function allowedOrigins(): string[] {
  const configured = (Deno.env.get('CHECKOUT_ALLOWED_ORIGINS') ?? '').split(',').map((o) => o.trim()).filter(Boolean)
  return configured.length > 0 ? configured : ['https://kalosstudio.it', 'https://www.kalosstudio.it']
}

function returnOrigin(req: Request): string {
  const origins = allowedOrigins()
  const origin = req.headers.get('origin')
  return origin && origins.includes(origin) ? origin : origins[0]
}

// Gli indirizzi dell'app, in un secret a parte: il sito continua a usare solo i suoi.
function appOrigins(): string[] {
  const configured = (Deno.env.get('APP_RETURN_ORIGINS') ?? '').split(',').map((o) => o.trim()).filter(Boolean)
  return configured.length > 0 ? configured : ['https://app.kalosstudio.it']
}

type ReturnTarget = { app: boolean; success: (paymentId: string) => string; cancel: (paymentId: string) => string }

/**
 * Dove torna la persona. Dall'app sul web: la stessa origine, se è fra quelle dell'app. Da iPhone e
 * Android (nessuna origine): la pagina web dell'app con `native=1`, che rimanda a `kalos://` (Stripe non
 * accetta indirizzi che non siano http/https) e chiude il browser dell'app.
 */
function appReturn(req: Request, body: Record<string, unknown>): ReturnTarget {
  const origins = appOrigins()
  const origin = req.headers.get('origin')
  const native = body.platform === 'ios' || body.platform === 'android'
  const base = !native && origin && origins.includes(origin) ? origin : origins[0]
  const suffix = native ? '&native=1' : ''
  return {
    app: true,
    success: (id) => `${base}/payment/return?payment=${id}${suffix}`,
    cancel: (id) => `${base}/payment/return?payment=${id}&esito=annullato${suffix}`,
  }
}

const isApp = (body: Record<string, unknown>) => body.client === 'app'
const isUuid = (value: unknown): value is string =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return jsonResponse({ ok: false, reason: 'METHOD_NOT_ALLOWED' }, 405)

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return jsonResponse({ ok: false, reason: 'INVALID_BODY' }, 400)
  }

  const admin = adminClient()
  const configured = getStripe()
  if (!configured) return jsonResponse({ ok: false, reason: 'STRIPE_NOT_CONFIGURED' }, 503)
  const { stripe, mode } = configured

  const modeProblem = await checkStripeMode(admin, mode)
  if (modeProblem) {
    console.error('[stripe-checkout] chiave Stripe e interruttore stripe_live non coerenti:', mode)
    return jsonResponse({ ok: false, reason: modeProblem }, 503)
  }

  try {
    if (body.purpose === 'membership_fee') return await membershipCheckout(req, body, stripe, mode)
    if (body.purpose === 'donation') return await donationCheckout(req, body, stripe, mode)
    if (body.purpose === 'subscription' || body.purpose === 'event' || body.purpose === 'settlement') {
      return await appPurchaseCheckout(req, body, stripe, mode)
    }
    return jsonResponse({ ok: false, reason: 'INVALID_PURPOSE' }, 400)
  } catch (err) {
    console.error('[stripe-checkout]', err)
    return jsonResponse({ ok: false, reason: 'CHECKOUT_FAILED' }, 502)
  }
})

// ─────────────────────────────────────────────────────────────────────────────
// Checkout ancora aperti per la stessa cosa
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Un'altra scheda (o un doppio tocco) ha già un checkout aperto per la stessa cosa: lo si chiude. Se
 * nel frattempo risulta pagato, lo si registra e si dice che è già pagato.
 */
async function closeOpenCheckouts(
  stripe: Stripe,
  filter: { targetId: string; clientId?: string; kind?: string },
): Promise<'paid' | 'in_progress' | null> {
  const admin = adminClient()
  let query = admin
    .from('stripe_payments')
    .select('id, checkout_session_id, metadata')
    .eq('target_id', filter.targetId)
    .eq('status', 'created')
    .not('checkout_session_id', 'is', null)
  if (filter.clientId) query = query.eq('client_id', filter.clientId)
  const { data: open } = await query

  for (const row of open ?? []) {
    if (filter.kind && (row.metadata as Record<string, unknown> | null)?.kind !== filter.kind) continue
    const session = await stripe.checkout.sessions.retrieve(row.checkout_session_id)
    if (session.status === 'complete' && typeof session.payment_intent === 'string') {
      await reconcilePaymentIntent(stripe, admin, session.payment_intent, {
        stripePaymentId: row.id, checkoutSessionId: session.id,
      })
      return 'paid'
    }
    if (session.status === 'open') {
      try {
        await stripe.checkout.sessions.expire(session.id)
      } catch (err) {
        // Pagata proprio adesso: la prossima richiesta la troverà completa
        console.error('[stripe-checkout] sessione non scaduta:', err)
        return 'in_progress'
      }
    }
    await admin.rpc('stripe_checkout_expired', { p_checkout_session_id: session.id })
  }
  return null
}

// ─────────────────────────────────────────────────────────────────────────────
// Quota associativa
// ─────────────────────────────────────────────────────────────────────────────

async function membershipCheckout(
  req: Request,
  body: Record<string, unknown>,
  stripe: Stripe,
  mode: 'test' | 'live',
): Promise<Response> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)

  const user = userClient(authHeader)
  const year = Number.isInteger(body.year) ? body.year as number : undefined
  const { data: prepared, error } = await user.rpc('prepare_my_fee_payment', year ? { p_year: year } : {})
  if (error) {
    console.error('[stripe-checkout] prepare_my_fee_payment:', error.message)
    return jsonResponse({ ok: false, reason: 'PREPARE_FAILED' }, 500)
  }
  if (!prepared?.ok) return jsonResponse({ ok: false, reason: prepared?.reason ?? 'PREPARE_FAILED' })

  const admin = adminClient()

  const open = await closeOpenCheckouts(stripe, { targetId: prepared.member_fee_id })
  if (open === 'paid') return jsonResponse({ ok: false, reason: 'FEE_ALREADY_PAID' })
  if (open === 'in_progress') return jsonResponse({ ok: false, reason: 'CHECKOUT_IN_PROGRESS' }, 409)

  const fromApp = isApp(body)
  const { data: row, error: insertError } = await admin
    .from('stripe_payments')
    .insert({
      purpose: 'membership_fee',
      target_id: prepared.member_fee_id,
      client_id: prepared.client_id,
      amount_cents: prepared.amount_cents,
      currency: 'EUR',
      status: 'created',
      livemode: mode === 'live',
      source: fromApp ? 'app' : 'site',
      receipt_email: prepared.email ?? null,
      metadata: fromApp ? { year: prepared.year, title: `Quota associativa ${prepared.year}` } : { year: prepared.year },
    })
    .select('id')
    .single()
  if (insertError || !row) throw new Error(insertError?.message ?? 'riga del pagamento non creata')

  const title = `Quota associativa ${prepared.year}`
  const back = fromApp ? appReturn(req, body) : null
  const origin = returnOrigin(req)
  const session = await createSession(stripe, row.id, {
    mode: 'payment',
    client_reference_id: row.id,
    customer_email: prepared.email ?? undefined,
    line_items: [{
      quantity: 1,
      price_data: {
        currency: 'eur',
        unit_amount: prepared.amount_cents,
        product_data: {
          name: title,
          description: `Studio Kalòs APS — quota per l'anno ${prepared.year}, dal 1° gennaio al 31 dicembre`,
        },
      },
    }],
    payment_method_types: ['card'],
    submit_type: 'pay',
    locale: 'it',
    expires_at: Math.floor(Date.now() / 1000) + SESSION_LIFETIME_SECONDS,
    success_url: back ? back.success(row.id) : `${origin}/diventa-socio/grazie/?sessione={CHECKOUT_SESSION_ID}`,
    cancel_url: back ? back.cancel(row.id) : `${origin}/diventa-socio/?pagamento=annullato`,
    metadata: { kalos_payment_id: row.id, purpose: 'membership_fee', year: String(prepared.year) },
    payment_intent_data: {
      description: `${title} — Studio Kalòs APS`,
      metadata: { kalos_payment_id: row.id, purpose: 'membership_fee', year: String(prepared.year) },
    },
  })

  return jsonResponse({ ok: true, url: session.url, payment_id: row.id })
}

// ─────────────────────────────────────────────────────────────────────────────
// Dall'app: abbonamento, contributo di un evento, "da saldare" (sessione 9)
// ─────────────────────────────────────────────────────────────────────────────

async function appPurchaseCheckout(
  req: Request,
  body: Record<string, unknown>,
  stripe: Stripe,
  mode: 'test' | 'live',
): Promise<Response> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)
  const user = userClient(authHeader)
  const admin = adminClient()

  // Cosa si paga, e se si può: lo decide il database con il token di chi paga
  let rpcName: string
  let args: Record<string, string>
  if (body.purpose === 'subscription') {
    if (!isUuid(body.plan_id)) return jsonResponse({ ok: false, reason: 'INVALID_BODY' }, 400)
    rpcName = 'prepare_my_plan_purchase'
    args = { p_plan_id: body.plan_id }
  } else if (body.purpose === 'event') {
    if (!isUuid(body.event_booking_id)) return jsonResponse({ ok: false, reason: 'INVALID_BODY' }, 400)
    rpcName = 'prepare_my_event_payment'
    args = { p_event_booking_id: body.event_booking_id }
  } else {
    if (!isUuid(body.transaction_id)) return jsonResponse({ ok: false, reason: 'INVALID_BODY' }, 400)
    rpcName = 'prepare_my_settlement'
    args = { p_transaction_id: body.transaction_id }
  }

  const { data: prepared, error } = await user.rpc(rpcName, args)
  if (error) {
    console.error(`[stripe-checkout] ${rpcName}:`, error.message)
    return jsonResponse({ ok: false, reason: 'PREPARE_FAILED' }, 500)
  }
  if (!prepared?.ok) return jsonResponse({ ok: false, reason: prepared?.reason ?? 'PREPARE_FAILED' })

  // Limite per persona: niente raffiche di checkout (carte provate a ripetizione)
  const personHash = (await sha256Hex(`kalos-checkout-client:${prepared.client_id}`)).slice(0, 32)
  const purposeForLimit = body.purpose === 'event' ? 'event' : 'subscription'
  const { data: allowed } = await admin.rpc('stripe_register_checkout_attempt', {
    p_ip_hash: personHash, p_purpose: purposeForLimit, p_limit: APP_CHECKOUTS_PER_PERSON_PER_HOUR, p_window_minutes: 60,
  })
  if (allowed === false) return jsonResponse({ ok: false, reason: 'TOO_MANY_ATTEMPTS' }, 429)

  // Che cosa nasce col pagamento
  let purpose: 'subscription' | 'event' | 'membership_fee'
  let kind: 'new_subscription' | 'event_booking' | 'settlement'
  let targetId: string
  let title: string
  let description: string
  const metadata: Record<string, unknown> = {}

  if (body.purpose === 'subscription') {
    purpose = 'subscription'
    kind = 'new_subscription'
    targetId = prepared.plan.plan_id
    title = `Abbonamento ${prepared.plan.name}`
    description = 'Parte dal primo ingresso; se entro 60 giorni non lo usi, parte comunque'
    metadata.plan = prepared.plan
  } else if (prepared.kind === 'settlement') {
    // Un "da saldare" (anche di un evento registrato in studio)
    purpose = body.purpose === 'event' || prepared.transaction_kind === 'event'
      ? 'event'
      : prepared.transaction_kind === 'membership_fee' ? 'membership_fee' : 'subscription'
    kind = 'settlement'
    targetId = prepared.transaction_id
    title = prepared.title ?? 'Pagamento'
    description = 'Saldo di quanto registrato in studio'
  } else {
    purpose = 'event'
    kind = 'event_booking'
    targetId = prepared.event_booking_id
    title = prepared.title ?? 'Contributo'
    description = 'Contributo per la tua iscrizione'
  }
  metadata.kind = kind
  metadata.title = title

  const open = await closeOpenCheckouts(stripe, { targetId, clientId: prepared.client_id, kind })
  if (open === 'paid') return jsonResponse({ ok: false, reason: 'ALREADY_PAID' })
  if (open === 'in_progress') return jsonResponse({ ok: false, reason: 'CHECKOUT_IN_PROGRESS' }, 409)

  const { data: row, error: insertError } = await admin
    .from('stripe_payments')
    .insert({
      purpose,
      target_id: targetId,
      client_id: prepared.client_id,
      amount_cents: prepared.amount_cents,
      currency: 'EUR',
      status: 'created',
      livemode: mode === 'live',
      source: 'app',
      receipt_email: prepared.email ?? null,
      metadata,
    })
    .select('id')
    .single()
  if (insertError || !row) throw new Error(insertError?.message ?? 'riga del pagamento non creata')

  const back = appReturn(req, body)
  const session = await createSession(stripe, row.id, {
    mode: 'payment',
    client_reference_id: row.id,
    customer_email: prepared.email ?? undefined,
    line_items: [{
      quantity: 1,
      price_data: {
        currency: 'eur',
        unit_amount: prepared.amount_cents,
        product_data: { name: title, description: `Studio Kalòs APS — ${description}` },
      },
    }],
    payment_method_types: ['card'],
    submit_type: 'pay',
    locale: 'it',
    expires_at: Math.floor(Date.now() / 1000) + SESSION_LIFETIME_SECONDS,
    success_url: back.success(row.id),
    cancel_url: back.cancel(row.id),
    metadata: { kalos_payment_id: row.id, purpose, kind },
    payment_intent_data: {
      description: `${title} — Studio Kalòs APS`,
      metadata: { kalos_payment_id: row.id, purpose, kind },
    },
  })

  return jsonResponse({ ok: true, url: session.url, payment_id: row.id })
}

// ─────────────────────────────────────────────────────────────────────────────
// Donazione
// ─────────────────────────────────────────────────────────────────────────────

async function donationCheckout(
  req: Request,
  body: Record<string, unknown>,
  stripe: Stripe,
  mode: 'test' | 'live',
): Promise<Response> {
  const admin = adminClient()
  if (!(await paymentsEnabled(admin))) return jsonResponse({ ok: false, reason: 'PAYMENTS_DISABLED' })

  const amount = Number(body.amount_cents)
  const name = typeof body.name === 'string' ? body.name.trim().replace(/\s+/g, ' ') : ''
  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : ''
  const fiscalCode = typeof body.fiscal_code === 'string' ? body.fiscal_code.trim().toUpperCase() : ''

  if (!Number.isInteger(amount) || amount < DONATION_MIN_CENTS || amount > DONATION_MAX_CENTS) {
    return jsonResponse({ ok: false, reason: 'INVALID_AMOUNT', min_cents: DONATION_MIN_CENTS, max_cents: DONATION_MAX_CENTS })
  }
  if (name.length < 3 || name.length > 120) return jsonResponse({ ok: false, reason: 'INVALID_NAME' })
  if (!EMAIL_RE.test(email) || email.length > 200) return jsonResponse({ ok: false, reason: 'INVALID_EMAIL' })
  if (fiscalCode && !/^[A-Z0-9]{11,16}$/.test(fiscalCode)) return jsonResponse({ ok: false, reason: 'INVALID_FISCAL_CODE' })

  // Limite per IP: un modulo aperto a tutti è un bersaglio per chi prova carte rubate
  const ip = clientIp(req) ?? 'sconosciuto'
  const ipHash = (await sha256Hex(`kalos-checkout:${ip}`)).slice(0, 32)
  const { data: allowed } = await admin.rpc('stripe_register_checkout_attempt', {
    p_ip_hash: ipHash, p_purpose: 'donation', p_limit: DONATIONS_PER_IP_PER_HOUR, p_window_minutes: 60,
  })
  if (allowed === false) return jsonResponse({ ok: false, reason: 'TOO_MANY_ATTEMPTS' }, 429)

  const payer = { name, email, ...(fiscalCode ? { fiscal_code: fiscalCode } : {}) }
  const { data: row, error: insertError } = await admin
    .from('stripe_payments')
    .insert({
      purpose: 'donation',
      amount_cents: amount,
      currency: 'EUR',
      status: 'created',
      livemode: mode === 'live',
      source: 'site',
      receipt_email: email,
      metadata: { payer },
    })
    .select('id')
    .single()
  if (insertError || !row) throw new Error(insertError?.message ?? 'riga del pagamento non creata')

  const origin = returnOrigin(req)
  const session = await createSession(stripe, row.id, {
    mode: 'payment',
    client_reference_id: row.id,
    customer_email: email,
    line_items: [{
      quantity: 1,
      price_data: {
        currency: 'eur',
        unit_amount: amount,
        product_data: {
          name: 'Donazione a Studio Kalòs APS',
          description: 'Erogazione liberale: torna tutta nelle attività dell\'associazione',
        },
      },
    }],
    payment_method_types: ['card'],
    submit_type: 'donate',
    locale: 'it',
    expires_at: Math.floor(Date.now() / 1000) + SESSION_LIFETIME_SECONDS,
    success_url: `${origin}/donazioni/grazie/?sessione={CHECKOUT_SESSION_ID}`,
    cancel_url: `${origin}/donazioni/?pagamento=annullato#dona-ora`,
    metadata: { kalos_payment_id: row.id, purpose: 'donation' },
    payment_intent_data: {
      description: 'Donazione — Studio Kalòs APS',
      metadata: { kalos_payment_id: row.id, purpose: 'donation' },
    },
  })

  return jsonResponse({ ok: true, url: session.url, payment_id: row.id })
}

/** Crea la sessione e la collega alla riga; se Stripe rifiuta, la riga resta segnata come fallita. */
async function createSession(
  stripe: Stripe,
  paymentId: string,
  params: Stripe.Checkout.SessionCreateParams,
): Promise<Stripe.Checkout.Session> {
  const admin = adminClient()
  try {
    const session = await stripe.checkout.sessions.create(params, { idempotencyKey: `checkout-${paymentId}` })
    const { error } = await admin
      .from('stripe_payments')
      .update({ checkout_session_id: session.id })
      .eq('id', paymentId)
    if (error) throw new Error(`collegamento della sessione: ${error.message}`)
    return session
  } catch (err) {
    await admin
      .from('stripe_payments')
      .update({ status: 'failed', failure_message: err instanceof Error ? err.message.slice(0, 500) : 'errore Stripe' })
      .eq('id', paymentId)
    throw err
  }
}
