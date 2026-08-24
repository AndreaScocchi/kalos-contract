// Amazon SES event notifications, delivered over SNS.
//
// SES configuration set → SNS topic → HTTPS subscription pointing here.
// Mirrors the behaviour of resend-webhook: it resolves the newsletter_emails row
// from the `email_id` message tag, applies the highest-priority status seen,
// records a tracking event, and refreshes the campaign counters.
//
// Deploy with --no-verify-jwt (SNS cannot send a Supabase JWT):
//   supabase functions deploy ses-webhook --no-verify-jwt
//
// Optional secret SES_WEBHOOK_SECRET adds a shared-token check on top of the
// SNS signature verification: subscribe the topic to
//   https://<project>.supabase.co/functions/v1/ses-webhook?token=<secret>

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { createVerify } from 'node:crypto'
import { corsHeaders } from '../_shared/cors.ts'

interface SnsEnvelope {
  Type: 'Notification' | 'SubscriptionConfirmation' | 'UnsubscribeConfirmation'
  MessageId: string
  TopicArn: string
  Subject?: string
  Message: string
  Timestamp: string
  SignatureVersion: '1' | '2'
  Signature: string
  SigningCertURL: string
  SubscribeURL?: string
  Token?: string
}

interface SesEvent {
  eventType: 'Send' | 'Delivery' | 'Bounce' | 'Complaint' | 'Open' | 'Click' | 'Reject' | 'Rendering Failure' | 'DeliveryDelay' | 'Subscription'
  mail: {
    messageId: string
    timestamp: string
    // SES delivers tag values as arrays, e.g. { email_id: ["<uuid>"] }
    tags?: Record<string, string[]>
  }
  delivery?: { timestamp?: string }
  bounce?: { bounceType?: 'Permanent' | 'Transient' | 'Undetermined'; timestamp?: string }
  complaint?: { timestamp?: string }
  open?: { timestamp?: string }
  click?: { timestamp?: string; link?: string }
}

interface ResponseBody {
  ok: boolean
  reason?: string
}

// Map SES event types to newsletter_tracking_events.event_type
const EVENT_TYPE_MAP: Record<string, string> = {
  'Delivery': 'delivered',
  'Open': 'opened',
  'Click': 'clicked',
  'Bounce': 'bounced',
  'Complaint': 'complained',
}

// Map SES event types to newsletter_emails status
const STATUS_MAP: Record<string, string> = {
  'Delivery': 'delivered',
  'Open': 'opened',
  'Click': 'clicked',
  'Bounce': 'bounced',
  'Complaint': 'complained',
}

// Status priority for updates (higher number = more significant)
const STATUS_PRIORITY: Record<string, number> = {
  'pending': 0,
  'sent': 1,
  'delivered': 2,
  'opened': 3,
  'clicked': 4,
  'bounced': 10, // High priority because it's a failure state
  'complained': 11,
  'failed': 12,
}

// Fields that make up the SNS signature payload, per message type and in this order.
const SIGNED_FIELDS: Record<string, string[]> = {
  'Notification': ['Message', 'MessageId', 'Subject', 'Timestamp', 'TopicArn', 'Type'],
  'SubscriptionConfirmation': ['Message', 'MessageId', 'SubscribeURL', 'Timestamp', 'Token', 'TopicArn', 'Type'],
  'UnsubscribeConfirmation': ['Message', 'MessageId', 'SubscribeURL', 'Timestamp', 'Token', 'TopicArn', 'Type'],
}

const certCache = new Map<string, string>()

/**
 * Fetch the SNS signing certificate, refusing any URL that is not an AWS SNS
 * host — otherwise an attacker could point us at a certificate they control.
 */
async function fetchSigningCert(url: string): Promise<string | null> {
  const cached = certCache.get(url)
  if (cached) return cached

  let parsed: URL
  try {
    parsed = new URL(url)
  } catch {
    return null
  }

  if (parsed.protocol !== 'https:') return null
  if (!/^sns\.[a-z0-9-]+\.amazonaws\.com$/.test(parsed.hostname)) return null

  const response = await fetch(url)
  if (!response.ok) return null

  const pem = await response.text()
  certCache.set(url, pem)
  return pem
}

/**
 * Verify the SNS message signature against the published signing certificate.
 * SignatureVersion 1 is SHA1withRSA, version 2 is SHA256withRSA.
 */
async function verifySnsSignature(envelope: SnsEnvelope): Promise<boolean> {
  const fields = SIGNED_FIELDS[envelope.Type]
  if (!fields) return false

  const record = envelope as unknown as Record<string, string | undefined>
  let payload = ''
  for (const field of fields) {
    const value = record[field]
    if (value === undefined || value === null) continue // Subject is optional
    payload += `${field}\n${value}\n`
  }

  const pem = await fetchSigningCert(envelope.SigningCertURL)
  if (!pem) return false

  const algorithm = envelope.SignatureVersion === '1' ? 'RSA-SHA1' : 'RSA-SHA256'
  try {
    const verifier = createVerify(algorithm)
    verifier.update(payload, 'utf8')
    return verifier.verify(pem, envelope.Signature, 'base64')
  } catch (error) {
    console.error('SNS signature verification threw:', error)
    return false
  }
}

/** SES tag values arrive as arrays; take the first entry. */
function tagValue(event: SesEvent, name: string): string | undefined {
  const values = event.mail.tags?.[name]
  return Array.isArray(values) ? values[0] : undefined
}

/** Timestamp of the specific sub-event, falling back to the mail timestamp. */
function eventTimestamp(event: SesEvent): string {
  return (
    event.delivery?.timestamp ??
    event.bounce?.timestamp ??
    event.complaint?.timestamp ??
    event.open?.timestamp ??
    event.click?.timestamp ??
    event.mail.timestamp ??
    new Date().toISOString()
  )
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Only accept POST requests
  if (req.method !== 'POST') {
    return jsonResponse({ ok: false, reason: 'METHOD_NOT_ALLOWED' }, 405)
  }

  // Optional shared-token gate, checked before any parsing work
  const expectedToken = Deno.env.get('SES_WEBHOOK_SECRET')
  if (expectedToken) {
    const providedToken = new URL(req.url).searchParams.get('token')
    if (providedToken !== expectedToken) {
      return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)
    }
  }

  try {
    const envelope: SnsEnvelope = await req.json()

    if (!(await verifySnsSignature(envelope))) {
      console.error('Rejected SNS message with invalid signature:', envelope.MessageId)
      return jsonResponse({ ok: false, reason: 'INVALID_SIGNATURE' }, 403)
    }

    // Confirm the subscription the first time SNS calls us
    if (envelope.Type === 'SubscriptionConfirmation') {
      if (!envelope.SubscribeURL) {
        return jsonResponse({ ok: false, reason: 'MISSING_SUBSCRIBE_URL' }, 400)
      }
      const confirmation = await fetch(envelope.SubscribeURL)
      console.log(`SNS subscription confirmation for ${envelope.TopicArn}: ${confirmation.status}`)
      return jsonResponse({ ok: true }, 200)
    }

    if (envelope.Type !== 'Notification') {
      return jsonResponse({ ok: true }, 200)
    }

    const event: SesEvent = JSON.parse(envelope.Message)

    // Only process events we care about
    const eventType = EVENT_TYPE_MAP[event.eventType]
    if (!eventType) {
      // Acknowledge but don't process (Send, Reject, DeliveryDelay, ...)
      return jsonResponse({ ok: true }, 200)
    }

    const emailId = tagValue(event, 'email_id')
    if (!emailId) {
      // Transactional mail carries no email_id tag: nothing to reconcile here
      console.log('No email_id tag found in SES event, skipping')
      return jsonResponse({ ok: true }, 200)
    }

    const occurredAt = eventTimestamp(event)

    // Create admin client with service_role key
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Get current email record to check status priority
    const { data: emailRecord, error: fetchError } = await supabaseAdmin
      .from('newsletter_emails')
      .select('id, campaign_id, status, client_id')
      .eq('id', emailId)
      .single()

    if (fetchError || !emailRecord) {
      console.error('Email record not found:', emailId)
      return jsonResponse({ ok: true }, 200) // Still return 200 to avoid retries
    }

    // Check if we should update the status (only if new status is more significant)
    const newStatus = STATUS_MAP[event.eventType]
    const currentPriority = STATUS_PRIORITY[emailRecord.status] ?? 0
    const newPriority = STATUS_PRIORITY[newStatus] ?? 0

    if (newPriority > currentPriority) {
      const updateData: Record<string, unknown> = { status: newStatus }

      // Add timestamp for the specific event
      switch (event.eventType) {
        case 'Delivery':
          updateData.delivered_at = occurredAt
          break
        case 'Open':
          updateData.opened_at = occurredAt
          break
        case 'Click':
          updateData.clicked_at = occurredAt
          break
        case 'Bounce':
          updateData.bounced_at = occurredAt
          // Only a permanent bounce means the address is dead. Transient bounces
          // (full mailbox, greylisting) must not disable a client's email —
          // SES gives us this distinction, Resend did not.
          if (emailRecord.client_id && event.bounce?.bounceType === 'Permanent') {
            await supabaseAdmin
              .from('clients')
              .update({
                email_bounced: true,
                email_bounced_at: occurredAt,
              })
              .eq('id', emailRecord.client_id)
            console.log(`Marked client ${emailRecord.client_id} as email_bounced (permanent)`)
          }
          break
      }

      await supabaseAdmin
        .from('newsletter_emails')
        .update(updateData)
        .eq('id', emailId)
    }

    // Always record the tracking event
    const eventData: Record<string, unknown> = {}
    if (event.eventType === 'Click' && event.click?.link) {
      eventData.link = event.click.link
    }
    if (event.eventType === 'Bounce' && event.bounce?.bounceType) {
      eventData.bounce_type = event.bounce.bounceType
    }

    await supabaseAdmin
      .from('newsletter_tracking_events')
      .insert({
        email_id: emailId,
        event_type: eventType,
        event_data: Object.keys(eventData).length > 0 ? eventData : null,
        occurred_at: occurredAt,
      })

    // Update campaign stats (denormalized counts)
    await updateCampaignStats(supabaseAdmin, emailRecord.campaign_id)

    return jsonResponse({ ok: true }, 200)

  } catch (error) {
    console.error('Webhook error:', error)
    // Return 200 to avoid SNS retries for malformed requests
    return jsonResponse({ ok: true }, 200)
  }
})

// Edge functions don't import the generated Database types, so the client's schema
// generic resolves to `never` and every table call fails to typecheck. Pinning the
// schema to 'public' restores it without pulling the whole type tree in.
type AdminClient = SupabaseClient<any, 'public', any>

async function updateCampaignStats(supabase: AdminClient, campaignId: string) {
  try {
    // Get counts for each status
    const { data: emails } = await supabase
      .from('newsletter_emails')
      .select('status')
      .eq('campaign_id', campaignId)

    if (!emails) return

    const counts = {
      delivered_count: 0,
      opened_count: 0,
      clicked_count: 0,
      bounced_count: 0,
    }

    for (const email of emails) {
      switch (email.status) {
        case 'delivered':
          counts.delivered_count++
          break
        case 'opened':
          counts.delivered_count++ // Opened implies delivered
          counts.opened_count++
          break
        case 'clicked':
          counts.delivered_count++ // Clicked implies delivered and opened
          counts.opened_count++
          counts.clicked_count++
          break
        case 'bounced':
        case 'complained':
          counts.bounced_count++
          break
      }
    }

    await supabase
      .from('newsletter_campaigns')
      .update(counts)
      .eq('id', campaignId)

  } catch (error) {
    console.error('Error updating campaign stats:', error)
  }
}

function jsonResponse(body: ResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
