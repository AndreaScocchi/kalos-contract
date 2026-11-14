// Calendario collegato (14/11/2026): le prenotazioni di una persona in formato iCalendar (RFC 5545),
// per Google Calendar e il calendario del telefono. Solo funzioni pure: le prova
// `tests/calendar_test.ts` senza database.

export type CalendarFeedItem = {
  uid: string
  kind: 'lesson' | 'event'
  id: string
  title: string
  is_trial: boolean
  starts_at: string
  ends_at: string
  place: string | null
  address: string | null
  operator: string | null
  booked_at: string | null
}

const APP_URL = 'https://app.kalosstudio.it'
const CALENDAR_NAME = 'Studio Kalòs'

/** Un istante in UTC nel formato di iCalendar: `20261116T174500Z`. */
export function icsDate(value: string | Date): string {
  const date = typeof value === 'string' ? new Date(value) : value
  return date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '')
}

/** Testo di una proprietà: barre, punti e virgola, virgole e a capo in escape (RFC 5545 §3.3.11). */
export function icsText(value: string): string {
  return value
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r\n|\r|\n/g, '\\n')
}

const encoder = new TextEncoder()

/**
 * Una riga lunga si piega a 75 byte (RFC 5545 §3.1): a capo e uno spazio all'inizio della riga dopo.
 * Mai a metà di un carattere: «ò» e «ə» occupano due byte, le emoji quattro.
 */
export function foldLine(line: string): string {
  const out: string[] = []
  let current = ''
  let bytes = 0
  for (const char of line) {
    const size = encoder.encode(char).length
    // La prima riga ha 75 byte; le altre 74, perché cominciano con lo spazio.
    const limit = out.length === 0 ? 75 : 74
    if (bytes + size > limit) {
      out.push(current)
      current = ''
      bytes = 0
    }
    current += char
    bytes += size
  }
  out.push(current)
  return out.join('\r\n ')
}

function appPath(item: CalendarFeedItem): string {
  return `${APP_URL}/${item.kind === 'lesson' ? 'lesson' : 'event'}/${item.id}`
}

function summary(item: CalendarFeedItem): string {
  return item.is_trial ? `${item.title} · lezione di prova` : item.title
}

function location(item: CalendarFeedItem): string | null {
  const parts = [item.place, item.address].filter((p): p is string => !!p && p.trim() !== '')
  return parts.length > 0 ? parts.join(', ') : null
}

function description(item: CalendarFeedItem): string {
  const lines: string[] = []
  if (item.operator) lines.push(`Con ${item.operator}`)
  lines.push(`Apri nell'app: ${appPath(item)}`)
  lines.push('Per disdire usa l’app Kalòs.')
  return lines.join('\n')
}

/**
 * Il calendario intero. `now` è l'istante della risposta (DTSTAMP). Anche senza prenotazioni è un
 * calendario valido, vuoto: chi lo ha collegato non vede errori.
 */
export function buildCalendar(items: CalendarFeedItem[], now: Date = new Date()): string {
  const stamp = icsDate(now)
  const lines: string[] = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Studio Kalòs APS//Calendario collegato//IT',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    `X-WR-CALNAME:${icsText(CALENDAR_NAME)}`,
    `X-WR-CALDESC:${icsText('Le tue prenotazioni a Studio Kalòs, aggiornate da sole.')}`,
    'X-WR-TIMEZONE:Europe/Rome',
    'REFRESH-INTERVAL;VALUE=DURATION:PT1H',
    'X-PUBLISHED-TTL:PT1H',
  ]
  for (const item of items) {
    const where = location(item)
    lines.push(
      'BEGIN:VEVENT',
      `UID:${item.uid}@kalosstudio.it`,
      `DTSTAMP:${stamp}`,
      `DTSTART:${icsDate(item.starts_at)}`,
      `DTEND:${icsDate(item.ends_at)}`,
      `SUMMARY:${icsText(summary(item))}`,
      ...(where ? [`LOCATION:${icsText(where)}`] : []),
      `DESCRIPTION:${icsText(description(item))}`,
      `URL:${appPath(item)}`,
      'STATUS:CONFIRMED',
      'TRANSP:OPAQUE',
      'END:VEVENT',
    )
  }
  lines.push('END:VCALENDAR')
  return lines.map(foldLine).join('\r\n') + '\r\n'
}

/**
 * Il token dall'indirizzo: `/calendar-feed/<token>.ics` (quello che l'app dà a Google e al telefono)
 * o `?token=<token>`. Solo 64 cifre esadecimali minuscole; tutto il resto è null.
 */
export function tokenFromUrl(url: string): string | null {
  const parsed = new URL(url)
  const fromPath = /\/([0-9a-f]{64})(?:\.ics)?\/?$/.exec(parsed.pathname)?.[1]
  const fromQuery = parsed.searchParams.get('token')
  const token = fromPath ?? fromQuery
  return token && /^[0-9a-f]{64}$/.test(token) ? token : null
}
