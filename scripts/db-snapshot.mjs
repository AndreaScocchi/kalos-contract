#!/usr/bin/env node

/**
 * db-snapshot — snapshot logico COMPLETO della prod, da eseguire PRIMA di ogni `db push`.
 * È la nostra rete di sicurezza "backup" senza piano Pro/PITR (vedi NEW_APP_PLAN.md §3.bis).
 *
 * Usa `supabase db dump` (pg_dump bundlato nel CLI). Scrive in backups/<UTC>.sql (gitignored).
 * In caso di migrazione andata male, si ripristina da qui.
 *
 * Connessione: usa il progetto LINKATO (`supabase link`) oppure SUPABASE_DB_URL.
 *
 * USO:
 *     node scripts/db-snapshot.mjs              # snapshot completo (ruoli + schema + dati)
 *     node scripts/db-snapshot.mjs --data-only  # solo dati
 *
 * NB: richiede Supabase CLI installato e progetto linkato/credenziali. Da validare nella
 * sessione con Docker/credenziali prod attive.
 */

import { mkdir } from 'fs/promises';
import { join } from 'path';
import { spawnSync } from 'child_process';

const BACKUPS_DIR = join(process.cwd(), 'backups');

function utcStamp() {
  // Date.now()/new Date() non sono disponibili in alcuni runtime; usiamo l'orario di sistema via shell.
  const r = spawnSync('date', ['-u', '+%Y%m%dT%H%M%SZ'], { encoding: 'utf-8' });
  return (r.stdout || 'snapshot').trim();
}

async function main() {
  const dataOnly = process.argv.includes('--data-only');
  await mkdir(BACKUPS_DIR, { recursive: true });
  const outFile = join(BACKUPS_DIR, `${utcStamp()}${dataOnly ? '-data' : '-full'}.sql`);

  const args = ['db', 'dump', '-f', outFile];
  if (dataOnly) args.push('--data-only');
  if (process.env.SUPABASE_DB_URL) args.push('--db-url', process.env.SUPABASE_DB_URL);
  else args.push('--linked');

  console.log(`📦 Snapshot prod → ${outFile}`);
  const res = spawnSync('npx', ['--yes', 'supabase', ...args], { stdio: 'inherit' });
  if (res.status !== 0) {
    console.error('❌ Snapshot fallito. Assicurati di aver fatto `supabase link` o di aver impostato SUPABASE_DB_URL.');
    process.exit(1);
  }
  console.log(`✅ Snapshot completato: ${outFile}`);
  console.log('   Conservalo finché la migrazione non è verificata in prod.');
}

main().catch(err => { console.error('❌ db-snapshot errore:', err.message); process.exit(1); });
