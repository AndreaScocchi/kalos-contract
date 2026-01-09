#!/usr/bin/env node

/**
 * Script per verificare la coerenza tra abbonamenti, ingressi e prenotazioni
 * Esegue lo script SQL di verifica e mostra i risultati in modo leggibile
 */

import { readFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = join(__dirname, '..');

async function main() {
  console.log('🔍 Verifica coerenza: Abbonamenti, Ingressi e Prenotazioni\n');
  console.log('   Questo script verifica 13 aspetti di coerenza del database...\n');

  const sqlFile = join(__dirname, 'verify-subscriptions-bookings-entries.sql');
  
  try {
    // Leggi il file SQL
    const sql = await readFile(sqlFile, 'utf-8');
    
    // Esegui le query usando psql tramite Supabase CLI
    console.log('📊 Esecuzione verifiche...\n');
    
    try {
      const output = execSync(
        `npx supabase db execute --file "${sqlFile}"`,
        { 
          cwd: repoRoot, 
          encoding: 'utf-8',
          stdio: 'pipe'
        }
      );
      
      // Parse e formatta i risultati
      formatResults(output);
      
    } catch (err) {
      // Se il comando fallisce, prova con psql diretto
      console.log('⚠️  Tentativo con metodo alternativo...\n');
      
      try {
        // Prova a eseguire direttamente con psql se disponibile
        const output = execSync(
          `psql "$(npx supabase status --output json | jq -r '.DB_URL')" -f "${sqlFile}"`,
          { 
            cwd: repoRoot, 
            encoding: 'utf-8',
            stdio: 'pipe'
          }
        );
        
        formatResults(output);
      } catch (err2) {
        console.error('❌ Errore durante l\'esecuzione delle query:', err2.message);
        console.error('\n   Opzioni alternative:');
        console.error('   1. Esegui manualmente lo script SQL:');
        console.error(`      psql <CONNECTION_STRING> -f ${sqlFile}`);
        console.error('   2. Oppure copia e incolla il contenuto in un client SQL\n');
        process.exit(1);
      }
    }
    
  } catch (err) {
    console.error('❌ Errore nella lettura del file SQL:', err.message);
    process.exit(1);
  }
}

function formatResults(output) {
  // Il formato dell'output di psql è tabellare
  // Dividiamo per righe e cerchiamo i risultati
  
  const lines = output.split('\n');
  let currentCheck = null;
  let inResult = false;
  let resultLines = [];
  
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    
    // Cerca le righe che iniziano con il nome del check
    if (line.includes('check_type') || line.includes('CHECK_TYPE')) {
      // Salta la riga header se presente
      continue;
    }
    
    // Cerca pattern di risultati (righe con pipe | che indicano tabelle)
    if (line.includes('|')) {
      if (!inResult) {
        inResult = true;
        resultLines = [];
      }
      resultLines.push(line);
      continue;
    }
    
    // Quando finisce un risultato, processalo
    if (inResult && (line.trim() === '' || line.match(/^[\s-]+$/))) {
      if (resultLines.length > 0) {
        processResult(resultLines);
        resultLines = [];
        inResult = false;
      }
    }
    
    // Cerca i nomi dei check nel formato SQL
    const checkMatch = line.match(/'(.*?)' AS check_type/);
    if (checkMatch) {
      currentCheck = checkMatch[1];
    }
  }
  
  // Processa l'ultimo risultato se presente
  if (resultLines.length > 0) {
    processResult(resultLines);
  }
  
  console.log('═══════════════════════════════════════════════════════════════\n');
  console.log('✅ Verifica completata!\n');
}

function processResult(resultLines) {
  if (resultLines.length === 0) return;
  
  // Estrai header e dati
  const headerLine = resultLines.find(line => 
    line.toLowerCase().includes('check_type') || 
    line.toLowerCase().includes('count') ||
    line.toLowerCase().includes('subscription')
  );
  
  if (!headerLine) return;
  
  // Parse semplice: cerca il numero nella colonna count
  const countMatch = resultLines[resultLines.length - 1]?.match(/\|\s*(\d+)\s*\|/);
  const count = countMatch ? parseInt(countMatch[1], 10) : 0;
  
  // Estrai il tipo di check dalla prima riga o dall'header
  let checkType = 'Verifica';
  for (const line of resultLines) {
    if (line.toLowerCase().includes('check_type')) {
      const match = line.match(/\|\s*([^|]+?)\s*\|/);
      if (match) {
        checkType = match[1].trim();
        break;
      }
    }
  }
  
  // Mostra risultato
  if (count === 0) {
    console.log(`✅ ${checkType}`);
    console.log(`   Nessun problema trovato\n`);
  } else {
    console.log(`❌ ${checkType}`);
    console.log(`   Trovati ${count} problema/i\n`);
    
    // Mostra i dettagli se disponibili
    if (resultLines.length > 2) {
      console.log('   Dettagli:');
      resultLines.slice(1, Math.min(6, resultLines.length - 1)).forEach(line => {
        if (line.trim() && !line.match(/^[\s-]+$/)) {
          console.log(`   ${line.replace(/\|/g, ' | ').trim()}`);
        }
      });
      if (resultLines.length > 6) {
        console.log(`   ... (altri ${resultLines.length - 6} risultati)`);
      }
      console.log('');
    }
  }
}

main().catch(err => {
  console.error('❌ Errore:', err);
  process.exit(1);
});

