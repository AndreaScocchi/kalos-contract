#!/usr/bin/env node

/**
 * make-anon-seed — genera un seed ANONIMIZZATO dai dati di prod, per lo staging LOCALE.
 * (Fase 0, §3.bis — alternativa free al branching con dati reali.)
 *
 * Legge la prod in SOLA LETTURA, anonimizza le sole colonne PII (preservando id/FK/enum/date così
 * le relazioni restano valide) ed emette supabase/seed-anon.sql (gitignored).
 *
 * Carica i dati in locale (dopo `supabase db reset`) con:
 *     psql "$LOCAL_DB_URL" -f supabase/seed-anon.sql
 *
 * Connessione prod: SUPABASE_DB_URL (consigliato un ruolo read-only).
 * USO: SUPABASE_DB_URL=postgres://… node scripts/make-anon-seed.mjs
 *
 * ⚠️ DRAFT da validare nella sessione con credenziali prod: l'elenco tabelle/PII va confermato
 *    contro lo schema reale prima dell'uso. Non esegue nulla in scrittura sulla prod.
 */

import { writeFile } from 'fs/promises';
import { join } from 'path';

const OUT = join(process.cwd(), 'supabase', 'seed-anon.sql');

// Tabelle da esportare (ordine = rispetto delle FK). NIENTE profiles/auth (dipende da auth.users).
const TABLES = ['activities', 'operators', 'plans', 'plan_activities', 'clients', 'events'];

// Colonne PII da anonimizzare: column → (rowIndex, value) => nuovoValore (string SQL-ready o null).
const PII = {
  clients: {
    full_name: (i) => `'Cliente ${i + 1}'`,
    email: (i) => `'cliente${i + 1}@example.test'`,
    phone: (i) => `'+39 000 ${String(i + 1).padStart(6, '0')}'`,
    notes: () => 'NULL',
    birthday: (i, v) => (v == null ? 'NULL' : `'19${String(70 + (i % 30)).padStart(2, '0')}-01-01'`),
  },
  operators: {
    // gli operatori sono pubblici sul sito; manteniamo i nomi ma azzeriamo eventuali contatti privati
    phone: () => 'NULL',
    email: (i) => `'operatore${i + 1}@example.test'`,
  },
};

function sqlLiteral(v) {
  if (v === null || v === undefined) return 'NULL';
  if (typeof v === 'number') return String(v);
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'object') return `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb`;
  return `'${String(v).replace(/'/g, "''")}'`;
}

async function main() {
  if (!process.env.SUPABASE_DB_URL) {
    console.error('❌ Imposta SUPABASE_DB_URL (consigliato ruolo read-only).');
    process.exit(1);
  }
  let pg;
  try { pg = await import('pg'); } catch { console.error('❌ Manca `pg` (npm i -D pg).'); process.exit(1); }
  const { Client } = pg.default ?? pg;
  const client = new Client({ connectionString: process.env.SUPABASE_DB_URL });
  await client.connect();

  const out = ['-- SEED ANONIMIZZATO (generato da make-anon-seed.mjs) — solo staging locale. NON committare.', 'BEGIN;'];
  try {
    for (const table of TABLES) {
      let rows;
      try {
        rows = (await client.query(`SELECT * FROM public.${table} ORDER BY 1`)).rows;
      } catch (e) {
        out.push(`-- ${table}: SKIP (${e.message})`);
        continue;
      }
      if (!rows.length) { out.push(`-- ${table}: 0 righe`); continue; }
      const cols = Object.keys(rows[0]);
      out.push(`\n-- ${table} (${rows.length} righe)`);
      rows.forEach((row, i) => {
        const values = cols.map(col => {
          const rule = PII[table]?.[col];
          if (rule) return rule(i, row[col]);
          return sqlLiteral(row[col]);
        });
        out.push(`INSERT INTO public.${table} (${cols.join(', ')}) VALUES (${values.join(', ')}) ON CONFLICT DO NOTHING;`);
      });
    }
    out.push('COMMIT;');
    await writeFile(OUT, out.join('\n') + '\n');
    console.log(`✅ Seed anonimizzato scritto: ${OUT}`);
    console.log('   Caricalo in locale con: psql "$LOCAL_DB_URL" -f supabase/seed-anon.sql');
  } finally {
    await client.end();
  }
}

main().catch(err => { console.error('❌ make-anon-seed errore:', err.message); process.exit(1); });
