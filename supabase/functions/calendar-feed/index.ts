// Calendario collegato (14/11/2026): Google Calendar e il calendario del telefono rileggono da qui
// le prenotazioni di una persona, in iCalendar.
//
//     GET /functions/v1/calendar-feed/<token>.ics
//
// Senza JWT (config.toml): la sicurezza è il token segreto, che il database riconosce con
// `calendar_feed_items` (solo service_role). Un token sconosciuto, cambiato, di una scheda archiviata
// o senza account riceve 404, sempre uguale: nessun indizio su cosa esiste.

import { adminClient } from '../_shared/http.ts'
import { buildCalendar, tokenFromUrl, type CalendarFeedItem } from '../_shared/calendar.ts'

function notFound(): Response {
  return new Response('Calendario non trovato.\n', {
    status: 404,
    headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
  })
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return new Response(null, { status: 405, headers: { Allow: 'GET, HEAD' } })
  }

  const token = tokenFromUrl(req.url)
  if (!token) return notFound()

  const { data, error } = await adminClient().rpc('calendar_feed_items', { p_token: token })
  if (error) {
    console.error('[calendar-feed] lettura non riuscita:', error.message)
    return new Response('Il calendario non è disponibile in questo momento.\n', {
      status: 503,
      headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Retry-After': '900', 'Cache-Control': 'no-store' },
    })
  }
  const feed = data as { found: boolean; items?: CalendarFeedItem[] } | null
  if (!feed?.found) return notFound()

  const body = buildCalendar(feed.items ?? [])
  return new Response(req.method === 'HEAD' ? null : body, {
    status: 200,
    headers: {
      'Content-Type': 'text/calendar; charset=utf-8',
      'Content-Disposition': 'inline; filename="studio-kalos.ics"',
      // Le prenotazioni sono personali: nessuna cache condivisa, ma un quarto d'ora nel calendario.
      'Cache-Control': 'private, max-age=900',
      'X-Robots-Tag': 'noindex',
    },
  })
})
