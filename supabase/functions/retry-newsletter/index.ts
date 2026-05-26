import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { sendEmail, replaceTemplateVariables, getReplyToEmail, buildBulkHeaders, buildPrimaryHeaders, buildFromAddress, delay, PRIMARY_DEFAULT_FROM_NAME } from '../_shared/resend.ts'

type DeliveryMode = 'promotions' | 'primary'

interface RequestBody {
  campaignId: string
}

interface ResponseBody {
  ok: boolean
  reason?: string
  message?: string
  sentCount?: number
  failedCount?: number
  totalRetried?: number
}

// Rate limiting: Resend allows 2 requests per second
// We send emails sequentially with 1000ms delay to stay safely under the limit
const EMAIL_DELAY_MS = 1000

// Generate unsubscribe token (must match unsubscribe-newsletter function)
async function generateUnsubscribeToken(email: string): Promise<string> {
  const secret = Deno.env.get('UNSUBSCRIBE_SECRET') || 'kalos-newsletter-2024'
  const data = new TextEncoder().encode(email + secret)
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  return hashArray.slice(0, 16).map(b => b.toString(16).padStart(2, '0')).join('')
}

// Generate public URL for newsletter image (bucket is public, URLs never expire)
function getImagePublicUrl(imageUrl: string | null): string | null {
  if (!imageUrl) return null

  // If it's already a full URL, return as-is
  if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
    return imageUrl
  }

  // Generate public URL from storage bucket
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  return `${supabaseUrl}/storage/v1/object/public/newsletter/${imageUrl}`
}

// HTML email template with professional styling (same as send-newsletter)
function wrapTextInHtml(text: string, unsubscribeUrl: string, imageUrl: string | null = null): string {
  // Escape HTML entities
  const escaped = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')

  // Convert newlines to <br>
  const htmlContent = escaped.replace(/\n/g, '<br>')

  // Colors from Studio Kalos brand
  const primaryColor = '#0F2D3B'
  const accentColor = '#036257'
  const accentOrange = '#F75C2C'
  const backgroundColor = '#FDFBF7'
  const cardBackground = '#FFFFFF'
  const footerText = '#6B7280'

  return `<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="color-scheme" content="light only">
  <meta name="supported-color-schemes" content="light only">
  <title>Studio Kalos</title>
  <!--[if mso]>
  <noscript>
    <xml>
      <o:OfficeDocumentSettings>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
  </noscript>
  <![endif]-->
  <style>
    :root { color-scheme: light only; }
    * { box-sizing: border-box; }
  </style>
</head>
<body style="margin: 0; padding: 0; background-color: ${backgroundColor}; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; -webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale;">
  <!-- Wrapper table for full-width background -->
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color: ${backgroundColor};">
    <tr>
      <td align="center" style="padding: 40px 20px;">
        <!-- Main content card -->
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width: 600px; background-color: ${cardBackground}; border-radius: 16px; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.05); overflow: hidden;">
          <!-- Header with logo/brand -->
          <tr>
            <td style="padding: 32px 40px 0 40px; text-align: center;">
              <h1 style="margin: 0; font-size: 28px; font-weight: 600; color: ${primaryColor}; letter-spacing: 2px;">STUDIO KALOS</h1>
              <div style="width: 40px; height: 1px; background-color: ${accentOrange}; margin: 16px auto 24px auto;"></div>
            </td>
          </tr>
          ${imageUrl ? `<!-- Newsletter Image -->
          <tr>
            <td style="padding: 0 40px;">
              <img src="${imageUrl}" alt="Newsletter" style="width: 100%; height: auto; border-radius: 8px; display: block;" />
            </td>
          </tr>` : ''}
          <!-- Body content -->
          <tr>
            <td style="padding: 40px; color: ${primaryColor}; font-size: 16px; line-height: 1.7;">
              ${htmlContent}
            </td>
          </tr>
          <!-- Footer -->
          <tr>
            <td style="padding: 24px 40px 32px 40px; background-color: #F9FAFB; border-radius: 0 0 16px 16px; border-top: 1px solid #E5E7EB;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td style="text-align: center;">
                    <p style="margin: 0 0 8px 0; font-size: 14px; font-weight: 600; color: ${primaryColor};">Studio Kalos</p>
                    <p style="margin: 0 0 4px 0; font-size: 13px; color: ${footerText};">
                      <a href="mailto:info.studiokalos@gmail.com" style="color: ${accentColor}; text-decoration: none;">info.studiokalos@gmail.com</a>
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 13px; color: ${footerText};">Localita Casello Ferroviario, 3 - 34079 Staranzano (GO)</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
        <!-- Unsubscribe note -->
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width: 600px;">
          <tr>
            <td style="padding: 24px 20px; text-align: center;">
              <p style="margin: 0; font-size: 12px; color: ${footerText};">
                Ricevi questa email perche sei iscritto alla newsletter di Studio Kalos.
              </p>
              <p style="margin: 8px 0 0 0; font-size: 11px;">
                <a href="${unsubscribeUrl}" style="color: ${footerText}; text-decoration: underline;">Annulla iscrizione</a>
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`
}

// Minimal HTML template for "primary" mode — see send-newsletter for design rationale.
function wrapTextInHtmlPrimary(text: string, unsubscribeUrl: string): string {
  const escaped = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
  const htmlContent = escaped.replace(/\n/g, '<br>')

  const primaryColor = '#0F2D3B'
  const footerText = '#6B7280'

  return `<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Studio Kalos</title>
</head>
<body style="margin: 0; padding: 0; background-color: #ffffff; font-family: -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif; color: ${primaryColor};">
  <div style="max-width: 560px; margin: 0 auto; padding: 24px 20px; font-size: 15px; line-height: 1.6;">
    <div style="font-size: 12px; color: ${footerText}; letter-spacing: 1px; margin-bottom: 4px;">STUDIO KALOS</div>
    <hr style="border: none; border-top: 1px solid #E5E7EB; margin: 0 0 20px 0;">
    <div style="color: ${primaryColor};">${htmlContent}</div>
    <hr style="border: none; border-top: 1px solid #E5E7EB; margin: 24px 0 12px 0;">
    <div style="font-size: 11px; color: ${footerText}; line-height: 1.5;">
      Staranzano (GO) &middot; <a href="${unsubscribeUrl}" style="color: ${footerText}; text-decoration: underline;">annulla iscrizione</a>
    </div>
  </div>
</body>
</html>`
}

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

    // Get all failed emails for this campaign
    const { data: failedEmailsRaw, error: failedError } = await supabaseAdmin
      .from('newsletter_emails')
      .select('*')
      .eq('campaign_id', body.campaignId)
      .eq('status', 'failed')

    if (failedError) {
      console.error('Error getting failed emails:', failedError)
      return jsonResponse({ ok: false, reason: 'FAILED_EMAILS_FETCH_ERROR' }, 500)
    }

    if (!failedEmailsRaw || failedEmailsRaw.length === 0) {
      return jsonResponse({
        ok: true,
        sentCount: 0,
        failedCount: 0,
        totalRetried: 0,
        message: 'No failed emails to retry',
      }, 200)
    }

    // Re-check opt-out state before retrying: a client may have unsubscribed (or
    // hard-bounced) between the original send and this retry. Drop those records.
    const clientIds = failedEmailsRaw
      .map((e: { client_id: string | null }) => e.client_id)
      .filter((id: string | null): id is string => !!id)
    const externalEmails = failedEmailsRaw
      .filter((e: { client_id: string | null }) => !e.client_id)
      .map((e: { email_address: string }) => e.email_address)

    const blockedClientIds = new Set<string>()
    if (clientIds.length > 0) {
      const { data: blockedClients } = await supabaseAdmin
        .from('clients')
        .select('id, newsletter_subscribed, email_bounced, deleted_at')
        .in('id', clientIds)
      for (const c of blockedClients ?? []) {
        if (c.newsletter_subscribed === false || c.email_bounced === true || c.deleted_at !== null) {
          blockedClientIds.add(c.id)
        }
      }
    }

    const blockedExtraEmails = new Set<string>()
    if (externalEmails.length > 0) {
      const { data: deletedExtras } = await supabaseAdmin
        .from('newsletter_extra_emails')
        .select('email, deleted_at')
        .in('email', externalEmails)
        .not('deleted_at', 'is', null)
      for (const e of deletedExtras ?? []) {
        blockedExtraEmails.add(e.email)
      }
    }

    const failedEmails = failedEmailsRaw.filter((e: { client_id: string | null; email_address: string }) => {
      if (e.client_id) return !blockedClientIds.has(e.client_id)
      return !blockedExtraEmails.has(e.email_address)
    })

    if (failedEmails.length < failedEmailsRaw.length) {
      console.log(`[Retry opt-out filter] Skipped ${failedEmailsRaw.length - failedEmails.length} retries (unsubscribed / bounced / deleted)`)
    }

    if (failedEmails.length === 0) {
      return jsonResponse({
        ok: true,
        sentCount: 0,
        failedCount: 0,
        totalRetried: 0,
        message: 'No failed emails to retry (all skipped due to opt-out)',
      }, 200)
    }

    // Update campaign status to 'sending'
    await supabaseAdmin
      .from('newsletter_campaigns')
      .update({ status: 'sending' })
      .eq('id', body.campaignId)

    // Resolve delivery mode (defaults to 'promotions' for legacy campaigns)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const deliveryMode: DeliveryMode = ((campaign as any).delivery_mode === 'primary') ? 'primary' : 'promotions'
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const fromNameOverride: string | null = (campaign as any).from_name_override ?? null
    const primaryFromName = (fromNameOverride && fromNameOverride.trim()) || PRIMARY_DEFAULT_FROM_NAME
    const fromEmail = buildFromAddress(deliveryMode === 'primary' ? primaryFromName : null)
    console.log(`[Retry] delivery_mode=${deliveryMode}, from=${fromEmail}`)

    // Send emails sequentially to respect Resend rate limit (2 req/sec)
    let sentCount = 0
    let failedCount = 0

    // Generate public URL for newsletter image (only used in promotions mode)
    const imagePublicUrl = getImagePublicUrl(campaign.image_url)

    for (let i = 0; i < failedEmails.length; i++) {
      const emailRecord = failedEmails[i]

      // Reset the email status to pending before retry
      await supabaseAdmin
        .from('newsletter_emails')
        .update({
          status: 'pending',
          error_message: null,
        })
        .eq('id', emailRecord.id)

      // Replace template variables ({{nome}} -> recipient name)
      const personalizedText = replaceTemplateVariables(campaign.content, {
        nome: emailRecord.client_name,
        client_name: emailRecord.client_name,
        studio_name: 'Studio Kalos',
      })

      // Generate unsubscribe URL
      const token = await generateUnsubscribeToken(emailRecord.email_address)
      const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
      const unsubscribeUrl = `${supabaseUrl}/functions/v1/unsubscribe-newsletter?email=${encodeURIComponent(emailRecord.email_address)}&token=${token}`

      const personalizedHtml = deliveryMode === 'primary'
        ? wrapTextInHtmlPrimary(personalizedText, unsubscribeUrl)
        : wrapTextInHtml(personalizedText, unsubscribeUrl, imagePublicUrl)
      const messageHeaders = deliveryMode === 'primary'
        ? buildPrimaryHeaders({ unsubscribeUrl })
        : buildBulkHeaders({ unsubscribeUrl, campaignId: body.campaignId })

      const { data, error } = await sendEmail({
        from: fromEmail,
        to: emailRecord.email_address,
        subject: campaign.subject,
        html: personalizedHtml,
        text: personalizedText,
        replyTo: getReplyToEmail(),
        tags: [
          { name: 'campaign_id', value: body.campaignId },
          { name: 'email_id', value: emailRecord.id },
          { name: 'retry', value: 'true' },
          { name: 'delivery_mode', value: deliveryMode },
        ],
        headers: messageHeaders,
      })

      if (error) {
        console.error(`Retry failed for ${emailRecord.email_address}:`, error)
        await supabaseAdmin
          .from('newsletter_emails')
          .update({
            status: 'failed',
            error_message: error.message,
          })
          .eq('id', emailRecord.id)
        failedCount++
      } else {
        // Update email record with Resend ID
        await supabaseAdmin
          .from('newsletter_emails')
          .update({
            status: 'sent',
            resend_id: data?.id ?? null,
            sent_at: new Date().toISOString(),
            error_message: null,
          })
          .eq('id', emailRecord.id)
        sentCount++
      }

      // Delay between emails to respect rate limit
      if (i < failedEmails.length - 1) {
        await delay(EMAIL_DELAY_MS)
      }
    }

    // Update campaign status
    const finalStatus = failedCount === failedEmails.length ? 'failed' : 'sent'
    await supabaseAdmin
      .from('newsletter_campaigns')
      .update({
        status: finalStatus,
      })
      .eq('id', body.campaignId)

    return jsonResponse({
      ok: true,
      sentCount,
      failedCount,
      totalRetried: failedEmails.length,
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
