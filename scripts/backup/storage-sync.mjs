#!/usr/bin/env node

/**
 * storage-sync — copia completa dello Storage Supabase su disco, e ripristino. Vedi BACKUP.md.
 *
 *     node scripts/backup/storage-sync.mjs pull <cartella>   # scarica bucket e file
 *     node scripts/backup/storage-sync.mjs push <cartella>   # ricrea i bucket e ricarica i file
 *     node scripts/backup/storage-sync.mjs verify <cartella> # riscarica e confronta i checksum
 *     node scripts/backup/storage-sync.mjs list              # quanto scaricherebbe pull, senza scaricare
 *
 * Variabili: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
 *
 * Struttura della cartella:
 *     buckets.json              definizione dei bucket (pubblico/privato, limiti, tipi ammessi)
 *     manifest.json             un elemento per file: bucket, percorso, dimensione, sha256, tipo
 *     files/<bucket>/<percorso> i file
 *
 * Non copia le cartelle `varianti/` delle foto (vedi CARTELLE_ESCLUSE).
 * Non stampa mai nomi di file: i log delle Actions del repo sono pubblici.
 */

import { createClient } from '@supabase/supabase-js';
import { createHash } from 'crypto';
import { mkdir, readFile, writeFile } from 'fs/promises';
import { dirname, join } from 'path';

const [mode, dir] = process.argv.slice(2);
if (!['pull', 'push', 'verify', 'list'].includes(mode) || (!dir && mode !== 'list')) {
  console.error('Uso: storage-sync.mjs pull|push|verify <cartella>, oppure storage-sync.mjs list');
  process.exit(2);
}

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error('❌ Servono SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(2);
}

/**
 * Cartelle in cima ai bucket che il backup non copia. `varianti/` contiene le versioni ridotte
 * delle foto (supabase/storage/FOTO.md): pesano più degli originali, e dopo un ripristino si
 * ricreano dagli originali in Gestionale → Sistema → Foto. Ogni MB scaricato da qui conta nel
 * traffico in uscita (egress) di Supabase, che nel piano gratuito ha un tetto mensile.
 */
const CARTELLE_ESCLUSE = new Set(['varianti']);

/** Tentativi per ogni file, e tempo massimo di una richiesta, risposta compresa. */
const TENTATIVI = 4;
const TEMPO_MASSIMO_MS = 120_000;

const fetchConTempoMassimo = (input, init = {}) => {
  const limite = AbortSignal.timeout(TEMPO_MASSIMO_MS);
  return fetch(input, { ...init, signal: init.signal ? AbortSignal.any([init.signal, limite]) : limite });
};

const supabase = createClient(url, key, {
  auth: { persistSession: false },
  global: { fetch: fetchConTempoMassimo },
});
const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');
const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

/** Messaggio con la causa: per una connessione interrotta, fetch dice solo «terminated». */
const motivo = (err) => (err?.cause?.message ? `${err.message} (${err.cause.message})` : String(err?.message ?? err));

/**
 * Scarica un file, riprovando con pause crescenti: una connessione che cade a metà non deve far
 * fallire tutto il backup, né far riscaricare da capo i file già presi.
 */
async function download(bucket, path) {
  for (let tentativo = 1; ; tentativo++) {
    try {
      const { data: blob, error } = await supabase.storage.from(bucket).download(path);
      if (error) throw error;
      return Buffer.from(await blob.arrayBuffer());
    } catch (err) {
      if (tentativo === TENTATIVI) throw new Error(`download in ${bucket}: ${motivo(err)}`);
      console.log(`  ↻ download in ${bucket} non riuscito (${motivo(err)}): tentativo ${tentativo + 1} di ${TENTATIVI}`);
      await sleep(5000 * 2 ** (tentativo - 1));
    }
  }
}

/** Elenca ricorsivamente i file di un bucket (le cartelle arrivano con id null). */
async function listAll(bucket, prefix = '') {
  const files = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await supabase.storage.from(bucket).list(prefix, { limit: 1000, offset });
    if (error) throw new Error(`list ${bucket}: ${error.message}`);
    for (const item of data) {
      const path = prefix ? `${prefix}/${item.name}` : item.name;
      if (item.id === null) {
        if (!prefix && CARTELLE_ESCLUSE.has(item.name)) continue;
        files.push(...await listAll(bucket, path));
      } else {
        files.push({ path, contentType: item.metadata?.mimetype ?? null, size: item.metadata?.size ?? 0 });
      }
    }
    if (data.length < 1000) return files;
  }
}

/** Solo l'elenco: quanti file e MB copierebbe pull. Non scarica nessun file. */
async function list() {
  const { data: buckets, error } = await supabase.storage.listBuckets();
  if (error) throw new Error(`listBuckets: ${error.message}`);
  let count = 0;
  let bytes = 0;
  for (const b of buckets) {
    const files = await listAll(b.id);
    const size = files.reduce((sum, f) => sum + f.size, 0);
    console.log(`  ${b.id}: ${files.length} file, ${(size / 1048576).toFixed(1)} MB`);
    count += files.length;
    bytes += size;
  }
  console.log(`Totale: ${buckets.length} bucket, ${count} file, ${(bytes / 1048576).toFixed(1)} MB (escluse: ${[...CARTELLE_ESCLUSE].join(', ')})`);
}

async function pull() {
  const { data: buckets, error } = await supabase.storage.listBuckets();
  if (error) throw new Error(`listBuckets: ${error.message}`);

  const manifest = [];
  let bytes = 0;
  for (const b of buckets) {
    for (const f of await listAll(b.id)) {
      const buf = await download(b.id, f.path);
      const target = join(dir, 'files', b.id, f.path);
      await mkdir(dirname(target), { recursive: true });
      await writeFile(target, buf);
      manifest.push({ bucket: b.id, path: f.path, size: buf.length, sha256: sha256(buf), contentType: f.contentType });
      bytes += buf.length;
    }
  }

  const bucketDefs = buckets.map(({ id, name, public: isPublic, file_size_limit, allowed_mime_types }) =>
    ({ id, name, public: isPublic, file_size_limit, allowed_mime_types }));
  await writeFile(join(dir, 'buckets.json'), JSON.stringify(bucketDefs, null, 2));
  await writeFile(join(dir, 'manifest.json'), JSON.stringify(manifest, null, 2));
  console.log(`✅ Storage: ${buckets.length} bucket, ${manifest.length} file, ${(bytes / 1048576).toFixed(1)} MB`);
}

async function push() {
  const bucketDefs = JSON.parse(await readFile(join(dir, 'buckets.json'), 'utf-8'));
  const manifest = JSON.parse(await readFile(join(dir, 'manifest.json'), 'utf-8'));

  const { data: existing } = await supabase.storage.listBuckets();
  const have = new Set((existing ?? []).map(b => b.id));
  for (const b of bucketDefs) {
    if (have.has(b.id)) continue;
    const { error } = await supabase.storage.createBucket(b.id, {
      public: b.public,
      fileSizeLimit: b.file_size_limit ?? undefined,
      allowedMimeTypes: b.allowed_mime_types ?? undefined,
    });
    if (error) throw new Error(`createBucket ${b.id}: ${error.message}`);
  }

  for (const f of manifest) {
    const buf = await readFile(join(dir, 'files', f.bucket, f.path));
    if (sha256(buf) !== f.sha256) throw new Error(`checksum diverso in ${f.bucket}: file corrotto nell'archivio`);
    const { error } = await supabase.storage.from(f.bucket)
      .upload(f.path, buf, { upsert: true, contentType: f.contentType ?? undefined });
    if (error) throw new Error(`upload in ${f.bucket}: ${error.message}`);
  }
  console.log(`✅ Storage ripristinato: ${bucketDefs.length} bucket, ${manifest.length} file`);
}

/** Riscarica ogni file dal progetto e lo confronta con il manifest del backup. */
async function verify() {
  const manifest = JSON.parse(await readFile(join(dir, 'manifest.json'), 'utf-8'));
  for (const f of manifest) {
    const buf = await download(f.bucket, f.path);
    if (sha256(buf) !== f.sha256) throw new Error(`checksum diverso in ${f.bucket}`);
  }
  console.log(`✅ Storage verificato: ${manifest.length} file identici al backup (sha256)`);
}

({ pull, push, verify, list })[mode]().catch(err => { console.error('❌', err.message); process.exit(1); });
