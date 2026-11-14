// Calendario collegato (14/11/2026): il formato iCalendar che leggono Google e il telefono.
//
//     cd supabase/functions && deno test --node-modules-dir=none tests/calendar_test.ts

import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1'
import { buildCalendar, foldLine, icsDate, icsText, tokenFromUrl, type CalendarFeedItem } from '../_shared/calendar.ts'

const TOKEN = 'a'.repeat(32) + '0123456789abcdef'.repeat(2)
const encoder = new TextEncoder()

const lesson: CalendarFeedItem = {
  uid: 'booking-11111111-1111-1111-1111-111111111111',
  kind: 'lesson',
  id: '22222222-2222-2222-2222-222222222222',
  title: 'Vinyasa Yoga',
  is_trial: false,
  starts_at: '2026-11-16T17:45:00+00:00',
  ends_at: '2026-11-16T18:45:00+00:00',
  place: 'Sala del Parco',
  address: 'Via dei Tigli 3, 34077 Ronchi dei Legionari, GO',
  operator: 'Alice Driussi',
  booked_at: '2026-11-10T09:00:00+00:00',
}

Deno.test('date in UTC', () => {
  assertEquals(icsDate('2026-11-16T18:45:00+01:00'), '20261116T174500Z')
})

Deno.test('testo in escape', () => {
  assertEquals(icsText('Yoga, respiro; corpo\\mente\nfine'), 'Yoga\\, respiro\\; corpo\\\\mente\\nfine')
})

Deno.test('righe piegate a 75 byte senza spezzare i caratteri', () => {
  const line = 'SUMMARY:' + 'ò'.repeat(60)
  const folded = foldLine(line).split('\r\n')
  assert(folded.length > 1)
  for (const part of folded) assert(encoder.encode(part).length <= 75, part)
  assertEquals(folded.map((p, i) => (i === 0 ? p : p.slice(1))).join(''), line)
  assertEquals(foldLine('BREVE'), 'BREVE')
})

Deno.test('il calendario con una lezione', () => {
  const ics = buildCalendar([lesson], new Date('2026-11-14T10:00:00Z'))
  assert(ics.startsWith('BEGIN:VCALENDAR\r\n'))
  assert(ics.endsWith('END:VCALENDAR\r\n'))
  assertMatch(ics, /\r\nX-WR-CALNAME:Studio Kalòs\r\n/)
  assertMatch(ics, /\r\nUID:booking-11111111-1111-1111-1111-111111111111@kalosstudio\.it\r\n/)
  assertMatch(ics, /\r\nDTSTART:20261116T174500Z\r\n/)
  assertMatch(ics, /\r\nDTEND:20261116T184500Z\r\n/)
  assertMatch(ics, /\r\nSUMMARY:Vinyasa Yoga\r\n/)
  assertMatch(ics, /\r\nURL:https:\/\/app\.kalosstudio\.it\/lesson\/22222222-2222-2222-2222-222222222222\r\n/)
  const unfolded = ics.replace(/\r\n /g, '')
  assertMatch(unfolded, /\r\nLOCATION:Sala del Parco\\, Via dei Tigli 3\\, 34077 Ronchi dei Legionari\\, GO\r\n/)
  assertMatch(unfolded, /\r\nDESCRIPTION:Con Alice Driussi\\nApri nell'app: https:\/\/app\.kalosstudio\.it\/lesson\//)
  for (const line of ics.split('\r\n')) assert(encoder.encode(line).length <= 75, line)
})

Deno.test('la prova e l’evento senza luogo', () => {
  const ics = buildCalendar([
    { ...lesson, is_trial: true },
    { ...lesson, uid: 'event-booking-3', kind: 'event', title: 'Chat & Craft', place: null, address: null, operator: null },
  ]).replace(/\r\n /g, '')
  assertMatch(ics, /SUMMARY:Vinyasa Yoga · lezione di prova\r\n/)
  assertMatch(ics, /SUMMARY:Chat & Craft\r\n/)
  assertMatch(ics, /URL:https:\/\/app\.kalosstudio\.it\/event\//)
  assertEquals(ics.match(/LOCATION:/g)?.length, 1)
})

Deno.test('senza prenotazioni è un calendario vuoto, valido', () => {
  const ics = buildCalendar([])
  assert(!ics.includes('BEGIN:VEVENT'))
  assertMatch(ics, /END:VCALENDAR\r\n$/)
})

Deno.test('il token dall’indirizzo', () => {
  const base = 'https://x.supabase.co/functions/v1/calendar-feed'
  assertEquals(tokenFromUrl(`${base}/${TOKEN}.ics`), TOKEN)
  assertEquals(tokenFromUrl(`${base}/${TOKEN}`), TOKEN)
  assertEquals(tokenFromUrl(`${base}?token=${TOKEN}`), TOKEN)
  assertEquals(tokenFromUrl(`${base}/${TOKEN.toUpperCase()}.ics`), null)
  assertEquals(tokenFromUrl(`${base}/abc.ics`), null)
  assertEquals(tokenFromUrl(`${base}?token=../../etc`), null)
  assertEquals(tokenFromUrl(base), null)
})
