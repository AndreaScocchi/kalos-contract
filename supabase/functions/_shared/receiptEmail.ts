// Invio della ricevuta per email, con il PDF allegato.
//
// Lo usano il webhook di Stripe (ogni pagamento online, sempre) e `send-receipt` (lo staff, dal
// gestionale). Prima si "prenota" l'invio in `receipts` (`receipt_claim_send`), poi si manda, poi si
// registra l'esito: due consegne dello stesso evento non mandano due email, e se l'invio fallisce
// resta scritto il motivo (lo segnala ops-health, e dal gestionale si reinvia con un clic).
//
// L'indirizzo, se non è indicato: quello usato per pagare (Stripe), poi quello del donatore, poi
// quello della scheda cliente, poi quello della domanda di ammissione.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { legalLine, legalLineHtml } from './legal.ts'
import { loadReceiptPdfData } from './receiptData.ts'
import { formatDateIt, formatEuro, METHOD_LABELS, receiptFileName, renderReceiptPdf } from './receiptPdf.ts'
import { getFromEmail, getReplyToEmail, sendRawEmail } from './ses.ts'
import { EMAIL_RE } from './http.ts'

export type SendReceiptResult = { ok: true; to: string } | { ok: false; reason: string; message?: string }

type ContactRow = {
  kind: string | null
  client_id: string | null
  metadata: Record<string, unknown> | null
  client: { email: string | null } | { email: string | null }[] | null
  stripe_payment: { receipt_email: string | null } | { receipt_email: string | null }[] | null
}

function one<T>(value: T | T[] | null): T | null {
  return Array.isArray(value) ? value[0] ?? null : value
}

async function findRecipientEmail(admin: SupabaseClient, receiptId: string): Promise<{ email: string | null; kind: string | null }> {
  const { data } = await admin
    .from('receipts')
    .select(`transaction:transactions (
      kind, client_id, metadata,
      client:clients ( email ),
      stripe_payment:stripe_payments!transactions_stripe_payment_id_fkey ( receipt_email )
    )`)
    .eq('id', receiptId)
    .maybeSingle()

  const tx = one((data as { transaction: ContactRow | ContactRow[] | null } | null)?.transaction ?? null)
  if (!tx) return { email: null, kind: null }

  const payer = (tx.metadata?.payer ?? null) as { email?: string } | null
  const candidates = [
    one(tx.stripe_payment)?.receipt_email,
    payer?.email,
    one(tx.client)?.email,
  ]
  if (tx.client_id) {
    const { data: app } = await admin
      .from('member_applications')
      .select('email')
      .eq('client_id', tx.client_id)
      .order('submitted_at', { ascending: false })
      .limit(1)
      .maybeSingle()
    candidates.push(app?.email ?? null)
  }
  const email = candidates.map((c) => c?.trim()).find((c): c is string => !!c && EMAIL_RE.test(c)) ?? null
  return { email, kind: tx.kind }
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

export function buildReceiptEmail(input: {
  recipientName: string
  fullNumber: string
  causale: string
  amountCents: number
  method: string | null
  occurredOn: string | null
  kind: string | null
  voided: boolean
}): { subject: string; html: string; text: string } {
  const firstName = input.recipientName.trim().split(/\s+/)[0] || ''
  const hello = firstName ? `Ciao ${firstName},` : 'Ciao,'
  const isDonation = input.kind === 'donation'
  const amount = formatEuro(input.amountCents)
  const paidOn = input.occurredOn ? formatDateIt(input.occurredOn) : null
  const method = input.method ? (METHOD_LABELS[input.method] ?? input.method).toLowerCase() : null

  const subject = isDonation
    ? `Grazie! La ricevuta della tua donazione (n. ${input.fullNumber})`
    : `La tua ricevuta Studio Kalòs n. ${input.fullNumber}`

  const opening = isDonation
    ? 'grazie di cuore per la tua donazione: quello che riceviamo torna tutto nelle attività dell\'associazione.'
    : 'grazie! Ti mandiamo la ricevuta del tuo pagamento.'

  const details = [
    `Ricevuta n. ${input.fullNumber}`,
    `${input.causale}: ${amount}`,
    paidOn ? `Pagato il ${paidOn}${method ? ` (${method})` : ''}` : null,
  ].filter((line): line is string => !!line)

  const voidedNote = input.voided
    ? 'Attenzione: questa ricevuta risulta annullata. Se ti serve un chiarimento, rispondi a questa email.'
    : null

  const closing = 'La trovi in allegato in PDF: conservala, vale come documento del pagamento. Per qualsiasi domanda rispondi pure a questa email.'

  const text = [
    hello,
    '',
    opening,
    '',
    ...details,
    '',
    ...(voidedNote ? [voidedNote, ''] : []),
    closing,
    '',
    'Studio Kalòs',
    '',
    '—',
    legalLine(),
  ].join('\n')

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
    <p style="color: #0F2D3B; font-size: 16px; line-height: 1.6; margin: 0 0 24px;">${escapeHtml(opening)}</p>
    <div style="background: #FAFAF1; border-radius: 12px; padding: 20px 24px; margin-bottom: 24px;">
      ${details.map((line, i) => `<p style="color: #0F2D3B; font-size: ${i === 1 ? '17px' : '15px'}; ${i === 1 ? 'font-weight: 600; ' : ''}line-height: 1.5; margin: ${i === 0 ? '0' : '6px 0 0'};">${escapeHtml(line)}</p>`).join('\n      ')}
    </div>
    ${voidedNote ? `<p style="color: #B5482E; font-size: 15px; line-height: 1.6; margin: 0 0 16px;">${escapeHtml(voidedNote)}</p>` : ''}
    <p style="color: #0F2D3B; font-size: 15px; line-height: 1.6; margin: 0;">${escapeHtml(closing)}</p>
  </div>
  <p style="text-align: center; margin-top: 24px; font-size: 12px; color: #6B7280; line-height: 1.6;">
    ${legalLineHtml()}
  </p>
</body>
</html>`

  return { subject, html, text }
}

/**
 * Manda la ricevuta. `admin` è il client con la chiave di servizio: chi chiama ha già controllato
 * che la persona possa farlo (lo staff, oppure il webhook di Stripe).
 */
export async function sendReceiptEmail(
  admin: SupabaseClient,
  receiptId: string,
  options: { to?: string | null; resend?: boolean } = {},
): Promise<SendReceiptResult> {
  const { data: claim, error: claimError } = await admin.rpc('receipt_claim_send', {
    p_receipt_id: receiptId,
    p_resend: options.resend ?? false,
  })
  if (claimError) return { ok: false, reason: 'CLAIM_FAILED', message: claimError.message }
  if (!claim?.ok) return { ok: false, reason: String(claim?.reason ?? 'CLAIM_FAILED') }

  const fail = async (reason: string, message?: string): Promise<SendReceiptResult> => {
    await admin.rpc('receipt_mark_sent', { p_receipt_id: receiptId, p_to: null, p_error: message ?? reason })
    return { ok: false, reason, message }
  }

  try {
    const loaded = await loadReceiptPdfData(admin, receiptId)
    if (!loaded.ok) return await fail(loaded.reason, loaded.message)

    const contact = await findRecipientEmail(admin, receiptId)
    const to = options.to?.trim() || contact.email
    if (!to || !EMAIL_RE.test(to)) return await fail('NO_EMAIL', 'Nessun indirizzo email valido per questa ricevuta')

    const data = loaded.data
    const pdf = await renderReceiptPdf(data)
    const email = buildReceiptEmail({
      recipientName: data.recipient_name,
      fullNumber: data.full_number,
      causale: data.causale,
      amountCents: data.amount_cents,
      method: data.method,
      occurredOn: data.occurred_on,
      kind: contact.kind,
      voided: !!data.voided_at,
    })

    const { error } = await sendRawEmail({
      from: getFromEmail(),
      to,
      replyTo: getReplyToEmail(),
      subject: email.subject,
      html: email.html,
      text: email.text,
      attachments: [{ filename: receiptFileName(data.full_number), content: pdf, contentType: 'application/pdf' }],
      tags: [{ name: 'type', value: 'receipt' }],
    })
    if (error) return await fail('SEND_FAILED', `${error.name}: ${error.message}`)

    await admin.rpc('receipt_mark_sent', { p_receipt_id: receiptId, p_to: to, p_error: null })
    return { ok: true, to }
  } catch (err) {
    return await fail('SEND_FAILED', err instanceof Error ? err.message : String(err))
  }
}
