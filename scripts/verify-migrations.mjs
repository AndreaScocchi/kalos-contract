#!/usr/bin/env node

/**
 * Script di verifica per il workflow migrations
 * 
 * Verifica che:
 * 1. I types sono aggiornati (typecheck passa)
 * 2. Il build funziona
 * 3. Le migrations sono in ordine e non duplicate
 * 4. Non ci sono migrations con errori di sintassi SQL evidenti
 */

import { readdir, readFile } from 'fs/promises';
import { join } from 'path';
import { execSync } from 'child_process';

const MIGRATIONS_DIR = join(process.cwd(), 'supabase', 'migrations');
const MAX_MIGRATION_SIZE = 500 * 1024; // 500KB max per migration

async function checkMigrationsOrder() {
  console.log('🔍 Verificando ordine delle migrations...');
  
  const files = await readdir(MIGRATIONS_DIR);
  const migrations = files
    .filter(f => f.endsWith('.sql') && !f.startsWith('README'))
    .sort();
  
  console.log(`   Trovate ${migrations.length} migrations`);
  
  // Verifica formato timestamp
  const timestampRegex = /^(\d{14})_/;
  const timestamps = [];
  
  for (const migration of migrations) {
    const match = migration.match(timestampRegex);
    if (!match) {
      throw new Error(`❌ Migration "${migration}" non rispetta il formato: YYYYMMDDHHMMSS_description.sql`);
    }
    
    const timestamp = match[1];
    if (timestamps.includes(timestamp)) {
      throw new Error(`❌ Timestamp duplicato: ${timestamp} in "${migration}"`);
    }
    
    timestamps.push(timestamp);
    
    // Verifica ordine
    if (timestamps.length > 1) {
      const prev = timestamps[timestamps.length - 2];
      if (timestamp <= prev) {
        throw new Error(`❌ Migration "${migration}" è fuori ordine (timestamp ${timestamp} <= ${prev})`);
      }
    }
    
    // Verifica dimensione
    const filePath = join(MIGRATIONS_DIR, migration);
    const stats = await import('fs').then(fs => fs.promises.stat(filePath));
    if (stats.size > MAX_MIGRATION_SIZE) {
      console.warn(`⚠️  Migration "${migration}" è molto grande (${(stats.size / 1024).toFixed(0)}KB). Considera di dividerla.`);
    }
  }
  
  console.log('✅ Ordine delle migrations corretto');
}

async function checkMigrationsSyntax() {
  console.log('🔍 Verificando sintassi SQL base...');
  
  const files = await readdir(MIGRATIONS_DIR);
  const migrations = files
    .filter(f => f.endsWith('.sql') && !f.startsWith('README'))
    .sort();
  
  for (const migration of migrations) {
    const filePath = join(MIGRATIONS_DIR, migration);
    const content = await readFile(filePath, 'utf-8');
    
    // Verifiche base di sintassi SQL
    const openParens = (content.match(/\(/g) || []).length;
    const closeParens = (content.match(/\)/g) || []).length;
    
    if (openParens !== closeParens) {
      throw new Error(`❌ Migration "${migration}" ha parentesi non bilanciate (${openParens} aperte, ${closeParens} chiuse)`);
    }
    
    // Verifica che non ci siano modifiche a migrations già applicate
    // (non possiamo verificare questo senza accesso al DB, ma possiamo avvisare)
    if (content.includes('DROP TABLE') || content.includes('ALTER TABLE ... DROP')) {
      console.warn(`⚠️  Migration "${migration}" contiene DROP. Assicurati che non modifichi migrations già applicate in produzione.`);
    }
  }
  
  console.log('✅ Sintassi SQL base corretta');
}

async function checkTypes() {
  console.log('🔍 Verificando types TypeScript...');
  
  try {
    execSync('npm run typecheck', { 
      stdio: 'inherit',
      cwd: process.cwd()
    });
    console.log('✅ Types TypeScript corretti');
  } catch (error) {
    throw new Error('❌ Typecheck fallito. Esegui "npm run typecheck" per dettagli.');
  }
}

async function checkBuild() {
  console.log('🔍 Verificando build...');
  
  try {
    execSync('npm run build', { 
      stdio: 'inherit',
      cwd: process.cwd()
    });
    console.log('✅ Build completato con successo');
  } catch (error) {
    throw new Error('❌ Build fallito. Esegui "npm run build" per dettagli.');
  }
}

async function main() {
  console.log('🚀 Verifica migrations e contract...\n');
  
  try {
    await checkMigrationsOrder();
    await checkMigrationsSyntax();
    await checkTypes();
    await checkBuild();
    
    console.log('\n✅ Tutte le verifiche completate con successo!');
    console.log('\n📝 Prossimi passi:');
    console.log('   1. Testa le migrations in locale: npm run db:start && supabase db reset');
    console.log('   2. Applica a staging: npm run db:push');
    console.log('   3. Rigenera types: supabase gen types typescript --project-id <id> > src/types/database.ts');
    console.log('   4. Verifica: npm run verify');
    console.log('   5. Commit, tag e push');
    
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Verifica fallita:', error.message);
    process.exit(1);
  }
}

main();

