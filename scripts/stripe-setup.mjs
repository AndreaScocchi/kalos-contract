#!/usr/bin/env node
/**
 * Collega l'account Stripe dell'APS senza passare dalla dashboard (STRIPE_SETUP.md §3–§4):
 * controlla l'account, crea l'endpoint del webhook con gli eventi e la versione dell'API giusti e
 * scrive il file dei secret per `supabase secrets set --env-file`.
 *
 *   node scripts/stripe-setup.mjs --key-file <file> [--out <file>] [--check-only] [--replace-webhook]
 *   node scripts/stripe-setup.mjs --key-file <file> --update-events
 *
 * --key-file         file con la sola chiave segreta (sk_… o rk_…, test o live). Non si passa mai
 *                    come argomento: finirebbe nella cronologia della shell.
 * --out              dove scrivere STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET e CHECKOUT_ALLOWED_ORIGINS
 *                    (permessi 600). Poi: `npx supabase secrets set --env-file <file>` e cancellarlo.
 * --check-only       solo i controlli: nessun endpoint creato, nessun file scritto.
 * --replace-webhook  se l'endpoint esiste già lo cancella e lo ricrea: il suo segreto non si può
 *                    rileggere, quindi è l'unico modo di averlo senza la dashboard.
 * --update-events    aggiunge all'endpoint esistente gli eventi che mancano (per esempio i `payout.*`
 *                    della v0.3.15). Il segreto non cambia: nessun secret da aggiornare.
 *
 * La chiave e il segreto del webhook non vengono mai stampati.
 */

import { chmodSync, readFileSync, writeFileSync } from 'node:fs'

const ENDPOINT_URL = 'https://tkioedsebdxqblgcctxv.supabase.co/functions/v1/stripe-webhook'
// La stessa della libreria delle function (`npm:stripe@22.6.2` in supabase/functions/_shared/stripe.ts)
const API_VERSION = '2026-08-26.dahlia'
// Gli eventi che stripe-webhook usa: STRIPE_SETUP.md §3
const EVENTS = [
  'checkout.session.completed',
  'checkout.session.async_payment_succeeded',
  'checkout.session.async_payment_failed',
  'checkout.session.expired',
  'charge.updated',
  'charge.refunded',
  'refund.created',
  'refund.updated',
  'refund.failed',
  'charge.dispute.created',
  'charge.dispute.updated',
  'charge.dispute.closed',
  // Accrediti sul conto (v0.3.15): diventano giroconti Stripe → banca
  'payout.paid',
  'payout.failed',
  'payout.canceled',
  'payout.updated',
]
const CHECKOUT_ALLOWED_ORIGINS = 'https://kalosstudio.it,https://www.kalosstudio.it'
const DESCRIPTOR = 'STUDIO KALOS APS'
const BRAND_COLOR = '#036257'

// ── Argomenti ────────────────────────────────────────────────────────────────────────────────

const args = process.argv.slice(2)
const opt = (name) => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const flag = (name) => args.includes(name)

const keyFile = opt('--key-file')
const outFile = opt('--out')
const checkOnly = flag('--check-only')
const replaceWebhook = flag('--replace-webhook')
const updateEvents = flag('--update-events')

if (!keyFile || (!checkOnly && !updateEvents && !outFile)) {
  console.error('Uso: node scripts/stripe-setup.mjs --key-file <file> (--out <file> | --check-only | --update-events) [--replace-webhook]')
  process.exit(1)
}

const key = readFileSync(keyFile, 'utf8').trim()
const mode = /^(sk|rk)_live_/.test(key) ? 'live' : /^(sk|rk)_test_/.test(key) ? 'test' : null
if (!mode) {
  console.error('Il file non contiene una chiave segreta di Stripe (sk_… o rk_…).')
  process.exit(1)
}

// ── Stripe ───────────────────────────────────────────────────────────────────────────────────

function form(params, prefix = '', out = new URLSearchParams()) {
  for (const [k, v] of Object.entries(params)) {
    const name = prefix ? `${prefix}[${k}]` : k
    if (Array.isArray(v)) v.forEach((item) => out.append(`${name}[]`, item))
    else if (v && typeof v === 'object') form(v, name, out)
    else if (v !== undefined) out.append(name, String(v))
  }
  return out
}

async function stripe(method, path, params) {
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${key}`,
      'Stripe-Version': API_VERSION,
      ...(params ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
    },
    body: params ? form(params) : undefined,
  })
  const json = await res.json()
  if (!res.ok) {
    const e = json?.error ?? {}
    throw new Error(`${method} ${path}: ${res.status} ${e.type ?? ''} ${e.code ?? ''} ${e.message ?? ''}`.trim())
  }
  return json
}

// ── Controlli ────────────────────────────────────────────────────────────────────────────────

const problems = []
const ok = (label) => console.log(`  ✅ ${label}`)
const warn = (label) => {
  problems.push(label)
  console.log(`  ⚠️  ${label}`)
}

console.log(`Chiave ${mode === 'live' ? 'LIVE' : 'di prova'} (${key.slice(0, 8)}…)\n`)

console.log('Account')
const account = await stripe('GET', 'account')
const name = account.business_profile?.name ?? account.settings?.dashboard?.display_name ?? '—'
console.log(`  ${account.id} · ${name} · ${account.country} · ${account.business_type ?? 'tipo non indicato'}`)
if (/pallacanestro|bisiaca/i.test(`${name} ${account.settings?.dashboard?.display_name ?? ''}`)) {
  console.error('\n❌ Questa è la chiave di un altro ente. Mai nei secret di Kalòs.')
  process.exit(1)
}
account.country === 'IT' ? ok('paese Italia') : warn(`paese ${account.country}, atteso IT`)
account.default_currency === 'eur' ? ok('valuta euro') : warn(`valuta ${account.default_currency}, attesa eur`)
if (mode === 'live') {
  account.charges_enabled ? ok('pagamenti abilitati') : warn('Stripe non ha ancora abilitato i pagamenti (verifica in corso)')
  account.payouts_enabled ? ok('accrediti sul conto abilitati') : warn('accrediti sul conto non ancora abilitati')
  account.details_submitted ? ok('dati dell\'attività inviati') : warn('attivazione dell\'account non completata')
  const due = [...(account.requirements?.past_due ?? []), ...(account.requirements?.currently_due ?? [])]
  due.length === 0 ? ok('nessun dato richiesto da Stripe') : warn(`Stripe chiede ancora: ${[...new Set(due)].join(', ')}`)
}
const descriptor = account.settings?.payments?.statement_descriptor ?? ''
descriptor.toUpperCase() === DESCRIPTOR ? ok(`descrittore «${descriptor}»`) : warn(`descrittore «${descriptor || 'vuoto'}», atteso «${DESCRIPTOR}»`)
const supportEmail = account.business_profile?.support_email
supportEmail ? ok(`email di assistenza ${supportEmail}`) : warn('email di assistenza non impostata')
const color = account.settings?.branding?.primary_color
color?.toLowerCase() === BRAND_COLOR ? ok('colore del marchio') : warn(`colore del marchio ${color ?? 'non impostato'} (facoltativo: ${BRAND_COLOR})`)
account.settings?.branding?.icon || account.settings?.branding?.logo ? ok('logo') : warn('logo non caricato (facoltativo)')

console.log('\nMetodi di pagamento (il checkout chiede solo `card`: carta, Apple Pay, Google Pay)')
try {
  const configs = await stripe('GET', 'payment_method_configurations?limit=20')
  const conf = configs.data.find((c) => c.is_default && !c.parent) ?? configs.data.find((c) => c.is_default) ?? configs.data[0]
  for (const pm of ['card', 'apple_pay', 'google_pay']) {
    const on = conf?.[pm]?.available
    on ? ok(pm) : warn(`${pm} non disponibile`)
  }
} catch (err) {
  console.log(`  (non leggibili con questa chiave: ${err.message})`)
}

console.log('\nWebhook')
const endpoints = await stripe('GET', 'webhook_endpoints?limit=100')
const ours = endpoints.data.filter((e) => e.url === ENDPOINT_URL)
const others = endpoints.data.filter((e) => e.url !== ENDPOINT_URL)
if (others.length) console.log(`  (altri endpoint sull'account, non toccati: ${others.map((e) => e.url).join(', ')})`)
for (const e of ours) {
  const missing = EVENTS.filter((ev) => !e.enabled_events.includes(ev) && !e.enabled_events.includes('*'))
  console.log(`  esiste ${e.id}: ${e.status}, API ${e.api_version ?? 'dell\'account'}, ${missing.length ? `mancano ${missing.join(', ')}` : 'eventi completi'}`)
}

if (checkOnly) {
  console.log(problems.length ? `\n${problems.length} cose da sistemare.` : '\nTutto a posto.')
  process.exit(0)
}

if (updateEvents) {
  if (ours.length !== 1) {
    console.error(`\n❌ Serve esattamente un endpoint ${ENDPOINT_URL}, ce ne sono ${ours.length}: usa --out (e --replace-webhook).`)
    process.exit(1)
  }
  const [endpoint] = ours
  const missing = EVENTS.filter((ev) => !endpoint.enabled_events.includes(ev) && !endpoint.enabled_events.includes('*'))
  if (!missing.length) {
    ok('eventi già completi: niente da cambiare')
    process.exit(0)
  }
  // Si tengono anche gli eventi in più che l'endpoint avesse già: si aggiunge soltanto
  const events = [...new Set([...endpoint.enabled_events, ...EVENTS])]
  const updated = await stripe('POST', `webhook_endpoints/${endpoint.id}`, { enabled_events: events })
  ok(`aggiornato ${updated.id}: aggiunti ${missing.join(', ')} (${updated.enabled_events.length} eventi, segreto invariato)`)
  process.exit(0)
}

if (mode === 'live' && !account.charges_enabled) {
  console.error('\n❌ In live i pagamenti non sono ancora abilitati: niente webhook né secret finché Stripe non attiva l\'account.')
  process.exit(1)
}

if (ours.length && !replaceWebhook) {
  console.error('\n❌ L\'endpoint esiste già e il suo segreto non si può rileggere: rilancia con --replace-webhook.')
  process.exit(1)
}
for (const e of ours) {
  await stripe('DELETE', `webhook_endpoints/${e.id}`)
  console.log(`  cancellato ${e.id}`)
}

const created = await stripe('POST', 'webhook_endpoints', {
  url: ENDPOINT_URL,
  api_version: API_VERSION,
  enabled_events: EVENTS,
  description: 'Studio Kalòs: stripe-webhook di Supabase (STRIPE_SETUP.md)',
})
ok(`creato ${created.id} (${created.livemode ? 'live' : 'prova'}, API ${created.api_version}, ${created.enabled_events.length} eventi)`)

writeFileSync(outFile, [
  `STRIPE_SECRET_KEY=${key}`,
  `STRIPE_WEBHOOK_SECRET=${created.secret}`,
  `CHECKOUT_ALLOWED_ORIGINS=${CHECKOUT_ALLOWED_ORIGINS}`,
  '',
].join('\n'), { mode: 0o600 })
chmodSync(outFile, 0o600)
console.log(`\nSecret scritti in ${outFile} (600). Poi: npx supabase secrets set --env-file ${outFile}, e cancellarlo.`)
if (problems.length) console.log(`Restano ${problems.length} cose da sistemare (sopra).`)
