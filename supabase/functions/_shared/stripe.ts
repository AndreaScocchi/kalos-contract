// Stripe per le edge function: client, verifica della firma del webhook e riconciliazione.
//
// IL PRINCIPIO (migrazione 20260924100000): gli eventi di Stripe sono un campanello, non dati.
// Qualunque evento che riguarda un pagamento porta a `reconcilePaymentIntent`: si rilegge da Stripe
// lo stato completo del PaymentIntent (pagamento, commissione, rimborsi) e lo si passa a
// `stripe_apply_payment_state`, l'unico punto che scrive nel database. Così l'ordine e i doppioni
// degli eventi non contano.
//
// Secret:
//   STRIPE_SECRET_KEY       chiave segreta (sk_test_… o sk_live_…, oppure una chiave ristretta rk_…)
//   STRIPE_WEBHOOK_SECRET   segreto di firma dell'endpoint (whsec_…); più d'uno separati da virgola
//                           durante una rotazione
//   STRIPE_API_BASE         SOLO IN LOCALE: indirizzo del finto server Stripe (scripts/stripe-local).
//                           Fuori dal Supabase locale viene ignorato.

import Stripe from 'npm:stripe@22.6.2'
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export { Stripe }

/** Versione dell'API a cui è fissata la libreria. L'endpoint del webhook va creato con questa. */
export const STRIPE_API_VERSION: string = (Stripe as unknown as { API_VERSION: string }).API_VERSION

export type StripeMode = 'test' | 'live'

export function stripeKeyMode(key: string): StripeMode | null {
  if (/^(sk|rk)_live_/.test(key)) return 'live'
  if (/^(sk|rk)_test_/.test(key)) return 'test'
  return null
}

/** Il Supabase locale (`supabase start` / `functions serve`), mai la produzione. */
export function isLocalSupabase(): boolean {
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  return /^http:\/\/(kong|127\.0\.0\.1|localhost|host\.docker\.internal)(:\d+)?(\/|$)/.test(url)
}

export function getStripe(): { stripe: Stripe; mode: StripeMode } | null {
  const key = Deno.env.get('STRIPE_SECRET_KEY')?.trim()
  if (!key) return null
  const mode = stripeKeyMode(key)
  if (!mode) return null

  const config: Stripe.StripeConfig = {
    httpClient: Stripe.createFetchHttpClient(),
    maxNetworkRetries: 2,
    appInfo: { name: 'Studio Kalos' },
  }

  const base = Deno.env.get('STRIPE_API_BASE')?.trim()
  if (base) {
    if (isLocalSupabase() && mode === 'test') {
      const url = new URL(base)
      config.host = url.hostname
      config.port = url.port || (url.protocol === 'https:' ? '443' : '80')
      config.protocol = url.protocol.replace(':', '') as 'http' | 'https'
    } else {
      console.error('[stripe] STRIPE_API_BASE ignorato: vale solo in locale e con una chiave di prova')
    }
  }

  return { stripe: new Stripe(key, config), mode }
}

/**
 * La chiave deve essere coerente con l'interruttore `stripe_live`: una chiave live con l'interruttore
 * spento (o una di prova con l'interruttore acceso) vuol dire che qualcosa è stato configurato a
 * metà, e in quel caso non si apre nessun pagamento.
 */
export async function checkStripeMode(admin: SupabaseClient, mode: StripeMode): Promise<string | null> {
  const { data, error } = await admin.from('feature_flags').select('enabled').eq('key', 'stripe_live').maybeSingle()
  if (error) return 'FLAGS_UNAVAILABLE'
  const live = !!data?.enabled
  if (live !== (mode === 'live')) return 'STRIPE_MODE_MISMATCH'
  return null
}

export async function paymentsEnabled(admin: SupabaseClient): Promise<boolean> {
  const { data } = await admin.from('feature_flags').select('enabled').eq('key', 'payments').maybeSingle()
  return !!data?.enabled
}

/** Verifica la firma sul corpo GREZZO della richiesta (mai su un JSON riserializzato). */
export async function verifyStripeEvent(stripe: Stripe, rawBody: string, signature: string): Promise<Stripe.Event> {
  const secrets = (Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '').split(',').map((s) => s.trim()).filter(Boolean)
  if (secrets.length === 0) throw new Error('STRIPE_WEBHOOK_SECRET non configurato')

  let lastError: unknown = null
  for (const secret of secrets) {
    try {
      return await stripe.webhooks.constructEventAsync(
        rawBody, signature, secret, undefined, Stripe.createSubtleCryptoProvider(),
      )
    } catch (err) {
      lastError = err
    }
  }
  throw lastError
}

export interface ApplyResult {
  ok: boolean
  reason?: string
  stripe_payment_id?: string
  status?: string
  transaction_id?: string | null
  is_duplicate?: boolean
  ledger?: boolean
  receipt_ids?: string[]
}

/**
 * Rilegge da Stripe lo stato completo di un pagamento e lo riporta nel database.
 * `hints` aiuta a trovare la nostra riga quando il PaymentIntent è nuovo (arriva dal Checkout).
 */
export async function reconcilePaymentIntent(
  stripe: Stripe,
  admin: SupabaseClient,
  paymentIntentId: string,
  hints: { stripePaymentId?: string | null; checkoutSessionId?: string | null } = {},
): Promise<ApplyResult> {
  const pi = await stripe.paymentIntents.retrieve(paymentIntentId, {
    expand: ['latest_charge.balance_transaction'],
  })

  const charge = pi.latest_charge && typeof pi.latest_charge === 'object' ? pi.latest_charge : null
  const balance = charge && charge.balance_transaction && typeof charge.balance_transaction === 'object'
    ? charge.balance_transaction
    : null

  const refunds: Stripe.Refund[] = []
  for await (const refund of stripe.refunds.list({ payment_intent: paymentIntentId, limit: 100 })) {
    refunds.push(refund)
  }

  const details = charge?.payment_method_details ?? null
  const paymentMethodType = details?.card?.wallet?.type ?? details?.type ?? pi.payment_method_types?.[0] ?? null

  const payload = {
    stripe_payment_id: hints.stripePaymentId ?? pi.metadata?.kalos_payment_id ?? null,
    checkout_session_id: hints.checkoutSessionId ?? null,
    payment_intent: {
      id: pi.id,
      status: pi.status,
      amount_received: pi.amount_received,
      currency: pi.currency,
      livemode: pi.livemode,
      payment_method_type: paymentMethodType,
      receipt_email: charge?.billing_details?.email ?? pi.receipt_email ?? null,
      last_payment_error: pi.last_payment_error?.message ?? null,
      charge: charge
        ? {
          created: charge.created,
          // La commissione può non essere ancora nota: `charge.updated` la porterà dopo
          fee_cents: balance ? balance.fee : null,
          net_cents: balance ? balance.net : null,
        }
        : null,
    },
    refunds: refunds.map((r) => ({
      id: r.id,
      amount: r.amount,
      status: r.status,
      created: r.created,
      reason: r.reason,
      metadata: r.metadata ?? {},
    })),
  }

  const { data, error } = await admin.rpc('stripe_apply_payment_state', { p_payload: payload })
  if (error) throw new Error(`stripe_apply_payment_state: ${error.message}`)
  return data as ApplyResult
}
