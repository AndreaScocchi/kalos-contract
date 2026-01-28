-- Migration: Add get_event_booking_count RPC
--
-- Problema: La query per contare i posti disponibili degli eventi è soggetta
-- alle RLS policies, quindi ogni utente vede solo le proprie prenotazioni
-- invece del totale. Questo causa numeri diversi su dispositivi diversi.
--
-- Soluzione: Funzione RPC con SECURITY DEFINER che bypassa le RLS e conta
-- tutte le prenotazioni per un evento.

-- ============================================================================
-- FUNZIONE: get_event_booking_count
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_event_booking_count(p_event_id uuid)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO public
AS $$
  SELECT count(*)::integer
  FROM public.event_bookings
  WHERE event_id = p_event_id
    AND status IN ('booked', 'attended', 'no_show');
$$;

COMMENT ON FUNCTION public.get_event_booking_count(uuid) IS
  'Conta tutte le prenotazioni attive per un evento (booked, attended, no_show).
   Usa SECURITY DEFINER per bypassare le RLS e restituire il conteggio totale.';

-- Grant execute a tutti gli utenti autenticati
GRANT EXECUTE ON FUNCTION public.get_event_booking_count(uuid) TO authenticated;

-- ============================================================================
-- FUNZIONE: get_events_booking_counts (batch per performance)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_events_booking_counts(p_event_ids uuid[])
RETURNS TABLE(event_id uuid, booked_count integer)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO public
AS $$
  SELECT
    eb.event_id,
    count(*)::integer AS booked_count
  FROM public.event_bookings eb
  WHERE eb.event_id = ANY(p_event_ids)
    AND eb.status IN ('booked', 'attended', 'no_show')
  GROUP BY eb.event_id;
$$;

COMMENT ON FUNCTION public.get_events_booking_counts(uuid[]) IS
  'Conta tutte le prenotazioni attive per più eventi in una singola query (batch).
   Usa SECURITY DEFINER per bypassare le RLS e restituire i conteggi totali.';

-- Grant execute a tutti gli utenti autenticati
GRANT EXECUTE ON FUNCTION public.get_events_booking_counts(uuid[]) TO authenticated;
