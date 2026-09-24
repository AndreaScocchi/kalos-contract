#!/usr/bin/env node

/**
 * verify-access — verifica il modello di accesso del DB passando dall'API, come fanno le app.
 * Vedi ACCESS_MODEL.md.
 *
 * LOCALE (default): crea utenti e dati di prova sul Supabase locale (`npm run db:start`) e prova
 * cinque attori — anon, cliente (registrazione e login veri), operatrice, admin, service_role.
 * Controlla che gli accessi chiusi falliscano e che i flussi di sito, webapp, gestionale, push e
 * Finanze funzionino ancora.
 *
 *     node scripts/verify-access.mjs
 *
 * PRODUZIONE: solo chiave anon e solo richieste che non leggono dati personali (HEAD con
 * count=exact, RPC con parametri innocui: date del 1900, id inesistenti, nessun canale di invio).
 * Anche se un accesso fosse ancora aperto, nessuna chiamata invia messaggi o modifica dati.
 *
 *     SUPABASE_URL=https://<ref>.supabase.co SUPABASE_ANON_KEY=<chiave anon> \
 *       node scripts/verify-access.mjs --prod
 *
 * Esce con codice 1 se almeno un controllo non dà l'esito atteso.
 */

import { spawnSync } from 'child_process';

const PROD = process.argv.includes('--prod');
const ZERO_UUID = '00000000-0000-0000-0000-000000000000';
const results = [];

// ── Configurazione ────────────────────────────────────────────────────────────────────────────

function localConfig() {
  const r = spawnSync('npx', ['supabase', 'status', '-o', 'json'], { encoding: 'utf-8' });
  const start = (r.stdout || '').indexOf('{');
  if (r.status !== 0 || start < 0) {
    console.error('❌ Supabase locale non raggiungibile: avvialo con `npm run db:start`.');
    process.exit(1);
  }
  const s = JSON.parse(r.stdout.slice(start));
  return { url: s.API_URL, anonKey: s.ANON_KEY, serviceKey: s.SERVICE_ROLE_KEY };
}

function prodConfig() {
  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    console.error('❌ Servono SUPABASE_URL e SUPABASE_ANON_KEY.');
    process.exit(1);
  }
  return { url: url.replace(/\/$/, ''), anonKey };
}

const cfg = PROD ? prodConfig() : localConfig();

// ── HTTP ──────────────────────────────────────────────────────────────────────────────────────

/** Un attore è la coppia di chiavi con cui si presenta all'API. */
const anon = { name: 'anon', apikey: cfg.anonKey, token: cfg.anonKey };
const service = PROD ? null : { name: 'service_role', apikey: cfg.serviceKey, token: cfg.serviceKey };

async function call(actor, method, path, body, headers = {}) {
  const res = await fetch(cfg.url + path, {
    method,
    headers: {
      apikey: actor.apikey,
      Authorization: `Bearer ${actor.token}`,
      'Content-Type': 'application/json',
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = method === 'HEAD' ? '' : await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* risposta non JSON */ }
  return { status: res.status, json, text, headers: res.headers };
}

const rpc = (actor, fn, args = {}) => call(actor, 'POST', `/rest/v1/rpc/${fn}`, args);
const select = (actor, path) => call(actor, 'GET', `/rest/v1/${path}`);
const insert = (actor, table, row) =>
  call(actor, 'POST', `/rest/v1/${table}`, row, { Prefer: 'return=representation' });
const patch = (actor, path, values) =>
  call(actor, 'PATCH', `/rest/v1/${path}`, values, { Prefer: 'return=representation' });

/** Numero di righe visibili (header Content-Range), senza scaricarne nessuna. */
async function count(actor, table) {
  const r = await call(actor, 'HEAD', `/rest/v1/${table}?select=*`, undefined, { Prefer: 'count=exact' });
  const range = r.headers.get('content-range') || '';
  const n = Number(range.split('/')[1]);
  return { status: r.status, n: Number.isFinite(n) ? n : null };
}

// ── Esiti ─────────────────────────────────────────────────────────────────────────────────────

function check(label, ok, detail = '') {
  results.push({ label, ok });
  console.log(`${ok ? '  ✅' : '  ❌'} ${label}${ok ? '' : `  → ${detail}`}`);
}

const isDenied = (r) => r.status === 401 || r.status === 403;
const describe = (r) => `HTTP ${r.status} ${r.text ? r.text.slice(0, 160) : ''}`.trim();

/** Rifiuto esplicito del permesso: "zero righe" non basta, perché anche una tabella vuota le dà. */
async function expectReadDenied(actor, table) {
  const c = await count(actor, table);
  check(`${actor.name}: ${table} non leggibile`, c.status === 401 || c.status === 403,
    `HTTP ${c.status}, righe visibili: ${c.n}`);
}

/**
 * La riga esiste davvero (lo conferma service_role) ma questo ruolo non la vede: è la forma che
 * prende il divieto quando la tabella è aperta ad authenticated e a filtrare sono le policy.
 * Un "zero righe" da solo non proverebbe niente, perché lo dà anche una tabella vuota.
 */
async function expectRowsHidden(actor, table) {
  const all = await count(service, table);
  const mine = await count(actor, table);
  check(`${actor.name}: ${table} non mostra righe altrui`,
    all.n > 0 && (mine.status === 200 || mine.status === 206) && mine.n === 0,
    `righe esistenti: ${all.n}, visibili: ${mine.n} (HTTP ${mine.status})`);
}

async function expectRpcDenied(actor, fn, args, label = fn) {
  const r = await rpc(actor, fn, args);
  check(`${actor.name}: ${label} rifiutata`, isDenied(r), describe(r));
}

/**
 * Dalla sessione 3 le funzioni interne stanno nello schema `internal`, che PostgREST non espone:
 * dall'API non sono "vietate", sono inesistenti (404 PGRST202). È una garanzia più forte del 403,
 * perché non c'è nessun GRANT che possa riaprirle, ma va verificata per quello che è.
 */
async function expectRpcNotExposed(actor, fn, args, label = fn) {
  const r = await rpc(actor, fn, args);
  const notFound = r.status === 404 && (r.text || '').includes('PGRST202');
  check(`${actor.name}: ${label} non esiste nell'API`, notFound || isDenied(r), describe(r));
}

async function expectRpcOk(actor, fn, args, label = fn) {
  const r = await rpc(actor, fn, args);
  const ok = r.status === 200 && !(r.json && typeof r.json === 'object' && r.json.ok === false);
  check(`${actor.name}: ${label} funziona`, ok, describe(r));
  return r.json;
}

// ── Controlli con la sola chiave anon (validi anche in produzione) ────────────────────────────

const FINANCE_1900 = { p_month_start: '1900-01-01', p_month_end: '1900-01-31' };

async function anonChecks() {
  console.log('\n▸ anon — accessi che devono essere chiusi');
  for (const t of ['clients', 'device_tokens', 'notification_logs', 'notification_queue', 'financial_monthly_summary',
    // Sessione 3: soci, incassi e compensi non si leggono senza accesso
    'members', 'member_applications', 'member_fees', 'member_registry', 'transactions', 'receipts',
    'volunteers', 'volunteer_reimbursements', 'compensation_models', 'compensation_entries',
    'association_settings', 'trials', 'stripe_payments',
    // Sessione 5: pagamenti online
    'stripe_refunds', 'stripe_events', 'stripe_checkout_attempts',
    // Sessione 6: lista d'attesa, feedback e stato della ricostruzione del sito
    'waitlist', 'feedback', 'site_rebuild_state']) {
    await expectReadDenied(anon, t);
  }
  const ins = await insert(anon, 'device_tokens', { client_id: ZERO_UUID, expo_push_token: 'verify-access' });
  check('anon: scrittura su device_tokens rifiutata', isDenied(ins), describe(ins));

  await expectRpcDenied(anon, 'calculate_operator_compensation', { ...FINANCE_1900, p_operator_id: null });
  await expectRpcDenied(anon, 'get_monthly_revenue_by_client', FINANCE_1900);
  await expectRpcDenied(anon, 'get_monthly_revenue_by_plan', FINANCE_1900);
  // Nome di funzione inesistente: se fosse aperta, la chiamata finirebbe su un 404 innocuo.
  await expectRpcNotExposed(anon, 'call_edge_function', { p_function_name: '__verify_access_noop__', p_body: {} });
  // Modalità test verso un cliente inesistente: se fosse aperta, non accoderebbe nulla.
  await expectRpcNotExposed(anon, 'queue_announcement', {
    p_announcement_id: ZERO_UUID, p_title: 'verify-access', p_body: 'verify-access',
    p_scheduled_for: new Date().toISOString(), p_is_test: true, p_test_client_id: ZERO_UUID,
  });
  // Nessun canale: se fosse aperta, uscirebbe subito senza accodare nulla.
  await expectRpcDenied(anon, 'queue_new_event', {
    p_event_id: ZERO_UUID, p_event_name: 'verify-access', p_event_date: new Date().toISOString(),
    p_send_push: false, p_send_email: false,
  });
  // Funzioni interne di sola lettura: rappresentano tutte quelle chiuse dal "tutto chiuso".
  await expectRpcNotExposed(anon, 'count_attended_lessons', { p_client_id: ZERO_UUID });
  await expectRpcNotExposed(anon, 'get_notification_channel', { p_client_id: ZERO_UUID, p_category: 'birthday' });
  // Sessione 5: le funzioni del webhook e dell'invio ricevute sono solo per le edge function.
  // Payload vuoti: anche se fossero aperte, non scriverebbero nulla.
  await expectRpcDenied(anon, 'stripe_apply_payment_state', { p_payload: {} });
  await expectRpcDenied(anon, 'receipt_claim_send', { p_receipt_id: ZERO_UUID, p_resend: false });
  await expectRpcDenied(anon, 'stripe_checkout_expired', { p_checkout_session_id: 'cs_verify_access' });
  await expectRpcDenied(anon, 'prepare_my_fee_payment', {});
  // Sessione 6: lista d'attesa lato staff, questionario dopo la prova, job interni
  await expectRpcDenied(anon, 'staff_add_to_waitlist', { p_lesson_id: ZERO_UUID, p_client_id: ZERO_UUID });
  await expectRpcDenied(anon, 'staff_remove_from_waitlist', { p_waitlist_id: ZERO_UUID });
  await expectRpcDenied(anon, 'submit_trial_feedback', { p_trial_id: ZERO_UUID, p_rating: 5 });
  await expectRpcNotExposed(anon, 'cron_site_rebuild', {});
  await expectRpcNotExposed(anon, 'cron_waitlist', {});

  console.log('\n▸ anon — dati pubblici che il sito deve continuare a leggere');
  for (const t of ['public_site_activities', 'public_site_events', 'public_site_operators', 'public_site_schedule',
    'public_site_pricing', 'activities', 'lessons', 'events', 'plans', 'operators', 'feature_flags',
    // Sessione 3: gruppi e luoghi alimentano le pagine del sito e la SEO per comune
    'public_site_groups', 'public_site_locations', 'activity_groups', 'locations']) {
    const c = await count(anon, t);
    check(`anon: ${t} leggibile`, c.status === 200 || c.status === 206, `HTTP ${c.status}`);
  }
  await expectRpcOk(anon, 'get_events_booking_counts', { p_event_ids: [ZERO_UUID] });
}

// ── Solo in locale: utenti e dati di prova ────────────────────────────────────────────────────

const stamp = Date.now();
const PASSWORD = 'verify-access-Pw1!';
const iso = (d) => d.toISOString();
const days = (n, h = 18) => { const d = new Date(); d.setDate(d.getDate() + n); d.setHours(h, 0, 0, 0); return d; };

async function login(email) {
  const r = await call(anon, 'POST', '/auth/v1/token?grant_type=password', { email, password: PASSWORD });
  if (r.status !== 200) throw new Error(`login ${email}: ${describe(r)}`);
  return r.json;
}

/** Utente staff creato come dalla dashboard di Supabase, con il ruolo assegnato via SQL. */
async function staffUser(label, role) {
  const email = `verify-${label}-${stamp}@example.test`;
  const created = await call(service, 'POST', '/auth/v1/admin/users',
    { email, password: PASSWORD, email_confirm: true, user_metadata: { full_name: `Verifica ${label}` } });
  if (created.status !== 200) throw new Error(`creazione ${label}: ${describe(created)}`);
  sql(`update public.profiles set role = '${role}' where id = '${created.json.id}' returning id`);
  const session = await login(email);
  return { name: label, apikey: cfg.anonKey, token: session.access_token, userId: created.json.id, email };
}

async function one(r, what) {
  if (r.status >= 300 || !Array.isArray(r.json) || r.json.length !== 1) throw new Error(`${what}: ${describe(r)}`);
  return r.json[0];
}

/** SQL sul DB locale come postgres: solo per preparare i dati di prova, mai per le verifiche. */
function sql(query) {
  const r = spawnSync('npx', ['supabase', 'db', 'query', '--local', '-o', 'json', query], { encoding: 'utf-8' });
  const start = (r.stdout || '').indexOf('{');
  if (r.status !== 0 || start < 0) throw new Error(`SQL: ${(r.stderr || r.stdout).slice(0, 300)}`);
  return JSON.parse(r.stdout.slice(start)).rows;
}

async function localChecks() {
  console.log('\n▸ dati di prova (SQL come postgres)');
  const [fx] = sql(`
    with a as (
      insert into public.activities (name, discipline, is_active)
      values ('Verifica ${stamp}', 'verifica-${stamp}', true) returning id
    ), o as (
      insert into public.operators (name, role, is_active)
      values ('Operatrice verifica ${stamp}', 'Insegnante', true) returning id
    ), p as (
      insert into public.plans (name, price_cents, validity_days, entries, is_active)
      values ('10 ingressi verifica ${stamp}', 10000, 60, 10, true) returning id
    ), l1 as (
      insert into public.lessons (activity_id, operator_id, capacity, starts_at, ends_at)
      select a.id, o.id, 10, '${iso(days(1))}', '${iso(days(1, 19))}' from a, o returning id
    ), l2 as (
      insert into public.lessons (activity_id, operator_id, capacity, starts_at, ends_at)
      select a.id, o.id, 10, '${iso(days(3))}', '${iso(days(3, 19))}' from a, o returning id
    ), e as (
      insert into public.events (name, starts_at, capacity, is_active)
      values ('Evento verifica ${stamp}', '${iso(days(7))}', 20, true) returning id, name, starts_at
    ), cm as (
      insert into public.compensation_models (name, min_guaranteed_cents)
      values ('Modello verifica ${stamp}', 2000) returning id
    ), vol as (
      insert into public.volunteers (full_name, started_on)
      values ('Volontaria verifica ${stamp}', current_date) returning id
    ), vr as (
      insert into public.volunteer_reimbursements
        (volunteer_id, spent_on, amount_cents, description, attachment_path)
      select vol.id, current_date, 1500, 'Spesa di verifica', 'verifica/${stamp}.pdf'
      from vol returning id
    )
    select a.id activity_id, o.id operator_id, p.id plan_id, l1.id lesson_id, l2.id lesson2_id,
           e.id event_id, e.name event_name, e.starts_at event_starts_at
    from a, o, p, l1, l2, e`);
  const activity = { id: fx.activity_id };
  const operatorRow = { id: fx.operator_id };
  const plan = { id: fx.plan_id };
  const lesson = { id: fx.lesson_id };
  const lesson2 = { id: fx.lesson2_id };
  const event = { id: fx.event_id, name: fx.event_name, starts_at: fx.event_starts_at };
  console.log('  dati creati');

  console.log('\n▸ cliente — registrazione e login (webapp)');
  const clientEmail = `verify-cliente-${stamp}@example.test`;
  const signup = await call(anon, 'POST', '/auth/v1/signup',
    { email: clientEmail, password: PASSWORD, data: { full_name: 'Cliente Verifica' } });
  check('registrazione dalla webapp', signup.status === 200 && !!signup.json?.access_token, describe(signup));
  const session = await login(clientEmail);
  check('login con email e password', !!session.access_token, 'nessun token');
  const cliente = { name: 'cliente', apikey: cfg.anonKey, token: session.access_token, userId: session.user.id };

  const profile = await select(cliente, `profiles?id=eq.${cliente.userId}&select=role,full_name`);
  check('cliente: il profilo esiste con ruolo user', profile.json?.[0]?.role === 'user', describe(profile));
  const myClient = await rpc(cliente, 'get_my_client_id');
  check('cliente: la registrazione ha creato la scheda cliente', typeof myClient.json === 'string', describe(myClient));
  const clientId = myClient.json;

  const staff = await staffUser('operatrice', 'operator');
  const admin = await staffUser('admin', 'admin');

  console.log('\n▸ operatrice — gestionale');
  const clientsSeen = await count(staff, 'clients');
  check('operatrice: vede le schede clienti', clientsSeen.status === 200 && clientsSeen.n >= 1, `HTTP ${clientsSeen.status} n=${clientsSeen.n}`);
  const newClient = await insert(staff, 'clients', { full_name: `Cliente da gestionale ${stamp}` });
  check('operatrice: crea una scheda cliente', newClient.status === 201, describe(newClient));
  const sub = await insert(staff, 'subscriptions', {
    client_id: clientId, plan_id: plan.id, status: 'active',
    started_at: iso(new Date()).slice(0, 10), expires_at: iso(days(60)).slice(0, 10),
  });
  check('operatrice: crea un abbonamento', sub.status === 201, describe(sub));
  const subscriptionId = sub.json?.[0]?.id;

  const staffBook = await expectRpcOk(staff, 'staff_book_lesson',
    { p_lesson_id: lesson2.id, p_client_id: clientId, p_subscription_id: subscriptionId });
  await expectRpcOk(staff, 'staff_cancel_booking', { p_booking_id: staffBook?.booking_id });
  const rebook = await expectRpcOk(staff, 'staff_book_lesson',
    { p_lesson_id: lesson2.id, p_client_id: clientId, p_subscription_id: subscriptionId }, 'staff_book_lesson (di nuovo)');
  await expectRpcOk(staff, 'staff_update_booking_status', { p_booking_id: rebook?.booking_id, p_status: 'attended' },
    'staff_update_booking_status → presente');

  const individual = await insert(staff, 'lessons', {
    activity_id: activity.id, operator_id: operatorRow.id, capacity: 1, is_individual: true,
    assigned_client_id: clientId, starts_at: iso(days(2)), ends_at: iso(days(2, 19)),
  });
  check('operatrice: crea una lezione individuale', individual.status === 201, describe(individual));
  // Il trigger scatta quando cambiano cliente, abbonamento o tipo: qui cambia l'abbonamento, e il
  // cliente ha l'account app — il caso che prima andava in errore (colonne user_id inesistenti).
  const individualId = individual.json?.[0]?.id;
  const indUpd = await patch(staff, `lessons?id=eq.${individualId}`, { assigned_subscription_id: subscriptionId });
  check('operatrice: cambia l\'abbonamento di una lezione individuale di un cliente con account app',
    indUpd.status === 200 && indUpd.json?.length === 1, describe(indUpd));
  const indBooking = await select(staff, `bookings?select=subscription_id&lesson_id=eq.${individualId}&status=eq.booked`);
  check('operatrice: la prenotazione della lezione individuale usa il nuovo abbonamento',
    indBooking.json?.[0]?.subscription_id === subscriptionId, describe(indBooking));

  const ann = await insert(staff, 'announcements',
    { title: `Annuncio verifica ${stamp}`, body: 'verifica', category: 'general', is_active: true, starts_at: iso(new Date()) });
  check('operatrice: pubblica un annuncio (trigger notify_new_announcement)', ann.status === 201, describe(ann));
  const actUpd = await patch(staff, `activities?id=eq.${activity.id}`, { description: 'aggiornata dalla verifica' });
  check('operatrice: modifica un\'attività (trigger update_activity_slug)', actUpd.status === 200 && actUpd.json?.length === 1, describe(actUpd));
  await expectRpcOk(staff, 'queue_new_event', {
    p_event_id: event.id, p_event_name: event.name, p_event_date: event.starts_at, p_send_push: false, p_send_email: false,
  }, 'queue_new_event (senza canali)');
  const evBook = await insert(staff, 'event_bookings', { event_id: event.id, client_id: clientId, status: 'booked' });
  check('operatrice: iscrive un cliente a un evento', evBook.status === 201, describe(evBook));
  const staffEventBookingId = evBook.json?.[0]?.id;
  await expectRpcOk(staff, 'staff_cancel_event_booking', { p_booking_id: staffEventBookingId });

  await expectRpcDenied(staff, 'get_monthly_revenue_by_client', FINANCE_1900);

  // Sessione 3 — le operatrici registrano gli incassi ma non vedono le Finanze (E3)
  const staffPay = await rpc(staff, 'staff_register_payment', {
    p_payload: { kind: 'other', amount_cents: 500, method: 'cash', source: 'studio' },
  });
  check('operatrice: registra un incasso in studio',
    staffPay.status === 200 && staffPay.json?.ok === true, describe(staffPay));

  // Sessione 4 — "da saldare", quota e stato di iscrizione, sempre senza vedere le Finanze
  const pending = await rpc(staff, 'staff_register_payment', {
    p_payload: { kind: 'other', amount_cents: 700, method: 'cash', source: 'studio', status: 'pending' },
  });
  check('operatrice: registra un incasso da saldare',
    pending.status === 200 && pending.json?.ok === true, describe(pending));
  const settled = await rpc(staff, 'staff_settle_transaction', {
    p_transaction_id: pending.json?.transaction_id, p_method: 'bank_transfer', p_issue_receipt: false,
  });
  check('operatrice: salda un incasso da saldare',
    settled.status === 200 && settled.json?.ok === true, describe(settled));
  const statuses = await rpc(staff, 'staff_get_member_statuses', { p_client_ids: [clientId] });
  check('operatrice: legge lo stato di iscrizione dei clienti',
    statuses.status === 200 && typeof statuses.json?.statuses?.[clientId] === 'string', describe(statuses));
  await expectRowsHidden(staff, 'compensation_models');
  await expectRowsHidden(staff, 'volunteer_reimbursements');
  // Sessione 6 — lista d'attesa dal gestionale (qui la lezione non è piena: la regola risponde)
  const wlNotFull = await rpc(staff, 'staff_add_to_waitlist', { p_lesson_id: lesson.id, p_client_id: clientId });
  check('operatrice: mette in lista d\'attesa (solo per le lezioni piene)',
    wlNotFull.status === 200 && wlNotFull.json?.reason === 'LESSON_NOT_FULL', describe(wlNotFull));
  const wlRemove = await rpc(staff, 'staff_remove_from_waitlist', { p_waitlist_id: ZERO_UUID });
  check('operatrice: toglie dalla lista d\'attesa',
    wlRemove.status === 200 && wlRemove.json?.reason === 'NOT_IN_WAITLIST', describe(wlRemove));
  const staffTrials = await count(staff, 'trials');
  check('operatrice: legge le prove (pagina Prove)', staffTrials.status === 200 || staffTrials.status === 206, `HTTP ${staffTrials.status}`);
  await expectReadDenied(staff, 'site_rebuild_state');
  // Sessione 5 — i pagamenti online e i loro rimborsi sono cosa delle Finanze. Una riga "aperta" di
  // prova (nessun pagamento, nessun incasso) serve a provare che esiste ma l'operatrice non la vede.
  await insert(service, 'stripe_payments', {
    purpose: 'donation', amount_cents: 500, status: 'created', source: 'site', checkout_session_id: `cs_verify_${stamp}`,
  });
  await expectRowsHidden(staff, 'stripe_payments');
  const staffStripeRefund = await rpc(staff, 'staff_prepare_stripe_refund', { p_transaction_id: ZERO_UUID, p_amount_cents: 100 });
  check('operatrice: non rimborsa pagamenti online',
    staffStripeRefund.status === 200 && staffStripeRefund.json?.reason === 'NOT_FINANCE', describe(staffStripeRefund));
  await expectRpcDenied(staff, 'calculate_compensation_v2', { ...FINANCE_1900, p_operator_id: null });
  await expectRpcDenied(staff, 'calculate_operator_compensation', { ...FINANCE_1900, p_operator_id: null });
  await expectReadDenied(staff, 'financial_monthly_summary');
  const staffSelfRole = await patch(staff, `profiles?id=eq.${staff.userId}`, { role: 'admin' });
  check('operatrice: non può darsi il ruolo admin', isDenied(staffSelfRole), describe(staffSelfRole));
  const staffOtherRole = await patch(staff, `profiles?id=eq.${cliente.userId}`, { role: 'operator' });
  check('operatrice: non può cambiare il ruolo di un cliente', isDenied(staffOtherRole), describe(staffOtherRole));

  console.log('\n▸ cliente — webapp');
  const edit = await patch(cliente, `profiles?id=eq.${cliente.userId}`, { full_name: 'Cliente Verificata', phone: '3330000000' });
  check('cliente: modifica nome e telefono', edit.status === 200 && edit.json?.[0]?.full_name === 'Cliente Verificata', describe(edit));
  const selfAdmin = await patch(cliente, `profiles?id=eq.${cliente.userId}`, { role: 'admin' });
  check('cliente: non può darsi il ruolo admin', isDenied(selfAdmin), describe(selfAdmin));
  const selfEmail = await patch(cliente, `profiles?id=eq.${cliente.userId}`, { email: `altra-${stamp}@example.test` });
  check('cliente: non può cambiare l\'email del profilo', isDenied(selfEmail), describe(selfEmail));
  const roleAfter = await select(cliente, `profiles?id=eq.${cliente.userId}&select=role`);
  check('cliente: il ruolo è rimasto user', roleAfter.json?.[0]?.role === 'user', describe(roleAfter));
  const ownClients = await count(cliente, 'clients');
  check('cliente: vede solo la propria scheda', ownClients.n === 1, `righe visibili: ${ownClients.n}`);

  const booked = await expectRpcOk(cliente, 'book_lesson', { p_lesson_id: lesson.id, p_subscription_id: subscriptionId });
  const myBookings = await select(cliente, `bookings?select=id,status&lesson_id=eq.${lesson.id}`);
  check('cliente: vede la sua prenotazione', myBookings.json?.[0]?.status === 'booked', describe(myBookings));
  await expectRpcOk(cliente, 'cancel_booking', { p_booking_id: booked?.booking_id });
  const directBooking = await insert(cliente, 'bookings', { lesson_id: lesson.id, client_id: clientId, status: 'booked' });
  check('cliente: non può inserire prenotazioni saltando book_lesson', isDenied(directBooking), describe(directBooking));
  const directEvent = await insert(cliente, 'event_bookings', { event_id: event.id, client_id: clientId, status: 'booked' });
  check('cliente: non può iscriversi a un evento saltando book_event', isDenied(directEvent), describe(directEvent));
  const evBooked = await expectRpcOk(cliente, 'book_event', { p_event_id: event.id });
  const directCancel = await patch(cliente, `event_bookings?id=eq.${evBooked?.booking_id}`, { status: 'canceled' });
  check('cliente: non può disdire un evento saltando cancel_event_booking',
    isDenied(directCancel) || (directCancel.status === 200 && directCancel.json?.length === 0), describe(directCancel));
  await expectRpcOk(cliente, 'cancel_event_booking', { p_booking_id: evBooked?.booking_id });

  await expectRpcOk(cliente, 'register_device_token',
    { p_token: `ExponentPushToken[verify-${stamp}]`, p_platform: 'web', p_device_id: 'verify', p_app_version: '0' });
  const tokens = await count(cliente, 'device_tokens');
  check('cliente: vede il proprio token push', tokens.n === 1, `righe visibili: ${tokens.n}`);
  await expectRpcOk(cliente, 'deactivate_device_token', { p_token: `ExponentPushToken[verify-${stamp}]` });
  await expectRpcOk(cliente, 'get_my_notifications', { p_limit: 20, p_offset: 0 });
  await expectRpcOk(cliente, 'get_unread_notifications_count');
  const logs = await select(cliente, `notification_logs?select=id&client_id=eq.${clientId}`);
  check('cliente: legge le proprie notifiche', logs.status === 200, describe(logs));

  await expectRpcDenied(cliente, 'get_monthly_revenue_by_client', FINANCE_1900);

  // Sessione 3 — soci e incassi
  await expectRpcOk(cliente, 'get_my_membership_status', {});
  const cardNoMember = await rpc(cliente, 'get_my_member_card', {});
  check('cliente: senza iscrizione la tessera non esiste',
    cardNoMember.status === 200 && cardNoMember.json?.reason === 'NOT_A_MEMBER', describe(cardNoMember));
  const payAsClient = await rpc(cliente, 'staff_register_payment', { p_payload: { amount_cents: 100 } });
  check('cliente: non può registrare incassi',
    payAsClient.status === 200 && payAsClient.json?.reason === 'NOT_STAFF', describe(payAsClient));
  const settleAsClient = await rpc(cliente, 'staff_settle_transaction', { p_transaction_id: ZERO_UUID });
  check('cliente: non può saldare incassi',
    settleAsClient.status === 200 && settleAsClient.json?.reason === 'NOT_STAFF', describe(settleAsClient));
  const feeAsClient = await rpc(cliente, 'staff_pay_member_fee', { p_client_id: clientId, p_year: 2026 });
  check('cliente: non può incassare quote',
    feeAsClient.status === 200 && feeAsClient.json?.reason === 'NOT_STAFF', describe(feeAsClient));
  const statusesAsClient = await rpc(cliente, 'staff_get_member_statuses', { p_client_ids: [clientId] });
  check('cliente: non legge lo stato di iscrizione degli altri',
    statusesAsClient.status === 200 && statusesAsClient.json?.reason === 'NOT_STAFF', describe(statusesAsClient));
  await expectRowsHidden(cliente, 'transactions');
  await expectRowsHidden(cliente, 'compensation_models');
  // Sessione 5 — pagare la propria quota: il cliente chiede, il database decide
  const myFee = await rpc(cliente, 'prepare_my_fee_payment', {});
  check('cliente: chiede se può pagare la quota online',
    myFee.status === 200 && typeof myFee.json?.reason === 'string', describe(myFee));
  const refundAsClient = await rpc(cliente, 'staff_prepare_stripe_refund', { p_transaction_id: ZERO_UUID, p_amount_cents: 100 });
  check('cliente: non può preparare rimborsi',
    refundAsClient.status === 200 && refundAsClient.json?.reason === 'NOT_FINANCE', describe(refundAsClient));
  await expectRpcDenied(cliente, 'stripe_apply_payment_state', { p_payload: {} });
  await expectRpcDenied(cliente, 'receipt_mark_sent', { p_receipt_id: ZERO_UUID, p_to: 'x@example.test', p_error: null });
  await expectRpcNotExposed(cliente, 'call_edge_function', { p_function_name: '__verify_access_noop__', p_body: {} });
  await expectRpcDenied(cliente, 'queue_new_event', {
    p_event_id: ZERO_UUID, p_event_name: 'x', p_event_date: iso(new Date()), p_send_push: false, p_send_email: false,
  });
  await expectRpcNotExposed(cliente, 'create_user_profile',
    { user_id: cliente.userId, full_name: 'x', phone: null, role: 'admin' });
  await expectReadDenied(cliente, 'financial_monthly_summary');
  // Sessione 6 — la lista d'attesa la gestisce lo staff; il questionario vale solo per le proprie prove
  const wlAsClient = await rpc(cliente, 'staff_add_to_waitlist', { p_lesson_id: lesson.id, p_client_id: clientId });
  check('cliente: non mette altrə in lista d\'attesa',
    wlAsClient.status === 200 && wlAsClient.json?.reason === 'NOT_STAFF', describe(wlAsClient));
  const trialFb = await rpc(cliente, 'submit_trial_feedback', { p_trial_id: ZERO_UUID, p_rating: 5 });
  check('cliente: il questionario si manda solo per una propria prova',
    trialFb.status === 200 && trialFb.json?.reason === 'TRIAL_NOT_FOUND', describe(trialFb));
  await expectReadDenied(cliente, 'site_rebuild_state');

  console.log('\n▸ admin — gestionale e Finanze');
  const month = { p_month_start: iso(new Date()).slice(0, 8) + '01', p_month_end: iso(days(30)).slice(0, 10) };
  await expectRpcOk(admin, 'calculate_operator_compensation', { ...month, p_operator_id: null });
  await expectRpcOk(admin, 'get_monthly_revenue_by_client', month);
  await expectRpcOk(admin, 'get_monthly_revenue_by_plan', month);
  const expenses = await select(admin, 'expenses?select=id&limit=1');
  check('admin: legge le spese', expenses.status === 200, describe(expenses));
  const adminRefund = await rpc(admin, 'staff_prepare_stripe_refund', { p_transaction_id: ZERO_UUID, p_amount_cents: 100 });
  check('admin: prepara i rimborsi online (qui su un incasso inesistente)',
    adminRefund.status === 200 && adminRefund.json?.reason === 'TRANSACTION_NOT_FOUND', describe(adminRefund));
  const adminClients = await count(admin, 'clients');
  check('admin: vede le schede clienti', adminClients.n >= 2, `righe visibili: ${adminClients.n}`);
  const promoted = await expectRpcOk(admin, 'promote_profile_to_operator', { p_profile_id: cliente.userId });
  check('admin: la promozione a operatrice ha effetto', promoted?.role === 'operator', JSON.stringify(promoted));

  console.log('\n▸ service_role — edge function e automazioni');
  await expectRpcOk(service, 'queue_birthday', {}, 'queue_birthday (schedule-notifications)');
  const svcToken = await insert(service, 'device_tokens',
    { client_id: clientId, expo_push_token: `ExponentPushToken[svc-${stamp}]`, platform: 'web', is_active: true });
  check('service_role: registra un token push (register-push-token)', svcToken.status === 201, describe(svcToken));
  const svcState = await rpc(service, 'stripe_apply_payment_state', { p_payload: {} });
  check('service_role: il webhook di Stripe raggiunge stripe_apply_payment_state',
    svcState.status === 200 && svcState.json?.reason === 'MISSING_PAYMENT_INTENT', describe(svcState));
  const queue = await count(service, 'notification_queue');
  check('service_role: legge la coda notifiche (process-notification-queue)', queue.status === 200, `HTTP ${queue.status}`);
  const rebuildReport = await patch(service, 'site_rebuild_state?id=eq.true', { reported_at: iso(new Date()), last_ok: null });
  check('service_role: scrive l\'esito della ricostruzione del sito (site-rebuild)',
    rebuildReport.status === 200 && rebuildReport.json?.length === 1, describe(rebuildReport));

  // Scritture delle edge function con service_role: fino alla sessione 1 fallivano per permessi mancanti.
  const unsub = await patch(service, `clients?id=eq.${clientId}`, { newsletter_subscribed: false });
  check('service_role: disiscrizione dalla newsletter (unsubscribe-newsletter)', unsub.status === 200 && unsub.json?.length === 1, describe(unsub));
  const bounce = await patch(service, `clients?id=eq.${clientId}`, { email_bounced: true, email_bounced_at: iso(new Date()) });
  check('service_role: bounce permanente segnato (ses-webhook)', bounce.status === 200 && bounce.json?.length === 1, describe(bounce));
  const delBookings = await patch(service, `bookings?client_id=eq.${clientId}&status=eq.booked`, { status: 'canceled' });
  check('service_role: annulla le prenotazioni di chi elimina l\'account (delete-account)', delBookings.status === 200, describe(delBookings));
  const delEvents = await patch(service, `event_bookings?client_id=eq.${clientId}&status=eq.booked`, { status: 'canceled' });
  check('service_role: annulla le iscrizioni agli eventi (delete-account)', delEvents.status === 200, describe(delEvents));
  const delClient = await patch(service, `clients?id=eq.${clientId}`,
    { deleted_at: iso(new Date()), is_active: false, notes: 'Account eliminato (verifica)' });
  check('service_role: archivia la scheda cliente (delete-account)', delClient.status === 200 && delClient.json?.length === 1, describe(delClient));
  const delProfile = await patch(service, `profiles?id=eq.${cliente.userId}`,
    { deleted_at: iso(new Date()), full_name: 'Account eliminato', phone: null, avatar_url: null });
  check('service_role: archivia il profilo (delete-account)', delProfile.status === 200 && delProfile.json?.length === 1, describe(delProfile));
}

// ── Main ──────────────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`🔒 verify-access — ${PROD ? 'PRODUZIONE (solo anon, nessun dato personale)' : 'LOCALE'} · ${cfg.url}`);
  await anonChecks();
  if (!PROD) await localChecks();

  const failed = results.filter(r => !r.ok);
  console.log(`\n${failed.length === 0 ? '✅' : '❌'} ${results.length - failed.length}/${results.length} controlli con l'esito atteso`);
  if (failed.length) {
    for (const f of failed) console.log(`   ❌ ${f.label}`);
    process.exit(1);
  }
}

main().catch(err => { console.error('❌ verify-access errore:', err.message); process.exit(1); });
