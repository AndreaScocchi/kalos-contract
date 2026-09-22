#!/usr/bin/env node

/**
 * ops-health — controlla che la coda delle notifiche funzioni. Vedi BACKUP.md.
 *
 *     node scripts/backup/ops-health.mjs
 *
 * Variabili: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Soglie facoltative:
 *   QUEUE_STUCK_MINUTES  (30)  una notifica pronta e non ancora elaborata dopo questi minuti = coda ferma
 *   QUEUE_FAILED_HOURS   (2)   finestra in cui contare le notifiche fallite (= cadenza del controllo)
 *   QUEUE_FAILED_MAX     (0)   fallite ammesse nella finestra; in condizioni normali sono zero
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
const ago = (ms) => new Date(Date.now() - ms).toISOString();

async function count(filter) {
  const res = await fetch(`${url}/rest/v1/notification_queue?select=id&${filter}`, {
    method: 'HEAD',
    headers: { apikey: key, Authorization: `Bearer ${key}`, Prefer: 'count=exact' },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} leggendo notification_queue`);
  return Number((res.headers.get('content-range') || '').split('/')[1]);
}

async function main() {
  const stuckSince = ago(stuckMinutes * 60_000);
  const failedSince = ago(failedHours * 3_600_000);
  const stuck = await count(`status=eq.pending&attempts=lt.3&scheduled_for=lt.${stuckSince}`);
  const failed = await count(`status=eq.failed&or=(processed_at.gt.${failedSince},last_attempt_at.gt.${failedSince})`);

  const problems = [];
  if (stuck > 0) problems.push(`${stuck} notifiche pronte da più di ${stuckMinutes} minuti e mai elaborate: la coda è ferma (cron o edge function process-notification-queue).`);
  if (failed > failedMax) problems.push(`${failed} notifiche fallite nelle ultime ${failedHours} ore (dettagli in notification_queue.error_message).`);

  if (problems.length === 0) {
    console.log(`✅ Coda notifiche: nessuna ferma da più di ${stuckMinutes} minuti, ${failed} fallite nelle ultime ${failedHours} ore.`);
    return;
  }
  for (const p of problems) console.log(`❌ ${p}`);
  process.exit(1);
}

main().catch(err => { console.log(`❌ Controllo della coda non riuscito: ${err.message}`); process.exit(1); });
