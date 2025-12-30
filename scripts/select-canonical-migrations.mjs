#!/usr/bin/env node

/**
 * Script per selezionare il set canonico di migrations confrontando:
 * - supabase/_legacy/kalos-app/migrations
 * - supabase/_legacy/kalos-app-management/migrations
 * - supabase/_remote/migration-list.txt (generato da `supabase migration list`)
 * 
 * Se un set ha 100% overlap con la remote list, viene copiato in supabase/migrations.
 * Altrimenti, viene scelto il set con maggiore overlap e viene creato CANONICAL_NOT_CONFIRMED.md
 */

import { readdir, readFile, mkdir, copyFile, writeFile, stat } from 'fs/promises';
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

async function getMigrationFiles(dir) {
  try {
    const files = await readdir(dir);
    return files.filter(f => f.endsWith('.sql')).sort();
  } catch (err) {
    if (err.code === 'ENOENT') {
      return [];
    }
    throw err;
  }
}

async function parseRemoteMigrationList(filePath) {
  try {
    const content = await readFile(filePath, 'utf-8');
    // La migration list di Supabase CLI ha formato:
    // [timestamp] [version] [name]
    // Esempio: 20240101120000 20240101120000_create_users_table
    const lines = content.trim().split('\n').filter(Boolean);
    
    // Estrai i nomi delle migrations (ultima colonna)
    return lines.map(line => {
      const parts = line.trim().split(/\s+/);
      // Prendi l'ultima parte (il nome del file senza .sql)
      return parts[parts.length - 1];
    }).filter(Boolean);
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.warn(`⚠️  File remote migration list non trovato: ${filePath}`);
      console.warn(`   Esegui prima: npm run db:migrations:list`);
      return [];
    }
    throw err;
  }
}

function calculateOverlap(legacyFiles, remoteFiles) {
  if (remoteFiles.length === 0) {
    return { overlap: 0, matches: [], missing: legacyFiles };
  }

  const matches = legacyFiles.filter(file => {
    // Rimuovi .sql e confronta il nome base
    const baseName = file.replace(/\.sql$/, '');
    return remoteFiles.some(remote => {
      // Il remote potrebbe avere timestamp prefix, confronta solo il nome
      const remoteBase = remote.split('_').slice(1).join('_') || remote;
      return baseName.includes(remoteBase) || remoteBase.includes(baseName);
    });
  });

  const overlap = (matches.length / remoteFiles.length) * 100;
  const missing = remoteFiles.filter(remote => {
    const remoteBase = remote.split('_').slice(1).join('_') || remote;
    return !legacyFiles.some(file => {
      const baseName = file.replace(/\.sql$/, '');
      return baseName.includes(remoteBase) || remoteBase.includes(baseName);
    });
  });

  return { overlap, matches, missing };
}

async function copyMigrationFiles(sourceDir, targetDir) {
  await ensureDir(targetDir);
  const files = await getMigrationFiles(sourceDir);
  
  for (const file of files) {
    await copyFile(
      join(sourceDir, file),
      join(targetDir, file)
    );
  }
  
  return files.length;
}

async function main() {
  console.log('🔍 Analisi migrations per set canonico...\n');

  const kalosAppMigrationsDir = join(repoRoot, 'supabase', '_legacy', 'kalos-app', 'migrations');
  const kalosAppManagementMigrationsDir = join(repoRoot, 'supabase', '_legacy', 'kalos-app-management', 'migrations');
  const remoteListPath = join(repoRoot, 'supabase', '_remote', 'migration-list.txt');
  const canonicalMigrationsDir = join(repoRoot, 'supabase', 'migrations');
  const notConfirmedPath = join(repoRoot, 'supabase', 'CANONICAL_NOT_CONFIRMED.md');

  // Leggi migrations da entrambi i legacy
  const kalosAppFiles = await getMigrationFiles(kalosAppMigrationsDir);
  const kalosAppManagementFiles = await getMigrationFiles(kalosAppManagementMigrationsDir);

  console.log(`📁 kalos-app: ${kalosAppFiles.length} migration(s)`);
  if (kalosAppFiles.length > 0) {
    console.log(`   ${kalosAppFiles.slice(0, 5).join(', ')}${kalosAppFiles.length > 5 ? '...' : ''}`);
  }

  console.log(`📁 kalos-app-management: ${kalosAppManagementFiles.length} migration(s)`);
  if (kalosAppManagementFiles.length > 0) {
    console.log(`   ${kalosAppManagementFiles.slice(0, 5).join(', ')}${kalosAppManagementFiles.length > 5 ? '...' : ''}`);
  }

  // Leggi remote list
  const remoteFiles = await parseRemoteMigrationList(remoteListPath);
  console.log(`🌐 Remote: ${remoteFiles.length} migration(s)\n`);

  if (remoteFiles.length === 0) {
    console.warn('⚠️  Nessuna migration remota trovata.');
    console.warn('   Esegui prima: npm run db:migrations:list');
    console.warn('   Oppure: supabase link + supabase migration list\n');
  }

  // Calcola overlap
  const kalosAppOverlap = calculateOverlap(kalosAppFiles, remoteFiles);
  const kalosAppManagementOverlap = calculateOverlap(kalosAppManagementFiles, remoteFiles);

  console.log('📊 Risultati confronto:\n');
  console.log(`kalos-app:`);
  console.log(`  Overlap: ${kalosAppOverlap.overlap.toFixed(1)}%`);
  console.log(`  Matches: ${kalosAppOverlap.matches.length}/${remoteFiles.length}`);
  
  console.log(`\nkalos-app-management:`);
  console.log(`  Overlap: ${kalosAppManagementOverlap.overlap.toFixed(1)}%`);
  console.log(`  Matches: ${kalosAppManagementOverlap.matches.length}/${remoteFiles.length}\n`);

  // Determina quale set usare
  let selectedSet = null;
  let selectedName = null;
  let selectedOverlap = null;

  if (kalosAppOverlap.overlap === 100 && kalosAppManagementOverlap.overlap !== 100) {
    selectedSet = kalosAppMigrationsDir;
    selectedName = 'kalos-app';
    selectedOverlap = kalosAppOverlap;
  } else if (kalosAppManagementOverlap.overlap === 100 && kalosAppOverlap.overlap !== 100) {
    selectedSet = kalosAppManagementMigrationsDir;
    selectedName = 'kalos-app-management';
    selectedOverlap = kalosAppManagementOverlap;
  } else if (kalosAppOverlap.overlap > kalosAppManagementOverlap.overlap) {
    selectedSet = kalosAppMigrationsDir;
    selectedName = 'kalos-app';
    selectedOverlap = kalosAppOverlap;
  } else if (kalosAppManagementOverlap.overlap > kalosAppOverlap.overlap) {
    selectedSet = kalosAppManagementMigrationsDir;
    selectedName = 'kalos-app-management';
    selectedOverlap = kalosAppManagementOverlap;
  } else if (kalosAppFiles.length > 0) {
    // Stesso overlap, preferisci quello con più file
    selectedSet = kalosAppFiles.length >= kalosAppManagementFiles.length 
      ? kalosAppMigrationsDir 
      : kalosAppManagementMigrationsDir;
    selectedName = kalosAppFiles.length >= kalosAppManagementFiles.length 
      ? 'kalos-app' 
      : 'kalos-app-management';
    selectedOverlap = kalosAppFiles.length >= kalosAppManagementFiles.length 
      ? kalosAppOverlap 
      : kalosAppManagementOverlap;
  } else if (kalosAppManagementFiles.length > 0) {
    selectedSet = kalosAppManagementMigrationsDir;
    selectedName = 'kalos-app-management';
    selectedOverlap = kalosAppManagementOverlap;
  }

  if (!selectedSet) {
    console.log('❌ Nessun set di migrations trovato nei legacy repo.\n');
    return;
  }

  // Copia in canonico
  console.log(`✅ Set selezionato: ${selectedName}`);
  console.log(`   Overlap: ${selectedOverlap.overlap.toFixed(1)}%\n`);

  const copiedCount = await copyMigrationFiles(selectedSet, canonicalMigrationsDir);
  console.log(`📋 Copiate ${copiedCount} migration(s) in supabase/migrations/\n`);

  // Se non è 100% overlap, crea file di avviso
  if (selectedOverlap.overlap !== 100 && remoteFiles.length > 0) {
    const warningContent = `# ⚠️ Canonical Migrations Non Confermate

Il set canonico in \`supabase/migrations/\` è stato selezionato automaticamente dal set **${selectedName}**
basandosi sul maggiore overlap (${selectedOverlap.overlap.toFixed(1)}%) con la migration history remota.

**ATTENZIONE**: Questo set NON ha 100% overlap con le migrations remote, quindi potrebbe non rappresentare
correttamente lo stato attuale del database in produzione.

## Cosa fare

1. **Verifica manuale**: Controlla le migrations in \`supabase/migrations/\` e confrontale con:
   - Le migrations remote (vedi \`supabase/_remote/migration-list.txt\`)
   - Le migrations legacy in \`supabase/_legacy/\`

2. **Opzioni**:
   - Se il set canonico è corretto: rimuovi questo file dopo aver verificato
   - Se serve aggiustare: modifica manualmente \`supabase/migrations/\` e poi rimuovi questo file
   - Se serve un reset completo: considera di fare \`supabase db pull\` (ATTENZIONE: può fallire se c'è mismatch nella history)

3. **Dopo la verifica**: Rimuovi questo file quando sei sicuro che il set canonico sia corretto.

## Dettagli tecnici

- Set selezionato: \`${selectedName}\`
- Overlap: ${selectedOverlap.overlap.toFixed(1)}%
- Migrations remote: ${remoteFiles.length}
- Migrations nel set selezionato: ${selectedOverlap.matches.length}

## Comandi utili

\`\`\`bash
# Visualizza migration list remota
npm run db:migrations:list

# Confronta con locale
ls -la supabase/migrations/

# Verifica stato database
supabase db diff
\`\`\`
`;

    await writeFile(notConfirmedPath, warningContent, 'utf-8');
    console.log(`⚠️  Creato file di avviso: supabase/CANONICAL_NOT_CONFIRMED.md`);
    console.log(`   Verifica manualmente prima di procedere.\n`);
  } else if (selectedOverlap.overlap === 100) {
    // Rimuovi file di avviso se esiste
    try {
      await stat(notConfirmedPath);
      await import('fs/promises').then(fs => fs.unlink(notConfirmedPath));
      console.log(`✅ Rimosso file di avviso (overlap 100%)\n`);
    } catch {
      // File non esiste, ok
    }
  }

  console.log('🎉 Processo completato!');
}

main().catch(err => {
  console.error('❌ Errore:', err);
  process.exit(1);
});

