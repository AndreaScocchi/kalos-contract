/**
 * Utilità comuni degli scenari in locale col finto Stripe (sessione 5, `run-scenarios.mjs`, e
 * sessione 9, `run-scenarios-app.mjs`): configurazione del Supabase locale, chiamate REST, RPC ed
 * edge function, controllo del finto Stripe, eventi firmati come li firma Stripe, utenti di prova,
 * interruttori.
 */

import { createHmac, randomBytes } from 'node:crypto'
import { execSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ENV_FILE = join(HERE, '.env.functions.local')
export const FAKE = process.env.FAKE_STRIPE_URL ?? 'http://localhost:12111'
const WHSEC = 'whsec_local_prove_sessione5'

// Da dove torna l'app dopo il pagamento, in locale (sessione 9)
export const APP_ORIGIN = 'http://localhost:8081'

// ── Configurazione del Supabase locale ─────────────────────────────────────────────────────

const status = JSON.parse(execSync('npx supabase status -o json 2>/dev/null', { cwd: join(HERE, '../..') }).toString())
const API = status.API_URL
const ANON = status.ANON_KEY
const SERVICE = status.SERVICE_ROLE_KEY
const FN = `${API}/functions/v1`

if (!existsSync(ENV_FILE)) {
  writeFileSync(ENV_FILE, [
    '# Scritto da scripts/stripe-local/lib.mjs. SOLO per le prove in locale.',
    'STRIPE_SECRET_KEY=sk_test_locale_finto',
    `STRIPE_WEBHOOK_SECRET=${WHSEC}`,
    'STRIPE_API_BASE=http://host.docker.internal:12111',
    'CHECKOUT_ALLOWED_ORIGINS=http://localhost:3333',
    `APP_RETURN_ORIGINS=${APP_ORIGIN}`,
    '',
  ].join('\n'))
  console.log(`Scritto ${ENV_FILE}: rilancia \`npx supabase functions serve --env-file ${ENV_FILE}\` e poi questo script.`)
  process.exit(2)
}
// Il file scritto nella sessione 5 non ha l'indirizzo dell'app: lo si aggiunge una volta
if (!readFileSync(ENV_FILE, 'utf8').includes('APP_RETURN_ORIGINS=')) {
  writeFileSync(ENV_FILE, `${readFileSync(ENV_FILE, 'utf8').trimEnd()}\nAPP_RETURN_ORIGINS=${APP_ORIGIN}\n`)
  console.log(`Aggiunto APP_RETURN_ORIGINS a ${ENV_FILE}: rilancia \`npx supabase functions serve --env-file ${ENV_FILE}\` e poi questo script.`)
  process.exit(2)
}

// ── Utilità ──────────────────────────────────────────────────────────────────────────────────

let passed = 0
let failed = 0
export function check(label, ok, detail = '') {
  if (ok) { passed++; console.log(`  ✅ ${label}`) } else { failed++; console.log(`  ❌ ${label}${detail ? ` — ${detail}` : ''}`) }
}
export const results = () => ({ passed, failed })
export const section = (title) => console.log(`\n${title}`)
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

export async function rest(path, { method = 'GET', body, token = SERVICE, prefer } = {}) {
  const res = await fetch(`${API}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: token === SERVICE ? SERVICE : ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
      ...(prefer ? { Prefer: prefer } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  return { status: res.status, json: text ? JSON.parse(text) : null }
}
export const rpc = (name, args = {}, token = SERVICE) => rest(`rpc/${name}`, { method: 'POST', body: args, token })

export async function fn(name, body, { token = ANON, headers = {} } = {}) {
  const res = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Origin: 'http://localhost:3333', ...headers },
    body: JSON.stringify(body),
  })
  const text = await res.text()
  let json = null
  try { json = JSON.parse(text) } catch { json = { raw: text } }
  return { status: res.status, json }
}

export async function control(path, body) {
  const res = await fetch(`${FAKE}/_control/${path}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`finto Stripe ${path}: ${await res.text()}`)
  return res.json()
}
export const object = (kind, id) => control('object', { kind, id })

/** Un evento firmato come lo firma Stripe (schema v1: HMAC-SHA256 di "timestamp.corpo"). */
export async function webhook(type, dataObject, { secret = WHSEC, livemode = false, eventId, signature } = {}) {
  const payload = JSON.stringify({
    id: eventId ?? `evt_test_${randomBytes(8).toString('hex')}`,
    object: 'event', api_version: '2026-08-26.dahlia', created: Math.floor(Date.now() / 1000),
    livemode, type, data: { object: dataObject },
  })
  const t = Math.floor(Date.now() / 1000)
  const v1 = createHmac('sha256', secret).update(`${t}.${payload}`).digest('hex')
  const res = await fetch(`${FN}/stripe-webhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(signature === null ? {} : { 'Stripe-Signature': signature ?? `t=${t},v1=${v1}` }) },
    body: payload,
  })
  const text = await res.text()
  let json = null
  try { json = JSON.parse(text) } catch { json = { raw: text } }
  return { status: res.status, json, eventPayload: payload }
}

export async function user(emailPrefix, role, meta) {
  const email = `${emailPrefix}+${Date.now()}@test.kalos`
  const password = 'prova-sessione5-Pw1!'
  const created = await fetch(`${API}/auth/v1/admin/users`, {
    method: 'POST', headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, email_confirm: true, ...(meta ? { user_metadata: meta } : {}) }),
  }).then((r) => r.json())
  if (role) await rest(`profiles?id=eq.${created.id}`, { method: 'PATCH', body: { role } })
  const session = await fetch(`${API}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }),
  }).then((r) => r.json())
  return { id: created.id, email, token: session.access_token }
}

export async function setFlag(key, enabled) {
  await rest('feature_flags?on_conflict=key', { method: 'POST', body: { key, enabled }, prefer: 'resolution=merge-duplicates' })
}

export const one = async (path) => (await rest(path)).json?.[0] ?? null
export const count = async (path) => (await rest(path)).json?.length ?? 0
