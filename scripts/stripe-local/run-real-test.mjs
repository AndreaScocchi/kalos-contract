#!/usr/bin/env node
/**
 * Prova in locale con lo Stripe VERO in modalità test (prima di andare live, STRIPE_SETUP.md §4).
 *
 * Il finto Stripe (`run-scenarios*.mjs`) prova la nostra logica; questa prova quello che il finto
 * non può: che Stripe accetti davvero i nostri checkout, che la firma dei suoi eventi passi, che le
 * sue risposte (versione dell'API, commissione, rimborsi) abbiano la forma che ci aspettiamo.
 * I pagamenti si completano sulla vera pagina di Checkout, in un browser senza finestra (Playwright),
 * con le carte di prova di Stripe.
 *
 * Serve la chiave di prova dell'account dell'APS in un file (mai come argomento), poi:
 *
 *   npx supabase start && npx supabase db reset
 *   stripe listen --api-key "$(cat <file>)" --print-secret                  # il whsec_ per l'env
 *   # env delle function (fuori dal repo): STRIPE_SECRET_KEY=<chiave di prova>, STRIPE_WEBHOOK_SECRET=<whsec>,
 *   #   CHECKOUT_ALLOWED_ORIGINS=http://localhost:3333, APP_RETURN_ORIGINS=http://localhost:8081
 *   npx supabase functions serve --env-file <env>
 *   stripe listen --api-key "$(cat <file>)" --forward-to http://127.0.0.1:54321/functions/v1/stripe-webhook
 *   STRIPE_KEY_FILE=<file> PLAYWRIGHT_FROM=<cartella con node_modules/playwright> \
 *     node scripts/stripe-local/run-real-test.mjs
 *
 * Nessun STRIPE_API_BASE: le function parlano con api.stripe.com. Scrive solo nel database locale.
 */

import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { randomUUID } from 'node:crypto'

import { APP_ORIGIN, check, count, fn, one, results, rest, section, setFlag, sleep, user } from './lib.mjs'

const key = readFileSync(process.env.STRIPE_KEY_FILE ?? '', 'utf8').trim()
if (!/^(sk|rk)_test_/.test(key)) throw new Error('STRIPE_KEY_FILE deve contenere una chiave di PROVA (sk_test_…)')

const require = createRequire(join(process.env.PLAYWRIGHT_FROM ?? process.cwd(), 'package.json'))
const { chromium } = require('playwright')

const SITE = 'http://localhost:3333'
const APP = { client: 'app', platform: 'web' }

async function stripeGet(path) {
  const res = await fetch(`https://api.stripe.com/v1/${path}`, { headers: { Authorization: `Bearer ${key}` } })
  return res.json()
}

/** Aspetta che il database arrivi dove deve (il webhook di Stripe non è istantaneo). */
async function until(label, probe, { timeoutMs = 45_000 } = {}) {
  const started = Date.now()
  let last = null
  while (Date.now() - started < timeoutMs) {
    last = await probe()
    if (last) return last
    await sleep(1000)
  }
  console.log(`  … scaduto il tempo: ${label}`)
  return null
}

let browser
/** Paga sulla vera pagina di Checkout di Stripe, come farebbe una persona. */
async function payOnCheckout(url, { card = '4242424242424242', expectDecline = false } = {}) {
  const page = await browser.newPage({ locale: 'it-IT' })
  // Il ritorno va al sito o all'app in locale, che qui non girano: basta vedere che ci si arriva
  await page.route(/^http:\/\/localhost:(3333|8081)\//, (route) => route.fulfill({ status: 200, body: 'ritorno' }))
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded' })
    await page.locator('#cardNumber').waitFor({ timeout: 30_000 })
    const email = page.locator('#email')
    if (await email.isEditable().catch(() => false) && !(await email.inputValue())) await email.fill('prova@test.kalos')
    await page.locator('#cardNumber').fill(card)
    await page.locator('#cardExpiry').fill('12 / 34')
    await page.locator('#cardCvc').fill('123')
    const name = page.locator('#billingName')
    if (await name.isVisible().catch(() => false)) await name.fill('Prova Kalos')
    const country = page.locator('#billingCountry')
    if (await country.isVisible().catch(() => false)) await country.selectOption('IT').catch(() => {})
    const zip = page.locator('#billingPostalCode')
    if (await zip.isVisible().catch(() => false)) await zip.fill('34077')
    await page.locator('button[type="submit"], .SubmitButton').first().click()
    if (expectDecline) {
      await page.getByText(/rifiutat|declined/i).first().waitFor({ timeout: 30_000 })
      return { ok: true, url: page.url() }
    }
    await page.waitForURL(/^http:\/\/localhost:(3333|8081)\//, { timeout: 60_000 })
    return { ok: true, url: page.url() }
  } catch (err) {
    const text = (await page.locator('body').innerText().catch(() => '')).slice(0, 600).replace(/\s+/g, ' ')
    return { ok: false, error: `${err.message.split('\n')[0]} · pagina: ${text}` }
  } finally {
    await page.close()
  }
}

async function main() {
  const flags = (await rest('feature_flags?select=key,enabled')).json
  const flagWas = (k) => !!flags.find((f) => f.key === k)?.enabled
  const year = Number(new Intl.DateTimeFormat('en', { timeZone: 'Europe/Rome', year: 'numeric' }).format(new Date()))
  const yearRow = await one(`association_years?year=eq.${year}&select=fee_cents`)

  await setFlag('payments', true)
  await setFlag('stripe_live', false)
  await setFlag('stripe_test_ledger', true)
  await setFlag('members_only', false)
  await rest(`association_years?year=eq.${year}`, { method: 'PATCH', body: { fee_cents: 2500 } })

  const tag = randomUUID().slice(0, 8)
  const activity = (await rest('activities', { method: 'POST', body: { name: `Vero Yoga ${tag}`, discipline: `vero_${tag}` }, prefer: 'return=representation' })).json[0]
  const plan = (await rest('plans', { method: 'POST', body: { name: `Vero Carnet ${tag}`, price_cents: 6000, entries: 5, validity_days: 60, sold_in_app: true }, prefer: 'return=representation' })).json[0]
  await rest('plan_activities', { method: 'POST', body: { plan_id: plan.id, activity_id: activity.id } })

  browser = await chromium.launch({ headless: true })
  try {
    const account = await stripeGet('account')
    section(`Account di prova ${account.id} · ${account.business_profile?.name ?? account.settings?.dashboard?.display_name ?? '—'}`)
    check('è un account italiano in euro', account.country === 'IT' && account.default_currency === 'eur', `${account.country} ${account.default_currency}`)

    section('1. Donazione con carta dal sito')
    const d = await fn('stripe-checkout', { purpose: 'donation', amount_cents: 1000, name: 'Maria Prova', email: 'maria@test.kalos', fiscal_code: 'rssmra80a41f205x' },
      { headers: { Origin: SITE, 'cf-connecting-ip': '198.51.100.21' } })
    check('Stripe accetta il checkout della donazione', d.json?.ok === true && /^https:\/\/checkout\.stripe\.com\//.test(d.json?.url ?? ''), JSON.stringify(d.json))
    const donRow = await one('stripe_payments?purpose=eq.donation&order=created_at.desc&limit=1&select=id,checkout_session_id')
    const session = await stripeGet(`checkout/sessions/${donRow?.checkout_session_id}`)
    check('sessione: 10 €, euro, solo carta, in italiano, una tantum',
      session.amount_total === 1000 && session.currency === 'eur' && session.mode === 'payment'
        && JSON.stringify(session.payment_method_types) === '["card"]' && session.locale === 'it',
      JSON.stringify({ a: session.amount_total, c: session.currency, m: session.mode, t: session.payment_method_types, l: session.locale }))
    const paid = await payOnCheckout(d.json.url)
    check('pagata sulla pagina di Stripe con la carta di prova', paid.ok, paid.error)
    const donTx = await until('incasso della donazione', () => one(`transactions?stripe_payment_id=eq.${donRow.id}&select=id,kind,method,source,amount_cents`))
    check('il webhook vero arriva, la firma passa e nasce l\'incasso', donTx?.kind === 'donation' && donTx?.method === 'stripe' && donTx?.amount_cents === 1000, JSON.stringify(donTx))
    const donPay = await one(`stripe_payments?id=eq.${donRow.id}&select=status,livemode,payment_method_type,fee_cents,payment_intent_id`)
    check('pagamento riuscito, di prova, con carta', donPay?.status === 'succeeded' && donPay?.livemode === false && donPay?.payment_method_type === 'card', JSON.stringify(donPay))
    const fee = await until('commissione', async () => (await one(`stripe_payments?id=eq.${donRow.id}&select=fee_cents`))?.fee_cents ?? null)
    check('la commissione di Stripe è letta dal saldo', typeof fee === 'number' && fee > 0 && fee < 1000, String(fee))
    check('e diventa un\'uscita', (await until('uscita della commissione', async () => (await count(`expenses?source=eq.stripe_fee&notes=like.*${donPay?.payment_intent_id}*&select=id`)) || null)) === 1)
    const donReceipt = await until('ricevuta', () => one(`receipts?transaction_id=eq.${donTx?.id}&select=causale,recipient_name,recipient_fiscal_code`))
    check('ricevuta «Erogazione liberale» a chi ha donato', donReceipt?.causale === 'Erogazione liberale' && donReceipt?.recipient_name === 'Maria Prova', JSON.stringify(donReceipt))

    section('2. Quota associativa dal sito')
    const socia = await user('vera-socia', null)
    const app = await fn('member-application', {
      first_name: 'Giulia', last_name: 'Vera', birth_date: '1990-04-02', fiscal_code: 'vrtglu90d42f356x',
      birth_place: 'Monfalcone', birth_province: 'GO', address_street: 'Via Roma 1', address_zip: '34074',
      address_city: 'Monfalcone', address_province: 'GO', email: socia.email, phone: '3330000001',
      accepted_statute: true, accepted_privacy: true, image_release: false,
    }, { token: socia.token, headers: { Origin: SITE } })
    check('domanda di ammissione inviata', app.json?.ok === true, JSON.stringify(app.json))
    const q = await fn('stripe-checkout', { purpose: 'membership_fee' }, { token: socia.token, headers: { Origin: SITE } })
    check('Stripe accetta il checkout della quota', q.json?.ok === true, JSON.stringify(q.json))
    const qPaid = await payOnCheckout(q.json.url)
    check('quota pagata sulla pagina di Stripe', qPaid.ok && qPaid.url.startsWith(`${SITE}/diventa-socio/grazie/`), qPaid.error ?? qPaid.url)
    const qRow = await one('stripe_payments?purpose=eq.membership_fee&order=created_at.desc&limit=1&select=id')
    const qTx = await until('incasso della quota', () => one(`transactions?stripe_payment_id=eq.${qRow?.id}&select=id,kind,member_fee_id`))
    const memberFee = qTx ? await one(`member_fees?id=eq.${qTx.member_fee_id}&select=status`) : null
    check('quota segnata pagata, con incasso', qTx?.kind === 'membership_fee' && memberFee?.status === 'paid', JSON.stringify({ qTx, memberFee }))

    section('3. Abbonamento comprato dall\'app')
    const anna = await user('vera-anna', null, { full_name: 'Anna Vera' })
    const s = await fn('stripe-checkout', { ...APP, purpose: 'subscription', plan_id: plan.id }, { token: anna.token, headers: { Origin: APP_ORIGIN } })
    check('Stripe accetta il checkout dell\'abbonamento', s.json?.ok === true, JSON.stringify(s.json))
    const sPaid = await payOnCheckout(s.json.url)
    check('abbonamento pagato, ritorno alla pagina dell\'app', sPaid.ok && sPaid.url.startsWith(`${APP_ORIGIN}/payment/return?payment=${s.json.payment_id}`), sPaid.error ?? sPaid.url)
    const annaClient = await one(`clients?profile_id=eq.${anna.id}&select=id`)
    const sub = await until('abbonamento', () => one(`subscriptions?client_id=eq.${annaClient?.id}&select=id,starts_on_first_entry,custom_validity_days`))
    check('nasce l\'abbonamento, che parte dal primo ingresso', sub?.starts_on_first_entry === true && sub?.custom_validity_days === 60, JSON.stringify(sub))

    section('4. Carta rifiutata')
    const r = await fn('stripe-checkout', { purpose: 'donation', amount_cents: 700, name: 'Rifiuto Prova', email: 'rifiuto@test.kalos' }, { headers: { Origin: SITE, 'cf-connecting-ip': '198.51.100.22' } })
    const rRow = await one('stripe_payments?purpose=eq.donation&order=created_at.desc&limit=1&select=id')
    const declined = await payOnCheckout(r.json?.url, { card: '4000000000000002', expectDecline: true })
    check('Stripe rifiuta la carta sulla sua pagina', declined.ok, declined.error)
    await sleep(4000)
    check('nessun incasso per il pagamento rifiutato', (await count(`transactions?stripe_payment_id=eq.${rRow?.id}&select=id`)) === 0)

    section('5. Rimborso parziale dal gestionale')
    const tesoriere = await user('vero-tesoriere', 'finance')
    const refund = await fn('stripe-refund', { transaction_id: donTx?.id, amount_cents: 300, reason: 'Prova di rimborso', request_id: randomUUID() }, { token: tesoriere.token, headers: { Origin: SITE } })
    check('Stripe accetta il rimborso', refund.json?.ok === true, JSON.stringify(refund.json))
    const refundRow = await until('rimborso riuscito', () => one(`stripe_refunds?stripe_payment_id=eq.${donRow.id}&status=eq.succeeded&select=id,amount_cents`))
    check('rimborso riuscito secondo Stripe', refundRow?.amount_cents === 300, JSON.stringify(refundRow))
    const neg = await until('riga negativa', () => one(`transactions?refund_of_id=eq.${donTx?.id}&select=amount_cents`))
    check('nel registro una riga di rimborso da −3 €', neg?.amount_cents === -300, JSON.stringify(neg))

    section('6. Eventi di Stripe')
    await sleep(3000)
    const events = (await rest('stripe_events?select=type,processed_at,error_message&order=received_at.asc')).json ?? []
    const bad = events.filter((e) => !e.processed_at || e.error_message)
    check(`${events.length} eventi ricevuti, tutti elaborati senza errori`, events.length > 0 && bad.length === 0, JSON.stringify(bad.slice(0, 5)))
  } finally {
    await browser.close()
    await rest(`plans?id=eq.${plan.id}`, { method: 'PATCH', body: { sold_in_app: false } })
    await setFlag('payments', flagWas('payments'))
    await setFlag('stripe_live', flagWas('stripe_live'))
    await setFlag('members_only', flagWas('members_only'))
    if (yearRow) await rest(`association_years?year=eq.${year}`, { method: 'PATCH', body: { fee_cents: yearRow.fee_cents } })
  }

  const { passed, failed } = results()
  console.log(`\n${passed} riusciti, ${failed} falliti`)
  process.exit(failed ? 1 : 0)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
