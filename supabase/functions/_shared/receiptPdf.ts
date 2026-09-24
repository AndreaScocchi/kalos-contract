// PDF della ricevuta dell'associazione.
//
// Un solo disegno per tutte le strade da cui passerà una ricevuta: download dal gestionale
// (sessione 4), invio per email e pagamenti Stripe (sessione 5), download in app (sessione 10).
//
// Il PDF NON si conserva: si ridisegna ogni volta dalla riga di `receipts`, che ha dentro i dati
// congelati al momento dell'emissione (`issuer_snapshot`, destinatario, causale, importo). Stessa
// riga, stesso PDF, anche fra anni e anche dopo il passaggio a "APS - ETS".
//
// Niente testi legali inventati qui: le diciture fiscali (esenzioni, bollo, formule) arrivano dalle
// risposte del commercialista (DOMANDE-COMMERCIALISTA.md §2) e vivono in
// `association_settings.receipt_footer`, che la ricevuta ricopia nel suo `issuer_snapshot`.
//
// Font: Helvetica, uno dei 14 standard del PDF, così non serve incorporare file né chiedersi di
// licenze. Copre l'alfabeto dell'Europa occidentale (WinAnsi): i pochi caratteri fuori (ə, ł, …)
// si riducono alla lettera base invece di far fallire la generazione.

import { PDFDocument, StandardFonts, degrees, rgb, type PDFFont, type PDFPage } from 'https://esm.sh/pdf-lib@1.17.1'

export interface ReceiptIssuer {
  legal_name?: string | null
  short_legal_name?: string | null
  fiscal_code?: string | null
  vat_number?: string | null
  address?: string | null
  pec?: string | null
  email?: string | null
  footer?: string | null
}

export interface ReceiptPdfData {
  full_number: string
  issued_at: string
  recipient_name: string
  recipient_fiscal_code: string | null
  recipient_address: string | null
  issuer_snapshot: ReceiptIssuer
  causale: string
  amount_cents: number
  stamp_duty_cents: number
  voided_at: string | null
  void_reason: string | null
  /** Dalla transazione collegata: come e quando è arrivato il denaro. */
  method: string | null
  occurred_on: string | null
}

// Colori del brand (BRAND.md §2): blu notte per il testo, arancio per l'accento. Esportati per il PDF
// della domanda di ammissione (`applicationPdf.ts`), che ha lo stesso aspetto.
export const INK = rgb(0x0f / 255, 0x2d / 255, 0x3b / 255)
export const MUTED = rgb(0x5a / 255, 0x6b / 255, 0x73 / 255)
export const RULE = rgb(0xd9 / 255, 0xd4 / 255, 0xc6 / 255)
export const ACCENT = rgb(0xf7 / 255, 0x5c / 255, 0x2c / 255)
const VOID = rgb(0xb5 / 255, 0x48 / 255, 0x2e / 255)

export const METHOD_LABELS: Record<string, string> = {
  cash: 'Contanti',
  bank_transfer: 'Bonifico bancario',
  stripe: 'Pagamento elettronico',
  other: 'Altro',
}

export function receiptFileName(fullNumber: string): string {
  return `Ricevuta-${fullNumber.replace(/[^A-Za-z0-9]+/g, '-')}.pdf`
}

export function formatEuro(cents: number): string {
  const sign = cents < 0 ? '-' : ''
  const abs = Math.abs(cents)
  const euros = Math.floor(abs / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')
  const decimals = (abs % 100).toString().padStart(2, '0')
  return `${sign}€ ${euros},${decimals}`
}

/** "2026-09-23" → "23/09/2026". Accetta anche un timestamp: prende la data a Roma. */
export function formatDateIt(value: string | null | undefined): string {
  if (!value) return ''
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const [y, m, d] = value.split('-')
    return `${d}/${m}/${y}`
  }
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value
  const parts = new Intl.DateTimeFormat('it-IT', {
    timeZone: 'Europe/Rome', day: '2-digit', month: '2-digit', year: 'numeric',
  }).formatToParts(date)
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? ''
  return `${get('day')}/${get('month')}/${get('year')}`
}

/** Riduce il testo ai caratteri che Helvetica sa disegnare, invece di far fallire il PDF. */
export function makeSanitizer(font: PDFFont): (text: string) => string {
  const supported = new Set(font.getCharacterSet())
  const fallback: Record<string, string> = { 'ə': 'e', 'Ə': 'E', 'ł': 'l', 'Ł': 'L', 'đ': 'd', 'Đ': 'D', '’': "'", '‘': "'" }
  return (text: string) =>
    Array.from(text.replace(/\r\n?/g, '\n'))
      .map((ch) => {
        if (ch === '\n' || supported.has(ch.codePointAt(0)!)) return ch
        const base = ch.normalize('NFD').replace(/[\u0300-\u036f]/g, '')
        if (base && Array.from(base).every((c) => supported.has(c.codePointAt(0)!))) return base
        return fallback[ch] ?? '?'
      })
      .join('')
}

export function wrap(text: string, font: PDFFont, size: number, maxWidth: number): string[] {
  const lines: string[] = []
  for (const paragraph of text.split('\n')) {
    const words = paragraph.split(/\s+/).filter(Boolean)
    let line = ''
    for (const word of words) {
      const candidate = line ? `${line} ${word}` : word
      if (font.widthOfTextAtSize(candidate, size) <= maxWidth || !line) {
        line = candidate
      } else {
        lines.push(line)
        line = word
      }
    }
    lines.push(line)
  }
  return lines
}

export async function renderReceiptPdf(data: ReceiptPdfData): Promise<Uint8Array> {
  const doc = await PDFDocument.create()
  const regular = await doc.embedFont(StandardFonts.Helvetica)
  const bold = await doc.embedFont(StandardFonts.HelveticaBold)
  const clean = makeSanitizer(regular)

  const issuer = data.issuer_snapshot ?? {}
  const title = `Ricevuta ${data.full_number}`
  doc.setTitle(clean(title))
  doc.setAuthor(clean(issuer.short_legal_name || issuer.legal_name || ''))
  doc.setCreator('Gestionale Studio Kalòs')
  doc.setLanguage('it-IT')

  // A4 verticale
  const page: PDFPage = doc.addPage([595.28, 841.89])
  const { width, height } = page.getSize()
  const margin = 56
  const contentWidth = width - margin * 2
  let y = height - margin

  const text = (value: string, x: number, yPos: number, size: number, font: PDFFont = regular, color = INK) => {
    page.drawText(clean(value), { x, y: yPos, size, font, color })
  }
  const textRight = (value: string, yPos: number, size: number, font: PDFFont = regular, color = INK) => {
    const v = clean(value)
    page.drawText(v, { x: width - margin - font.widthOfTextAtSize(v, size), y: yPos, size, font, color })
  }

  // ── Intestazione: chi emette a sinistra, numero e data a destra ──────────────────────────
  page.drawRectangle({ x: margin, y: y + 6, width: 36, height: 3, color: ACCENT })
  y -= 14
  text(issuer.short_legal_name || issuer.legal_name || '', margin, y, 16, bold)
  textRight('RICEVUTA', y + 2, 10, bold, MUTED)
  y -= 16
  if (issuer.legal_name && issuer.legal_name !== issuer.short_legal_name) {
    text(issuer.legal_name, margin, y, 9, regular, MUTED)
  }
  textRight(`N. ${data.full_number}`, y - 6, 18, bold)
  y -= 12
  if (issuer.address) {
    text(issuer.address, margin, y, 9, regular, MUTED)
    y -= 12
  }
  const fiscal = [
    issuer.fiscal_code ? `C.F. ${issuer.fiscal_code}` : null,
    issuer.vat_number ? `P.IVA ${issuer.vat_number}` : null,
  ].filter(Boolean).join(' · ')
  if (fiscal) {
    text(fiscal, margin, y, 9, regular, MUTED)
  }
  textRight(`Emessa il ${formatDateIt(data.issued_at)}`, y, 9, regular, MUTED)
  y -= 12
  const contacts = [issuer.pec ? `PEC ${issuer.pec}` : null, issuer.email].filter(Boolean).join(' · ')
  if (contacts) {
    text(contacts, margin, y, 9, regular, MUTED)
    y -= 12
  }

  y -= 14
  page.drawLine({ start: { x: margin, y }, end: { x: width - margin, y }, thickness: 0.8, color: RULE })
  y -= 30

  // ── Chi ha pagato ─────────────────────────────────────────────────────────────────────────
  text('RICEVUTO DA', margin, y, 8, bold, MUTED)
  y -= 18
  text(data.recipient_name, margin, y, 13, bold)
  y -= 16
  if (data.recipient_fiscal_code) {
    text(`C.F. ${data.recipient_fiscal_code}`, margin, y, 10, regular, MUTED)
    y -= 14
  }
  if (data.recipient_address) {
    for (const line of wrap(clean(data.recipient_address), regular, 10, contentWidth)) {
      text(line, margin, y, 10, regular, MUTED)
      y -= 14
    }
  }

  y -= 20

  // ── Righe: causale, importo, pagamento ────────────────────────────────────────────────────
  const labelWidth = 150
  const valueX = margin + labelWidth
  const valueWidth = contentWidth - labelWidth
  const row = (label: string, value: string, opts: { strong?: boolean } = {}) => {
    const size = opts.strong ? 13 : 11
    const font = opts.strong ? bold : regular
    const lines = wrap(clean(value), font, size, valueWidth)
    page.drawLine({ start: { x: margin, y: y + 16 }, end: { x: width - margin, y: y + 16 }, thickness: 0.5, color: RULE })
    text(label, margin, y, 9, bold, MUTED)
    for (const line of lines) {
      text(line, valueX, y, size, font)
      y -= size + 5
    }
    y -= 12
  }

  row('Causale', data.causale)
  row('Importo', formatEuro(data.amount_cents), { strong: true })
  if (data.method) row('Modalità di pagamento', METHOD_LABELS[data.method] ?? data.method)
  if (data.occurred_on) row('Data del pagamento', formatDateIt(data.occurred_on))
  if (data.stamp_duty_cents > 0) row('Imposta di bollo', formatEuro(data.stamp_duty_cents))
  page.drawLine({ start: { x: margin, y: y + 16 }, end: { x: width - margin, y: y + 16 }, thickness: 0.5, color: RULE })

  // ── Firma ─────────────────────────────────────────────────────────────────────────────────
  y -= 40
  const signX = width - margin - 200
  text(`Per ${issuer.short_legal_name || issuer.legal_name || ''}`, signX, y, 9, regular, MUTED)
  y -= 34
  page.drawLine({ start: { x: signX, y }, end: { x: width - margin, y }, thickness: 0.5, color: RULE })

  // ── Piede: le diciture decise con il commercialista ──────────────────────────────────────
  if (issuer.footer) {
    let fy = margin + 10
    const footerLines = wrap(clean(issuer.footer), regular, 8, contentWidth)
    fy += (footerLines.length - 1) * 11
    page.drawLine({ start: { x: margin, y: fy + 16 }, end: { x: width - margin, y: fy + 16 }, thickness: 0.5, color: RULE })
    for (const line of footerLines) {
      text(line, margin, fy, 8, regular, MUTED)
      fy -= 11
    }
  }

  // ── Annullata: resta leggibile, con il suo numero, ma non si confonde con una valida ─────
  if (data.voided_at) {
    const stamp = 'ANNULLATA'
    const size = 72
    const w = bold.widthOfTextAtSize(stamp, size)
    page.drawText(stamp, {
      x: width / 2 - (w / 2) * Math.cos(Math.PI / 6),
      y: height / 2 - (w / 2) * Math.sin(Math.PI / 6),
      size, font: bold, color: VOID, opacity: 0.18,
      rotate: degrees(30),
    })
    const reason = `Annullata il ${formatDateIt(data.voided_at)}${data.void_reason ? `: ${data.void_reason}` : ''}`
    let ry = margin + 90
    for (const line of wrap(clean(reason), bold, 10, contentWidth)) {
      text(line, margin, ry, 10, bold, VOID)
      ry -= 14
    }
  }

  return await doc.save()
}
