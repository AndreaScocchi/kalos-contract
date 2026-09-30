// Edge Function: process-notification-queue
// Processa la coda notifiche: push web (Web Push API, VAPID), push delle app per iPhone e Android
// (servizio push di Expo, dalla sessione 11) ed email (Amazon SES).
// Chiamata ogni 5 minuti dal cron job.
//
// `data.url` (scritto dal database, `internal.notification_path`) è la pagina dell'app da aprire: il
// service worker e l'app lo aprono al tocco, e il pulsante dell'email ci porta.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { sendEmail, getFromEmail, delay, checkDailyCap } from '../_shared/ses.ts'
import { legalLineHtml, legalLine } from '../_shared/legal.ts'

const BATCH_SIZE = 50

interface WebPushSubscription {
  endpoint: string
  keys: {
    p256dh: string
    auth: string
  }
}

interface WebPushResult {
  success: boolean
  statusCode?: number
  error?: string
}

interface QueueItem {
  id: string
  client_id: string
  category: string
  channel: 'push' | 'email'
  title: string
  body: string
  data: Record<string, unknown>
  scheduled_for: string
  status: string
  attempts: number
  clients: {
    id: string
    email: string | null
    full_name: string
    email_bounced: boolean | null
  }
}

// Titolo e testo arrivano dalla coda e possono contenere dati scritti dalle persone (per esempio il nome
// nell'avviso di una prova allo staff): vanno sempre trattati come testo, mai come HTML.
function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}

// HTML email template
function emailTemplate(rawTitle: string, rawBody: string, ctaUrl: string, preferencesUrl: string): string {
  const title = escapeHtml(rawTitle)
  const body = escapeHtml(rawBody).replace(/\n/g, '<br>')
  return `
<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
</head>
<body style="font-family: 'Jost', 'Segoe UI', Arial, sans-serif; background: #FDFBF7; margin: 0; padding: 40px 20px;">
  <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 16px; padding: 40px; box-shadow: 0 4px 6px rgba(0,0,0,0.05);">
    <div style="text-align: center; margin-bottom: 24px;">
      <h1 style="color: #036257; font-size: 24px; margin: 0;">Studio Kalòs</h1>
    </div>
    <h2 style="color: #0F2D3B; font-size: 20px; margin-bottom: 16px;">${title}</h2>
    <p style="color: #0F2D3B; font-size: 16px; line-height: 1.6; margin-bottom: 24px;">${body}</p>
    <div style="text-align: center; margin-top: 32px;">
      <a href="${ctaUrl}" style="display: inline-block; background: #036257; color: white; padding: 14px 28px; border-radius: 8px; text-decoration: none; font-weight: 500;">
        Apri l'app
      </a>
    </div>
  </div>
  <p style="text-align: center; margin-top: 24px; font-size: 12px; color: #6B7280; line-height: 1.6;">
    <a href="${preferencesUrl}" style="color: #6B7280;">Scegli quali messaggi ricevere</a><br>
    ${legalLineHtml()}
  </p>
</body>
</html>`
}

// Send Web Push notification
async function sendWebPush(
  subscription: WebPushSubscription,
  payload: { title: string; body: string; data?: Record<string, unknown> }
): Promise<WebPushResult> {
  const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY')
  const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY')
  const vapidSubject = Deno.env.get('VAPID_SUBJECT') || 'mailto:info@kalosstudio.it'

  if (!vapidPublicKey || !vapidPrivateKey) {
    console.error('VAPID keys not configured')
    return { success: false, error: 'VAPID keys not configured' }
  }

  try {
    // Import web-push library
    const webpush = await import('npm:web-push@3.6.7')

    webpush.default.setVapidDetails(
      vapidSubject,
      vapidPublicKey,
      vapidPrivateKey
    )

    const pushPayload = JSON.stringify({
      title: payload.title,
      body: payload.body,
      icon: '/icons/icon-192.png',
      badge: '/icons/icon-192.png',
      data: payload.data || {},
    })

    const result = await webpush.default.sendNotification(
      {
        endpoint: subscription.endpoint,
        keys: {
          p256dh: subscription.keys.p256dh,
          auth: subscription.keys.auth,
        },
      },
      pushPayload
    )

    return { success: true, statusCode: result.statusCode }
  } catch (error) {
    console.error('Web push error:', error)

    // Check if subscription is expired/invalid
    if (error.statusCode === 410 || error.statusCode === 404) {
      return { success: false, statusCode: error.statusCode, error: 'SUBSCRIPTION_EXPIRED' }
    }

    return { success: false, statusCode: error.statusCode, error: error.message }
  }
}

interface ExpoTicket {
  status: 'ok' | 'error'
  id?: string
  message?: string
  details?: { error?: string }
}

interface ExpoPushResult {
  sent: boolean
  /** Primo ticket accettato: si salva nel log (`expo_receipt_id`). */
  ticketId: string | null
  /** Token che Expo dice non più registrati (app disinstallata, permesso tolto): da disattivare. */
  deadTokens: string[]
}

// In locale si può puntare a un servizio finto (`EXPO_PUSH_URL` nel file d'ambiente delle function)
const EXPO_PUSH_URL = Deno.env.get('EXPO_PUSH_URL') || 'https://exp.host/--/api/v2/push/send'

function isExpoToken(token: string): boolean {
  return token.startsWith('ExponentPushToken[') || token.startsWith('ExpoPushToken[')
}

// Push alle app di iPhone e Android con il servizio di Expo (C6): una richiesta per notifica, un
// messaggio per dispositivo. `EXPO_ACCESS_TOKEN` è facoltativo (serve se si attiva la sicurezza
// avanzata delle push nel progetto Expo).
async function sendExpoPush(
  tokens: string[],
  payload: { title: string; body: string; data?: Record<string, unknown> }
): Promise<ExpoPushResult> {
  const result: ExpoPushResult = { sent: false, ticketId: null, deadTokens: [] }
  if (tokens.length === 0) return result

  const headers: Record<string, string> = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  }
  const accessToken = Deno.env.get('EXPO_ACCESS_TOKEN')
  if (accessToken) headers['Authorization'] = `Bearer ${accessToken}`

  const messages = tokens.map((to) => ({
    to,
    title: payload.title,
    body: payload.body,
    data: payload.data || {},
    sound: 'default',
    // Il canale che l'app crea su Android (`src/lib/push`)
    channelId: 'default',
  }))

  try {
    const response = await fetch(EXPO_PUSH_URL, { method: 'POST', headers, body: JSON.stringify(messages) })
    const json = await response.json().catch(() => null) as { data?: ExpoTicket[]; errors?: unknown } | null
    if (!response.ok || !Array.isArray(json?.data)) {
      console.error('Expo push error:', response.status, JSON.stringify(json?.errors ?? json).slice(0, 300))
      return result
    }
    json.data.forEach((ticket, i) => {
      if (ticket.status === 'ok') {
        result.sent = true
        result.ticketId = result.ticketId ?? ticket.id ?? null
      } else if (ticket.details?.error === 'DeviceNotRegistered') {
        result.deadTokens.push(tokens[i])
      } else {
        console.error('Expo push ticket error:', ticket.details?.error ?? ticket.message)
      }
    })
  } catch (error) {
    console.error('Expo push request failed:', error)
  }
  return result
}

// Check if token is a web push subscription (JSON) or Expo token
function isWebPushSubscription(token: string): boolean {
  try {
    const parsed = JSON.parse(token)
    return parsed.endpoint && parsed.keys?.p256dh && parsed.keys?.auth
  } catch {
    return false
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify service role authentication
    const authHeader = req.headers.get('Authorization')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!authHeader || !authHeader.includes(serviceKey ?? '')) {
      return new Response(
        JSON.stringify({ ok: false, reason: 'UNAUTHORIZED' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create admin client with service role - bypasses RLS
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
        db: {
          schema: 'public',
        },
        global: {
          headers: {
            Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
          },
        },
      }
    )

    // Get pending notifications: push ed email in due code separate, così un blocco di email ferme
    // (tetto giornaliero) non tiene indietro le push che arrivano dopo.
    const fetchPending = (channel: 'push' | 'email') => supabaseAdmin
      .from('notification_queue')
      .select(`
        *,
        clients!inner(id, email, full_name, email_bounced)
      `)
      .eq('status', 'pending')
      .eq('channel', channel)
      .lte('scheduled_for', new Date().toISOString())
      .lt('attempts', 3)
      .order('scheduled_for', { ascending: true })
      .limit(BATCH_SIZE) as unknown as Promise<{ data: QueueItem[] | null, error: Error | null }>
    const [pushRes, emailRes] = await Promise.all([fetchPending('push'), fetchPending('email')])
    const queueError = pushRes.error ?? emailRes.error
    const fetched: QueueItem[] | null = queueError ? null : [...(pushRes.data ?? []), ...(emailRes.data ?? [])]

    // Un promemoria di una lezione già iniziata non si manda più (per esempio dopo un blocco della
    // coda): si segna saltato.
    const now = Date.now()
    const stale = (fetched ?? []).filter((n) => {
      const startsAt = typeof n.data?.starts_at === 'string' ? Date.parse(n.data.starts_at as string) : NaN
      return n.category === 'lesson_reminder' && Number.isFinite(startsAt) && startsAt <= now
    })
    for (const notification of stale) {
      await supabaseAdmin
        .from('notification_queue')
        .update({
          status: 'skipped',
          error_message: 'Lesson already started',
          attempts: notification.attempts + 1,
          processed_at: new Date().toISOString(),
        })
        .eq('id', notification.id)
    }
    const queue = fetched ? fetched.filter((n) => !stale.includes(n)) : null

    if (queueError) {
      console.error('Error fetching queue:', queueError)
      return new Response(
        JSON.stringify({ ok: false, reason: 'QUEUE_FETCH_ERROR', error: queueError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!queue || queue.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, processed: 0, message: 'No pending notifications' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Processing ${queue.length} notifications`)

    let pushCount = 0
    let emailCount = 0
    let failedCount = 0

    // Separate by channel
    const pushNotifications = queue.filter(n => n.channel === 'push')
    const emailNotifications = queue.filter(n => n.channel === 'email')

    // Process push notifications
    if (pushNotifications.length > 0) {
      // Get all tokens for clients with push notifications
      const clientIds = [...new Set(pushNotifications.map(n => n.client_id))]
      const { data: tokens } = await supabaseAdmin
        .from('device_tokens')
        .select('client_id, expo_push_token, platform')
        .in('client_id', clientIds)
        .eq('is_active', true)

      if (tokens && tokens.length > 0) {
        for (const notification of pushNotifications) {
          const clientTokens = tokens.filter(t => t.client_id === notification.client_id)
          let sent = false
          let expoTicketId: string | null = null

          // App di iPhone e Android: tutti i dispositivi della persona in una richiesta
          const expoTokens = clientTokens.map(t => t.expo_push_token).filter(isExpoToken)
          if (expoTokens.length > 0) {
            const expo = await sendExpoPush(expoTokens, {
              title: notification.title,
              body: notification.body,
              data: notification.data,
            })
            if (expo.sent) {
              sent = true
              pushCount++
              expoTicketId = expo.ticketId
            }
            for (const dead of expo.deadTokens) {
              await supabaseAdmin
                .from('device_tokens')
                .update({ is_active: false })
                .eq('expo_push_token', dead)
              console.log('Deactivated unregistered Expo push token')
            }
          }

          for (const token of clientTokens) {
            // Check if it's a web push subscription
            if (isWebPushSubscription(token.expo_push_token)) {
              const subscription: WebPushSubscription = JSON.parse(token.expo_push_token)
              const result = await sendWebPush(subscription, {
                title: notification.title,
                body: notification.body,
                data: notification.data,
              })

              if (result.success) {
                sent = true
                pushCount++
              } else if (result.error === 'SUBSCRIPTION_EXPIRED') {
                // Deactivate expired subscription
                await supabaseAdmin
                  .from('device_tokens')
                  .update({ is_active: false })
                  .eq('expo_push_token', token.expo_push_token)
                console.log(`Deactivated expired web push subscription`)
              }
            }
            // I token di Expo sono già stati mandati tutti insieme, sopra
          }

          // Update queue status
          const status = sent ? 'sent' : (clientTokens.length > 0 ? 'failed' : 'skipped')
          await supabaseAdmin
            .from('notification_queue')
            .update({
              status,
              processed_at: new Date().toISOString(),
              attempts: notification.attempts + 1,
              error_message: sent ? null : (clientTokens.length > 0 ? 'Push send failed' : 'No active push tokens'),
            })
            .eq('id', notification.id)

          // Log the notification
          await supabaseAdmin.from('notification_logs').insert({
            client_id: notification.client_id,
            category: notification.category,
            channel: 'push',
            title: notification.title,
            body: notification.body,
            data: notification.data,
            expo_receipt_id: expoTicketId,
            status,
          })

          if (!sent) failedCount++
        }
      } else {
        // No tokens found for any client
        for (const notification of pushNotifications) {
          await supabaseAdmin
            .from('notification_queue')
            .update({
              status: 'skipped',
              processed_at: new Date().toISOString(),
              attempts: notification.attempts + 1,
              error_message: 'No active push tokens',
            })
            .eq('id', notification.id)

          await supabaseAdmin.from('notification_logs').insert({
            client_id: notification.client_id,
            category: notification.category,
            channel: 'push',
            title: notification.title,
            body: notification.body,
            data: notification.data,
            status: 'skipped',
          })
        }
      }
    }

    // Process email notifications
    const fromEmail = getFromEmail()
    const appUrl = 'https://app.kalosstudio.it'

    // This path is trigger- and cron-driven, so a misbehaving trigger could keep
    // refilling the queue indefinitely. Check the 24h ceiling before the batch:
    // notifications left pending are retried on the next run, nothing is lost.
    const cap = await checkDailyCap(emailNotifications.length)
    if (!cap.allowed) {
      console.error(`Daily cap gate: ${emailNotifications.length} email notifications queued, ${cap.available} available (cap ${cap.cap}, sent ${cap.sentLast24Hours})`)
    }
    // Con il tetto quasi raggiunto si manda quello che si può; il resto resta in coda per il giro dopo.
    const emailsToSend = cap.allowed ? emailNotifications : emailNotifications.slice(0, Math.max(0, cap.available))

    for (const notification of emailsToSend) {
      const client = notification.clients
      if (client?.email && client.email_bounced) {
        await supabaseAdmin
          .from('notification_queue')
          .update({
            status: 'skipped',
            error_message: 'Email bounced',
            attempts: notification.attempts + 1,
            processed_at: new Date().toISOString(),
          })
          .eq('id', notification.id)
        continue
      }
      if (!client?.email) {
        await supabaseAdmin
          .from('notification_queue')
          .update({
            status: 'skipped',
            error_message: 'No email address',
            attempts: notification.attempts + 1,
            processed_at: new Date().toISOString(),
          })
          .eq('id', notification.id)
        continue
      }

      // Il pulsante porta alla pagina giusta dell'app (solo percorsi dell'app, mai altri siti)
      const path = typeof notification.data?.url === 'string' ? notification.data.url : ''
      const ctaUrl = /^\/([^/\\]|$)/.test(path) ? appUrl + path : appUrl
      const html = emailTemplate(notification.title, notification.body, ctaUrl, `${appUrl}/notifications/preferences`)

      const { data, error } = await sendEmail({
        from: fromEmail,
        to: client.email,
        subject: notification.title,
        html,
        text: `${notification.body}\n\n—\n${legalLine()}`,
        tags: [
          { name: 'category', value: notification.category },
          { name: 'client_id', value: notification.client_id },
        ],
      })

      if (error) {
        failedCount++
        await supabaseAdmin
          .from('notification_queue')
          .update({
            status: notification.attempts >= 2 ? 'failed' : 'pending',
            error_message: error.message,
            attempts: notification.attempts + 1,
            last_attempt_at: new Date().toISOString(),
          })
          .eq('id', notification.id)
      } else {
        emailCount++
        await supabaseAdmin
          .from('notification_queue')
          .update({
            status: 'sent',
            processed_at: new Date().toISOString(),
            attempts: notification.attempts + 1,
          })
          .eq('id', notification.id)

        // Log the notification
        await supabaseAdmin.from('notification_logs').insert({
          client_id: notification.client_id,
          category: notification.category,
          channel: 'email',
          title: notification.title,
          body: notification.body,
          data: notification.data,
          resend_id: data?.id,
          status: 'sent',
        })
      }

      // Pace the loop under the SES sending rate
      await delay(100)
    }

    const result = {
      ok: true,
      processed: queue.length,
      push: pushCount,
      email: emailCount,
      failed: failedCount,
    }

    console.log('Queue processing complete:', result)

    return new Response(
      JSON.stringify(result),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Queue processor error:', error)
    return new Response(
      JSON.stringify({ ok: false, reason: 'INTERNAL_ERROR', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
