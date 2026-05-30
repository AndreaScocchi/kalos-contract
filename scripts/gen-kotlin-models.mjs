#!/usr/bin/env node

/**
 * gen-kotlin-models — secondo stadio della pipeline di codegen (Fase 0, punto 4).
 * Legge codegen/schema.json (tipi Postgres precisi) ed emette data class kotlinx.serialization,
 * versionate con lo stesso tag del contract. Output deterministico per il drift-check in CI.
 *
 *     codegen/schema.json → codegen/kotlin/models/<Model>.kt + Enums.kt
 *
 * USO: node scripts/gen-kotlin-models.mjs
 *
 * NB sui tipi data/ora: timestamptz/date/time sono mappati a String (ISO-8601). Quando la nuova
 * app KMP adotterà kotlinx-datetime potremo cambiare la mappa qui in un punto solo.
 */

import { readFile, writeFile, mkdir, rm, readdir } from 'fs/promises';
import { existsSync } from 'fs';
import { join } from 'path';

const ROOT = process.cwd();
const SCHEMA_PATH = join(ROOT, 'codegen', 'schema.json');
const OUT_DIR = join(ROOT, 'codegen', 'kotlin', 'models');
const PKG = 'it.kalos.contract.models';

// udt_name Postgres → tipo Kotlin
const TYPE_MAP = {
  uuid: 'String',
  text: 'String', varchar: 'String', bpchar: 'String', char: 'String', citext: 'String', name: 'String',
  bool: 'Boolean',
  int2: 'Int', int4: 'Int', int8: 'Long', oid: 'Long',
  float4: 'Float', float8: 'Double', numeric: 'Double',
  json: 'JsonElement', jsonb: 'JsonElement',
  date: 'String', timestamp: 'String', timestamptz: 'String', time: 'String', timetz: 'String', interval: 'String',
  bytea: 'String', inet: 'String', cidr: 'String', macaddr: 'String',
};

const warnings = [];

function pascal(snake) {
  return snake.split(/[_\s]+/).filter(Boolean).map(s => s[0].toUpperCase() + s.slice(1)).join('');
}
function camel(snake) {
  const p = pascal(snake);
  return p[0].toLowerCase() + p.slice(1);
}
function singularize(name) {
  if (name.endsWith('ies')) return name.slice(0, -3) + 'y';
  if (name.endsWith('ss')) return name;
  if (name.endsWith('s')) return name.slice(0, -1);
  return name;
}
function className(table) { return pascal(singularize(table)); }
function enumClassName(udt) { return pascal(udt); }
function enumConstName(label) { return label.toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/^_|_$/g, ''); }

/** Restituisce { kotlin, usesJson } per una colonna. */
function kotlinType(col, enums) {
  let usesJson = false;
  const resolveBase = (udt, isEnum) => {
    if (isEnum || enums[udt]) return enumClassName(udt);
    const mapped = TYPE_MAP[udt];
    if (mapped) { if (mapped === 'JsonElement') usesJson = true; return mapped; }
    warnings.push(`tipo Postgres non mappato "${udt}" (colonna ${col.name}) → JsonElement`);
    usesJson = true;
    return 'JsonElement';
  };

  let base;
  if (col.isArray) {
    const elemUdt = col.udtName.slice(1); // "_text" → "text"
    const elem = resolveBase(elemUdt, !!enums[elemUdt]);
    base = `List<${elem}>`;
  } else {
    base = resolveBase(col.udtName, col.isEnum);
  }
  return { kotlin: base, usesJson };
}

function genModelFile(table, enums) {
  const cls = className(table.name);
  let usesJson = false;
  let usesSerialName = false;
  const props = table.columns.map(col => {
    const { kotlin, usesJson: j } = kotlinType(col, enums);
    usesJson = usesJson || j;
    const prop = camel(col.name);
    const needsSerial = prop !== col.name;
    usesSerialName = usesSerialName || needsSerial;
    const ann = needsSerial ? `@SerialName("${col.name}") ` : '';
    const type = col.nullable ? `${kotlin}? = null` : kotlin;
    return `    ${ann}val ${prop}: ${type},`;
  });

  const imports = ['import kotlinx.serialization.Serializable'];
  if (usesSerialName) imports.push('import kotlinx.serialization.SerialName');
  if (usesJson) imports.push('import kotlinx.serialization.json.JsonElement');

  return `// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: ${table.name}
package ${PKG}

${imports.sort().join('\n')}

@Serializable
data class ${cls}(
${props.join('\n')}
)
`;
}

function genEnumsFile(enums) {
  const names = Object.keys(enums).sort();
  const blocks = names.map(name => {
    const consts = enums[name].map(label => `    @SerialName("${label}") ${enumConstName(label)},`).join('\n');
    return `@Serializable\nenum class ${enumClassName(name)} {\n${consts}\n}`;
  });
  return `// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
package ${PKG}

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

${blocks.join('\n\n')}
`;
}

async function main() {
  if (!existsSync(SCHEMA_PATH)) {
    console.error(`❌ Manca ${SCHEMA_PATH}. Genera prima lo schema: node scripts/introspect-schema.mjs (richiede DB).`);
    process.exit(1);
  }
  const schema = JSON.parse(await readFile(SCHEMA_PATH, 'utf-8'));
  const enums = schema.enums || {};

  // Pulisci la dir per non lasciare modelli stale di tabelle rimosse.
  if (existsSync(OUT_DIR)) {
    for (const f of await readdir(OUT_DIR)) {
      if (f.endsWith('.kt')) await rm(join(OUT_DIR, f));
    }
  }
  await mkdir(OUT_DIR, { recursive: true });

  const tables = [...schema.tables].sort((a, b) => a.name.localeCompare(b.name));
  for (const table of tables) {
    await writeFile(join(OUT_DIR, `${className(table.name)}.kt`), genModelFile(table, enums));
  }
  if (Object.keys(enums).length) {
    await writeFile(join(OUT_DIR, 'Enums.kt'), genEnumsFile(enums));
  }

  console.log(`✅ Kotlin generato: ${tables.length} modelli + ${Object.keys(enums).length} enum → codegen/kotlin/models/`);
  if (warnings.length) {
    console.log(`⚠️  ${warnings.length} avvisi di mappatura:`);
    for (const w of [...new Set(warnings)]) console.log(`   - ${w}`);
  }
}

main().catch(err => { console.error('❌ gen-kotlin-models errore:', err.message); process.exit(1); });
