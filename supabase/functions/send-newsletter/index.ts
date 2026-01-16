import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { sendEmail, replaceTemplateVariables, getFromEmail, delay } from '../_shared/resend.ts'

interface Recipient {
  email: string
  name: string
  clientId?: string // Optional: null for manual email addresses
}

interface RequestBody {
  campaignId: string
  recipients?: Recipient[] // Recipients passed from frontend (optional for marketing campaigns)
  testClientId?: string // When set, send only to this client (for testing marketing campaigns)
}

interface ResponseBody {
  ok: boolean
  reason?: string
  message?: string
  sentCount?: number
  failedCount?: number
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

// Parse markdown bold and italic to HTML
function parseMarkdownFormatting(text: string): string {
  // Process double asterisks first (**text**) then single (*text*)
  // **text** -> <em>text</em> (italic)
  let result = text.replace(/\*\*(.+?)\*\*/g, '<em>$1</em>')
  // *text* -> <strong>text</strong> (bold)
  result = result.replace(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/g, '<strong>$1</strong>')
  return result
}

// Generate preview text padding to hide other content from email preview
function generatePreviewPadding(): string {
  // Use zero-width non-joiners and non-breaking spaces to fill the preview area
  const padding = '&nbsp;&zwnj;'.repeat(100)
  return padding
}

// HTML email template with professional styling
function wrapTextInHtml(text: string, unsubscribeUrl: string, imageUrl: string | null = null, previewText: string | null = null): string {
  // Escape HTML entities (but preserve our markdown markers for now)
  const escaped = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')

  // Parse markdown formatting (bold/italic) into HTML tags
  const formatted = parseMarkdownFormatting(escaped)

  // Convert newlines to <br>
  const htmlContent = formatted.replace(/\n/g, '<br>')

  // Colors from Studio Kalòs brand
  const primaryColor = '#0F2D3B' // Dark teal - text color
  const accentColor = '#036257' // Teal accent
  const accentOrange = '#F75C2C' // Orange accent
  const backgroundColor = '#FDFBF7' // Warm white background
  const cardBackground = '#FFFFFF'
  const footerText = '#6B7280'

  return `<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="color-scheme" content="light only">
  <meta name="supported-color-schemes" content="light only">
  <title>Studio Kalòs</title>
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
  ${previewText ? `<!-- Preview text (preheader) - hidden but shown in email client preview -->
  <div style="display:none;font-size:1px;color:#ffffff;line-height:1px;max-height:0px;max-width:0px;opacity:0;overflow:hidden;">
    ${previewText}${generatePreviewPadding()}
  </div>` : ''}
  <!-- Wrapper table for full-width background -->
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color: ${backgroundColor};">
    <tr>
      <td align="center" style="padding: 40px 20px;">
        <!-- Main content card -->
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width: 600px; background-color: ${cardBackground}; border-radius: 16px; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.05); overflow: hidden;">
          <!-- Header with logo/brand -->
          <tr>
            <td style="padding: 32px 40px 0 40px; text-align: center;">
              <h1 style="margin: 0; font-size: 28px; font-weight: 600; color: ${primaryColor}; letter-spacing: 2px;">STUDIO KALÒS</h1>
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
                    <p style="margin: 0 0 8px 0; font-size: 14px; font-weight: 600; color: ${primaryColor};">Studio Kalòs</p>
                    <p style="margin: 0; font-size: 13px; color: ${footerText};">
                      <a href="mailto:info.studiokalos@gmail.com" style="color: ${accentColor}; text-decoration: none;">info.studiokalos@gmail.com</a>
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 13px; color: ${footerText};">Località Casello Ferroviario, 3 - 34079 Staranzano (GO)</p>
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
                Ricevi questa email perché sei iscritto alla newsletter di Studio Kalòs.
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

    // Determine recipients - either passed directly or fetched from clients
    let recipients: Recipient[] = body.recipients || []

    // If testClientId is provided, fetch only that client
    if (body.testClientId && recipients.length === 0) {
      const { data: testClient, error: testClientError } = await supabaseUser
        .from('clients')
        .select('id, first_name, last_name, email')
        .eq('id', body.testClientId)
        .single()

      if (testClientError || !testClient || !testClient.email) {
        return jsonResponse({ ok: false, reason: 'TEST_CLIENT_NOT_FOUND', message: 'Cliente test non trovato o senza email' }, 400)
      }

      recipients = [{
        email: testClient.email,
        name: `${testClient.first_name || ''} ${testClient.last_name || ''}`.trim() || 'Cliente',
        clientId: testClient.id,
      }]
    }

    // If still no recipients, fetch all active clients with email (for marketing campaigns without test)
    if (recipients.length === 0) {
      const { data: clients, error: clientsError } = await supabaseUser
        .from('clients')
        .select('id, first_name, last_name, email')
        .not('email', 'is', null)
        .is('deleted_at', null)
        .eq('email_bounced', false)

      if (clientsError || !clients) {
        return jsonResponse({ ok: false, reason: 'CLIENTS_FETCH_ERROR' }, 500)
      }

      recipients = clients
        .filter((c: { email: string | null }) => c.email)
        .map((c: { id: string; first_name: string | null; last_name: string | null; email: string | null }) => ({
          email: c.email!,
          name: `${c.first_name || ''} ${c.last_name || ''}`.trim() || 'Cliente',
          clientId: c.id,
        }))
    }

    if (recipients.length === 0) {
      return jsonResponse({ ok: false, reason: 'NO_RECIPIENTS' }, 400)
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

    // Create newsletter_emails records for all recipients
    const emailRecords = recipients.map(recipient => ({
      campaign_id: body.campaignId,
      client_id: recipient.clientId || null,
      email_address: recipient.email,
      client_name: recipient.name,
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

    // Send emails sequentially to respect Resend rate limit (2 req/sec)
    let sentCount = 0
    let failedCount = 0
    const fromEmail = getFromEmail()

    // Generate public URL for newsletter image (if present)
    const imagePublicUrl = getImagePublicUrl(campaign.image_url)

    for (let i = 0; i < pendingEmails.length; i++) {
      const emailRecord = pendingEmails[i]

      // Replace template variables ({{nome}} -> recipient name)
      const personalizedText = replaceTemplateVariables(campaign.content, {
        nome: emailRecord.client_name,
        client_name: emailRecord.client_name, // Keep old variable for compatibility
        studio_name: 'Studio Kalòs',
      })

      // Generate unsubscribe URL
      const token = await generateUnsubscribeToken(emailRecord.email_address)
      const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
      const unsubscribeUrl = `${supabaseUrl}/functions/v1/unsubscribe-newsletter?email=${encodeURIComponent(emailRecord.email_address)}&token=${token}`

      // Convert plain text to HTML (with image and preview text if present)
      const personalizedHtml = wrapTextInHtml(personalizedText, unsubscribeUrl, imagePublicUrl, campaign.preview_text)

      // Send email with List-Unsubscribe headers for better deliverability
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
        headers: {
          'List-Unsubscribe': `<${unsubscribeUrl}>`,
          'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
        },
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
        failedCount++
      } else {
        // Update email record with Resend ID
        await supabaseAdmin
          .from('newsletter_emails')
          .update({
            status: 'sent',
            resend_id: data?.id ?? null,
            sent_at: new Date().toISOString(),
          })
          .eq('id', emailRecord.id)
        sentCount++
      }

      // Delay between emails to respect rate limit (2 req/sec = 500ms minimum)
      // Using 550ms to have a safety margin
      if (i < pendingEmails.length - 1) {
        await delay(EMAIL_DELAY_MS)
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
