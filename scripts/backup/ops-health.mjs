#!/usr/bin/env node

/**
 * ops-health — controlla che la coda delle notifiche e i pagamenti online funzionino. Vedi BACKUP.md.
 *
 *     node scripts/backup/ops-health.mjs
 *
 * Variabili: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Soglie facoltative:
 *   QUEUE_STUCK_MINUTES  (30)  una notifica pronta e non ancora elaborata dopo questi minuti = coda ferma
 *   QUEUE_FAILED_HOURS   (2)   finestra in cui contare le notifiche fallite (= cadenza del controllo)
 *   QUEUE_FAILED_MAX     (0)   fallite ammesse nella finestra; in condizioni normali sono zero
 *   STRIPE_STUCK_MINUTES (60)  un evento di Stripe non elaborato dopo questi minuti = webhook in difficoltà
 *                              (Stripe riprova da solo, ma se l'errore è nostro non smette di fallire)
 *
 * Pagamenti online (sessione 5): eventi di Stripe non elaborati, contestazioni (chargeback) arrivate
 * nella finestra, ricevute di pagamenti online non inviate per email da più di un'ora. Finché Stripe
 * non è attivo sono tutti zero.
 *
 * Ricostruzione del sito (sessione 6): l'ultima chiamata al build hook di Netlify è fallita
 * (`site_rebuild_state.last_ok = false`, motivo in `last_error`).
 *
 * Legge solo conteggi (i log delle Actions sono pubblici). Stampa l'esito; esce con 1 se c'è un
 * problema, e il workflow manda l'avviso.
 */

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error('❌ Servono SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(2);
}

const stuckMinutes = Number(process.env.QUEUE_STUCK_MINUTES ?? 30);
const failedHours = Number(process.env.QUEUE_FAILED_HOURS ?? 2);
const failedMax = Number(process.env.QUEUE_FAILED_MAX ?? 0);
const stripeStuckMinutes = Number(process.env.STRIPE_STUCK_MINUTES ?? 60);
const ago = (ms) => new Date(Date.now() - ms).toISOString();

async function count(filter, table = 'notification_queue', select = 'id', { optional = false } = {}) {
  const res = await fetch(`${url}/rest/v1/${table}?select=${select}&${filter}`, {
    method: 'HEAD',
    headers: { apikey: key, Authorization: `Bearer ${key}`, Prefer: 'count=exact' },
  });
  // Una tabella nuova non ancora in produzione (fra il merge e il db push) non è un guasto
  if (optional && res.status === 404) return 0;
  if (!res.ok) throw new Error(`HTTP ${res.status} leggendo ${table}`);
  return Number((res.headers.get('content-range') || '').split('/')[1]);
}

async function main() {
  const stuckSince = ago(stuckMinutes * 60_000);
  const failedSince = ago(failedHours * 3_600_000);
  const stuck = await count(`status=eq.pending&attempts=lt.3&scheduled_for=lt.${stuckSince}`);
  const failed = await count(`status=eq.failed&or=(processed_at.gt.${failedSince},last_attempt_at.gt.${failedSince})`);

  const stripeSince = ago(stripeStuckMinutes * 60_000);
  const stripeStuck = await count(`processed_at=is.null&received_at=lt.${stripeSince}`, 'stripe_events');
  const disputes = await count(`type=like.charge.dispute.*&received_at=gt.${failedSince}`, 'stripe_events');
  const unsentReceipts = await count(
    `sent_at=is.null&voided_at=is.null&issued_at=lt.${stripeSince}&transaction.method=eq.stripe`,
    'receipts', 'id,transaction:transactions!inner(method)',
  );
  const rebuildFailed = await count('last_ok=is.false', 'site_rebuild_state', 'id', { optional: true });

  const problems = [];
  if (stripeStuck > 0) problems.push(`${stripeStuck} eventi di Stripe non elaborati da più di ${stripeStuckMinutes} minuti (dettagli in stripe_events.error_message): pagamenti o rimborsi potrebbero mancare dal registro.`);
  if (disputes > 0) problems.push(`${disputes} eventi di contestazione (chargeback) nelle ultime ${failedHours} ore: vanno gestiti dalla dashboard di Stripe.`);
  if (unsentReceipts > 0) problems.push(`${unsentReceipts} ricevute di pagamenti online non inviate per email da più di ${stripeStuckMinutes} minuti (motivo in receipts.send_error): si reinviano dal gestionale, Incassi → Ricevute.`);
  if (stuck > 0) problems.push(`${stuck} notifiche pronte da più di ${stuckMinutes} minuti e mai elaborate: la coda è ferma (cron o edge function process-notification-queue).`);
  if (rebuildFailed > 0) problems.push('L\'ultima ricostruzione del sito su Netlify non è partita (motivo in site_rebuild_state.last_error): le modifiche a luoghi, gruppi, attività ed eventi non sono ancora nelle pagine del sito.');
  if (failed > failedMax) problems.push(`${failed} notifiche fallite nelle ultime ${failedHours} ore (dettagli in notification_queue.error_message).`);

  if (problems.length === 0) {
    console.log(`✅ Coda notifiche: nessuna ferma da più di ${stuckMinutes} minuti, ${failed} fallite nelle ultime ${failedHours} ore.`);
    console.log('✅ Pagamenti online: nessun evento Stripe indietro, nessuna contestazione, nessuna ricevuta online non inviata.');
    console.log('✅ Ricostruzione del sito: nessun errore dall\'ultima chiamata al build hook.');
    return;
  }
  for (const p of problems) console.log(`❌ ${p}`);
  process.exit(1);
}

main().catch(err => { console.log(`❌ Controllo della coda e dei pagamenti non riuscito: ${err.message}`); process.exit(1); });
