#!/usr/bin/env node

/**
 * introspect-schema — legge lo schema REALE dal Postgres ermetico e produce codegen/schema.json,
 * la rappresentazione intermedia con TIPI POSTGRES PRECISI (int4/int8/numeric/uuid/timestamptz/enum…).
 *
 * È il primo stadio della pipeline di codegen (Fase 0, punto 4):
 *     migrazioni → [supabase db start] → introspect-schema → codegen/schema.json → gen-kotlin-models
 *
 * Output deterministico (chiavi/ordini stabili) così il drift-check in CI è affidabile.
 *
 * USO:
 *     node scripts/introspect-schema.mjs                 # usa DATABASE_URL o il default Supabase locale
 *     DATABASE_URL=postgres://… node scripts/introspect-schema.mjs
 *     node scripts/introspect-schema.mjs --db-url postgres://…
 *
 * Richiede la devDependency `pg` e un Postgres raggiungibile (in CI: `supabase db start`).
 */

import { writeFile, mkdir } from 'fs/promises';
import { join, dirname } from 'path';

const DEFAULT_URL = 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const OUT_PATH = join(process.cwd(), 'codegen', 'schema.json');

function getDbUrl() {
  const i = process.argv.indexOf('--db-url');
  if (i !== -1 && process.argv[i + 1]) return process.argv[i + 1];
  return process.env.DATABASE_URL || DEFAULT_URL;
}

const ENUMS_SQL = `
  SELECT t.typname AS name,
         array_agg(e.enumlabel::text ORDER BY e.enumsortorder) AS labels
  FROM pg_type t
  JOIN pg_enum e ON e.enumtypid = t.oid
  JOIN pg_namespace n ON n.oid = t.typnamespace
  WHERE n.nspname = 'public'
  GROUP BY t.typname
  ORDER BY t.typname;
`;

const TABLES_SQL = `
  SELECT c.relname AS name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'            -- solo tabelle ordinarie (no view/matview)
    AND c.relname NOT LIKE 'pg_%'
  ORDER BY c.relname;
`;

// udt_name dà il tipo preciso; per gli ARRAY data_type='ARRAY' e udt_name='_<elem>'.
const COLUMNS_SQL = `
  SELECT
    a.attname                                   AS name,
    format_type(a.atttypid, NULL)               AS data_type,
    t.typname                                   AS udt_name,
    (t.typtype = 'e')                           AS is_enum,
    NOT a.attnotnull                            AS nullable,
    (a.atthasdef OR a.attidentity <> '')        AS has_default,
    a.attnum                                    AS ordinal
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_type t ON t.oid = a.atttypid
  WHERE n.nspname = 'public'
    AND c.relname = $1
    AND a.attnum > 0
    AND NOT a.attisdropped
  ORDER BY a.attnum;
`;

async function main() {
  let pg;
  try {
    pg = await import('pg');
  } catch {
    console.error('❌ Manca la dependency `pg`. Installa con: npm i -D pg');
    process.exit(1);
  }
  const { Client } = pg.default ?? pg;
  const client = new Client({ connectionString: getDbUrl() });

  await client.connect();
  try {
    const enumsRes = await client.query(ENUMS_SQL);
    const enums = {};
    for (const row of enumsRes.rows) enums[row.name] = row.labels;

    const tablesRes = await client.query(TABLES_SQL);
    const tables = [];
    for (const { name } of tablesRes.rows) {
      const colsRes = await client.query(COLUMNS_SQL, [name]);
      const columns = colsRes.rows.map(r => ({
        name: r.name,
        dataType: r.data_type,      // es. "integer", "uuid", "timestamp with time zone", "text[]"
        udtName: r.udt_name,        // es. "int4", "uuid", "timestamptz", "_text", "<enum>"
        isEnum: r.is_enum,
        isArray: r.udt_name.startsWith('_'),
        nullable: r.nullable,
        hasDefault: r.has_default,
      }));
      tables.push({ name, columns });
    }

    const schema = {
      $comment: 'GENERATO da scripts/introspect-schema.mjs — NON modificare a mano. Fonte: schema Postgres applicando le migrazioni.',
      schema: 'public',
      enums,
      tables,
    };

    await mkdir(dirname(OUT_PATH), { recursive: true });
    await writeFile(OUT_PATH, JSON.stringify(schema, null, 2) + '\n');
    console.log(`✅ schema.json scritto: ${tables.length} tabelle, ${Object.keys(enums).length} enum → codegen/schema.json`);
  } finally {
    await client.end();
  }
}

main().catch(err => { console.error('❌ introspect-schema errore:', err.message); process.exit(1); });
