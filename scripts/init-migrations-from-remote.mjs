#!/usr/bin/env node

/**
 * Script per inizializzare le migrations locali dalla lista remota.
 * 
 * Questo script legge supabase/_remote/migration-list.txt e crea migrations placeholder
 * locali per sincronizzare lo stato iniziale.
 * 
 * ATTENZIONE: Questo crea solo migrations placeholder vuote. Le migrations reali
 * dovrebbero essere recuperate dal database o dai repo legacy se disponibili.
 */

import { readFile, writeFile, mkdir, readdir } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = join(__dirname, '..');

async function ensureDir(path) {
  try {
    await mkdir(path, { recursive: true });
  } catch (err) {
    if (err.code !== 'EEXIST') throw err;
  }
}

function parseMigrationList(content) {
  const lines = content.trim().split('\n').filter(Boolean);
  
  // Salta la riga header se presente
  const headerIndex = lines.findIndex(line => line.includes('Local') && line.includes('Remote'));
  const dataLines = headerIndex >= 0 ? lines.slice(headerIndex + 2) : lines;
  
  const migrations = [];
  
  for (const line of dataLines) {
    const parts = line.trim().split('|').map(p => p.trim()).filter(Boolean);
    if (parts.length >= 2) {
      // Formato: Local | Remote | Time
      const remote = parts[1]; // Remote column
      if (remote && remote.match(/^\d{4}$/)) {
        // Sembra essere un numero di migration (0000, 0001, ecc.)
        migrations.push(remote);
      }
    }
  }
  
  return migrations;
}

async function getExistingMigrations(migrationsDir) {
  try {
    const files = await readdir(migrationsDir);
    return files.filter(f => f.endsWith('.sql')).map(f => {
      // Estrai il numero dalla migration (es. "20240101120000_name.sql" -> cerca il numero)
      const match = f.match(/^(\d{14})_/);
      return match ? match[1] : null;
    }).filter(Boolean);
  } catch {
    return [];
  }
}

async function createPlaceholderMigration(migrationsDir, migrationNumber) {
  // Crea un timestamp fittizio basato sul numero della migration
  // Usiamo un formato: YYYYMMDDHHMMSS dove i primi 4 caratteri sono il numero
  // Es. 0000 -> 20240001000000, 0001 -> 20240001000001
  const baseYear = 2024;
  const month = '01';
  const day = '01';
  const hour = '00';
  const minute = '00';
  const second = migrationNumber.padStart(2, '0');
  
  // Miglioramento: usa il numero come parte del timestamp in modo più sensato
  const timestamp = `${baseYear}${month}${day}${hour}${minute}${second}`;
  const filename = `${timestamp}_migration_${migrationNumber}.sql`;
  const filepath = join(migrationsDir, filename);
  
  const content = `-- Migration ${migrationNumber}
-- This is a placeholder migration created to sync with remote database.
-- 
-- ATTENTION: This migration file is empty. The actual migration content
-- should be retrieved from:
-- 1. The remote database schema (using \`supabase db dump\`)
-- 2. Legacy repositories (kalos-app or kalos-app-management)
-- 3. Manual recreation based on current database state
--
-- DO NOT apply this empty migration to production.
-- Fill this file with the actual SQL before using it.

`;

  await writeFile(filepath, content, 'utf-8');
  return filename;
}

async function main() {
  const remoteListPath = join(repoRoot, 'supabase', '_remote', 'migration-list.txt');
  const migrationsDir = join(repoRoot, 'supabase', 'migrations');

  console.log('📋 Inizializzazione migrations da remote list...\n');

  // Leggi la lista remota
  let remoteListContent;
  try {
    remoteListContent = await readFile(remoteListPath, 'utf-8');
  } catch (err) {
    console.error('❌ Errore: Impossibile leggere supabase/_remote/migration-list.txt');
    console.error('   Esegui prima: npm run db:migrations:list');
    process.exit(1);
  }

  // Parse della lista
  const remoteMigrations = parseMigrationList(remoteListContent);
  
  if (remoteMigrations.length === 0) {
    console.log('⚠️  Nessuna migration trovata nella lista remota.');
    console.log('   La lista potrebbe essere vuota o in formato non riconosciuto.\n');
    return;
  }

  console.log(`🌐 Trovate ${remoteMigrations.length} migrations remote: ${remoteMigrations.join(', ')}\n`);

  // Verifica migrations esistenti
  await ensureDir(migrationsDir);
  const existingMigrations = await getExistingMigrations(migrationsDir);

  if (existingMigrations.length > 0) {
    console.log(`📁 Trovate ${existingMigrations.length} migrations locali esistenti.`);
    console.log('   Verifica che corrispondano alle migrations remote.\n');
  }

  // Crea migrations placeholder mancanti
  console.log('📝 Creazione migrations placeholder...\n');
  
  let created = 0;
  let skipped = 0;

  for (const migrationNum of remoteMigrations) {
    // Verifica se esiste già una migration con questo numero
    // (controllo semplice basato sul timestamp)
    const timestamp = `202401010000${migrationNum.padStart(2, '0')}`;
    const potentialFilename = `${timestamp}_migration_${migrationNum}.sql`;
    
    try {
      await readFile(join(migrationsDir, potentialFilename), 'utf-8');
      console.log(`   ⏭️  ${potentialFilename} (già esistente)`);
      skipped++;
    } catch {
      // File non esiste, crealo
      const filename = await createPlaceholderMigration(migrationsDir, migrationNum);
      console.log(`   ✓ ${filename}`);
      created++;
    }
  }

  console.log(`\n✅ Completato!`);
  console.log(`   Create: ${created}`);
  console.log(`   Saltate: ${skipped}\n`);

  if (created > 0) {
    console.log('⚠️  ATTENZIONE: Le migrations create sono placeholder vuote.');
    console.log('   Devi riempirle con il contenuto SQL reale prima di usarle.\n');
    console.log('   Opzioni per ottenere il contenuto:');
    console.log('   1. Usa `supabase db dump --schema public` per vedere lo schema corrente');
    console.log('   2. Controlla i repo legacy in supabase/_legacy/');
    console.log('   3. Ricrea manualmente basandoti sullo stato attuale del database\n');
  }
}

main().catch(err => {
  console.error('❌ Errore:', err);
  process.exit(1);
});

