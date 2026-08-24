#!/usr/bin/env node

/**
 * db-snapshot — snapshot logico della prod, da eseguire PRIMA di ogni `db push`.
 * È la nostra rete di sicurezza "backup" senza piano Pro/PITR (vedi NEW_APP_PLAN.md §3.bis).
 *
 * Usa `supabase db dump` (pg_dump bundlato nel CLI). Scrive in backups/ (gitignored).
 *
 * ⚠️  `supabase db dump` SENZA flag esporta **solo lo schema**: ruoli e dati vanno chiesti a parte
 *     (`--role-only`, `--data-only`). Per questo lo snapshot "completo" produce TRE file.
 *     Ripristino nell'ordine: roles → schema → data.
 *
 * Connessione: usa il progetto LINKATO (`supabase link`) oppure SUPABASE_DB_URL.
 *
 * USO:
 *     node scripts/db-snapshot.mjs                # completo: ruoli + schema + dati (3 file)
 *     node scripts/db-snapshot.mjs --data-only    # solo dati
 *     node scripts/db-snapshot.mjs --schema-only  # solo schema
 *
 * NB: i dump dei dati contengono PII di clienti reali — restano in locale (backups/ è gitignored).
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

/** Un singolo `supabase db dump` verso outFile. `extra` = ['--role-only'] | ['--data-only'] | []. */
function dump(outFile, extra, label) {
  const args = ['db', 'dump', '-f', outFile, ...extra];
  if (process.env.SUPABASE_DB_URL) args.push('--db-url', process.env.SUPABASE_DB_URL);
  else args.push('--linked');

  console.log(`   → ${label}: ${outFile}`);
  const res = spawnSync('npx', ['--yes', 'supabase', ...args], { stdio: 'inherit' });
  if (res.status !== 0) {
    console.error(`❌ Snapshot (${label}) fallito. Assicurati di aver fatto \`supabase link\` o di aver impostato SUPABASE_DB_URL.`);
    process.exit(1);
  }
}

async function main() {
  const dataOnly = process.argv.includes('--data-only');
  const schemaOnly = process.argv.includes('--schema-only');
  if (dataOnly && schemaOnly) {
    console.error('❌ --data-only e --schema-only sono mutuamente esclusivi.');
    process.exit(1);
  }

  await mkdir(BACKUPS_DIR, { recursive: true });
  const stamp = utcStamp();
  const base = join(BACKUPS_DIR, stamp);

  console.log('📦 Snapshot prod → backups/');
  if (!dataOnly && !schemaOnly) {
    // Completo: tre dump distinti, perché il CLI non ne fa uno solo.
    dump(`${base}-roles.sql`, ['--role-only'], 'ruoli');
    dump(`${base}-schema.sql`, [], 'schema');
    dump(`${base}-data.sql`, ['--data-only'], 'dati');
    console.log(`✅ Snapshot completo: ${stamp}-{roles,schema,data}.sql`);
    console.log('   Ripristino nell\'ordine: roles → schema → data.');
  } else if (dataOnly) {
    dump(`${base}-data.sql`, ['--data-only'], 'dati');
    console.log(`✅ Snapshot dati: ${stamp}-data.sql`);
  } else {
    dump(`${base}-schema.sql`, [], 'schema');
    console.log(`✅ Snapshot schema: ${stamp}-schema.sql`);
  }

  console.log('   Conservalo finché la migrazione non è verificata in prod.');
  console.log('   ⚠️  Il dump dei dati contiene PII: tienilo in locale, non condividerlo.');
}

main().catch(err => { console.error('❌ db-snapshot errore:', err.message); process.exit(1); });
