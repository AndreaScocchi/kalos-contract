// Edge Function: process-notification-queue
// Processa la coda notifiche: invia push via Web Push API e email via Resend.
// Chiamata ogni 5 minuti dal cron job.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { sendEmail, getFromEmail, delay } from '../_shared/resend.ts'

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
  }
}

// HTML email template
function emailTemplate(title: string, body: string, ctaUrl: string): string {
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
      <h1 style="color: #036257; font-size: 24px; margin: 0;">Studio Kalos</h1>
    </div>
    <h2 style="color: #0F2D3B; font-size: 20px; margin-bottom: 16px;">${title}</h2>
    <p style="color: #0F2D3B; font-size: 16px; line-height: 1.6; margin-bottom: 24px;">${body}</p>
    <div style="text-align: center; margin-top: 32px;">
      <a href="${ctaUrl}" style="display: inline-block; background: #036257; color: white; padding: 14px 28px; border-radius: 8px; text-decoration: none; font-weight: 500;">
        Apri l'app
      </a>
    </div>
  </div>
  <p style="text-align: center; margin-top: 24px; font-size: 12px; color: #6B7280;">
    Studio Kalos - Il tuo centro benessere
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

    // Get pending notifications
    const { data: queue, error: queueError } = await supabaseAdmin
      .from('notification_queue')
      .select(`
        *,
        clients!inner(id, email, full_name)
      `)
      .eq('status', 'pending')
      .lte('scheduled_for', new Date().toISOString())
      .lt('attempts', 3)
      .order('scheduled_for', { ascending: true })
      .limit(BATCH_SIZE) as { data: QueueItem[] | null, error: Error | null }

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
            // Note: Expo tokens are no longer supported for web
            // If you want to support native apps in the future, add Expo push logic here
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

    for (const notification of emailNotifications) {
      const client = notification.clients
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

      const html = emailTemplate(notification.title, notification.body, appUrl)

      const { data, error } = await sendEmail({
        from: fromEmail,
        to: client.email,
        subject: notification.title,
        html,
        text: notification.body,
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

      // Rate limiting for Resend
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
