// Edge Function: site-rebuild (sessione 6)
//
// Fa ricostruire il sito su Netlify quando dal gestionale cambiano luoghi, gruppi, attività, eventi
// o l'interruttore del 5x1000: le pagine prerenderizzate (anteprime, sitemap, pagine per comune)
// nascono al build, quindi senza una build nuova resterebbero quelle di prima.
//
// La chiama solo il job `internal.cron_site_rebuild` (pg_cron, con la chiave di servizio), dopo
// qualche minuto di quiete. Qui si chiama il build hook e si scrive l'esito in
// `site_rebuild_state`, che ops-health controlla.
//
// Secret: NETLIFY_BUILD_HOOK_URL (Netlify → sito → Site configuration → Build & deploy → Build hooks).
// Senza secret risponde 503 e lo scrive nell'esito: niente di rotto, solo "non configurato".

import { corsHeaders } from '../_shared/cors.ts'
import { adminClient, jsonResponse } from '../_shared/http.ts'

const LABELS: Record<string, string> = {
  locations: 'luoghi',
  activity_groups: 'gruppi',
  activities: 'attività',
  events: 'eventi',
  feature_flags: '5x1000',
}

async function report(ok: boolean, status: number | null, error: string | null) {
  const { error: dbError } = await adminClient()
    .from('site_rebuild_state')
    .update({ reported_at: new Date().toISOString(), last_ok: ok, last_status: status, last_error: error })
    .eq('id', true)
  if (dbError) console.error('site-rebuild: esito non registrato', dbError.message)
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Solo il job, con la chiave di servizio (come process-notification-queue), ma una chiave vuota
  // non deve bastare: `includes('')` è sempre vero.
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const authHeader = req.headers.get('Authorization') ?? ''
  if (serviceKey.length < 20 || !authHeader.includes(serviceKey)) {
    return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)
  }

  const hookUrl = Deno.env.get('NETLIFY_BUILD_HOOK_URL') ?? ''
  if (!/^https:\/\/api\.netlify\.com\/build_hooks\/[A-Za-z0-9]+$/.test(hookUrl)) {
    await report(false, null, 'NOT_CONFIGURED: manca il secret NETLIFY_BUILD_HOOK_URL, o non è un build hook di Netlify')
    return jsonResponse({ ok: false, reason: 'NOT_CONFIGURED' }, 503)
  }

  let requestedBy = ''
  try {
    const body = await req.json()
    requestedBy = typeof body?.requested_by === 'string' ? body.requested_by : ''
  } catch {
    // corpo vuoto: si ricostruisce lo stesso
  }

  // Il titolo compare nell'elenco dei deploy di Netlify: dice perché è partita la build.
  const title = `Gestionale: ${LABELS[requestedBy] ?? 'contenuti'} aggiornati`
  const url = `${hookUrl}?trigger_title=${encodeURIComponent(title)}`

  try {
    const res = await fetch(url, { method: 'POST', body: '{}' })
    if (!res.ok) {
      const text = (await res.text()).slice(0, 300)
      await report(false, res.status, `Netlify ha risposto ${res.status}: ${text}`)
      return jsonResponse({ ok: false, reason: 'HOOK_FAILED', status: res.status }, 502)
    }
    await report(true, res.status, null)
    return jsonResponse({ ok: true, status: res.status })
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    await report(false, null, `Netlify non raggiungibile: ${message}`)
    return jsonResponse({ ok: false, reason: 'HOOK_UNREACHABLE' }, 502)
  }
})
