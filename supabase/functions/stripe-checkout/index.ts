// Apre un pagamento con Stripe Checkout (pagina di pagamento ospitata da Stripe) e restituisce
// l'indirizzo a cui mandare la persona.
//
// POST, due casi:
//   { purpose: 'membership_fee', year? }                    quota associativa, con il token di chi è loggato
//   { purpose: 'donation', amount_cents, name, email, fiscal_code? }   donazione dal sito, anche senza login
//
// L'importo della quota lo decide il database (`prepare_my_fee_payment`), mai il browser. Solo carta,
// Apple Pay e Google Pay (D2): `payment_method_types: ['card']` li comprende tutti e tre e nient'altro.
// Nessun rinnovo automatico: sempre `mode: 'payment'`.
//
// La riga in `stripe_payments` nasce qui, prima della sessione, così l'id va nei metadata e il webhook
// ritrova il pagamento senza ambiguità.
//
// Risponde { ok: true, url } oppure { ok: false, reason }.

import { corsHeaders } from '../_shared/cors.ts'
import { adminClient, clientIp, EMAIL_RE, jsonResponse, sha256Hex, userClient } from '../_shared/http.ts'
import {
  checkStripeMode, getStripe, paymentsEnabled, reconcilePaymentIntent, type Stripe,
} from '../_shared/stripe.ts'

const DONATION_MIN_CENTS = 500
const DONATION_MAX_CENTS = 100_000
const DONATIONS_PER_IP_PER_HOUR = 10
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
    return jsonResponse({ ok: false, reason: 'INVALID_PURPOSE' }, 400)
  } catch (err) {
    console.error('[stripe-checkout]', err)
    return jsonResponse({ ok: false, reason: 'CHECKOUT_FAILED' }, 502)
  }
})

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

  // Un'altra scheda del browser ha già un checkout aperto per la stessa quota: lo si chiude. Se nel
  // frattempo risulta pagato, la quota è pagata e non si apre nulla.
  const { data: open } = await admin
    .from('stripe_payments')
    .select('id, checkout_session_id')
    .eq('target_id', prepared.member_fee_id)
    .eq('status', 'created')
    .not('checkout_session_id', 'is', null)
  for (const row of open ?? []) {
    const session = await stripe.checkout.sessions.retrieve(row.checkout_session_id)
    if (session.status === 'complete' && typeof session.payment_intent === 'string') {
      await reconcilePaymentIntent(stripe, admin, session.payment_intent, {
        stripePaymentId: row.id, checkoutSessionId: session.id,
      })
      return jsonResponse({ ok: false, reason: 'FEE_ALREADY_PAID' })
    }
    if (session.status === 'open') {
      try {
        await stripe.checkout.sessions.expire(session.id)
      } catch (err) {
        // Pagata proprio adesso: la prossima richiesta la troverà completa
        console.error('[stripe-checkout] sessione non scaduta:', err)
        return jsonResponse({ ok: false, reason: 'CHECKOUT_IN_PROGRESS' }, 409)
      }
    }
    await admin.rpc('stripe_checkout_expired', { p_checkout_session_id: session.id })
  }

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
      source: 'site',
      receipt_email: prepared.email ?? null,
      metadata: { year: prepared.year },
    })
    .select('id')
    .single()
  if (insertError || !row) throw new Error(insertError?.message ?? 'riga del pagamento non creata')

  const origin = returnOrigin(req)
  const title = `Quota associativa ${prepared.year}`
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
    success_url: `${origin}/diventa-socio/grazie/?sessione={CHECKOUT_SESSION_ID}`,
    cancel_url: `${origin}/diventa-socio/?pagamento=annullato`,
    metadata: { kalos_payment_id: row.id, purpose: 'membership_fee', year: String(prepared.year) },
    payment_intent_data: {
      description: `${title} — Studio Kalòs APS`,
      metadata: { kalos_payment_id: row.id, purpose: 'membership_fee', year: String(prepared.year) },
    },
  })

  return jsonResponse({ ok: true, url: session.url })
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

  return jsonResponse({ ok: true, url: session.url })
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
