#!/usr/bin/env node
/**
 * Prova in locale del giro dei pagamenti online (sessione 5), senza un account Stripe.
 *
 * Servono tre cose accese:
 *   1. il Supabase locale:           npx supabase start   (e `npx supabase db reset` per partire puliti)
 *   2. il finto Stripe:              node scripts/stripe-local/fake-stripe.mjs
 *   3. le edge function in locale:   npx supabase functions serve --env-file scripts/stripe-local/.env.functions.local
 *      (il file lo scrive questo script al primo giro, poi va rilanciato `functions serve`)
 *
 *     node scripts/stripe-local/run-scenarios.mjs
 *
 * Fa quello che nella realtà fanno le persone e Stripe: domanda di ammissione dal sito, checkout della
 * quota, pagamento, eventi del webhook firmati come li firma Stripe (anche doppi, in parallelo e fuori
 * ordine), donazione con la commissione che arriva dopo, rimborsi dal gestionale e "dalla dashboard",
 * rimborso non riuscito, pagamento di prova dove il registro non è ammesso. Controlla il database
 * dopo ogni passo e alla fine rimette gli interruttori com'erano.
 *
 * Le email non partono (in locale SES non è configurato): si controlla che l'invio sia stato tentato.
 */

import { createHmac, randomBytes, randomUUID } from 'node:crypto'
import { execSync } from 'node:child_process'
import { existsSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ENV_FILE = join(HERE, '.env.functions.local')
const FAKE = process.env.FAKE_STRIPE_URL ?? 'http://localhost:12111'
const WHSEC = 'whsec_local_prove_sessione5'

// ── Configurazione del Supabase locale ─────────────────────────────────────────────────────

const status = JSON.parse(execSync('npx supabase status -o json 2>/dev/null', { cwd: join(HERE, '../..') }).toString())
const API = status.API_URL
const ANON = status.ANON_KEY
const SERVICE = status.SERVICE_ROLE_KEY
const FN = `${API}/functions/v1`

if (!existsSync(ENV_FILE)) {
  writeFileSync(ENV_FILE, [
    '# Scritto da scripts/stripe-local/run-scenarios.mjs. SOLO per le prove in locale.',
    'STRIPE_SECRET_KEY=sk_test_locale_finto',
    `STRIPE_WEBHOOK_SECRET=${WHSEC}`,
    'STRIPE_API_BASE=http://host.docker.internal:12111',
    'CHECKOUT_ALLOWED_ORIGINS=http://localhost:3333',
    '',
  ].join('\n'))
  console.log(`Scritto ${ENV_FILE}: rilancia \`npx supabase functions serve --env-file ${ENV_FILE}\` e poi questo script.`)
  process.exit(2)
}

// ── Utilità ──────────────────────────────────────────────────────────────────────────────────

let passed = 0
let failed = 0
function check(label, ok, detail = '') {
  if (ok) { passed++; console.log(`  ✅ ${label}`) } else { failed++; console.log(`  ❌ ${label}${detail ? ` — ${detail}` : ''}`) }
}
const section = (title) => console.log(`\n${title}`)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function rest(path, { method = 'GET', body, token = SERVICE, prefer } = {}) {
  const res = await fetch(`${API}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: token === SERVICE ? SERVICE : ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
      ...(prefer ? { Prefer: prefer } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  return { status: res.status, json: text ? JSON.parse(text) : null }
}
const rpc = (name, args = {}, token = SERVICE) => rest(`rpc/${name}`, { method: 'POST', body: args, token })

async function fn(name, body, { token = ANON, headers = {} } = {}) {
  const res = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Origin: 'http://localhost:3333', ...headers },
    body: JSON.stringify(body),
  })
  const text = await res.text()
  let json = null
  try { json = JSON.parse(text) } catch { json = { raw: text } }
  return { status: res.status, json }
}

async function control(path, body) {
  const res = await fetch(`${FAKE}/_control/${path}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`finto Stripe ${path}: ${await res.text()}`)
  return res.json()
}
const object = (kind, id) => control('object', { kind, id })

/** Un evento firmato come lo firma Stripe (schema v1: HMAC-SHA256 di "timestamp.corpo"). */
async function webhook(type, dataObject, { secret = WHSEC, livemode = false, eventId, signature } = {}) {
  const payload = JSON.stringify({
    id: eventId ?? `evt_test_${randomBytes(8).toString('hex')}`,
    object: 'event', api_version: '2026-08-26.dahlia', created: Math.floor(Date.now() / 1000),
    livemode, type, data: { object: dataObject },
  })
  const t = Math.floor(Date.now() / 1000)
  const v1 = createHmac('sha256', secret).update(`${t}.${payload}`).digest('hex')
  const res = await fetch(`${FN}/stripe-webhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(signature === null ? {} : { 'Stripe-Signature': signature ?? `t=${t},v1=${v1}` }) },
    body: payload,
  })
  const text = await res.text()
  let json = null
  try { json = JSON.parse(text) } catch { json = { raw: text } }
  return { status: res.status, json, eventPayload: payload }
}

async function user(emailPrefix, role) {
  const email = `${emailPrefix}+${Date.now()}@test.kalos`
  const password = 'prova-sessione5-Pw1!'
  const created = await fetch(`${API}/auth/v1/admin/users`, {
    method: 'POST', headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, email_confirm: true }),
  }).then((r) => r.json())
  if (role) await rest(`profiles?id=eq.${created.id}`, { method: 'PATCH', body: { role } })
  const session = await fetch(`${API}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }),
  }).then((r) => r.json())
  return { id: created.id, email, token: session.access_token }
}

async function setFlag(key, enabled) {
  await rest('feature_flags?on_conflict=key', { method: 'POST', body: { key, enabled }, prefer: 'resolution=merge-duplicates' })
}

const one = async (path) => (await rest(path)).json?.[0] ?? null
const count = async (path) => (await rest(path)).json?.length ?? 0

// ── Scenari ──────────────────────────────────────────────────────────────────────────────────

async function main() {
  const probe = await fetch(`${FAKE}/_control/object`, { method: 'POST', body: '{}', headers: { 'Content-Type': 'application/json' } }).catch(() => null)
  if (!probe) throw new Error(`Il finto Stripe non risponde su ${FAKE}: avvialo con node scripts/stripe-local/fake-stripe.mjs`)

  const flags = (await rest('feature_flags?select=key,enabled')).json
  const flagWas = (key) => !!flags.find((f) => f.key === key)?.enabled
  const year = Number(new Intl.DateTimeFormat('en', { timeZone: 'Europe/Rome', year: 'numeric' }).format(new Date()))
  const yearRow = await one(`association_years?year=eq.${year}&select=fee_cents`)

  await setFlag('payments', true)
  await setFlag('stripe_live', false)
  await setFlag('stripe_test_ledger', true)
  await rest(`association_years?year=eq.${year}`, { method: 'PATCH', body: { fee_cents: 2500 } })

  try {
    section('1. Domanda di ammissione dal sito')
    const socia = await user('socia', null)
    const tesoriere = await user('tesoriere', 'finance')
    const operatrice = await user('operatrice', 'operator')

    const app = await fn('member-application', {
      first_name: 'Giulia', last_name: 'Prova', birth_date: '1990-04-02', fiscal_code: 'prvglu90d42f356x',
      birth_place: 'Monfalcone', birth_province: 'GO', address_street: 'Via Duca d\'Aosta 1', address_zip: '34074',
      address_city: 'Monfalcone', address_province: 'GO', email: socia.email, phone: '3330000000',
      accepted_statute: true, accepted_privacy: true, image_release: false,
      channel: 'app-finto-per-provare-il-filtro', ip: '6.6.6.6',
    }, { token: socia.token, headers: { 'cf-connecting-ip': '203.0.113.7', 'User-Agent': 'Prova/1.0 (sessione 5)' } })
    check('la domanda si invia', app.json?.ok === true, JSON.stringify(app.json))
    const application = await one(`member_applications?id=eq.${app.json?.application_id}&select=channel,submitted_ip,submitted_user_agent,fiscal_code`)
    check('canale "site", IP e dispositivo presi dal server (non dal corpo)',
      application?.channel === 'site' && application?.submitted_ip === '203.0.113.7' && application?.submitted_user_agent?.startsWith('Prova/1.0'),
      JSON.stringify(application))
    check('l\'email con il PDF della domanda è stata tentata (in locale SES manca)', app.json?.email_sent === false)

    section('2. Checkout della quota')
    const c1 = await fn('stripe-checkout', { purpose: 'membership_fee' }, { token: socia.token })
    check('il checkout si apre', c1.json?.ok === true && c1.json?.url?.includes('/pay/cs_'), JSON.stringify(c1.json))
    const row1 = await one(`stripe_payments?purpose=eq.membership_fee&client_id=not.is.null&order=created_at.desc&limit=1&select=id,checkout_session_id,amount_cents,status`)
    check('la riga del pagamento nasce prima, con l\'importo deciso dal database', row1?.amount_cents === 2500 && !!row1?.checkout_session_id, JSON.stringify(row1))

    const c2 = await fn('stripe-checkout', { purpose: 'membership_fee' }, { token: socia.token })
    const row1After = await one(`stripe_payments?id=eq.${row1.id}&select=status`)
    const row2 = await one(`stripe_payments?purpose=eq.membership_fee&client_id=not.is.null&order=created_at.desc&limit=1&select=id,checkout_session_id`)
    check('un secondo checkout chiude il primo, ancora aperto', c2.json?.ok === true && row1After?.status === 'canceled' && row2.id !== row1.id,
      JSON.stringify({ c2: c2.json, row1After }))

    section('3. Pagamento e webhook')
    const paid = await control('pay', { session_id: row2.checkout_session_id, wallet: 'apple_pay' })
    const session = await object('session', row2.checkout_session_id)
    const completedEventId = `evt_test_${randomBytes(8).toString('hex')}`
    const w1 = await webhook('checkout.session.completed', session, { eventId: completedEventId })
    check('il webhook elabora il pagamento', w1.status === 200 && w1.json?.ok === true, JSON.stringify(w1.json))
    const tx = await one(`transactions?stripe_payment_id=eq.${row2.id}&select=id,kind,method,source,status,member_fee_id,amount_cents`)
    check('incasso nel registro: quota, carta, dal sito', tx?.kind === 'membership_fee' && tx?.method === 'stripe' && tx?.source === 'site' && tx?.amount_cents === 2500, JSON.stringify(tx))
    const fee = await one(`member_fees?id=eq.${tx?.member_fee_id}&select=status`)
    check('la quota risulta pagata', fee?.status === 'paid')
    const payment = await one(`stripe_payments?id=eq.${row2.id}&select=status,payment_method_type,fee_cents,payment_intent_id`)
    check('pagamento con Apple Pay, commissione registrata', payment?.payment_method_type === 'apple_pay' && payment?.fee_cents === 60 && payment?.payment_intent_id === paid.paymentIntentId, JSON.stringify(payment))
    await sleep(1500)
    const receipt = await one(`receipts?transaction_id=eq.${tx?.id}&select=id,full_number,causale,recipient_fiscal_code,sent_at,send_error`)
    check('ricevuta emessa con causale e codice fiscale', receipt?.causale === `Quota associativa ${year}` && receipt?.recipient_fiscal_code === 'PRVGLU90D42F356X', JSON.stringify(receipt))
    check('l\'invio per email è stato tentato dopo la risposta', !!receipt?.send_error && !receipt?.sent_at, JSON.stringify(receipt))

    section('4. Doppioni, parallelo, fuori ordine')
    const again = await webhook('checkout.session.completed', session, { eventId: completedEventId })
    check('lo stesso evento consegnato due volte', again.status === 200 && again.json?.duplicate === true, JSON.stringify(again.json))
    const charge = await object('charge', paid.chargeId)
    const parallel = await Promise.all([
      webhook('charge.succeeded', charge), webhook('charge.updated', charge), webhook('checkout.session.completed', session),
    ])
    check('tre eventi in parallelo sullo stesso pagamento', parallel.every((r) => r.status === 200), JSON.stringify(parallel.map((r) => r.json)))
    check('sempre un incasso solo', (await count(`transactions?stripe_payment_id=eq.${row2.id}&refund_of_id=is.null&select=id`)) === 1)
    check('e una ricevuta sola', (await count(`receipts?transaction_id=eq.${tx.id}&select=id`)) === 1)
    check('e una commissione sola tra le uscite', (await count(`expenses?source=eq.stripe_fee&notes=like.*${paid.paymentIntentId}*&select=id`)) === 1)

    // La prima sessione, già chiusa, viene pagata lo stesso (due schede del browser)
    const late = await control('pay', { session_id: row1.checkout_session_id, force: true })
    await webhook('checkout.session.completed', await object('session', row1.checkout_session_id))
    const dup = await one(`stripe_payments?id=eq.${row1.id}&select=status,is_duplicate,transaction_id`)
    check('la quota pagata due volte: il secondo incasso è un doppione', dup?.status === 'succeeded' && dup?.is_duplicate === true, JSON.stringify(dup))
    check('senza ricevuta, per non bruciare un numero', (await count(`receipts?transaction_id=eq.${dup?.transaction_id}&select=id`)) === 0)
    void late

    section('5. Donazione, con la commissione che arriva dopo')
    const d = await fn('stripe-checkout', { purpose: 'donation', amount_cents: 5000, name: '  Maria   Rossi ', email: 'Maria@Test.Kalos', fiscal_code: 'rssmra80a41f205x' },
      { headers: { 'cf-connecting-ip': '198.51.100.20' } })
    check('la donazione si apre senza login', d.json?.ok === true, JSON.stringify(d.json))
    const donRow = await one(`stripe_payments?purpose=eq.donation&order=created_at.desc&limit=1&select=id,checkout_session_id,metadata`)
    check('i dati del donatore sono puliti', donRow?.metadata?.payer?.name === 'Maria Rossi' && donRow?.metadata?.payer?.email === 'maria@test.kalos', JSON.stringify(donRow?.metadata))
    const donPaid = await control('pay', { session_id: donRow.checkout_session_id, feeLater: true, feeCents: 100 })
    await webhook('checkout.session.completed', await object('session', donRow.checkout_session_id))
    const donTx = await one(`transactions?stripe_payment_id=eq.${donRow.id}&select=id,kind,client_id`)
    const donReceipt = await one(`receipts?transaction_id=eq.${donTx?.id}&select=recipient_name,recipient_fiscal_code,causale`)
    check('ricevuta intestata a chi ha donato', donReceipt?.recipient_name === 'Maria Rossi' && donReceipt?.recipient_fiscal_code === 'RSSMRA80A41F205X' && donReceipt?.causale === 'Erogazione liberale', JSON.stringify(donReceipt))
    check('commissione non ancora nota: nessuna uscita', (await count(`expenses?notes=like.*${donPaid.paymentIntentId}*&select=id`)) === 0)
    await control('fee', { charge_id: donPaid.chargeId })
    await webhook('charge.updated', await object('charge', donPaid.chargeId))
    check('arrivata la commissione, diventa un\'uscita', (await count(`expenses?notes=like.*${donPaid.paymentIntentId}*&select=id`)) === 1)

    section('6. Rimborsi')
    const denied = await fn('stripe-refund', { transaction_id: tx.id, amount_cents: 1000, reason: 'Prova', request_id: randomUUID() }, { token: operatrice.token })
    check('un\'operatrice non rimborsa', denied.json?.reason === 'NOT_FINANCE', JSON.stringify(denied.json))
    const manual = await rpc('staff_refund_transaction', { p_transaction_id: tx.id, p_amount_cents: 500, p_reason: 'A mano' }, tesoriere.token)
    check('il rimborso "a mano" di un incasso online è rifiutato', manual.json?.reason === 'USE_STRIPE_REFUND', JSON.stringify(manual.json))
    const requestId = randomUUID()
    const r1 = await fn('stripe-refund', { transaction_id: tx.id, amount_cents: 1000, reason: 'Lezione annullata', request_id: requestId }, { token: tesoriere.token })
    check('il Tesoriere rimborsa 10 € sulla carta', r1.json?.ok === true && r1.json?.status === 'partially_refunded', JSON.stringify(r1.json))
    const r1again = await fn('stripe-refund', { transaction_id: tx.id, amount_cents: 1000, reason: 'Lezione annullata', request_id: requestId }, { token: tesoriere.token })
    check('un doppio clic non rimborsa due volte', r1again.json?.ok === true && (await count(`transactions?refund_of_id=eq.${tx.id}&select=id`)) === 1, JSON.stringify(r1again.json))
    const refundRow = await one(`transactions?refund_of_id=eq.${tx.id}&select=amount_cents,note,created_by`)
    check('riga negativa con motivo e autore', refundRow?.amount_cents === -1000 && refundRow?.note === 'Lezione annullata' && refundRow?.created_by === tesoriere.id, JSON.stringify(refundRow))
    const stripeRefund = await one(`stripe_refunds?stripe_payment_id=eq.${row2.id}&select=refund_id`)
    await webhook('refund.created', await object('refund', stripeRefund.refund_id))
    check('l\'evento del rimborso, arrivato dopo, non lo duplica', (await count(`transactions?refund_of_id=eq.${tx.id}&select=id`)) === 1)

    const dash = await control('refund', { payment_intent: donPaid.paymentIntentId, reason: 'requested_by_customer' })
    await webhook('charge.refunded', await object('charge', donPaid.chargeId))
    const donTxAfter = await one(`transactions?id=eq.${donTx.id}&select=status`)
    const dashRow = await one(`transactions?refund_of_id=eq.${donTx.id}&select=note,status`)
    check('rimborso fatto dalla dashboard di Stripe: registrato', donTxAfter?.status === 'refunded' && dashRow?.note?.startsWith('Rimborso da dashboard Stripe'), JSON.stringify({ donTxAfter, dashRow }))
    await control('refund-status', { refund_id: dash.id, status: 'failed' })
    await webhook('refund.failed', await object('refund', dash.id))
    const afterFail = await one(`transactions?id=eq.${donTx.id}&select=status`)
    const voided = await one(`transactions?refund_of_id=eq.${donTx.id}&select=status`)
    check('il rimborso non riuscito si annulla e la donazione torna incassata', afterFail?.status === 'paid' && voided?.status === 'void', JSON.stringify({ afterFail, voided }))

    section('7. Firma, modalità, interruttori')
    const noSig = await webhook('checkout.session.completed', session, { signature: null })
    check('senza firma: 400', noSig.status === 400)
    const badSig = await webhook('checkout.session.completed', session, { secret: 'whsec_sbagliato' })
    check('firma sbagliata: 400', badSig.status === 400)
    const live = await webhook('checkout.session.completed', session, { livemode: true })
    check('evento live con la chiave di prova: ignorato con 200', live.status === 200 && live.json?.ignored === 'MODE_MISMATCH', JSON.stringify(live.json))

    await setFlag('stripe_test_ledger', false)
    const t = await fn('stripe-checkout', { purpose: 'donation', amount_cents: 1000, name: 'Prova Produzione', email: 'prova@test.kalos' }, { headers: { 'cf-connecting-ip': '198.51.100.30' } })
    const tRow = await one(`stripe_payments?purpose=eq.donation&order=created_at.desc&limit=1&select=id,checkout_session_id`)
    const tPaid = await control('pay', { session_id: tRow.checkout_session_id })
    await webhook('checkout.session.completed', await object('session', tRow.checkout_session_id))
    const tState = await one(`stripe_payments?id=eq.${tRow.id}&select=status,transaction_id`)
    check('pagamento di prova dove il registro non è ammesso (produzione): nessun incasso',
      t.json?.ok === true && tState?.status === 'succeeded' && tState?.transaction_id === null, JSON.stringify(tState))
    check('né uscita per la commissione', (await count(`expenses?notes=like.*${tPaid.paymentIntentId}*&select=id`)) === 0)
    await setFlag('stripe_test_ledger', true)

    await setFlag('stripe_live', true)
    const mismatch = await fn('stripe-checkout', { purpose: 'donation', amount_cents: 1000, name: 'Mario Bianchi', email: 'mario@test.kalos' })
    check('chiave di prova con "stripe_live" acceso: nessun checkout', mismatch.status === 503 && mismatch.json?.reason === 'STRIPE_MODE_MISMATCH', JSON.stringify(mismatch.json))
    await setFlag('stripe_live', false)

    await setFlag('payments', false)
    const off = await fn('stripe-checkout', { purpose: 'donation', amount_cents: 1000, name: 'Mario Bianchi', email: 'mario@test.kalos' })
    const offFee = await fn('stripe-checkout', { purpose: 'membership_fee' }, { token: socia.token })
    check('pagamenti spenti: niente donazioni né quote', off.json?.reason === 'PAYMENTS_DISABLED' && offFee.json?.reason === 'PAYMENTS_DISABLED', JSON.stringify({ off: off.json, offFee: offFee.json }))
    await setFlag('payments', true)

    const small = await fn('stripe-checkout', { purpose: 'donation', amount_cents: 100, name: 'Mario Bianchi', email: 'mario@test.kalos' })
    check('sotto i 5 € la donazione è rifiutata', small.json?.reason === 'INVALID_AMOUNT', JSON.stringify(small.json))
    let last = null
    for (let i = 0; i < 11; i++) {
      last = await fn('stripe-checkout', { purpose: 'donation', amount_cents: 1000, name: 'Tanti Tentativi', email: 'tanti@test.kalos' }, { headers: { 'cf-connecting-ip': '198.51.100.99' } })
    }
    check('oltre 10 tentativi l\'ora dallo stesso IP: 429', last.status === 429 && last.json?.reason === 'TOO_MANY_ATTEMPTS', JSON.stringify(last.json))

    section('8. Invio della ricevuta dal gestionale')
    const byClient = await fn('send-receipt', { receipt_id: receipt.id }, { token: socia.token })
    check('un cliente non può farlo', byClient.status === 403)
    const byStaff = await fn('send-receipt', { receipt_id: receipt.id }, { token: operatrice.token })
    check('l\'operatrice sì (in locale l\'invio fallisce solo perché manca SES)', byStaff.json?.reason === 'SEND_FAILED' && /SES/.test(byStaff.json?.message ?? ''), JSON.stringify(byStaff.json))
  } finally {
    await setFlag('payments', flagWas('payments'))
    await setFlag('stripe_live', flagWas('stripe_live'))
    await setFlag('stripe_test_ledger', flagWas('stripe_test_ledger'))
    await rest(`association_years?year=eq.${year}`, { method: 'PATCH', body: { fee_cents: yearRow?.fee_cents ?? null } })
  }

  console.log(`\n${passed} ok, ${failed} falliti`)
  process.exit(failed ? 1 : 0)
}

main().catch((err) => { console.error(err); process.exit(1) })
