#!/usr/bin/env node

/**
 * Script per riempire le migrations placeholder con il contenuto del dump dello schema.
 * 
 * Strategia: Poiché non conosciamo la divisione originale delle migrations, dividiamo
 * lo schema in modo logico:
 * - 0000: Types (ENUMs) e tabelle base
 * - 0001: Funzioni base e triggers
 * - 0002: Views e funzioni aggiuntive
 * - 0003: RLS policies, grants, e finalizzazioni
 * 
 * Se la divisione non è chiara, consolidiamo tutto nella prima migration.
 */

import { readFile, writeFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = join(__dirname, '..');

async function parseDump(content) {
  // Divide il dump in sezioni logiche
  const lines = content.split('\n');
  
  const sections = {
    header: [],           // SET statements, schema creation
    types: [],            // CREATE TYPE
    tables: [],           // CREATE TABLE
    functions: [],        // CREATE FUNCTION
    triggers: [],         // CREATE TRIGGER
    views: [],            // CREATE VIEW
    rls: [],              // ALTER TABLE ... ENABLE ROW LEVEL SECURITY, CREATE POLICY
    grants: [],           // GRANT statements
    indexes: [],          // CREATE INDEX
    comments: [],         // COMMENT ON
    other: []             // Everything else
  };
  
  let currentSection = 'other';
  let inFunction = false;
  let functionLines = [];
  let functionDepth = 0;
  
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    const upper = trimmed.toUpperCase();
    
    // Gestione funzioni (possono essere multi-linea con $$)
    if (upper.startsWith('CREATE OR REPLACE FUNCTION') || upper.startsWith('CREATE FUNCTION')) {
      inFunction = true;
      functionLines = [line];
      functionDepth = 0;
      currentSection = 'functions';
      continue;
    }
    
    if (inFunction) {
      functionLines.push(line);
      // Conta le coppie di $$
      const dollarMatches = line.match(/\$\$/g);
      if (dollarMatches) {
        functionDepth += dollarMatches.length;
        if (functionDepth >= 2) {
          // Fine della funzione
          sections.functions.push(...functionLines);
          functionLines = [];
          inFunction = false;
          functionDepth = 0;
        }
      }
      continue;
    }
    
    // Header (SET statements, schema setup)
    if (upper.startsWith('SET ') || 
        upper.startsWith('SELECT PG_CATALOG') ||
        (trimmed.startsWith('--') && i < 20)) {
      sections.header.push(line);
      continue;
    }
    
    // Types
    if (upper.startsWith('CREATE TYPE') || upper.startsWith('ALTER TYPE')) {
      currentSection = 'types';
      sections.types.push(line);
      continue;
    }
    
    // Tables
    if (upper.startsWith('CREATE TABLE')) {
      currentSection = 'tables';
      sections.tables.push(line);
      continue;
    }
    
    // ALTER TABLE (continuazione di CREATE TABLE o modifiche)
    if (upper.startsWith('ALTER TABLE') && currentSection === 'tables') {
      sections.tables.push(line);
      continue;
    }
    
    // Views
    if (upper.startsWith('CREATE VIEW') || upper.startsWith('CREATE OR REPLACE VIEW')) {
      currentSection = 'views';
      sections.views.push(line);
      continue;
    }
    
    // Triggers
    if (upper.startsWith('CREATE TRIGGER')) {
      currentSection = 'triggers';
      sections.triggers.push(line);
      continue;
    }
    
    // RLS Policies
    if (upper.includes('ROW LEVEL SECURITY') || upper.startsWith('CREATE POLICY') || 
        upper.startsWith('ALTER TABLE') && upper.includes('ENABLE ROW LEVEL SECURITY')) {
      currentSection = 'rls';
      sections.rls.push(line);
      continue;
    }
    
    // Grants
    if (upper.startsWith('GRANT ') || upper.startsWith('REVOKE ')) {
      currentSection = 'grants';
      sections.grants.push(line);
      continue;
    }
    
    // Indexes
    if (upper.startsWith('CREATE INDEX') || upper.startsWith('CREATE UNIQUE INDEX')) {
      currentSection = 'indexes';
      sections.indexes.push(line);
      continue;
    }
    
    // Comments
    if (upper.startsWith('COMMENT ON')) {
      currentSection = 'comments';
      sections.comments.push(line);
      continue;
    }
    
    // Aggiungi alla sezione corrente se siamo in un blocco
    if (currentSection !== 'other' && trimmed && !trimmed.startsWith('--')) {
      if (sections[currentSection]) {
        sections[currentSection].push(line);
      }
    } else {
      sections.other.push(line);
    }
  }
  
  // Aggiungi eventuali funzioni rimanenti
  if (functionLines.length > 0) {
    sections.functions.push(...functionLines);
  }
  
  return sections;
}

function buildMigration(sections, migrationNum) {
  const parts = [];
  
  // Migration 0000: Types, Tables, Indexes base
  if (migrationNum === '0000') {
    parts.push('-- Migration 0000: Initial schema');
    parts.push('-- Types, Tables, and Base Indexes\n');
    parts.push(...sections.header);
    parts.push('');
    parts.push(...sections.types);
    parts.push('');
    parts.push(...sections.tables);
    parts.push('');
    parts.push(...sections.indexes);
    parts.push(...sections.comments);
  }
  
  // Migration 0001: Functions and Triggers
  else if (migrationNum === '0001') {
    parts.push('-- Migration 0001: Functions and Triggers\n');
    parts.push(...sections.functions);
    parts.push('');
    parts.push(...sections.triggers);
  }
  
  // Migration 0002: Views
  else if (migrationNum === '0002') {
    parts.push('-- Migration 0002: Views\n');
    parts.push(...sections.views);
  }
  
  // Migration 0003: RLS Policies and Grants
  else if (migrationNum === '0003') {
    parts.push('-- Migration 0003: RLS Policies and Grants\n');
    parts.push(...sections.rls);
    parts.push('');
    parts.push(...sections.grants);
  }
  
  // Se una sezione è vuota, aggiungi un commento
  if (parts.length <= 3) {
    parts.push('-- This migration was empty in the original database state.');
    parts.push('-- All schema changes were consolidated in previous migrations.');
  }
  
  return parts.join('\n') + '\n';
}

async function main() {
  const dumpPath = join(repoRoot, 'supabase', '_remote', 'schema-dump.sql');
  const migrationsDir = join(repoRoot, 'supabase', 'migrations');
  
  console.log('📝 Lettura dump schema...\n');
  
  let dumpContent;
  try {
    dumpContent = await readFile(dumpPath, 'utf-8');
  } catch (err) {
    console.error('❌ Errore: Impossibile leggere schema-dump.sql');
    console.error('   Esegui prima: npm run db:dump:schema');
    process.exit(1);
  }
  
  console.log('🔍 Analisi e divisione schema...\n');
  const sections = await parseDump(dumpContent);
  
  console.log('📊 Sezioni trovate:');
  console.log(`   Header: ${sections.header.length} righe`);
  console.log(`   Types: ${sections.types.length} righe`);
  console.log(`   Tables: ${sections.tables.length} righe`);
  console.log(`   Functions: ${sections.functions.length} righe`);
  console.log(`   Triggers: ${sections.triggers.length} righe`);
  console.log(`   Views: ${sections.views.length} righe`);
  console.log(`   RLS: ${sections.rls.length} righe`);
  console.log(`   Grants: ${sections.grants.length} righe`);
  console.log(`   Indexes: ${sections.indexes.length} righe`);
  console.log(`   Comments: ${sections.comments.length} righe`);
  console.log(`   Other: ${sections.other.length} righe\n`);
  
  // Strategia: se la divisione non è chiara, metti tutto nella prima migration
  const totalLines = Object.values(sections).reduce((sum, arr) => sum + arr.length, 0);
  const meaningfulSections = ['types', 'tables', 'functions', 'triggers', 'views', 'rls']
    .filter(key => sections[key].length > 10);
  
  if (meaningfulSections.length <= 1 || totalLines < 500) {
    console.log('⚠️  Schema relativamente piccolo o poco divisibile.');
    console.log('   Consolido tutto nella prima migration.\n');
    
    // Consolida tutto nella prima migration
    const consolidated = [
      '-- Migration 0000: Complete schema',
      '-- All database objects consolidated in initial migration\n',
      ...sections.header,
      '',
      ...sections.types,
      '',
      ...sections.tables,
      '',
      ...sections.indexes,
      '',
      ...sections.functions,
      '',
      ...sections.triggers,
      '',
      ...sections.views,
      '',
      ...sections.rls,
      '',
      ...sections.grants,
      '',
      ...sections.comments,
      ...sections.other.filter(line => line.trim() && !line.trim().startsWith('--'))
    ].join('\n') + '\n';
    
    const migration0000Path = join(migrationsDir, '2024010100000000_migration_0000.sql');
    await writeFile(migration0000Path, consolidated, 'utf-8');
    console.log('✅ Scritta migration 0000 con schema completo\n');
    
    // Le altre migrations rimangono vuote con commento
    for (let i = 1; i <= 3; i++) {
      const migrationNum = String(i).padStart(4, '0');
      const timestamp = `2024010100000${i}`;
      const filename = `${timestamp}_migration_${migrationNum}.sql`;
      const content = `-- Migration ${migrationNum}\n-- Empty migration (schema consolidated in 0000)\n`;
      await writeFile(join(migrationsDir, filename), content, 'utf-8');
      console.log(`✅ Scritta migration ${migrationNum} (vuota)`);
    }
  } else {
    // Divisione logica
    console.log('📋 Divisione schema in migrations logiche...\n');
    
    for (let i = 0; i <= 3; i++) {
      const migrationNum = String(i).padStart(4, '0');
      const timestamp = `2024010100000${i}`;
      const filename = `${timestamp}_migration_${migrationNum}.sql`;
      const content = buildMigration(sections, migrationNum);
      
      await writeFile(join(migrationsDir, filename), content, 'utf-8');
      console.log(`✅ Scritta migration ${migrationNum}`);
    }
  }
  
  console.log('\n🎉 Migrations riempite con successo!');
  console.log('   Verifica il contenuto e testa con: npm run db:push --local\n');
}

main().catch(err => {
  console.error('❌ Errore:', err);
  process.exit(1);
});

