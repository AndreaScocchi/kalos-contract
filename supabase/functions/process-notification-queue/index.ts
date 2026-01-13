// Edge Function: process-notification-queue
// Processa la coda notifiche: invia push via Expo e email via Resend.
// Chiamata ogni 5 minuti dal cron job.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { sendEmail, getFromEmail, delay } from '../_shared/resend.ts'

const BATCH_SIZE = 50
const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send'

interface ExpoPushMessage {
  to: string
  title: string
  body: string
  data?: Record<string, unknown>
  sound?: 'default' | null
  badge?: number
  channelId?: string
}

interface ExpoPushTicket {
  id?: string
  status: 'ok' | 'error'
  message?: string
  details?: { error: string }
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

// Send push notifications via Expo
async function sendExpoPush(messages: ExpoPushMessage[]): Promise<ExpoPushTicket[]> {
  if (messages.length === 0) return []

  try {
    const response = await fetch(EXPO_PUSH_URL, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Accept-encoding': 'gzip, deflate',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(messages),
    })

    if (!response.ok) {
      console.error('Expo push error:', response.status, await response.text())
      return messages.map(() => ({ status: 'error', message: 'HTTP error' }))
    }

    const result = await response.json()
    return result.data || []
  } catch (error) {
    console.error('Expo push network error:', error)
    return messages.map(() => ({ status: 'error', message: error.message }))
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
        .select('client_id, expo_push_token')
        .in('client_id', clientIds)
        .eq('is_active', true)

      if (tokens && tokens.length > 0) {
        // Build messages for each notification
        const messages: ExpoPushMessage[] = []
        const messageToNotification: Map<number, QueueItem> = new Map()

        for (const notification of pushNotifications) {
          const clientTokens = tokens.filter(t => t.client_id === notification.client_id)
          for (const token of clientTokens) {
            const idx = messages.length
            messages.push({
              to: token.expo_push_token,
              title: notification.title,
              body: notification.body,
              data: notification.data,
              sound: 'default',
            })
            messageToNotification.set(idx, notification)
          }
        }

        // Send in batches of 100 (Expo limit)
        const EXPO_BATCH_SIZE = 100
        for (let i = 0; i < messages.length; i += EXPO_BATCH_SIZE) {
          const batch = messages.slice(i, i + EXPO_BATCH_SIZE)
          const tickets = await sendExpoPush(batch)

          // Process results
          for (let j = 0; j < tickets.length; j++) {
            const ticket = tickets[j]
            const message = batch[j]

            if (ticket.status === 'ok') {
              pushCount++
            } else {
              // If token is invalid, deactivate it
              if (ticket.details?.error === 'DeviceNotRegistered') {
                await supabaseAdmin
                  .from('device_tokens')
                  .update({ is_active: false })
                  .eq('expo_push_token', message.to)
                console.log(`Deactivated invalid token: ${message.to}`)
              }
            }
          }
        }
      }

      // Update queue status and log for push notifications
      for (const notification of pushNotifications) {
        const hasTokens = tokens?.some(t => t.client_id === notification.client_id) ?? false
        const status = hasTokens ? 'sent' : 'skipped'

        await supabaseAdmin
          .from('notification_queue')
          .update({
            status,
            processed_at: new Date().toISOString(),
            attempts: notification.attempts + 1,
            error_message: hasTokens ? null : 'No active push tokens',
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
