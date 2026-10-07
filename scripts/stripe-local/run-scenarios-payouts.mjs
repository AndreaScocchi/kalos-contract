#!/usr/bin/env node
/**
 * Prova in locale del conto Stripe (v0.3.15), senza un account Stripe.
 *
 * Servono le stesse tre cose accese di `run-scenarios.mjs` (Supabase locale, finto Stripe, edge
 * function con `--env-file scripts/stripe-local/.env.functions.local`).
 *
 *     node scripts/stripe-local/run-scenarios-payouts.mjs
 *
 * Un pagamento con carta va sul conto Stripe, non in banca; l'accredito sul conto diventa un
 * giroconto Stripe → banca quando arriva (dal webhook o dal riallineamento `stripe-reconcile`), e
 * sparisce se fallisce; il saldo di Stripe torna sempre con il registro. Il confronto è relativo a
 * quello di partenza: con un `db reset` e un finto Stripe appena avviato la differenza è zero.
 */

import { check, control, FAKE, fn, object, one, rest, results, rpc, section, setFlag, user, webhook } from './lib.mjs'

const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Rome' }).format(new Date())
function plusDays(n) {
  const d = new Date(`${today}T12:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

async function main() {
  const probe = await fetch(`${FAKE}/_control/object`, { method: 'POST', body: '{}', headers: { 'Content-Type': 'application/json' } }).catch(() => null)
  if (!probe) throw new Error(`Il finto Stripe non risponde su ${FAKE}: avvialo con node scripts/stripe-local/fake-stripe.mjs`)

  const flags = (await rest('feature_flags?select=key,enabled')).json
  const flagWas = (key) => !!flags.find((f) => f.key === key)?.enabled
  await setFlag('payments', true)
  await setFlag('stripe_live', false)
  await setFlag('stripe_test_ledger', true)

  const tesoriere = await user('conto-tesoriere', 'finance')
  const operatrice = await user('conto-operatrice', 'operator')
  const balances = async () => (await rpc('finance_account_balances', { p_at: today }, tesoriere.token)).json
  const reconcile = () => fn('stripe-reconcile', {}, { token: tesoriere.token })
  async function cardPayment(amount, feeCents, ip) {
    const d = await fn('stripe-checkout', { purpose: 'donation', amount_cents: amount, name: 'Paola Conto', email: 'paola@test.kalos' },
      { headers: { 'cf-connecting-ip': ip } })
    if (!d.json?.ok) throw new Error(`checkout: ${JSON.stringify(d.json)}`)
    const row = await one('stripe_payments?purpose=eq.donation&order=created_at.desc&limit=1&select=id,checkout_session_id')
    await control('pay', { session_id: row.checkout_session_id, feeCents })
    await webhook('checkout.session.completed', await object('session', row.checkout_session_id))
  }

  try {
    section('1. Riallineamento: chi può e da dove si parte')
    const denied = await fn('stripe-reconcile', {}, { token: operatrice.token })
    check('un\'operatrice non può', denied.status === 403 && denied.json?.reason === 'NOT_FINANCE', JSON.stringify(denied.json))
    const start = await reconcile()
    check('il Tesoriere sì', start.json?.ok === true, JSON.stringify(start.json))
    const base = start.json?.difference_cents
    console.log(`  (differenza di partenza fra registro e finto Stripe: ${base} centesimi)`)
    check('l\'account dice se gli accrediti sono attivi e ogni quanto', start.json?.account?.payouts_enabled === true
      && start.json?.account?.schedule?.interval === 'daily', JSON.stringify(start.json?.account))
    const b0 = await balances()

    section('2. Un pagamento con carta va sul conto Stripe')
    await cardPayment(3500, 78, '198.51.100.41')
    const b1 = await balances()
    check('su Stripe 34,22 € in più (35 € meno 0,78 di commissione)', b1.stripe_cents - b0.stripe_cents === 3422, JSON.stringify({ b0, b1 }))
    check('in banca niente: non è ancora arrivato', b1.bank_cents === b0.bank_cents)
    const r1 = await reconcile()
    check('il saldo di Stripe torna con il registro', r1.json?.difference_cents === base, JSON.stringify(r1.json))

    section('3. L\'accredito parte: in viaggio')
    const po = await control('payout', { amount: 3422, status: 'in_transit', arrival_date: plusDays(2) })
    const r2 = await reconcile()
    check('in viaggio: nessun giroconto', !(await one(`account_transfers?stripe_payout_id=eq.${po.id}&select=id`)))
    check('per il confronto conta ancora come Stripe', r2.json?.stripe?.in_transit_cents === 3422 && r2.json?.difference_cents === base, JSON.stringify(r2.json))

    section('4. Arrivato: il webhook lo registra come giroconto')
    await control('payout', { id: po.id, status: 'paid', arrival_date: today })
    const w = await webhook('payout.paid', await object('payout', po.id))
    check('il webhook lo elabora', w.status === 200 && w.json?.handled === 'accredito recorded', JSON.stringify(w.json))
    const transfer = await one(`account_transfers?stripe_payout_id=eq.${po.id}&select=id,occurred_on,from_account,to_account,amount_cents`)
    check('giroconto Stripe → banca di 34,22 € nel giorno di arrivo', transfer?.occurred_on === today && transfer?.from_account === 'stripe'
      && transfer?.to_account === 'bank' && transfer?.amount_cents === 3422, JSON.stringify(transfer))
    const b2 = await balances()
    check('in banca 34,22 € in più, su Stripe altrettanto in meno', b2.bank_cents - b1.bank_cents === 3422 && b1.stripe_cents - b2.stripe_cents === 3422,
      JSON.stringify({ b1, b2 }))
    const again = await webhook('payout.paid', await object('payout', po.id))
    check('un secondo evento non lo duplica', again.json?.handled === 'accredito unchanged', JSON.stringify(again.json))
    const r3 = await reconcile()
    check('dopo l\'accredito il saldo torna ancora', r3.json?.difference_cents === base && r3.json?.payouts?.recorded === 0, JSON.stringify(r3.json))

    section('5. Senza webhook: lo trova il riallineamento')
    await cardPayment(5200, 103, '198.51.100.42')
    const po2 = await control('payout', { amount: 5097, status: 'paid', arrival_date: today })
    const r4 = await reconcile()
    check('registrato aprendo Cassa e banca', r4.json?.payouts?.recorded === 1 && !!(await one(`account_transfers?stripe_payout_id=eq.${po2.id}&select=id`)),
      JSON.stringify(r4.json))
    check('e il saldo torna', r4.json?.difference_cents === base, JSON.stringify(r4.json))

    section('6. Accredito fallito: i soldi tornano su Stripe')
    const b3 = await balances()
    await control('payout', { id: po2.id, status: 'failed' })
    const wf = await webhook('payout.failed', await object('payout', po2.id))
    check('il giroconto sparisce', wf.json?.handled === 'accredito removed' && !(await one(`account_transfers?stripe_payout_id=eq.${po2.id}&select=id`)),
      JSON.stringify(wf.json))
    const b4 = await balances()
    check('in banca 50,97 € in meno, su Stripe di nuovo', b3.bank_cents - b4.bank_cents === 5097 && b4.stripe_cents - b3.stripe_cents === 5097)
    const r5 = await reconcile()
    check('il saldo torna', r5.json?.difference_cents === base, JSON.stringify(r5.json))

    section('7. Accrediti bloccati da Stripe')
    await control('payouts-enabled', { enabled: false })
    const r6 = await reconcile()
    check('il riallineamento lo dice', r6.json?.account?.payouts_enabled === false, JSON.stringify(r6.json?.account))
    await control('payouts-enabled', { enabled: true })

    section('8. A mano no')
    const manual = await rest('account_transfers', { method: 'POST', token: tesoriere.token,
      body: { occurred_on: today, from_account: 'stripe', to_account: 'bank', amount_cents: 100 } })
    check('un giroconto da Stripe non si scrive dal gestionale', manual.status >= 400 && /AUTOMATIC_TRANSFER/.test(JSON.stringify(manual.json)), JSON.stringify(manual.json))
    await rest(`account_transfers?id=eq.${transfer.id}`, { method: 'DELETE', token: tesoriere.token })
    check('un accredito non si cancella dal gestionale', !!(await one(`account_transfers?id=eq.${transfer.id}&select=id`)))
  } finally {
    await setFlag('payments', flagWas('payments'))
    await setFlag('stripe_live', flagWas('stripe_live'))
    await setFlag('stripe_test_ledger', flagWas('stripe_test_ledger'))
  }

  const { passed, failed } = results()
  console.log(`\n${passed} ok, ${failed} falliti`)
  process.exit(failed ? 1 : 0)
}

main().catch((err) => { console.error(err); process.exit(1) })
