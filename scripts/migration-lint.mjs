#!/usr/bin/env node

/**
 * migration-lint — blocca operazioni DISTRUTTIVE / non-additive nelle migrazioni NUOVE.
 *
 * Principio cardine del progetto (vedi ../docs/NEW_APP_PLAN.md §3 e CONTRACT_DISCIPLINE.md):
 * lo schema condiviso può solo CRESCERE in modo additivo e retro-compatibile finché website,
 * gestionale e PWA vecchia leggono lo stesso DB di produzione. Questo linter rende la regola
 * eseguibile: fallisce (exit 1) se una migrazione contiene un'operazione distruttiva non
 * esplicitamente approvata.
 *
 * GRANDFATHERING: vengono analizzate solo le migrazioni con timestamp > baseline
 * (scripts/migration-lint-baseline.json). Le 144 migrazioni storiche già applicate in prod
 * sono "congelate" (forward-only) e non vengono ri-giudicate.
 *
 * APPROVAZIONE ESPLICITA: una migrazione che ha davvero bisogno di un'operazione distruttiva
 * (caso raro, fase "contract" dopo che tutti i consumer sono migrati) la deve dichiarare con un
 * commento, con motivazione obbligatoria:
 *
 *     -- migration-lint:allow drop-column — reason: colonna X non più usata da nessun consumer dalla v0.2.0
 *     -- migration-lint:allow set-not-null,add-column-not-null-no-default — reason: <perché è sicuro>
 *     -- migration-lint:allow all — reason: <motivazione complessiva>
 *
 * USO:
 *     node scripts/migration-lint.mjs           # lint delle sole migrazioni nuove (> baseline)
 *     node scripts/migration-lint.mjs --all      # lint di TUTTE le migrazioni (solo audit, non in CI)
 *     node scripts/migration-lint.mjs --init      # (ri)genera il baseline al timestamp massimo attuale
 *
 * LIMITE NOTO: i corpi di funzione dollar-quoted ($$ … $$) non vengono analizzati (per evitare
 * falsi positivi); le operazioni distruttive top-level coprono il rischio reale additivo.
 */

import { readdir, readFile, stat, writeFile } from 'fs/promises';
import { existsSync, readFileSync } from 'fs';
import { join, basename } from 'path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = join(ROOT, 'supabase', 'migrations');
const BASELINE_PATH = join(ROOT, 'scripts', 'migration-lint-baseline.json');
const TS_RE = /^(\d{14})_/;

// Regole "semplici": match su una singola istruzione SQL normalizzata (uppercase, spazi collassati).
const SIMPLE_RULES = [
  { id: 'drop-table',      re: /\bDROP\s+TABLE\b/,                   msg: 'DROP TABLE — perdita di dati e rottura dei consumer.' },
  { id: 'drop-column',     re: /\bDROP\s+COLUMN\b/,                  msg: 'DROP COLUMN — perdita di dati; rimuovi una colonna solo dopo che TUTTI i consumer hanno smesso di usarla (release successiva).' },
  { id: 'drop-type',       re: /\bDROP\s+TYPE\b/,                    msg: 'DROP TYPE — rompe colonne/consumer che usano l’enum/tipo.' },
  { id: 'drop-schema',     re: /\bDROP\s+SCHEMA\b/,                  msg: 'DROP SCHEMA — distruttivo.' },
  { id: 'drop-constraint', re: /\bDROP\s+CONSTRAINT\b/,              msg: 'DROP CONSTRAINT — rimuove un vincolo esistente.' },
  { id: 'rename-table',    re: /\bRENAME\s+TO\b/,                    msg: 'RENAME TO — rinominare una tabella rompe i consumer che usano il vecchio nome.' },
  { id: 'rename-column',   re: /\bRENAME\s+COLUMN\b/,                msg: 'RENAME COLUMN — rompe i consumer; aggiungi una colonna nuova invece di rinominare.' },
  { id: 'rename-value',    re: /\bRENAME\s+VALUE\b/,                 msg: 'ALTER TYPE … RENAME VALUE — cambia un valore enum esistente (gli enum si toccano solo con ADD VALUE).' },
  { id: 'set-not-null',    re: /\bSET\s+NOT\s+NULL\b/,              msg: 'SET NOT NULL — può rompere gli INSERT dei consumer che non valorizzano la colonna.' },
  { id: 'truncate',        re: /\bTRUNCATE\b/,                       msg: 'TRUNCATE — cancellazione massiva di dati.' },
  { id: 'revoke',          re: /\bREVOKE\b/,                         msg: 'REVOKE — restringe un accesso esistente (RLS/grant solo additivi).' },
];

/** Rimuove commenti e letterali (stringhe '…' e corpi dollar-quoted $$…$$) senza spezzare le istruzioni. */
function sanitize(sql) {
  let i = 0;
  const n = sql.length;
  const out = [];
  while (i < n) {
    const two = sql.slice(i, i + 2);
    if (two === '--') { while (i < n && sql[i] !== '\n') i++; out.push(' '); continue; }
    if (two === '/*') { i += 2; while (i < n && sql.slice(i, i + 2) !== '*/') i++; i += 2; out.push(' '); continue; }
    const c = sql[i];
    if (c === "'") {
      i++;
      while (i < n) {
        if (sql[i] === "'" && sql[i + 1] === "'") { i += 2; continue; }
        if (sql[i] === "'") { i++; break; }
        i++;
      }
      out.push(" '' ");
      continue;
    }
    if (c === '$') {
      const m = sql.slice(i).match(/^\$[A-Za-z0-9_]*\$/);
      if (m) {
        const tag = m[0];
        const end = sql.indexOf(tag, i + tag.length);
        i = end === -1 ? n : end + tag.length;
        out.push(' $$ ');
        continue;
      }
    }
    out.push(c);
    i++;
  }
  return out.join('');
}

/** Estrae le approvazioni dai commenti RAW (prima della sanitize, che li rimuove). */
function parseAllows(rawSql) {
  const allows = []; // { rules: Set|'all', reason: string|null, line: number }
  const lines = rawSql.split('\n');
  const re = /--\s*migration-lint:allow\s+([a-z0-9,\-\s]+?)\s*(?:—|--|:)\s*reason\s*:?\s*(.*)$/i;
  const reNoReason = /--\s*migration-lint:allow\s+([a-z0-9,\-\s]+)\s*$/i;
  lines.forEach((line, idx) => {
    let m = line.match(re);
    if (m) {
      const ids = m[1].split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
      const reason = (m[2] || '').trim();
      allows.push({ rules: ids.includes('all') ? 'all' : new Set(ids), reason: reason || null, line: idx + 1 });
      return;
    }
    m = line.match(reNoReason);
    if (m) {
      const ids = m[1].split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
      allows.push({ rules: ids.includes('all') ? 'all' : new Set(ids), reason: null, line: idx + 1 });
    }
  });
  return allows;
}

function isAllowed(ruleId, allows) {
  return allows.find(a => (a.rules === 'all' || a.rules.has(ruleId)));
}

function lintStatement(stmt) {
  const S = stmt.replace(/\s+/g, ' ').trim().toUpperCase();
  if (!S) return [];
  const findings = [];
  for (const rule of SIMPLE_RULES) {
    if (rule.re.test(S)) findings.push({ id: rule.id, msg: rule.msg });
  }
  // Contestuali
  if (/\bADD\s+COLUMN\b/.test(S) && /\bNOT\s+NULL\b/.test(S) && !/\bDEFAULT\b/.test(S) && !/\bGENERATED\b/.test(S)) {
    findings.push({ id: 'add-column-not-null-no-default', msg: 'ADD COLUMN … NOT NULL senza DEFAULT — fallisce se la tabella ha righe e rompe gli INSERT esistenti. Aggiungila NULL o con DEFAULT.' });
  }
  if (/^DELETE\s+FROM\b/.test(S) && !/\bWHERE\b/.test(S)) {
    findings.push({ id: 'delete-without-where', msg: 'DELETE senza WHERE — cancellazione massiva di dati.' });
  }
  return findings;
}

async function getMigrationFiles() {
  const files = (await readdir(MIGRATIONS_DIR))
    .filter(f => f.endsWith('.sql') && TS_RE.test(f))
    .sort();
  return files;
}

async function loadBaseline(files) {
  if (existsSync(BASELINE_PATH)) {
    return JSON.parse(readFileSync(BASELINE_PATH, 'utf-8')).grandfatheredThroughTimestamp;
  }
  // Self-init: congela tutto lo storico attuale.
  const maxTs = files.map(f => f.match(TS_RE)[1]).sort().at(-1) || '00000000000000';
  await writeFile(BASELINE_PATH, JSON.stringify({
    grandfatheredThroughTimestamp: maxTs,
    note: 'Migrazioni con timestamp <= questo valore sono storiche (forward-only) e non vengono analizzate. Generato automaticamente.',
  }, null, 2) + '\n');
  console.log(`ℹ️  Baseline creato: migrazioni storiche fino a ${maxTs} congelate.`);
  return maxTs;
}

async function main() {
  const args = process.argv.slice(2);
  const lintAll = args.includes('--all');
  const initOnly = args.includes('--init');

  const files = await getMigrationFiles();

  if (initOnly) {
    const maxTs = files.map(f => f.match(TS_RE)[1]).sort().at(-1) || '00000000000000';
    await writeFile(BASELINE_PATH, JSON.stringify({
      grandfatheredThroughTimestamp: maxTs,
      note: 'Migrazioni con timestamp <= questo valore sono storiche (forward-only) e non vengono analizzate.',
    }, null, 2) + '\n');
    console.log(`✅ Baseline aggiornato a ${maxTs}.`);
    process.exit(0);
  }

  const cutoff = await loadBaseline(files);
  const target = lintAll ? files : files.filter(f => f.match(TS_RE)[1] > cutoff);

  console.log(`🔒 migration-lint — ${target.length} migrazion${target.length === 1 ? 'e' : 'i'} da analizzare${lintAll ? ' (TUTTE, audit)' : ` (nuove, > ${cutoff})`}.`);

  let blocking = 0;
  let approved = 0;

  for (const file of target) {
    const raw = await readFile(join(MIGRATIONS_DIR, file), 'utf-8');
    const allows = parseAllows(raw);
    const statements = sanitize(raw).split(';');

    const fileFindings = [];
    for (const stmt of statements) {
      for (const f of lintStatement(stmt)) fileFindings.push(f);
    }
    // dedup per id
    const seen = new Set();
    const findings = fileFindings.filter(f => (seen.has(f.id) ? false : seen.add(f.id)));

    if (!findings.length) continue;

    console.log(`\n📄 ${file}`);
    for (const f of findings) {
      const allow = isAllowed(f.id, allows);
      if (allow && allow.reason) {
        approved++;
        console.log(`   ✅ [${f.id}] approvato — reason: ${allow.reason}`);
      } else if (allow && !allow.reason) {
        blocking++;
        console.log(`   ❌ [${f.id}] ${f.msg}`);
        console.log(`      ↳ approvazione presente MA senza "reason:" → non valida. Aggiungi la motivazione.`);
      } else {
        blocking++;
        console.log(`   ❌ [${f.id}] ${f.msg}`);
        console.log(`      ↳ se è davvero necessaria e sicura, aggiungi: -- migration-lint:allow ${f.id} — reason: <perché è sicuro>`);
      }
    }
  }

  console.log('');
  if (blocking > 0) {
    console.error(`❌ migration-lint FALLITO: ${blocking} operazion${blocking === 1 ? 'e' : 'i'} distruttiv${blocking === 1 ? 'a' : 'e'} non approvat${blocking === 1 ? 'a' : 'e'}${approved ? ` (${approved} approvate)` : ''}.`);
    console.error('   Le modifiche allo schema devono essere ADDITIVE e retro-compatibili. Vedi CONTRACT_DISCIPLINE.md.');
    process.exit(1);
  }
  console.log(`✅ migration-lint OK — nessuna operazione distruttiva non approvata${approved ? ` (${approved} approvate con motivazione)` : ''}.`);
  process.exit(0);
}

main().catch(err => { console.error('❌ migration-lint errore:', err); process.exit(1); });
