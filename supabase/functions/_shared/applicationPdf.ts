// PDF della domanda di ammissione, mandato a chi la invia dal sito o dall'app (A7).
//
// La domanda online è un'"accettazione registrata": dati, spunte di statuto e privacy, data, ora e
// dispositivo. Questo PDF è la copia che resta alla persona: riporta tutto, compreso quando e da dove
// è stata inviata. Non si conserva: si ridisegna dalla riga di `member_applications`, come la
// ricevuta dalla riga di `receipts`.
//
// Stesso aspetto e stesso font della ricevuta (`receiptPdf.ts`). Helvetica non ha lo schwa, quindi i
// testi del PDF usano forme che non ne hanno bisogno ("socia o socio").

import { PDFDocument, StandardFonts, type PDFFont, type PDFPage } from 'https://esm.sh/pdf-lib@1.17.1'
import { ASSOCIATION, legalAddress } from './legal.ts'
import { ACCENT, formatDateIt, INK, makeSanitizer, MUTED, RULE, wrap } from './receiptPdf.ts'

export interface ApplicationPdfData {
  id: string
  channel: string
  first_name: string
  last_name: string
  fiscal_code: string | null
  birth_date: string
  birth_place: string | null
  birth_province: string | null
  address_street: string | null
  address_zip: string | null
  address_city: string | null
  address_province: string | null
  email: string | null
  phone: string | null
  minor_at_submission: boolean
  guardian_full_name: string | null
  guardian_fiscal_code: string | null
  guardian_relationship: string | null
  guardian_email: string | null
  guardian_phone: string | null
  guardian_consent_at: string | null
  accepted_statute_at: string
  accepted_privacy_at: string
  image_release: boolean | null
  submitted_at: string
  submitted_ip: string | null
  submitted_user_agent: string | null
}

export const APPLICATION_PDF_SELECT = `
  id, channel, first_name, last_name, fiscal_code, birth_date, birth_place, birth_province,
  address_street, address_zip, address_city, address_province, email, phone,
  minor_at_submission, guardian_full_name, guardian_fiscal_code, guardian_relationship,
  guardian_email, guardian_phone, guardian_consent_at,
  accepted_statute_at, accepted_privacy_at, image_release,
  submitted_at, submitted_ip, submitted_user_agent
`

const CHANNEL_LABELS: Record<string, string> = { site: 'dal sito', app: "dall'app", paper: 'su carta' }

/** "23/09/2026 alle 18:42" (ora italiana). */
export function formatDateTimeIt(value: string): string {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value
  const time = new Intl.DateTimeFormat('it-IT', { timeZone: 'Europe/Rome', hour: '2-digit', minute: '2-digit' }).format(date)
  return `${formatDateIt(value)} alle ${time}`
}

export function applicationFileName(data: Pick<ApplicationPdfData, 'last_name' | 'submitted_at'>): string {
  const day = formatDateIt(data.submitted_at).split('/').reverse().join('-')
  const name = data.last_name.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9]+/g, '-')
  return `Domanda-ammissione-${name}-${day}.pdf`
}

export async function renderApplicationPdf(data: ApplicationPdfData): Promise<Uint8Array> {
  const doc = await PDFDocument.create()
  const regular = await doc.embedFont(StandardFonts.Helvetica)
  const bold = await doc.embedFont(StandardFonts.HelveticaBold)
  const clean = makeSanitizer(regular)

  doc.setTitle(clean(`Domanda di ammissione — ${data.first_name} ${data.last_name}`))
  doc.setAuthor(clean(ASSOCIATION.shortLegalName))
  doc.setCreator('Studio Kalòs')
  doc.setLanguage('it-IT')

  const page: PDFPage = doc.addPage([595.28, 841.89])
  const { width, height } = page.getSize()
  const margin = 56
  const contentWidth = width - margin * 2
  let y = height - margin

  const text = (value: string, x: number, yPos: number, size: number, font: PDFFont = regular, color = INK) => {
    page.drawText(clean(value), { x, y: yPos, size, font, color })
  }
  const paragraph = (value: string, size = 10, font: PDFFont = regular, color = INK) => {
    for (const line of wrap(clean(value), font, size, contentWidth)) {
      text(line, margin, y, size, font, color)
      y -= size + 4
    }
  }

  // ── Intestazione ───────────────────────────────────────────────────────────────────────────
  page.drawRectangle({ x: margin, y: y + 6, width: 36, height: 3, color: ACCENT })
  y -= 14
  text(ASSOCIATION.shortLegalName, margin, y, 16, bold)
  y -= 16
  text(ASSOCIATION.legalName, margin, y, 9, regular, MUTED)
  y -= 12
  text(`${legalAddress()} · C.F. ${ASSOCIATION.fiscalCode}`, margin, y, 9, regular, MUTED)
  y -= 26
  text('DOMANDA DI AMMISSIONE', margin, y, 13, bold)
  y -= 16
  paragraph(
    `Chi scrive chiede di essere ammessa o ammesso come socia o socio di ${ASSOCIATION.shortLegalName}, ` +
    "secondo l'art. 4 dello statuto. L'ammissione la delibera il Consiglio Direttivo.",
    10, regular, MUTED,
  )
  y -= 8
  page.drawLine({ start: { x: margin, y }, end: { x: width - margin, y }, thickness: 0.8, color: RULE })
  y -= 24

  // ── Dati ───────────────────────────────────────────────────────────────────────────────────
  const labelWidth = 150
  const valueX = margin + labelWidth
  const valueWidth = contentWidth - labelWidth
  const row = (label: string, value: string | null | undefined) => {
    if (!value) return
    const lines = wrap(clean(value), regular, 10.5, valueWidth)
    text(label, margin, y, 8.5, bold, MUTED)
    for (const line of lines) {
      text(line, valueX, y, 10.5)
      y -= 15
    }
    y -= 3
  }
  const section = (title: string) => {
    y -= 6
    text(title.toUpperCase(), margin, y, 8, bold, MUTED)
    y -= 6
    page.drawLine({ start: { x: margin, y }, end: { x: width - margin, y }, thickness: 0.5, color: RULE })
    y -= 16
  }

  const birthPlace = [data.birth_place, data.birth_province ? `(${data.birth_province})` : null].filter(Boolean).join(' ')
  const address = [
    data.address_street,
    [data.address_zip, data.address_city, data.address_province ? `(${data.address_province})` : null].filter(Boolean).join(' '),
  ].filter((v) => v && v.trim()).join(', ')

  section('Chi chiede di entrare')
  row('Nome e cognome', `${data.first_name} ${data.last_name}`)
  row('Codice fiscale', data.fiscal_code)
  row('Nascita', `${formatDateIt(data.birth_date)}${birthPlace ? `, ${birthPlace}` : ''}`)
  row('Residenza', address || null)
  row('Email', data.email)
  row('Telefono', data.phone)

  if (data.minor_at_submission) {
    section('Minorenne: chi esercita la responsabilità genitoriale')
    row('Nome e cognome', data.guardian_full_name)
    row('Codice fiscale', data.guardian_fiscal_code)
    row('Rapporto', data.guardian_relationship)
    row('Email', data.guardian_email)
    row('Telefono', data.guardian_phone)
    row('Consenso', data.guardian_consent_at ? `dato il ${formatDateTimeIt(data.guardian_consent_at)}` : null)
  }

  section('Accettazioni')
  row('Statuto', `letto e accettato il ${formatDateTimeIt(data.accepted_statute_at)}`)
  row('Informativa privacy', `letta e accettata il ${formatDateTimeIt(data.accepted_privacy_at)}`)
  if (data.image_release !== null) {
    row('Uso delle immagini', data.image_release
      ? 'acconsente alle foto e ai video delle attività per i canali dell\'associazione'
      : 'non acconsente alle foto e ai video delle attività')
  }

  // ── Come è stata inviata ───────────────────────────────────────────────────────────────────
  section('Invio')
  row('Inviata', `${CHANNEL_LABELS[data.channel] ?? data.channel} il ${formatDateTimeIt(data.submitted_at)}`)
  row('Indirizzo IP', data.submitted_ip)
  row('Dispositivo', data.submitted_user_agent ? data.submitted_user_agent.slice(0, 160) : null)
  row('Riferimento', data.id)

  // ── Piede ──────────────────────────────────────────────────────────────────────────────────
  const footer =
    "Copia della domanda inviata online, nella forma dell'accettazione registrata: i dati, le accettazioni " +
    "e il momento dell'invio sono conservati dall'associazione. Lo stato della domanda " +
    `si vede nell'app; per qualsiasi domanda scrivi a ${ASSOCIATION.email}.`
  let fy = margin + 10
  const footerLines = wrap(clean(footer), regular, 8, contentWidth)
  fy += (footerLines.length - 1) * 11
  page.drawLine({ start: { x: margin, y: fy + 16 }, end: { x: width - margin, y: fy + 16 }, thickness: 0.5, color: RULE })
  for (const line of footerLines) {
    text(line, margin, fy, 8, regular, MUTED)
    fy -= 11
  }

  return await doc.save()
}
