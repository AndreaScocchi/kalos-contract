#!/usr/bin/env node

/**
 * db-push-safe — l'UNICO modo consentito di applicare migrazioni alla PROD.
 * Operazionalizza la regola della Fase 0 (§3.bis): snapshot obbligatorio + conferma esplicita
 * prima di `supabase db push`.
 *
 * Sequenza:
 *   1. migration-lint (blocca operazioni distruttive non approvate)
 *   2. snapshot completo della prod (db-snapshot.mjs) → backups/
 *   3. mostra le migrazioni pendenti e CHIEDE conferma digitando "PUSH"
 *   4. supabase db push
 *
 * USO: npm run db:push:safe
 *
 * NB: richiede CLI + progetto linkato. Da validare nella sessione con credenziali prod.
 */

import { spawnSync } from 'child_process';
import { createInterface } from 'readline';

function run(cmd, args, opts = {}) {
  const res = spawnSync(cmd, args, { stdio: 'inherit', ...opts });
  return res.status === 0;
}

function ask(question) {
  return new Promise(resolve => {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    rl.question(question, ans => { rl.close(); resolve(ans); });
  });
}

async function main() {
  console.log('🔒 db:push:safe — applicazione sicura delle migrazioni alla PROD\n');

  console.log('1/4 · migration-lint');
  if (!run('node', ['scripts/migration-lint.mjs'])) {
    console.error('❌ migration-lint fallito: risolvi prima di procedere.');
    process.exit(1);
  }

  console.log('\n2/4 · snapshot della prod');
  if (!run('node', ['scripts/db-snapshot.mjs'])) {
    console.error('❌ Snapshot fallito: NON procedo senza backup.');
    process.exit(1);
  }

  console.log('\n3/4 · migrazioni pendenti su prod:');
  run('npx', ['--yes', 'supabase', 'migration', 'list', '--linked']);

  const ans = await ask('\n⚠️  Confermi il push in PRODUZIONE? Digita "PUSH" per procedere: ');
  if (ans.trim() !== 'PUSH') {
    console.log('🛑 Annullato. Nessuna modifica applicata.');
    process.exit(0);
  }

  console.log('\n4/4 · supabase db push');
  if (!run('npx', ['--yes', 'supabase', 'db', 'push'])) {
    console.error('❌ db push fallito. Valuta il ripristino dallo snapshot in backups/.');
    process.exit(1);
  }
  console.log('\n✅ Migrazioni applicate. Ricordati di: rigenerare i tipi (npm run codegen), taggare una nuova versione, aggiornare i consumer in modo opt-in.');
}

main().catch(err => { console.error('❌ db-push-safe errore:', err.message); process.exit(1); });
