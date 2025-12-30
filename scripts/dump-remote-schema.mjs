#!/usr/bin/env node

/**
 * Script helper per fare dump dello schema remoto.
 * Genera un file SQL con lo schema completo del database remoto.
 */

import { writeFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = join(__dirname, '..');

async function main() {
  const outputPath = join(repoRoot, 'supabase', '_remote', 'schema-dump.sql');

  console.log('📥 Generazione dump schema remoto...\n');
  console.log('   Questo potrebbe richiedere alcuni secondi...\n');

  try {
    // Genera dump dello schema pubblico
    const dump = execSync(
      'npx supabase db dump --schema public --data-only=false',
      { cwd: repoRoot, encoding: 'utf-8', stdio: 'pipe' }
    );

    await writeFile(outputPath, dump, 'utf-8');

    console.log(`✅ Dump salvato in: ${outputPath}\n`);
    console.log('   Puoi usare questo dump per:');
    console.log('   1. Analizzare lo schema corrente');
    console.log('   2. Creare migrations basate sulle differenze');
    console.log('   3. Ricostruire le migrations mancanti\n');
  } catch (err) {
    console.error('❌ Errore durante il dump:', err.message);
    console.error('\n   Assicurati di essere collegato al progetto:');
    console.error('   npm run db:link\n');
    process.exit(1);
  }
}

main().catch(err => {
  console.error('❌ Errore:', err);
  process.exit(1);
});

