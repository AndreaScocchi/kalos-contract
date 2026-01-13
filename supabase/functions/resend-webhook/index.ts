import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface ResendWebhookEvent {
  type: 'email.sent' | 'email.delivered' | 'email.delivery_delayed' | 'email.complained' | 'email.bounced' | 'email.opened' | 'email.clicked'
  created_at: string
  data: {
    email_id: string
    from: string
    to: string[]
    subject: string
    created_at: string
    // Tags can be either an object or an array depending on Resend API version
    tags?: { name: string; value: string }[] | Record<string, string>
    click?: { link: string }
  }
}

interface ResponseBody {
  ok: boolean
  reason?: string
}

// Map Resend event types to our database enum values
const EVENT_TYPE_MAP: Record<string, string> = {
  'email.delivered': 'delivered',
  'email.opened': 'opened',
  'email.clicked': 'clicked',
  'email.bounced': 'bounced',
  'email.complained': 'complained',
}

// Map Resend event types to newsletter_emails status
const STATUS_MAP: Record<string, string> = {
  'email.delivered': 'delivered',
  'email.opened': 'opened',
  'email.clicked': 'clicked',
  'email.bounced': 'bounced',
  'email.complained': 'complained',
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

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Only accept POST requests
  if (req.method !== 'POST') {
    return jsonResponse({ ok: false, reason: 'METHOD_NOT_ALLOWED' }, 405)
  }

  try {
    const event: ResendWebhookEvent = await req.json()

    // Only process events we care about
    const eventType = EVENT_TYPE_MAP[event.type]
    if (!eventType) {
      // Acknowledge but don't process
      return jsonResponse({ ok: true }, 200)
    }

    // Extract email_id from tags (handle both array and object formats)
    let emailId: string | undefined
    const tags = event.data.tags
    if (tags) {
      if (Array.isArray(tags)) {
        // Array format: [{ name: "email_id", value: "..." }]
        const emailIdTag = tags.find(t => t.name === 'email_id')
        emailId = emailIdTag?.value
      } else {
        // Object format: { email_id: "..." }
        emailId = tags.email_id
      }
    }

    if (!emailId) {
      console.log('No email_id tag found in webhook, skipping')
      return jsonResponse({ ok: true }, 200)
    }

    // Create admin client with service_role key
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Get current email record to check status priority
    const { data: emailRecord, error: fetchError } = await supabaseAdmin
      .from('newsletter_emails')
      .select('id, campaign_id, status')
      .eq('id', emailId)
      .single()

    if (fetchError || !emailRecord) {
      console.error('Email record not found:', emailId)
      return jsonResponse({ ok: true }, 200) // Still return 200 to avoid retries
    }

    // Check if we should update the status (only if new status is more significant)
    const newStatus = STATUS_MAP[event.type]
    const currentPriority = STATUS_PRIORITY[emailRecord.status] ?? 0
    const newPriority = STATUS_PRIORITY[newStatus] ?? 0

    if (newPriority > currentPriority) {
      // Update email record status
      const updateData: Record<string, unknown> = { status: newStatus }

      // Add timestamp for the specific event
      switch (event.type) {
        case 'email.delivered':
          updateData.delivered_at = event.created_at
          break
        case 'email.opened':
          updateData.opened_at = event.created_at
          break
        case 'email.clicked':
          updateData.clicked_at = event.created_at
          break
        case 'email.bounced':
          updateData.bounced_at = event.created_at
          break
      }

      await supabaseAdmin
        .from('newsletter_emails')
        .update(updateData)
        .eq('id', emailId)
    }

    // Always record the tracking event
    const eventData: Record<string, unknown> = {}
    if (event.type === 'email.clicked' && event.data.click) {
      eventData.link = event.data.click.link
    }

    await supabaseAdmin
      .from('newsletter_tracking_events')
      .insert({
        email_id: emailId,
        event_type: eventType,
        event_data: Object.keys(eventData).length > 0 ? eventData : null,
        occurred_at: event.created_at,
      })

    // Update campaign stats (denormalized counts)
    await updateCampaignStats(supabaseAdmin, emailRecord.campaign_id)

    return jsonResponse({ ok: true }, 200)

  } catch (error) {
    console.error('Webhook error:', error)
    // Return 200 to avoid Resend retries for malformed requests
    return jsonResponse({ ok: true }, 200)
  }
})

async function updateCampaignStats(supabase: ReturnType<typeof createClient>, campaignId: string) {
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
