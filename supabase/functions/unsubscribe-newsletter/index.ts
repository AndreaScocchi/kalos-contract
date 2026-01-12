import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Simple unsubscribe page - returns HTML directly
Deno.serve(async (req: Request): Promise<Response> => {
  const url = new URL(req.url)
  const email = url.searchParams.get('email')
  const token = url.searchParams.get('token')

  // Colors from Studio Kalòs brand
  const primaryColor = '#0F2D3B'
  const accentColor = '#036257'
  const accentOrange = '#F75C2C'
  const backgroundColor = '#FDFBF7'

  // Validate parameters
  if (!email || !token) {
    return htmlResponse(`
      <h1>Link non valido</h1>
      <p>Il link di disiscrizione non è valido o è scaduto.</p>
    `, primaryColor, accentColor, accentOrange, backgroundColor)
  }

  // Verify token (simple hash of email + secret)
  const expectedToken = await generateToken(email)
  if (token !== expectedToken) {
    return htmlResponse(`
      <h1>Link non valido</h1>
      <p>Il link di disiscrizione non è valido o è scaduto.</p>
    `, primaryColor, accentColor, accentOrange, backgroundColor)
  }

  // Create admin client
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { autoRefreshToken: false, persistSession: false } }
  )

  try {
    // Find the client by email and update newsletter_subscribed to false
    const { data: client, error: findError } = await supabaseAdmin
      .from('clients')
      .select('id, full_name')
      .eq('email', email)
      .single()

    if (findError || !client) {
      // Client not found - might be a manual email, just show success anyway
      return htmlResponse(`
        <h1>Disiscrizione completata</h1>
        <p>L'indirizzo <strong>${escapeHtml(email)}</strong> è stato rimosso dalla newsletter di Studio Kalòs.</p>
        <p>Non riceverai più comunicazioni da noi.</p>
      `, primaryColor, accentColor, accentOrange, backgroundColor)
    }

    // Update client to unsubscribe from newsletter
    const { error: updateError } = await supabaseAdmin
      .from('clients')
      .update({ newsletter_subscribed: false })
      .eq('id', client.id)

    if (updateError) {
      console.error('Error updating client:', updateError)
      return htmlResponse(`
        <h1>Errore</h1>
        <p>Si è verificato un errore durante la disiscrizione. Riprova più tardi.</p>
      `, primaryColor, accentColor, accentOrange, backgroundColor)
    }

    return htmlResponse(`
      <h1>Disiscrizione completata</h1>
      <p>Ciao ${escapeHtml(client.full_name || '')},</p>
      <p>L'indirizzo <strong>${escapeHtml(email)}</strong> è stato rimosso dalla newsletter di Studio Kalòs.</p>
      <p>Non riceverai più comunicazioni da noi.</p>
      <p style="margin-top: 24px; font-size: 14px; color: #6B7280;">Se hai cambiato idea, contattaci a <a href="mailto:info.studiokalos@gmail.com" style="color: ${accentColor};">info.studiokalos@gmail.com</a></p>
    `, primaryColor, accentColor, accentOrange, backgroundColor)

  } catch (error) {
    console.error('Unsubscribe error:', error)
    return htmlResponse(`
      <h1>Errore</h1>
      <p>Si è verificato un errore durante la disiscrizione. Riprova più tardi.</p>
    `, primaryColor, accentColor, accentOrange, backgroundColor)
  }
})

// Generate a simple token for email verification
async function generateToken(email: string): Promise<string> {
  const secret = Deno.env.get('UNSUBSCRIBE_SECRET') || 'kalos-newsletter-2024'
  const data = new TextEncoder().encode(email + secret)
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  return hashArray.slice(0, 16).map(b => b.toString(16).padStart(2, '0')).join('')
}

// Export for use in send-newsletter
export { generateToken }

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}

function htmlResponse(content: string, primaryColor: string, accentColor: string, accentOrange: string, backgroundColor: string): Response {
  const html = `<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Studio Kalòs - Disiscrizione Newsletter</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background-color: ${backgroundColor};
      color: ${primaryColor};
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      background: white;
      border-radius: 16px;
      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.05);
      max-width: 500px;
      width: 100%;
      overflow: hidden;
    }
    .accent-line {
      height: 1px;
      background-color: ${accentColor};
    }
    .header {
      padding: 32px 40px 0;
      text-align: center;
    }
    .header h2 {
      font-size: 24px;
      font-weight: 600;
      letter-spacing: 2px;
      margin: 0;
    }
    .header p {
      font-size: 12px;
      color: ${accentColor};
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-top: 8px;
      margin-bottom: 16px;
    }
    .header-divider {
      width: 40px;
      height: 1px;
      background-color: ${accentOrange};
      margin: 0 auto 24px auto;
    }
    .content {
      padding: 24px 40px 40px;
      line-height: 1.6;
    }
    .content h1 {
      font-size: 22px;
      margin-bottom: 16px;
      color: ${accentColor};
    }
    .content p {
      margin-bottom: 12px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="accent-line"></div>
    <div class="header">
      <h2>STUDIO KALÒS</h2>
      <p>Centro Olistico</p>
      <div class="header-divider"></div>
    </div>
    <div class="content">
      ${content}
    </div>
  </div>
</body>
</html>`

  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  })
}
