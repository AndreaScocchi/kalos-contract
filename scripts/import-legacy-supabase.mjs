#!/usr/bin/env node

/**
 * Script per importare le cartelle supabase/ dai due repo legacy
 * Estrae i file usando git show e li copia in supabase/_legacy/
 */

import { execSync } from 'child_process';
import { mkdir, writeFile, readFile } from 'fs/promises';
import { dirname, join } from 'path';
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

async function extractSupabaseFolder(remote, branch, targetDir) {
  console.log(`📦 Estraggo supabase/ da ${remote}/${branch}...`);
  
  try {
    // Lista tutti i file nella cartella supabase/
    const files = execSync(
      `git ls-tree -r --name-only ${remote}/${branch} -- supabase/`,
      { cwd: repoRoot, encoding: 'utf-8' }
    ).trim().split('\n').filter(Boolean);

    if (files.length === 0) {
      console.log(`⚠️  Nessun file trovato in ${remote}/${branch}/supabase/`);
      return;
    }

    console.log(`   Trovati ${files.length} file(s)`);

    for (const file of files) {
      try {
        // Estrai il contenuto del file
        const content = execSync(
          `git show ${remote}/${branch}:${file}`,
          { cwd: repoRoot, encoding: 'utf-8' }
        );

        // Calcola il path relativo a supabase/
        const relativePath = file.replace(/^supabase\//, '');
        const targetPath = join(targetDir, relativePath);
        const targetDirPath = dirname(targetPath);

        // Crea la directory se non esiste
        await ensureDir(targetDirPath);

        // Scrivi il file
        await writeFile(targetPath, content, 'utf-8');
        console.log(`   ✓ ${relativePath}`);
      } catch (err) {
        console.error(`   ✗ Errore su ${file}: ${err.message}`);
      }
    }

    console.log(`✅ Import completato in ${targetDir}\n`);
  } catch (err) {
    console.error(`❌ Errore nell'estrazione da ${remote}/${branch}:`, err.message);
  }
}

async function main() {
  const kalosAppDir = join(repoRoot, 'supabase', '_legacy', 'kalos-app');
  const kalosAppManagementDir = join(repoRoot, 'supabase', '_legacy', 'kalos-app-management');

  await ensureDir(kalosAppDir);
  await ensureDir(kalosAppManagementDir);

  await extractSupabaseFolder('kalos-app', 'main', kalosAppDir);
  await extractSupabaseFolder('kalos-app-management', 'main', kalosAppManagementDir);

  console.log('🎉 Import legacy completato!');
}

main().catch(console.error);

