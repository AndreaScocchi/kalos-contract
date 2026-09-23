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
import { receiptFileName, renderReceiptPdf } from '../_shared/receiptPdf.ts'
import { loadReceiptPdfData } from '../_shared/receiptData.ts'

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

  const loaded = await loadReceiptPdfData(supabase, receiptId)
  // Inesistente, o non visibile a chi chiede (anche la sola chiave pubblica): stessa risposta, così
  // non si scopre quali id esistono e non compare un falso guasto nei log
  if (!loaded.ok && loaded.reason === 'RECEIPT_NOT_FOUND') {
    return jsonResponse({ ok: false, reason: 'RECEIPT_NOT_FOUND' }, 404)
  }
  if (!loaded.ok) {
    console.error('[receipt-pdf] lettura ricevuta:', loaded.message)
    return jsonResponse({ ok: false, reason: 'READ_FAILED' }, 500)
  }
  const pdfData = loaded.data

  try {
    const pdf = await renderReceiptPdf(pdfData)
    const fileName = receiptFileName(pdfData.full_number)
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
