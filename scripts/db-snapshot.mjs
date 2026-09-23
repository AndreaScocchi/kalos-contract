#!/usr/bin/env node

/**
 * db-snapshot — snapshot logico COMPLETO della prod, da eseguire PRIMA di ogni `db push`.
 * È la nostra rete di sicurezza "backup" senza piano Pro/PITR (vedi NEW_APP_PLAN.md §3.bis).
 *
 * Usa `supabase db dump` (pg_dump bundlato nel CLI). Scrive in backups/ (gitignored) tre file:
 * <UTC>-roles.sql, <UTC>-schema.sql, <UTC>-data.sql. In caso di migrazione andata male, si
 * ripristina da qui (procedura in BACKUP.md).
 *
 * Fino al 2026-09-23 lo snapshot "completo" lanciava un solo `db dump` senza opzioni, che salva
 * SOLO lo schema: i dati non c'erano. Ora ruoli, schema e dati sono tre dump separati, e se uno
 * fallisce lo snapshot fallisce.
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

function dump(outFile, extraArgs) {
  const args = ['db', 'dump', '-f', outFile, ...extraArgs];
  if (process.env.SUPABASE_DB_URL) args.push('--db-url', process.env.SUPABASE_DB_URL);
  else args.push('--linked');
  console.log(`📦 ${outFile}`);
  const res = spawnSync('npx', ['--yes', 'supabase', ...args], { stdio: 'inherit' });
  return res.status === 0;
}

async function main() {
  const dataOnly = process.argv.includes('--data-only');
  await mkdir(BACKUPS_DIR, { recursive: true });
  const stamp = utcStamp();

  const parts = dataOnly
    ? [['data', ['--data-only']]]
    : [
        ['roles', ['--role-only']],
        ['schema', []],
        ['data', ['--data-only']],
      ];

  const written = [];
  for (const [name, extraArgs] of parts) {
    const outFile = join(BACKUPS_DIR, `${stamp}-${name}.sql`);
    if (!dump(outFile, extraArgs)) {
      console.error('❌ Snapshot fallito. Assicurati di aver fatto `supabase link` o di aver impostato SUPABASE_DB_URL.');
      process.exit(1);
    }
    written.push(outFile);
  }

  console.log(`✅ Snapshot completato (${dataOnly ? 'solo dati' : 'ruoli + schema + dati'}):`);
  for (const f of written) console.log(`   ${f}`);
  console.log('   Conservalo finché la migrazione non è verificata in prod.');
}

main().catch(err => { console.error('❌ db-snapshot errore:', err.message); process.exit(1); });
