// Piccole utilità comuni alle edge function della sessione 5 (pagamenti, domande, ricevute).

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from './cors.ts'

export function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

/** Client con la chiave di servizio: scrive dove le app non possono. Mai restituito al chiamante. */
export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { autoRefreshToken: false, persistSession: false } },
  )
}

/**
 * Client con il token di chi chiama: decidono le RLS e i controlli dentro le RPC, esattamente come
 * se la chiamata arrivasse dal sito o dal gestionale.
 */
export function userClient(authHeader: string): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    },
  )
}

/**
 * IP di chi ha fatto la richiesta, come lo vede il proxy davanti alle edge function. Serve alla
 * domanda di ammissione ("accettazione registrata": data, ora e dispositivo) e al limite dei checkout.
 * Restituisce null se quello che arriva non è un indirizzo valido.
 */
export function clientIp(req: Request): string | null {
  const candidates = [
    req.headers.get('cf-connecting-ip'),
    req.headers.get('x-real-ip'),
    req.headers.get('x-forwarded-for')?.split(',')[0],
  ]
  for (const raw of candidates) {
    const ip = raw?.trim()
    if (!ip) continue
    if (/^(\d{1,3}\.){3}\d{1,3}$/.test(ip) || /^[0-9a-f:]+$/i.test(ip)) return ip
  }
  return null
}

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/

/** SHA-256 in esadecimale: per salvare un'impronta dell'IP invece dell'IP. */
export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

/** Lavoro da finire dopo aver risposto (le email), dove il runtime lo permette. */
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined

export function runAfterResponse(task: Promise<unknown>): void {
  const guarded = task.catch((err) => console.error('[dopo la risposta]', err))
  if (typeof EdgeRuntime !== 'undefined' && EdgeRuntime?.waitUntil) {
    EdgeRuntime.waitUntil(guarded)
  }
}
