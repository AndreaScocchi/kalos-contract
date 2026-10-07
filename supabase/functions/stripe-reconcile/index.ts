// Riallineamento del conto Stripe (v0.3.15), per Cassa e banca del gestionale.
//
// POST {} con il token di chi è loggatə (solo Finanze: admin e Tesoriere):
//   1. rilegge da Stripe gli accrediti sul conto dall'inizio della contabilità e li riporta nel
//      registro con `stripe_apply_payout_state`, esattamente come il webhook. Serve se un evento
//      `payout.*` non è arrivato, e per gli accrediti partiti prima che il webhook li ricevesse;
//   2. confronta il saldo del conto Stripe nel registro con quello vero di Stripe.
//
// Per il registro sono ancora «su Stripe»: il saldo disponibile, quello in arrivo (pagamenti non
// ancora disponibili) e gli accrediti partiti ma non ancora arrivati in banca. Quindi:
//   differenza = conto Stripe nel registro − (disponibile + in arrivo + accrediti in viaggio)
// e deve essere zero.
//
// Risponde { ok: true, stripe, ledger_stripe_cents, difference_cents, payouts, account }
// oppure { ok: false, reason }.

import { corsHeaders } from '../_shared/cors.ts'
import { adminClient, jsonResponse, userClient } from '../_shared/http.ts'
import { checkStripeMode, getStripe, reconcilePayout, type Stripe } from '../_shared/stripe.ts'

/** Il giorno italiano (AAAA-MM-GG) di un istante di Stripe, in secondi. */
function romeDate(unixSeconds: number): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Rome' }).format(new Date(unixSeconds * 1000))
}

function sumEur(amounts: { amount: number; currency: string }[] | undefined): number {
  return (amounts ?? []).filter((a) => a.currency === 'eur').reduce((sum, a) => sum + a.amount, 0)
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return jsonResponse({ ok: false, reason: 'METHOD_NOT_ALLOWED' }, 405)

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)

  const user = userClient(authHeader)
  const { data: isFinance, error: financeError } = await user.rpc('can_access_finance')
  if (financeError) {
    console.error('[stripe-reconcile] can_access_finance:', financeError.message)
    return jsonResponse({ ok: false, reason: 'DB_UNAVAILABLE' }, 500)
  }
  if (!isFinance) return jsonResponse({ ok: false, reason: 'NOT_FINANCE' }, 403)

  const configured = getStripe()
  if (!configured) return jsonResponse({ ok: false, reason: 'STRIPE_NOT_CONFIGURED' }, 503)
  const { stripe, mode } = configured
  const admin = adminClient()
  const modeProblem = await checkStripeMode(admin, mode)
  if (modeProblem) return jsonResponse({ ok: false, reason: modeProblem }, 409)

  const { data: settings } = await admin
    .from('association_settings')
    .select('ledger_start_date')
    .eq('id', true)
    .maybeSingle()
  const since = Math.floor(Date.parse(`${settings?.ledger_start_date ?? '2026-08-19'}T00:00:00Z`) / 1000)
  const today = romeDate(Date.now() / 1000)

  const payouts = { seen: 0, recorded: 0, updated: 0, removed: 0 }
  let inTransitCents = 0
  let balance: Stripe.Balance
  try {
    for await (const payout of stripe.payouts.list({ created: { gte: since }, limit: 100 })) {
      payouts.seen++
      const result = await reconcilePayout(stripe, admin, payout)
      if (!result.ok) throw new Error(`accredito ${payout.id} non applicato: ${result.reason}`)
      if (result.action === 'recorded' || result.action === 'updated' || result.action === 'removed') {
        payouts[result.action]++
      }
      // Già tolto dal saldo di Stripe ma non ancora in banca: per il registro è ancora su Stripe
      const travelling = payout.status === 'pending' || payout.status === 'in_transit'
        || (payout.status === 'paid' && romeDate(payout.arrival_date) > today)
      if (travelling && payout.currency === 'eur') inTransitCents += payout.amount
    }
    balance = await stripe.balance.retrieve()
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error('[stripe-reconcile]', message)
    return jsonResponse({ ok: false, reason: 'STRIPE_UNAVAILABLE', message: message.slice(0, 300) }, 502)
  }

  // Facoltativo: se gli accrediti sono bloccati (verifiche di Stripe) lo si dice nel gestionale
  let account: { payouts_enabled: boolean; schedule: { interval: string; delay_days: number } | null } | null = null
  try {
    const a = await stripe.accounts.retrieveCurrent()
    const schedule = a.settings?.payouts?.schedule
    account = {
      payouts_enabled: !!a.payouts_enabled,
      schedule: schedule ? { interval: schedule.interval, delay_days: schedule.delay_days } : null,
    }
  } catch (err) {
    console.error('[stripe-reconcile] account non leggibile:', err instanceof Error ? err.message : err)
  }

  const { data: ledger, error: ledgerError } = await user.rpc('finance_account_balances', { p_at: today })
  if (ledgerError || !ledger?.ok) {
    console.error('[stripe-reconcile] finance_account_balances:', ledgerError?.message ?? ledger?.reason)
    return jsonResponse({ ok: false, reason: 'DB_UNAVAILABLE' }, 500)
  }

  const availableCents = sumEur(balance.available)
  const pendingCents = sumEur(balance.pending)
  const stripeTotal = availableCents + pendingCents + inTransitCents
  const ledgerStripe = Number(ledger.stripe_cents ?? 0)

  return jsonResponse({
    ok: true,
    mode,
    checked_at: new Date().toISOString(),
    at: today,
    stripe: {
      available_cents: availableCents,
      pending_cents: pendingCents,
      in_transit_cents: inTransitCents,
      total_cents: stripeTotal,
    },
    ledger_stripe_cents: ledgerStripe,
    difference_cents: ledgerStripe - stripeTotal,
    payouts,
    account,
  })
})
