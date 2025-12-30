#!/usr/bin/env node

/**
 * Script per riparare la migration history quando c'è un mismatch tra remote e local.
 * 
 * Questo script esegue i comandi suggeriti da Supabase per sincronizzare la history:
 * - Marca le migrations remote vecchie come "reverted"
 * - Marca le migrations locali nuove come "applied"
 * 
 * ATTENZIONE: Questo modifica la migration history table nel database remoto.
 * Usa solo se hai verificato che le migrations locali rappresentano correttamente
 * lo stato attuale del database.
 */

import { execSync } from 'child_process';
import { readdir } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = join(__dirname, '..');

async function getLocalMigrations() {
  const migrationsDir = join(repoRoot, 'supabase', 'migrations');
  const files = await readdir(migrationsDir);
  
  // Estrai migrations con formato timestamp_name.sql
  return files
    .filter(f => f.endsWith('.sql') && /^\d{14}_/.test(f))
    .map(f => {
      const match = f.match(/^(\d{14})_(.+)$/);
      return match ? { filename: f, timestamp: match[1], name: match[2] } : null;
    })
    .filter(Boolean)
    .sort((a, b) => a.timestamp.localeCompare(b.timestamp));
}

async function main() {
  console.log('🔧 Riparazione migration history...\n');
  console.log('⚠️  ATTENZIONE: Questo modificherà la migration history table nel database remoto.\n');
  
  // Leggi migrations locali
  const localMigrations = await getLocalMigrations();
  
  if (localMigrations.length === 0) {
    console.error('❌ Nessuna migration locale trovata.');
    process.exit(1);
  }
  
  console.log(`📋 Trovate ${localMigrations.length} migrations locali:\n`);
  localMigrations.forEach(m => {
    console.log(`   ${m.timestamp} (${m.name})`);
  });
  console.log('');
  
  // Le migrations remote vecchie da marcare come reverted
  const remoteOldMigrations = ['0000', '0001', '0002', '0003'];
  
  console.log('🔨 Step 1: Marcare migrations remote vecchie come "reverted"...\n');
  
  for (const migrationNum of remoteOldMigrations) {
    try {
      console.log(`   Reverting remote migration ${migrationNum}...`);
      execSync(
        `npx supabase migration repair --status reverted ${migrationNum}`,
        { cwd: repoRoot, stdio: 'inherit' }
      );
      console.log(`   ✅ Migration ${migrationNum} marcata come reverted\n`);
    } catch (err) {
      console.error(`   ⚠️  Errore su migration ${migrationNum}: ${err.message}\n`);
    }
  }
  
  console.log('🔨 Step 2: Marcare migrations locali come "applied"...\n');
  
  for (const migration of localMigrations) {
    try {
      console.log(`   Applying local migration ${migration.timestamp}...`);
      execSync(
        `npx supabase migration repair --status applied ${migration.timestamp}`,
        { cwd: repoRoot, stdio: 'inherit' }
      );
      console.log(`   ✅ Migration ${migration.timestamp} marcata come applied\n`);
    } catch (err) {
      console.error(`   ⚠️  Errore su migration ${migration.timestamp}: ${err.message}\n`);
    }
  }
  
  console.log('✅ Riparazione completata!\n');
  console.log('   Ora puoi eseguire: npm run db:pull\n');
}

main().catch(err => {
  console.error('❌ Errore:', err);
  process.exit(1);
});

