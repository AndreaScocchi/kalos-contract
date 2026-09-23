// PDF di una ricevuta, generato al momento dalla riga di `receipts`.
//
// POST { receipt_id } con il token di chi è loggato. La ricevuta si legge CON QUEL TOKEN, non con la
// chiave di servizio: decidono le RLS di `receipts` e `transactions` chi può scaricarla (oggi lo
// staff; quando l'app mostrerà le ricevute al socio basterà aggiungere la policy sul proprio
// client_id, senza toccare questa funzione).
//
// Risponde con il PDF (application/pdf, in download) oppure JSON { ok: false, reason }.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { receiptFileName, renderReceiptPdf, type ReceiptPdfData } from '../_shared/receiptPdf.ts'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return jsonResponse({ ok: false, reason: 'METHOD_NOT_ALLOWED' }, 405)
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)
  }

  let receiptId: string | undefined
  try {
    const body = await req.json()
    receiptId = typeof body?.receipt_id === 'string' ? body.receipt_id : undefined
  } catch {
    return jsonResponse({ ok: false, reason: 'INVALID_BODY' }, 400)
  }
  if (!receiptId || !UUID_RE.test(receiptId)) {
    return jsonResponse({ ok: false, reason: 'MISSING_RECEIPT_ID' }, 400)
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    },
  )

  const { data, error } = await supabase
    .from('receipts')
    .select(`
      full_number, issued_at, recipient_name, recipient_fiscal_code, recipient_address,
      issuer_snapshot, causale, amount_cents, stamp_duty_cents, voided_at, void_reason,
      transaction:transactions ( method, occurred_on )
    `)
    .eq('id', receiptId)
    .maybeSingle()

  // Chi non ha il permesso sulla tabella (per esempio la sola chiave pubblica) riceve la stessa
  // risposta di chi chiede una ricevuta inesistente: non è un guasto, e non si scopre nulla
  if (error && error.code === '42501') {
    return jsonResponse({ ok: false, reason: 'RECEIPT_NOT_FOUND' }, 404)
  }
  if (error) {
    console.error('[receipt-pdf] lettura ricevuta:', error.message)
    return jsonResponse({ ok: false, reason: 'READ_FAILED' }, 500)
  }
  // Inesistente o non visibile a chi chiede: stessa risposta, così non si scopre quali id esistono
  if (!data) {
    return jsonResponse({ ok: false, reason: 'RECEIPT_NOT_FOUND' }, 404)
  }

  const tx = Array.isArray(data.transaction) ? data.transaction[0] : data.transaction
  const pdfData: ReceiptPdfData = {
    full_number: data.full_number,
    issued_at: data.issued_at,
    recipient_name: data.recipient_name,
    recipient_fiscal_code: data.recipient_fiscal_code,
    recipient_address: data.recipient_address,
    issuer_snapshot: (data.issuer_snapshot ?? {}) as ReceiptPdfData['issuer_snapshot'],
    causale: data.causale,
    amount_cents: data.amount_cents,
    stamp_duty_cents: data.stamp_duty_cents,
    voided_at: data.voided_at,
    void_reason: data.void_reason,
    method: tx?.method ?? null,
    occurred_on: tx?.occurred_on ?? null,
  }

  try {
    const pdf = await renderReceiptPdf(pdfData)
    const fileName = receiptFileName(data.full_number)
    return new Response(pdf, {
      status: 200,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/pdf',
        'Content-Disposition': `attachment; filename="${fileName}"`,
        'Access-Control-Expose-Headers': 'Content-Disposition',
        'Cache-Control': 'no-store',
      },
    })
  } catch (err) {
    console.error('[receipt-pdf] generazione PDF:', err)
    return jsonResponse({ ok: false, reason: 'RENDER_FAILED' }, 500)
  }
})

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
