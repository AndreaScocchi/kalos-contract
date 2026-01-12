import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { sendEmail, replaceTemplateVariables, getFromEmail, delay } from '../_shared/resend.ts'

interface RequestBody {
  campaignId: string
}

interface ResponseBody {
  ok: boolean
  reason?: string
  message?: string
  sentCount?: number
  failedCount?: number
}

// Rate limiting: send in batches to avoid Resend limits
const BATCH_SIZE = 10
const BATCH_DELAY_MS = 1000

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify request has authorization
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)
    }

    // Create client with the user's token to verify they are staff
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    // Verify user is staff
    const { data: isStaff, error: staffError } = await supabaseUser.rpc('is_staff')
    if (staffError || !isStaff) {
      return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 403)
    }

    // Get request body
    const body: RequestBody = await req.json()
    if (!body.campaignId) {
      return jsonResponse({ ok: false, reason: 'MISSING_CAMPAIGN_ID' }, 400)
    }

    // Create admin client with service_role key
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Get campaign
    const { data: campaign, error: campaignError } = await supabaseAdmin
      .from('newsletter_campaigns')
      .select('*')
      .eq('id', body.campaignId)
      .single()

    if (campaignError || !campaign) {
      console.error('Error getting campaign:', campaignError)
      return jsonResponse({ ok: false, reason: 'CAMPAIGN_NOT_FOUND' }, 404)
    }

    // Check campaign status
    if (campaign.status === 'sent') {
      return jsonResponse({ ok: false, reason: 'CAMPAIGN_ALREADY_SENT' }, 400)
    }
    if (campaign.status === 'sending') {
      return jsonResponse({ ok: false, reason: 'CAMPAIGN_ALREADY_SENDING' }, 400)
    }

    // Update campaign status to 'sending'
    await supabaseAdmin
      .from('newsletter_campaigns')
      .update({ status: 'sending' })
      .eq('id', body.campaignId)

    // Get all clients with valid email addresses (not archived)
    const { data: clients, error: clientsError } = await supabaseAdmin
      .from('clients')
      .select('id, full_name, email')
      .not('email', 'is', null)
      .is('deleted_at', null)

    if (clientsError) {
      console.error('Error getting clients:', clientsError)
      await supabaseAdmin
        .from('newsletter_campaigns')
        .update({ status: 'failed' })
        .eq('id', body.campaignId)
      return jsonResponse({ ok: false, reason: 'CLIENTS_FETCH_ERROR' }, 500)
    }

    const validClients = clients?.filter(c => c.email && c.email.includes('@')) ?? []

    if (validClients.length === 0) {
      await supabaseAdmin
        .from('newsletter_campaigns')
        .update({ status: 'failed' })
        .eq('id', body.campaignId)
      return jsonResponse({ ok: false, reason: 'NO_VALID_RECIPIENTS' }, 400)
    }

    // Create newsletter_emails records for all recipients
    const emailRecords = validClients.map(client => ({
      campaign_id: body.campaignId,
      client_id: client.id,
      email_address: client.email,
      client_name: client.full_name,
      status: 'pending',
    }))

    const { error: insertError } = await supabaseAdmin
      .from('newsletter_emails')
      .insert(emailRecords)

    if (insertError) {
      console.error('Error creating email records:', insertError)
      // Continue anyway, some might already exist from a previous attempt
    }

    // Get all pending emails for this campaign
    const { data: pendingEmails, error: pendingError } = await supabaseAdmin
      .from('newsletter_emails')
      .select('*')
      .eq('campaign_id', body.campaignId)
      .eq('status', 'pending')

    if (pendingError || !pendingEmails) {
      console.error('Error getting pending emails:', pendingError)
      await supabaseAdmin
        .from('newsletter_campaigns')
        .update({ status: 'failed' })
        .eq('id', body.campaignId)
      return jsonResponse({ ok: false, reason: 'PENDING_EMAILS_FETCH_ERROR' }, 500)
    }

    // Send emails in batches
    let sentCount = 0
    let failedCount = 0
    const fromEmail = getFromEmail()

    for (let i = 0; i < pendingEmails.length; i += BATCH_SIZE) {
      const batch = pendingEmails.slice(i, i + BATCH_SIZE)

      // Process batch in parallel
      const results = await Promise.all(
        batch.map(async (emailRecord) => {
          // Replace template variables
          const personalizedHtml = replaceTemplateVariables(campaign.content_html, {
            client_name: emailRecord.client_name,
            studio_name: 'Studio Kalos',
          })
          const personalizedText = campaign.content_text
            ? replaceTemplateVariables(campaign.content_text, {
                client_name: emailRecord.client_name,
                studio_name: 'Studio Kalos',
              })
            : undefined

          // Send email
          const { data, error } = await sendEmail({
            from: fromEmail,
            to: emailRecord.email_address,
            subject: campaign.subject,
            html: personalizedHtml,
            text: personalizedText,
            tags: [
              { name: 'campaign_id', value: body.campaignId },
              { name: 'email_id', value: emailRecord.id },
            ],
          })

          if (error) {
            console.error(`Failed to send email to ${emailRecord.email_address}:`, error)
            await supabaseAdmin
              .from('newsletter_emails')
              .update({
                status: 'failed',
                error_message: error.message,
              })
              .eq('id', emailRecord.id)
            return { success: false }
          }

          // Update email record with Resend ID
          await supabaseAdmin
            .from('newsletter_emails')
            .update({
              status: 'sent',
              resend_id: data.id,
              sent_at: new Date().toISOString(),
            })
            .eq('id', emailRecord.id)

          return { success: true }
        })
      )

      // Count results
      results.forEach(r => {
        if (r.success) sentCount++
        else failedCount++
      })

      // Delay between batches (except for the last batch)
      if (i + BATCH_SIZE < pendingEmails.length) {
        await delay(BATCH_DELAY_MS)
      }
    }

    // Update campaign with final stats
    const finalStatus = failedCount === pendingEmails.length ? 'failed' : 'sent'
    await supabaseAdmin
      .from('newsletter_campaigns')
      .update({
        status: finalStatus,
        sent_at: new Date().toISOString(),
        recipient_count: sentCount + failedCount,
      })
      .eq('id', body.campaignId)

    return jsonResponse({
      ok: true,
      sentCount,
      failedCount,
    }, 200)

  } catch (error) {
    console.error('Edge function error:', error)
    return jsonResponse({ ok: false, reason: 'INTERNAL_ERROR', message: error.message }, 500)
  }
})

function jsonResponse(body: ResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}