// Edge Function: send-push  (Fase 8 — consegna push NATIVA APNs/FCM)
//
// STATO: SKELETON CABLATO MA NON DEPLOYATO. Spedire ≠ attivare (NEW_APP_PLAN.md §3/§8).
// Questa funzione è la consegna push per la NUOVA app KMP (token nativi APNs/FCM), distinta da
// `process-notification-queue` che serve la PWA legacy (Expo / Web Push).
//
// Resta INERTE finché non si verificano TUTTE queste condizioni:
//   1) feature_flags.push_delivery = true  (acceso dallo staff dal gestionale);
//   2) credenziali APNs presenti  (APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY);
//   3) credenziali FCM presenti   (FCM_SERVICE_ACCOUNT_JSON, progetto Firebase).
// In mancanza, ritorna { ok: true, skipped: <motivo> } senza inviare nulla — così il deploy è
// innocuo e si può collaudare la pipeline (queue → logs) prima di avere gli account store.
//
// PREREQUISITI (segnalati all'utente, non bloccano la parte in-app):
//   * iOS  → Apple Developer Program (99€/anno) + APNs Auth Key (.p8) + entitlement push + device fisico.
//   * Android → progetto Firebase (gratuito) + service account FCM HTTP v1 + google-services.json.
//
// Quando le credenziali esisteranno, completare i due TODO (signApnsJwt + invio HTTP/2 ad APNs;
// access token OAuth2 service-account + POST a fcm.googleapis.com/v1/.../messages:send).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface QueueRow {
  id: string
  client_id: string
  category: string
  title: string
  body: string
  data: Record<string, unknown> | null
}

interface DeviceTokenRow {
  expo_push_token: string
  platform: string | null
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const json = (status: number, payload: unknown) =>
    new Response(JSON.stringify(payload), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  try {
    // Service role: la funzione gira come cron/worker, legge la coda e i token.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // 1) Gate: feature flag push_delivery.
    const { data: flag } = await supabase
      .from('feature_flags')
      .select('enabled')
      .eq('key', 'push_delivery')
      .maybeSingle()
    if (!flag?.enabled) {
      return json(200, { ok: true, skipped: 'FLAG_OFF' })
    }

    // 2) Gate: credenziali APNs/FCM presenti.
    const hasApns = !!Deno.env.get('APNS_PRIVATE_KEY') && !!Deno.env.get('APNS_KEY_ID')
    const hasFcm = !!Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')
    if (!hasApns && !hasFcm) {
      return json(200, { ok: true, skipped: 'NO_CREDENTIALS' })
    }

    // 3) Preleva le notifiche push in coda e pronte all'invio.
    const { data: queued, error: queueError } = await supabase
      .from('notification_queue')
      .select('id, client_id, category, title, body, data')
      .eq('channel', 'push')
      .eq('status', 'pending')
      .lte('scheduled_for', new Date().toISOString())
      .order('scheduled_for', { ascending: true })
      .limit(100)
    if (queueError) throw queueError

    const rows = (queued ?? []) as QueueRow[]
    let sent = 0
    let failed = 0

    for (const item of rows) {
      // Token attivi del cliente (APNs/FCM, salvati in device_tokens.expo_push_token).
      const { data: tokens } = await supabase
        .from('device_tokens')
        .select('expo_push_token, platform')
        .eq('client_id', item.client_id)
        .eq('is_active', true)

      const deviceTokens = (tokens ?? []) as DeviceTokenRow[]
      if (deviceTokens.length === 0) {
        // Nessun device: registra skip nel log e marca la coda.
        await markProcessed(supabase, item, 'skipped', 'NO_DEVICE_TOKENS')
        continue
      }

      try {
        for (const t of deviceTokens) {
          if (t.platform === 'ios' && hasApns) {
            // TODO(APNs): firmare il JWT (ES256 con APNS_PRIVATE_KEY/KEY_ID/TEAM_ID) e fare la
            // POST HTTP/2 a https://api.push.apple.com/3/device/<token> con apns-topic = bundle id.
            throw new Error('APNS_NOT_IMPLEMENTED')
          } else if (t.platform === 'android' && hasFcm) {
            // TODO(FCM): ottenere l'access token OAuth2 dal service account e fare la POST a
            // https://fcm.googleapis.com/v1/projects/<id>/messages:send con { message: { token, notification } }.
            throw new Error('FCM_NOT_IMPLEMENTED')
          }
        }
        await markProcessed(supabase, item, 'sent', null)
        sent++
      } catch (err) {
        await markProcessed(supabase, item, 'failed', String(err))
        failed++
      }
    }

    return json(200, { ok: true, processed: rows.length, sent, failed })
  } catch (err) {
    console.error('send-push error:', err)
    return json(500, { ok: false, reason: String(err) })
  }
})

// Aggiorna la coda + scrive lo storico in notification_logs (anti-spam / analytics).
async function markProcessed(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  item: QueueRow,
  status: 'sent' | 'failed' | 'skipped',
  error: string | null,
): Promise<void> {
  await supabase
    .from('notification_queue')
    .update({ status, processed_at: new Date().toISOString(), error_message: error })
    .eq('id', item.id)

  if (status === 'sent') {
    await supabase.from('notification_logs').insert({
      client_id: item.client_id,
      category: item.category,
      channel: 'push',
      title: item.title,
      body: item.body,
      data: item.data ?? {},
      status: 'sent',
    })
  }
}
