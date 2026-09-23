// Invio (o nuovo invio) di una ricevuta per email, dal gestionale.
//
// POST { receipt_id, to?, resend? } con il token di chi è loggato. Chi chiede deve essere staff E poter
// leggere quella ricevuta col proprio token (decidono le RLS, come per `receipt-pdf`); solo dopo si
// usa la chiave di servizio per prenotare l'invio e registrarne l'esito, che le operatrici non
// potrebbero scrivere da sole.
//
// Senza `to` l'indirizzo è quello della persona (vedi `_shared/receiptEmail.ts`). `resend: false` è
// l'invio automatico dopo un incasso: se la ricevuta risulta già inviata non riparte (ALREADY_SENT).
// Il pulsante "Invia per email" usa il default, `true`: manda di nuovo.
// Risponde { ok: true, to } oppure { ok: false, reason }.

import { corsHeaders } from '../_shared/cors.ts'
import { adminClient, EMAIL_RE, jsonResponse, UUID_RE, userClient } from '../_shared/http.ts'
import { sendReceiptEmail } from '../_shared/receiptEmail.ts'

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

  const receiptId = typeof body.receipt_id === 'string' ? body.receipt_id : ''
  if (!UUID_RE.test(receiptId)) return jsonResponse({ ok: false, reason: 'MISSING_RECEIPT_ID' }, 400)
  const to = typeof body.to === 'string' && body.to.trim() ? body.to.trim() : null
  if (to && !EMAIL_RE.test(to)) return jsonResponse({ ok: false, reason: 'INVALID_EMAIL' })

  const user = userClient(authHeader)
  const { data: isStaff } = await user.rpc('is_staff')
  if (isStaff !== true) return jsonResponse({ ok: false, reason: 'NOT_STAFF' }, 403)

  const { data: visible, error } = await user.from('receipts').select('id').eq('id', receiptId).maybeSingle()
  if (error && error.code !== '42501') {
    console.error('[send-receipt] lettura ricevuta:', error.message)
    return jsonResponse({ ok: false, reason: 'READ_FAILED' }, 500)
  }
  if (!visible) return jsonResponse({ ok: false, reason: 'RECEIPT_NOT_FOUND' }, 404)

  const result = await sendReceiptEmail(adminClient(), receiptId, { to, resend: body.resend !== false })
  if (!result.ok && result.reason === 'SEND_FAILED') console.error('[send-receipt]', result.message)
  return jsonResponse(result)
})
