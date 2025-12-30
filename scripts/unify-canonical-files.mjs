#!/usr/bin/env node

/**
 * Script per unificare functions, seed.sql, config.toml dai legacy repo
 * Preferisce il file più completo o quello da kalos-app-management se equivalenti
 */

import { readFile, writeFile, copyFile, stat, readdir } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = join(__dirname, '..');

async function fileExists(path) {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

async function getFileSize(path) {
  try {
    const stats = await stat(path);
    return stats.size;
  } catch {
    return 0;
  }
}

async function unifyFile(name, kalosAppPath, kalosAppManagementPath, targetPath) {
  const kalosAppExists = await fileExists(kalosAppPath);
  const kalosAppManagementExists = await fileExists(kalosAppManagementPath);

  console.log(`\n📄 ${name}:`);

  if (!kalosAppExists && !kalosAppManagementExists) {
    console.log(`   ⚠️  Non trovato in nessun repo legacy`);
    return;
  }

  if (kalosAppExists && !kalosAppManagementExists) {
    await copyFile(kalosAppPath, targetPath);
    console.log(`   ✅ Copiato da kalos-app`);
    return;
  }

  if (kalosAppManagementExists && !kalosAppExists) {
    await copyFile(kalosAppManagementPath, targetPath);
    console.log(`   ✅ Copiato da kalos-app-management`);
    return;
  }

  // Entrambi esistono: scegli quello più completo
  const kalosAppSize = await getFileSize(kalosAppPath);
  const kalosAppManagementSize = await getFileSize(kalosAppManagementPath);

  // Leggi i contenuti per vedere se sono diversi
  const kalosAppContent = await readFile(kalosAppPath, 'utf-8');
  const kalosAppManagementContent = await readFile(kalosAppManagementPath, 'utf-8');

  if (kalosAppContent === kalosAppManagementContent) {
    // Identici, usa quello da kalos-app-management (preferenza)
    await copyFile(kalosAppManagementPath, targetPath);
    console.log(`   ✅ Copiato da kalos-app-management (identico a kalos-app)`);
  } else {
    // Diversi: preferisci quello più grande (presumibilmente più completo)
    if (kalosAppManagementSize >= kalosAppSize) {
      await copyFile(kalosAppManagementPath, targetPath);
      console.log(`   ✅ Copiato da kalos-app-management (${kalosAppManagementSize} bytes vs ${kalosAppSize} bytes)`);
      console.log(`   ⚠️  File diversi! Verifica manualmente se serve unire contenuti.`);
    } else {
      await copyFile(kalosAppPath, targetPath);
      console.log(`   ✅ Copiato da kalos-app (${kalosAppSize} bytes vs ${kalosAppManagementSize} bytes)`);
      console.log(`   ⚠️  File diversi! Verifica manualmente se serve unire contenuti.`);
    }
  }
}

async function unifyFunctions(kalosAppFunctionsDir, kalosAppManagementFunctionsDir, targetDir) {
  const kalosAppExists = await fileExists(kalosAppFunctionsDir);
  const kalosAppManagementExists = await fileExists(kalosAppManagementFunctionsDir);

  console.log(`\n📁 functions/:`);

  if (!kalosAppExists && !kalosAppManagementExists) {
    console.log(`   ⚠️  Directory non trovata in nessun repo legacy`);
    return;
  }

  // Per ora copiamo l'intera directory, preferendo kalos-app-management
  // In futuro si può fare merge più sofisticato
  if (kalosAppManagementExists) {
    // TODO: Copia ricorsiva directory
    console.log(`   ✅ Copiare manualmente da kalos-app-management (TODO: implementare copia ricorsiva)`);
  } else if (kalosAppExists) {
    console.log(`   ✅ Copiare manualmente da kalos-app (TODO: implementare copia ricorsiva)`);
  }
}

async function main() {
  const kalosAppLegacy = join(repoRoot, 'supabase', '_legacy', 'kalos-app');
  const kalosAppManagementLegacy = join(repoRoot, 'supabase', '_legacy', 'kalos-app-management');
  const targetSupabase = join(repoRoot, 'supabase');

  // Unifica config.toml
  await unifyFile(
    'config.toml',
    join(kalosAppLegacy, 'config.toml'),
    join(kalosAppManagementLegacy, 'config.toml'),
    join(targetSupabase, 'config.toml')
  );

  // Unifica seed.sql
  await unifyFile(
    'seed.sql',
    join(kalosAppLegacy, 'seed.sql'),
    join(kalosAppManagementLegacy, 'seed.sql'),
    join(targetSupabase, 'seed.sql')
  );

  // Unifica functions/ (se esistono)
  await unifyFunctions(
    join(kalosAppLegacy, 'functions'),
    join(kalosAppManagementLegacy, 'functions'),
    join(targetSupabase, 'functions')
  );

  console.log(`\n🎉 Unificazione completata!`);
  console.log(`   Verifica manualmente i file in supabase/ per assicurarti che siano corretti.`);
}

main().catch(err => {
  console.error('❌ Errore:', err);
  process.exit(1);
});

