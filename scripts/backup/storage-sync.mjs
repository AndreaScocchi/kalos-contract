#!/usr/bin/env node

/**
 * storage-sync — copia dello Storage Supabase, e ripristino. Vedi BACKUP.md.
 *
 *     node scripts/backup/storage-sync.mjs snapshot <cartella> # backup notturno: i file su S3, cifrati uno per uno
 *     node scripts/backup/storage-sync.mjs pull <cartella>     # scarica bucket e file su disco
 *     node scripts/backup/storage-sync.mjs unpack <cartella> <file-cifrati> <chiave-age>
 *                                                              # decifra i file di una notte scaricati da S3
 *     node scripts/backup/storage-sync.mjs push <cartella>     # ricrea i bucket e ricarica i file
 *     node scripts/backup/storage-sync.mjs verify <cartella>   # riscarica e confronta i checksum
 *     node scripts/backup/storage-sync.mjs list                # quanto scaricherebbe pull, senza scaricare
 *
 * Variabili: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (tutti tranne unpack); per snapshot anche
 * BACKUP_S3_BUCKET, BACKUP_AGE_RECIPIENT, BACKUP_SNAPSHOT (nome della notte) e le credenziali AWS.
 *
 * Struttura della cartella:
 *     buckets.json              definizione dei bucket (pubblico/privato, limiti, tipi ammessi)
 *     manifest.json             un elemento per file: bucket, percorso, dimensione, sha256, tipo
 *                               (con snapshot: `blob` al posto di sha256, che aggiunge unpack)
 *     snapshot.json             solo con snapshot: bucket S3 e prefisso dei file della notte
 *     files/<bucket>/<percorso> i file (con snapshot: solo dopo unpack)
 *
 * snapshot scarica da Supabase solo i file nuovi o cambiati: quelli già salvati una notte
 * precedente li copia dentro S3, senza traffico da Supabase. Non copia le cartelle `varianti/`
 * delle foto (vedi CARTELLE_ESCLUSE).
 * Non stampa mai nomi di file: i log delle Actions del repo sono pubblici.
 */

import { createClient } from '@supabase/supabase-js';
import { spawn } from 'child_process';
import { createHash } from 'crypto';
import { mkdir, readFile, rm, writeFile } from 'fs/promises';
import { dirname, join } from 'path';

const [mode, dir, ...rest] = process.argv.slice(2);
if (!['snapshot', 'pull', 'unpack', 'push', 'verify', 'list'].includes(mode)
    || (!dir && mode !== 'list') || (mode === 'unpack' && rest.length < 2)) {
  console.error('Uso: storage-sync.mjs snapshot|pull|push|verify <cartella>, storage-sync.mjs unpack <cartella> <file-cifrati> <chiave-age>, oppure storage-sync.mjs list');
  process.exit(2);
}

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (mode !== 'unpack' && (!url || !key)) {
  console.error('❌ Servono SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(2);
}

/**
 * Cartelle in cima ai bucket che il backup non copia. `varianti/` contiene le versioni ridotte
 * delle foto (supabase/storage/FOTO.md): pesano più degli originali, e dopo un ripristino si
 * ricreano dagli originali (FOTO.md, «Backup»). Ogni MB scaricato da qui conta nel
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

const supabase = mode === 'unpack' ? null : createClient(url, key, {
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

/** Esegue un comando (aws, age) e restituisce l'uscita; l'errore riporta solo il messaggio del comando. */
function run(cmd, args, input) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'pipe'] });
    const out = [];
    const err = [];
    child.stdout.on('data', chunk => out.push(chunk));
    child.stderr.on('data', chunk => err.push(chunk));
    child.stdin.on('error', () => {});
    child.on('error', reject);
    child.on('close', code => (code === 0
      ? resolve(Buffer.concat(out))
      : reject(new Error(`${cmd} ${args[0]}: ${Buffer.concat(err).toString().trim() || `uscita ${code}`}`))));
    child.stdin.end(input);
  });
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
        files.push({
          path,
          contentType: item.metadata?.mimetype ?? null,
          size: item.metadata?.size ?? 0,
          // Cambia se il file viene sostituito: è l'identità della copia su S3 (vedi snapshot).
          version: [item.id, item.metadata?.eTag, item.metadata?.size, item.metadata?.lastModified ?? item.updated_at].join('|'),
        });
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

const bucketDefinitions = (buckets) => buckets.map(({ id, name, public: isPublic, file_size_limit, allowed_mime_types }) =>
  ({ id, name, public: isPublic, file_size_limit, allowed_mime_types }));

/**
 * Backup notturno dello Storage su S3, un file cifrato per ogni file di Supabase, in
 * `storage/<notte>/<blob>.age`. `blob` è l'impronta di bucket, percorso e versione del file (niente
 * nomi su S3). Se lo stesso blob c'è già in una notte precedente lo copia dentro S3; altrimenti lo
 * scarica da Supabase. Ogni notte ha così tutti i suoi file, e la regola dei 30 giorni del bucket
 * li toglie insieme all'archivio della stessa notte.
 */
async function snapshot() {
  const s3Bucket = process.env.BACKUP_S3_BUCKET;
  const recipient = process.env.BACKUP_AGE_RECIPIENT;
  const night = process.env.BACKUP_SNAPSHOT;
  if (!s3Bucket || !recipient || !night) throw new Error('Servono BACKUP_S3_BUCKET, BACKUP_AGE_RECIPIENT e BACKUP_SNAPSHOT.');
  const prefix = `storage/${night}/`;

  // Il blob più recente già su S3, per impronta. I nomi delle notti sono date: l'ordine alfabetico è quello del tempo.
  const keys = JSON.parse((await run('aws', ['s3api', 'list-objects-v2', '--bucket', s3Bucket, '--prefix', 'storage/',
    '--query', 'Contents[].Key', '--output', 'json'])).toString()) ?? [];
  const saved = new Map();
  for (const k of keys.sort()) {
    const match = /^storage\/[^/]+\/([0-9a-f]{64})\.age$/.exec(k);
    if (match) saved.set(match[1], k);
  }

  const { data: buckets, error } = await supabase.storage.listBuckets();
  if (error) throw new Error(`listBuckets: ${error.message}`);

  await mkdir(dir, { recursive: true });
  const encrypted = join(dir, '.blob.age');
  const manifest = [];
  let copied = 0;
  let downloaded = 0;
  let bytes = 0;
  for (const b of buckets) {
    for (const f of await listAll(b.id)) {
      const blob = sha256(`${b.id}\n${f.path}\n${f.version}`);
      const target = `${prefix}${blob}.age`;
      let done = false;
      if (saved.has(blob)) {
        try {
          await run('aws', ['s3api', 'copy-object', '--bucket', s3Bucket, '--copy-source', `${s3Bucket}/${saved.get(blob)}`,
            '--key', target, '--output', 'json']);
          copied++;
          done = true;
        } catch (err) {
          // Per esempio la notte di origine è appena scaduta: si riscarica.
          console.log(`  ↻ copia su S3 non riuscita (${err.message}): lo riscarico`);
        }
      }
      if (!done) {
        const buf = await download(b.id, f.path);
        await writeFile(encrypted, await run('age', ['-r', recipient], buf));
        await run('aws', ['s3api', 'put-object', '--bucket', s3Bucket, '--key', target, '--body', encrypted, '--output', 'json']);
        downloaded++;
        bytes += buf.length;
      }
      manifest.push({ bucket: b.id, path: f.path, size: f.size, contentType: f.contentType, blob });
    }
  }
  await rm(encrypted, { force: true });

  // Controllo finale: su S3 la notte ha esattamente i file del manifest.
  const stored = JSON.parse((await run('aws', ['s3api', 'list-objects-v2', '--bucket', s3Bucket, '--prefix', prefix,
    '--query', 'Contents[].Key', '--output', 'json'])).toString()) ?? [];
  const expected = new Set(manifest.map(f => `${prefix}${f.blob}.age`));
  if (stored.length !== expected.size || !stored.every(k => expected.has(k))) {
    throw new Error(`su S3 la notte ha ${stored.length} file invece di ${expected.size}`);
  }

  await writeFile(join(dir, 'buckets.json'), JSON.stringify(bucketDefinitions(buckets), null, 2));
  await writeFile(join(dir, 'manifest.json'), JSON.stringify(manifest, null, 2));
  await writeFile(join(dir, 'snapshot.json'), JSON.stringify({ bucket: s3Bucket, prefix }, null, 2));
  console.log(`✅ Storage: ${buckets.length} bucket, ${manifest.length} file su S3 · scaricati da Supabase ${downloaded} (${(bytes / 1048576).toFixed(1)} MB), copiati dentro S3 ${copied}`);
}

/** Ripristino: decifra i file di una notte (scaricati da S3) nella cartella, e completa il manifest con gli sha256. */
async function unpack() {
  const [blobsDir, identity] = rest;
  const manifest = JSON.parse(await readFile(join(dir, 'manifest.json'), 'utf-8'));
  for (const f of manifest) {
    const source = join(blobsDir, `${f.blob}.age`);
    const buf = await run('age', ['-d', '-i', identity, source]).catch(err => {
      throw new Error(`file ${f.blob}.age mancante o illeggibile in ${blobsDir}: ${err.message}`);
    });
    if (buf.length !== f.size) throw new Error(`dimensione diversa per ${f.blob}.age: ${buf.length} invece di ${f.size}`);
    const target = join(dir, 'files', f.bucket, f.path);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, buf);
    f.sha256 = sha256(buf);
  }
  await writeFile(join(dir, 'manifest.json'), JSON.stringify(manifest, null, 2));
  console.log(`✅ Storage decifrato: ${manifest.length} file`);
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

  await writeFile(join(dir, 'buckets.json'), JSON.stringify(bucketDefinitions(buckets), null, 2));
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

({ snapshot, pull, unpack, push, verify, list })[mode]().catch(err => { console.error('❌', err.message); process.exit(1); });
