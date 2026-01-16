import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { sendEmail, getFromEmail } from '../_shared/resend.ts'

interface RequestBody {
  userId: string
}

interface ResponseBody {
  ok: boolean
  reason?: string
  message?: string
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
    if (!body.userId) {
      return jsonResponse({ ok: false, reason: 'MISSING_USER_ID' }, 400)
    }

    // Create admin client with service_role key
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Get user info
    const { data: userData, error: userError } = await supabaseAdmin.auth.admin.getUserById(body.userId)
    if (userError || !userData?.user) {
      console.error('Error getting user:', userError)
      return jsonResponse({ ok: false, reason: 'USER_NOT_FOUND' }, 404)
    }

    // Check if email is already confirmed
    if (userData.user.email_confirmed_at) {
      return jsonResponse({ ok: false, reason: 'ALREADY_CONFIRMED' }, 400)
    }

    // Check if user has an email
    if (!userData.user.email) {
      return jsonResponse({ ok: false, reason: 'NO_EMAIL' }, 400)
    }

    const userEmail = userData.user.email

    // Generate a confirmation link via Supabase Admin API
    const { data: linkData, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
      type: 'signup',
      email: userEmail,
    })

    if (linkError || !linkData?.properties?.action_link) {
      console.error('Error generating confirmation link:', linkError)

      // Log the failure
      await logAuthEmail(supabaseAdmin, {
        userId: body.userId,
        email: userEmail,
        emailType: 'resend',
        source: 'edge_function',
        status: 'failed',
        errorMessage: linkError?.message || 'Failed to generate link',
      })

      return jsonResponse(
        { ok: false, reason: 'LINK_GENERATION_FAILED', message: linkError?.message },
        500
      )
    }

    // Get the confirmation link
    const confirmationLink = linkData.properties.action_link

    // Send email via Resend for better deliverability
    const { data: resendData, error: resendError } = await sendEmail({
      from: `Kalos Studio <${getFromEmail()}>`,
      to: userEmail,
      subject: 'Conferma il tuo account Kalos Studio',
      html: generateConfirmationEmailHtml(confirmationLink),
      text: generateConfirmationEmailText(confirmationLink),
      tags: [
        { name: 'type', value: 'auth_confirmation' },
        { name: 'user_id', value: body.userId },
      ],
    })

    if (resendError) {
      console.error('Error sending email via Resend:', resendError)

      // Log the failure
      await logAuthEmail(supabaseAdmin, {
        userId: body.userId,
        email: userEmail,
        emailType: 'resend',
        source: 'resend_custom',
        status: 'failed',
        errorMessage: resendError.message,
      })

      return jsonResponse(
        { ok: false, reason: 'EMAIL_SEND_FAILED', message: resendError.message },
        500
      )
    }

    // Log the success
    await logAuthEmail(supabaseAdmin, {
      userId: body.userId,
      email: userEmail,
      emailType: 'resend',
      source: 'resend_custom',
      status: 'sent',
      resendId: resendData?.id,
    })

    console.log(`Confirmation email sent successfully to ${userEmail}, resend_id: ${resendData?.id}`)
    return jsonResponse({ ok: true }, 200)
  } catch (error) {
    console.error('Edge function error:', error)
    return jsonResponse({ ok: false, reason: 'INTERNAL_ERROR' }, 500)
  }
})

interface LogAuthEmailParams {
  userId: string
  email: string
  emailType: string
  source: string
  status: string
  resendId?: string
  errorMessage?: string
}

async function logAuthEmail(supabase: ReturnType<typeof createClient>, params: LogAuthEmailParams) {
  try {
    await supabase.from('auth_email_logs').insert({
      user_id: params.userId,
      email: params.email,
      email_type: params.emailType,
      source: params.source,
      status: params.status,
      resend_id: params.resendId,
      error_message: params.errorMessage,
    })
  } catch (err) {
    console.error('Failed to log auth email:', err)
  }
}

function generateConfirmationEmailHtml(confirmationLink: string): string {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Conferma il tuo account</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
  <div style="text-align: center; margin-bottom: 30px;">
    <h1 style="color: #8B5CF6; margin: 0;">Kalos Studio</h1>
    <p style="color: #666; margin-top: 5px;">Il tuo centro benessere</p>
  </div>

  <div style="background-color: #f9fafb; border-radius: 8px; padding: 30px; margin-bottom: 20px;">
    <h2 style="margin-top: 0; color: #1f2937;">Conferma il tuo account</h2>
    <p>Grazie per esserti registrato a Kalos Studio!</p>
    <p>Per completare la registrazione e accedere alla tua area personale, clicca sul pulsante qui sotto:</p>

    <div style="text-align: center; margin: 30px 0;">
      <a href="${confirmationLink}" style="display: inline-block; background-color: #8B5CF6; color: white; text-decoration: none; padding: 14px 30px; border-radius: 6px; font-weight: 600;">
        Conferma Email
      </a>
    </div>

    <p style="font-size: 14px; color: #666;">Se il pulsante non funziona, copia e incolla questo link nel tuo browser:</p>
    <p style="font-size: 12px; word-break: break-all; color: #8B5CF6;">${confirmationLink}</p>
  </div>

  <div style="text-align: center; font-size: 12px; color: #999;">
    <p>Questa email è stata inviata da Kalos Studio.</p>
    <p>Se non hai richiesto questa registrazione, puoi ignorare questa email.</p>
  </div>
</body>
</html>
`
}

function generateConfirmationEmailText(confirmationLink: string): string {
  return `
Kalos Studio - Conferma il tuo account

Grazie per esserti registrato a Kalos Studio!

Per completare la registrazione e accedere alla tua area personale, visita il seguente link:

${confirmationLink}

Se non hai richiesto questa registrazione, puoi ignorare questa email.

---
Kalos Studio - Il tuo centro benessere
`
}

function jsonResponse(body: ResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
