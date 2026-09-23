// Domanda di ammissione inviata dal sito (e, dalla sessione 9, dall'app).
//
// POST con il token di chi è loggato e i dati della domanda. La domanda la registra
// `submit_member_application` CON QUEL TOKEN, come se la chiamasse il sito: stessi controlli, stessa
// scheda cliente. Qui si aggiunge quello che il browser non può dire in modo affidabile: l'indirizzo IP
// e il dispositivo, presi dalla richiesta ("accettazione registrata", A7). Poi parte l'email "Domanda
// ricevuta" con il PDF della domanda.
//
// Risponde { ok, reason?, application_id?, email_sent? }. Un'email non partita non annulla la domanda.

import { corsHeaders } from '../_shared/cors.ts'
import { adminClient, clientIp, EMAIL_RE, jsonResponse, userClient } from '../_shared/http.ts'
import { legalLine, legalLineHtml } from '../_shared/legal.ts'
import {
  APPLICATION_PDF_SELECT, applicationFileName, formatDateTimeIt, renderApplicationPdf, type ApplicationPdfData,
} from '../_shared/applicationPdf.ts'
import { getFromEmail, getReplyToEmail, sendRawEmail } from '../_shared/ses.ts'

// Solo questi campi passano alla RPC: canale, IP e dispositivo li decide questa funzione.
const ALLOWED_FIELDS = [
  'year', 'first_name', 'last_name', 'fiscal_code', 'birth_date', 'birth_place', 'birth_province',
  'address_street', 'address_city', 'address_zip', 'address_province', 'email', 'phone',
  'guardian_full_name', 'guardian_fiscal_code', 'guardian_relationship', 'guardian_email', 'guardian_phone',
  'guardian_consent', 'accepted_statute', 'accepted_privacy', 'image_release',
] as const

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return jsonResponse({ ok: false, reason: 'METHOD_NOT_ALLOWED' }, 405)

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return jsonResponse({ ok: false, reason: 'INVALID_BODY' }, 400)
  }

  const payload: Record<string, unknown> = {}
  for (const key of ALLOWED_FIELDS) {
    if (body[key] !== undefined && body[key] !== null) payload[key] = body[key]
  }
  payload.channel = body.channel === 'app' ? 'app' : 'site'
  payload.ip = clientIp(req)
  payload.user_agent = (req.headers.get('user-agent') ?? '').slice(0, 500) || null

  const user = userClient(authHeader)
  const { data: userData } = await user.auth.getUser()
  if (!userData?.user) return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)

  const { data: result, error } = await user.rpc('submit_member_application', { p_payload: payload })
  if (error) {
    console.error('[member-application] submit_member_application:', error.message)
    return jsonResponse({ ok: false, reason: 'SUBMIT_FAILED' }, 500)
  }
  if (!result?.ok) return jsonResponse(result ?? { ok: false, reason: 'SUBMIT_FAILED' })

  // La copia della domanda, per email. Se non parte, la domanda resta valida: lo si scrive nei log.
  let emailSent = false
  try {
    emailSent = await sendApplicationEmail(result.application_id, userData.user.email ?? null)
  } catch (err) {
    console.error('[member-application] email della domanda:', err)
  }

  return jsonResponse({ ...result, email_sent: emailSent })
})

async function sendApplicationEmail(applicationId: string, accountEmail: string | null): Promise<boolean> {
  const admin = adminClient()
  const { data, error } = await admin
    .from('member_applications')
    .select(`${APPLICATION_PDF_SELECT}, metadata`)
    .eq('id', applicationId)
    .single()
  if (error || !data) throw new Error(error?.message ?? 'domanda non trovata')

  const application = data as unknown as ApplicationPdfData & { metadata: Record<string, unknown> | null }
  const pdf = await renderApplicationPdf(application)

  const recipients = new Set<string>()
  const main = (application.email ?? accountEmail ?? '').trim()
  if (EMAIL_RE.test(main)) recipients.add(main.toLowerCase())
  // Minorenne: la copia va anche a chi ha dato il consenso
  const guardian = (application.guardian_email ?? '').trim()
  if (application.minor_at_submission && EMAIL_RE.test(guardian)) recipients.add(guardian.toLowerCase())
  if (recipients.size === 0) return false

  const email = buildApplicationEmail(application)
  let sent = 0
  for (const to of recipients) {
    const { error: sendError } = await sendRawEmail({
      from: getFromEmail(),
      to,
      replyTo: getReplyToEmail(),
      subject: email.subject,
      html: email.html,
      text: email.text,
      attachments: [{ filename: applicationFileName(application), content: pdf, contentType: 'application/pdf' }],
      tags: [{ name: 'type', value: 'member_application' }],
    })
    if (sendError) console.error('[member-application] invio a', to, sendError.name, sendError.message)
    else sent++
  }

  await admin
    .from('member_applications')
    .update({
      metadata: {
        ...(application.metadata ?? {}),
        confirmation_sent_at: sent > 0 ? new Date().toISOString() : null,
        confirmation_recipients: sent,
      },
    })
    .eq('id', applicationId)

  return sent > 0
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

function buildApplicationEmail(a: ApplicationPdfData): { subject: string; html: string; text: string } {
  const subject = 'Abbiamo ricevuto la tua domanda di ammissione'
  const hello = `Ciao ${a.first_name},`
  const paragraphs = [
    `grazie! Abbiamo ricevuto la tua domanda per entrare in Studio Kalòs APS, inviata il ${formatDateTimeIt(a.submitted_at)}.`,
    "Ora la domanda passa al Consiglio Direttivo, che delibera le ammissioni. Intanto, se hai versato la quota associativa dell'anno, puoi già prenotare le attività dall'app: per partecipare serve che l'ammissione sia confermata, e te lo diciamo appena succede.",
    'In allegato trovi la copia della tua domanda in PDF, con i dati e le accettazioni che hai inviato. Se qualcosa non torna, rispondi pure a questa email.',
  ]

  const text = [hello, '', ...paragraphs.flatMap((p) => [p, '']), 'A presto,', 'Studio Kalòs', '', '—', legalLine()].join('\n')

  const html = `<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(subject)}</title>
</head>
<body style="font-family: 'Jost', 'Segoe UI', Arial, sans-serif; background: #FDFBF7; margin: 0; padding: 40px 20px;">
  <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 16px; padding: 40px; box-shadow: 0 4px 6px rgba(0,0,0,0.05);">
    <div style="text-align: center; margin-bottom: 24px;">
      <h1 style="color: #036257; font-size: 24px; margin: 0;">Studio Kalòs</h1>
    </div>
    <p style="color: #0F2D3B; font-size: 16px; line-height: 1.6; margin: 0 0 12px;">${escapeHtml(hello)}</p>
    ${paragraphs.map((p) => `<p style="color: #0F2D3B; font-size: 16px; line-height: 1.6; margin: 0 0 16px;">${escapeHtml(p)}</p>`).join('\n    ')}
    <p style="color: #0F2D3B; font-size: 16px; line-height: 1.6; margin: 8px 0 0;">A presto,<br>Studio Kalòs</p>
  </div>
  <p style="text-align: center; margin-top: 24px; font-size: 12px; color: #6B7280; line-height: 1.6;">
    ${legalLineHtml()}
  </p>
</body>
</html>`

  return { subject, html, text }
}
