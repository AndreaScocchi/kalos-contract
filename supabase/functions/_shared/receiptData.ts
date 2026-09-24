// Lettura di una ricevuta per disegnarne il PDF. La usano `receipt-pdf` (col token di chi scarica,
// quindi decidono le RLS) e l'invio per email (con la chiave di servizio, dopo che chi lo chiede è
// stato controllato). Stessa riga, stesso PDF.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import type { ReceiptPdfData } from './receiptPdf.ts'

export const RECEIPT_PDF_SELECT = `
  id, full_number, issued_at, recipient_name, recipient_fiscal_code, recipient_address,
  issuer_snapshot, causale, amount_cents, stamp_duty_cents, voided_at, void_reason,
  transaction:transactions ( method, occurred_on )
`

type ReceiptRow = {
  full_number: string
  issued_at: string
  recipient_name: string
  recipient_fiscal_code: string | null
  recipient_address: string | null
  issuer_snapshot: unknown
  causale: string
  amount_cents: number
  stamp_duty_cents: number
  voided_at: string | null
  void_reason: string | null
  transaction: { method: string | null; occurred_on: string | null } | { method: string | null; occurred_on: string | null }[] | null
}

export function toReceiptPdfData(row: ReceiptRow): ReceiptPdfData {
  const tx = Array.isArray(row.transaction) ? row.transaction[0] : row.transaction
  return {
    full_number: row.full_number,
    issued_at: row.issued_at,
    recipient_name: row.recipient_name,
    recipient_fiscal_code: row.recipient_fiscal_code,
    recipient_address: row.recipient_address,
    issuer_snapshot: (row.issuer_snapshot ?? {}) as ReceiptPdfData['issuer_snapshot'],
    causale: row.causale,
    amount_cents: row.amount_cents,
    stamp_duty_cents: row.stamp_duty_cents,
    voided_at: row.voided_at,
    void_reason: row.void_reason,
    method: tx?.method ?? null,
    occurred_on: tx?.occurred_on ?? null,
  }
}

export type LoadReceiptResult =
  | { ok: true; data: ReceiptPdfData }
  | { ok: false; reason: 'RECEIPT_NOT_FOUND' | 'READ_FAILED'; message?: string }

/**
 * Legge la ricevuta col client che le passi. Chi non ha il permesso (per esempio la sola chiave
 * pubblica) riceve la stessa risposta di chi chiede una ricevuta inesistente.
 */
export async function loadReceiptPdfData(client: SupabaseClient, receiptId: string): Promise<LoadReceiptResult> {
  const { data, error } = await client.from('receipts').select(RECEIPT_PDF_SELECT).eq('id', receiptId).maybeSingle()
  if (error && error.code === '42501') return { ok: false, reason: 'RECEIPT_NOT_FOUND' }
  if (error) return { ok: false, reason: 'READ_FAILED', message: error.message }
  if (!data) return { ok: false, reason: 'RECEIPT_NOT_FOUND' }
  return { ok: true, data: toReceiptPdfData(data as unknown as ReceiptRow) }
}
