#!/usr/bin/env node
/**
 * Prova in locale degli acquisti dall'app (sessione 9), senza un account Stripe.
 *
 * Stesse tre cose accese della sessione 5 (vedi `run-scenarios.mjs`): Supabase locale, finto Stripe,
 * edge function servite con `--env-file scripts/stripe-local/.env.functions.local`.
 *
 *     node scripts/stripe-local/run-scenarios-app.mjs
 *
 * Fa quello che fanno le persone dall'app e Stripe: acquisto di un abbonamento (dal web e da iPhone),
 * doppio tocco, contributo di un evento dopo l'iscrizione, iscrizione disdetta mentre si pagava,
 * "da saldare" pagato con carta, domanda e quota dall'app; più la regressione del sito (la quota dal
 * sito torna al sito, con fonte "site"). Controlla il database dopo ogni passo e alla fine rimette gli
 * interruttori com'erano.
 */

import { randomUUID } from 'node:crypto'

import {
  APP_ORIGIN, check, control, count, FAKE, fn, object, one, results, rest, rpc, section, setFlag, user, webhook,
} from './lib.mjs'

const APP = { client: 'app', platform: 'web' }
const fromApp = { Origin: APP_ORIGIN }

/** Paga la sessione come farebbe la persona e fa arrivare il webhook, come Stripe. */
async function payAndNotify(sessionId) {
  const paid = await control('pay', { session_id: sessionId })
  const hook = await webhook('checkout.session.completed', await object('session', sessionId))
  return { paid, hook }
}

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
  await setFlag('members_only', false)
  await rest(`association_years?year=eq.${year}`, { method: 'PATCH', body: { fee_cents: 2500 } })

  // Offerta di prova
  const tag = randomUUID().slice(0, 8)
  const activity = (await rest('activities', { method: 'POST', body: { name: `S9 Pilates ${tag}`, discipline: `s9_${tag}` }, prefer: 'return=representation' })).json[0]
  const plan = (await rest('plans', { method: 'POST', body: { name: `S9 Carnet 5 ${tag}`, price_cents: 6000, entries: 5, validity_days: 60, sold_in_app: true }, prefer: 'return=representation' })).json[0]
  const hidden = (await rest('plans', { method: 'POST', body: { name: `S9 Privata ${tag}`, price_cents: 9000, entries: 1, validity_days: 30 }, prefer: 'return=representation' })).json[0]
  await rest('plan_activities', { method: 'POST', body: { plan_id: plan.id, activity_id: activity.id } })
  const inDays = (d, h = 18) => new Date(Date.now() + d * 86_400_000 + (h - 12) * 3_600_000).toISOString()
  const event = (await rest('events', { method: 'POST', body: { name: `S9 Laboratorio ${tag}`, starts_at: inDays(6), ends_at: inDays(6, 20), price_cents: 1800, capacity: 5 }, prefer: 'return=representation' })).json[0]

  try {
    const anna = await user('s9-anna', null, { full_name: 'Anna App' })
    const bruno = await user('s9-bruno', null, { full_name: 'Bruno App' })

    section('1. Abbonamento dall\'app (web)')
    const c1 = await fn('stripe-checkout', { ...APP, purpose: 'subscription', plan_id: plan.id }, { token: anna.token, headers: fromApp })
    check('il checkout dell\'abbonamento si apre', c1.json?.ok === true && !!c1.json?.payment_id, JSON.stringify(c1.json))
    const row1 = await one(`stripe_payments?id=eq.${c1.json?.payment_id}&select=id,purpose,source,amount_cents,metadata,checkout_session_id`)
    check('riga del pagamento: abbonamento, dall\'app, importo del database, fotografia del piano',
      row1?.purpose === 'subscription' && row1?.source === 'app' && row1?.amount_cents === 6000
        && row1?.metadata?.kind === 'new_subscription' && row1?.metadata?.plan?.validity_days === 60, JSON.stringify(row1))
    const s1 = await object('session', row1.checkout_session_id)
    check('si torna alla pagina dell\'app, non al sito',
      s1.success_url === `${APP_ORIGIN}/payment/return?payment=${row1.id}`
        && s1.cancel_url === `${APP_ORIGIN}/payment/return?payment=${row1.id}&esito=annullato`, JSON.stringify({ s: s1.success_url, c: s1.cancel_url }))

    const c1b = await fn('stripe-checkout', { ...APP, purpose: 'subscription', plan_id: plan.id }, { token: anna.token, headers: fromApp })
    const row1After = await one(`stripe_payments?id=eq.${row1.id}&select=status`)
    check('un doppio tocco chiude il primo checkout ancora aperto', c1b.json?.ok === true && row1After?.status === 'canceled', JSON.stringify({ c1b: c1b.json, row1After }))

    const row1b = await one(`stripe_payments?id=eq.${c1b.json.payment_id}&select=id,checkout_session_id`)
    const { hook } = await payAndNotify(row1b.checkout_session_id)
    check('il webhook elabora il pagamento', hook.status === 200 && hook.json?.ok === true, JSON.stringify(hook.json))
    const sub = await one(`subscriptions?client_id=eq.${(await one(`clients?profile_id=eq.${anna.id}&select=id`)).id}&select=id,starts_on_first_entry,activation_deadline,first_entry_on,custom_validity_days,metadata`)
    check('nasce l\'abbonamento, che parte dal primo ingresso', sub?.starts_on_first_entry === true && sub?.custom_validity_days === 60 && sub?.metadata?.source === 'app', JSON.stringify(sub))
    const status1 = await rpc('get_my_payment_status', { p_payment_id: row1b.id }, anna.token)
    check('la pagina di ritorno legge l\'esito: riuscito, abbonamento, ricevuta',
      status1.json?.status === 'succeeded' && status1.json?.subscription_id === sub?.id && !!status1.json?.receipt_number, JSON.stringify(status1.json))
    const other = await rpc('get_my_payment_status', { p_payment_id: row1b.id }, bruno.token)
    check('un\'altra persona non lo vede', other.json?.reason === 'PAYMENT_NOT_FOUND', JSON.stringify(other.json))

    section('2. Da iPhone')
    const c2 = await fn('stripe-checkout', { client: 'app', platform: 'ios', purpose: 'subscription', plan_id: plan.id }, { token: bruno.token, headers: { Origin: '' } })
    const row2 = await one(`stripe_payments?id=eq.${c2.json?.payment_id}&select=checkout_session_id`)
    const s2 = await object('session', row2.checkout_session_id)
    check('senza origine si torna alla pagina web dell\'app con native=1 (che rimanda a kalos://)',
      s2.success_url === `${APP_ORIGIN}/payment/return?payment=${c2.json.payment_id}&native=1`, s2.success_url)

    section('3. Piani, interruttori')
    const notSold = await fn('stripe-checkout', { ...APP, purpose: 'subscription', plan_id: hidden.id }, { token: anna.token, headers: fromApp })
    check('un piano non in vendita nell\'app: niente checkout', notSold.json?.reason === 'PLAN_NOT_SOLD_IN_APP', JSON.stringify(notSold.json))
    const bad = await fn('stripe-checkout', { ...APP, purpose: 'subscription', plan_id: 'non-un-id' }, { token: anna.token, headers: fromApp })
    check('un id non valido: 400', bad.status === 400, JSON.stringify(bad.json))
    const anon = await fn('stripe-checkout', { ...APP, purpose: 'subscription', plan_id: plan.id }, { headers: { ...fromApp, Authorization: '' } })
    check('senza accesso: rifiutato', anon.status === 401 || anon.json?.reason === 'UNAUTHORIZED' || anon.json?.reason === 'NOT_AUTHENTICATED', JSON.stringify(anon))
    await setFlag('payments', false)
    const off = await fn('stripe-checkout', { ...APP, purpose: 'subscription', plan_id: plan.id }, { token: anna.token, headers: fromApp })
    check('pagamenti spenti: niente acquisti', off.json?.reason === 'PAYMENTS_DISABLED', JSON.stringify(off.json))
    await setFlag('payments', true)

    section('4. Evento: prima il posto, poi il pagamento')
    const booked = await rpc('book_event', { p_event_id: event.id }, anna.token)
    check('Anna si iscrive', booked.json?.ok === true, JSON.stringify(booked.json))
    const ebId = booked.json?.booking_id
    const stolen = await fn('stripe-checkout', { ...APP, purpose: 'event', event_booking_id: ebId }, { token: bruno.token, headers: fromApp })
    check('Bruno non può pagare l\'iscrizione di Anna', stolen.json?.reason === 'BOOKING_NOT_FOUND', JSON.stringify(stolen.json))
    const open = await rpc('get_my_open_payments', {}, anna.token)
    check('il contributo è tra le cose da pagare', open.json?.items?.some((i) => i.event_booking_id === ebId && i.amount_cents === 1800), JSON.stringify(open.json))
    const c4 = await fn('stripe-checkout', { ...APP, purpose: 'event', event_booking_id: ebId }, { token: anna.token, headers: fromApp })
    const row4 = await one(`stripe_payments?id=eq.${c4.json?.payment_id}&select=id,purpose,amount_cents,checkout_session_id,metadata`)
    check('checkout del contributo', row4?.purpose === 'event' && row4?.amount_cents === 1800 && row4?.metadata?.kind === 'event_booking', JSON.stringify(row4))
    await payAndNotify(row4.checkout_session_id)
    const tx4 = await one(`transactions?stripe_payment_id=eq.${row4.id}&select=id,kind,event_booking_id,source`)
    check('incasso collegato all\'iscrizione, dall\'app', tx4?.kind === 'event' && tx4?.event_booking_id === ebId && tx4?.source === 'app', JSON.stringify(tx4))
    check('con la ricevuta', (await count(`receipts?transaction_id=eq.${tx4?.id}&select=id`)) === 1)
    const cancelPaid = await rpc('cancel_event_booking', { p_booking_id: ebId }, anna.token)
    check('un\'iscrizione pagata si disdice parlando con lo studio', cancelPaid.json?.reason === 'PAID_CONTACT_STUDIO', JSON.stringify(cancelPaid.json))

    section('5. Iscrizione disdetta mentre si pagava')
    const bBooked = await rpc('book_event', { p_event_id: event.id }, bruno.token)
    const c5 = await fn('stripe-checkout', { ...APP, purpose: 'event', event_booking_id: bBooked.json?.booking_id }, { token: bruno.token, headers: fromApp })
    await rpc('cancel_event_booking', { p_booking_id: bBooked.json?.booking_id }, bruno.token)
    const row5 = await one(`stripe_payments?id=eq.${c5.json?.payment_id}&select=id,checkout_session_id`)
    await payAndNotify(row5.checkout_session_id)
    const dup5 = await one(`stripe_payments?id=eq.${row5.id}&select=is_duplicate,transaction_id`)
    const tx5 = await one(`transactions?id=eq.${dup5?.transaction_id}&select=event_booking_id`)
    check('il denaro è registrato come doppione da rimborsare, senza collegamento né ricevuta',
      dup5?.is_duplicate === true && tx5?.event_booking_id === null && (await count(`receipts?transaction_id=eq.${dup5?.transaction_id}&select=id`)) === 0,
      JSON.stringify({ dup5, tx5 }))

    section('6. Da saldare pagato con carta')
    const annaClient = (await one(`clients?profile_id=eq.${anna.id}&select=id`)).id
    const pending = (await rest('transactions', { method: 'POST', prefer: 'return=representation', body: {
      client_id: annaClient, kind: 'subscription', amount_cents: 4500, method: 'cash', source: 'studio', status: 'pending',
      subscription_id: sub.id, description: 'Abbonamento registrato in studio',
    } })).json[0]
    const c6 = await fn('stripe-checkout', { ...APP, purpose: 'settlement', transaction_id: pending.id }, { token: anna.token, headers: fromApp })
    const row6 = await one(`stripe_payments?id=eq.${c6.json?.payment_id}&select=id,checkout_session_id,amount_cents,metadata`)
    check('checkout del saldo, con l\'importo del «da saldare»', row6?.amount_cents === 4500 && row6?.metadata?.kind === 'settlement', JSON.stringify(row6))
    await payAndNotify(row6.checkout_session_id)
    const settled = await one(`transactions?id=eq.${pending.id}&select=status,method,source,stripe_payment_id`)
    check('la stessa riga diventa pagata con carta', settled?.status === 'paid' && settled?.method === 'stripe' && settled?.stripe_payment_id === row6.id, JSON.stringify(settled))
    check('nessun incasso in più', (await count(`transactions?stripe_payment_id=eq.${row6.id}&select=id`)) === 1)
    const again = await fn('stripe-checkout', { ...APP, purpose: 'settlement', transaction_id: pending.id }, { token: anna.token, headers: fromApp })
    check('un «da saldare» già saldato non si paga più', again.json?.reason === 'NOT_PENDING', JSON.stringify(again.json))

    section('7. Domanda e quota dall\'app')
    const application = await fn('member-application', {
      first_name: 'Anna', last_name: 'App', birth_date: '1992-05-10', fiscal_code: 'ppanna92e50f356w',
      birth_place: 'Gorizia', birth_province: 'GO', address_street: 'Via Roma 1', address_zip: '34077',
      address_city: 'Ronchi dei Legionari', address_province: 'GO', email: anna.email, phone: '3331112222',
      accepted_statute: true, accepted_privacy: true, image_release: true, channel: 'app',
    }, { token: anna.token, headers: fromApp })
    check('la domanda dall\'app si invia', application.json?.ok === true, JSON.stringify(application.json))
    const appRow = await one(`member_applications?id=eq.${application.json?.application_id}&select=channel`)
    check('con il canale «app»', appRow?.channel === 'app', JSON.stringify(appRow))
    const c7 = await fn('stripe-checkout', { ...APP, purpose: 'membership_fee' }, { token: anna.token, headers: fromApp })
    const row7 = await one(`stripe_payments?id=eq.${c7.json?.payment_id}&select=id,source,checkout_session_id`)
    const s7 = await object('session', row7.checkout_session_id)
    check('la quota dall\'app torna all\'app, con fonte «app»',
      row7?.source === 'app' && s7.success_url === `${APP_ORIGIN}/payment/return?payment=${row7.id}`, JSON.stringify({ row7, url: s7.success_url }))
    await payAndNotify(row7.checkout_session_id)
    const fee = await one(`member_fees?client_id=eq.${annaClient}&year=eq.${year}&select=status`)
    check('la quota risulta pagata', fee?.status === 'paid', JSON.stringify(fee))

    section('8. Regressione del sito')
    const site = await user('s9-sito', null)
    await fn('member-application', {
      first_name: 'Sara', last_name: 'Sito', birth_date: '1985-01-20', fiscal_code: 'sttsra85a60f356q',
      address_street: 'Via Verdi 2', address_zip: '34074', address_city: 'Monfalcone', address_province: 'GO',
      email: site.email, accepted_statute: true, accepted_privacy: true, image_release: false,
    }, { token: site.token })
    const c8 = await fn('stripe-checkout', { purpose: 'membership_fee' }, { token: site.token })
    const row8 = await one(`stripe_payments?id=eq.${c8.json?.payment_id}&select=id,source,metadata,checkout_session_id`)
    const s8 = await object('session', row8.checkout_session_id)
    check('dal sito la quota torna al sito, con fonte «site», come nella sessione 5',
      row8?.source === 'site' && s8.success_url === 'http://localhost:3333/diventa-socio/grazie/?sessione={CHECKOUT_SESSION_ID}'
        && JSON.stringify(row8?.metadata) === JSON.stringify({ year }), JSON.stringify({ row8, url: s8.success_url }))
    const d8 = await fn('stripe-checkout', { purpose: 'donation', amount_cents: 1000, name: 'Dora Dono', email: 'dora@test.kalos' }, { headers: { 'cf-connecting-ip': '198.51.100.9' } })
    check('le donazioni dal sito funzionano come prima', d8.json?.ok === true, JSON.stringify(d8.json))
  } finally {
    await setFlag('payments', flagWas('payments'))
    await setFlag('stripe_live', flagWas('stripe_live'))
    await setFlag('stripe_test_ledger', flagWas('stripe_test_ledger'))
    await setFlag('members_only', flagWas('members_only'))
    await rest(`association_years?year=eq.${year}`, { method: 'PATCH', body: { fee_cents: yearRow?.fee_cents ?? null } })
  }

  const { passed, failed } = results()
  console.log(`\n${passed} ok, ${failed} falliti`)
  process.exit(failed ? 1 : 0)
}

main().catch((err) => { console.error(err); process.exit(1) })
