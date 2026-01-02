-- Migration 0011: Ensure public_site_events shows all events (past and future)
--
-- Obiettivo: Assicurare che la view public_site_events mostri TUTTI gli eventi
-- (passati e futuri), senza filtri per data. La view deve restituire la lista completa
-- degli eventi non soft-deleted, lasciando al client-side il compito di filtrare
-- per mostrare solo eventi futuri o passati se necessario.

-- ============================================================================
-- 1. Aggiorna public_site_events per mostrare tutti gli eventi
-- ============================================================================

-- NOTA: DROP necessario perché PostgreSQL non permette di cambiare i filtri WHERE
-- con CREATE OR REPLACE VIEW se la struttura è identica ma il filtro cambia
DROP VIEW IF EXISTS public.public_site_events;

CREATE VIEW public.public_site_events AS
SELECT 
  e.id,
  e.name AS title,
  -- NOTA: Normalizzato come "title" per coerenza con l'uso nel sito
  e.description,
  e.image_url,
  e.starts_at AS start_date,
  -- NOTA: Normalizzato come "start_date" per coerenza con l'uso nel sito
  e.ends_at AS end_date,
  -- NOTA: Normalizzato come "end_date" per coerenza con l'uso nel sito
  e.link AS registration_url,
  -- NOTA: Normalizzato come "registration_url" per coerenza con l'uso nel sito
  -- NOTA: link_url non esiste nella tabella events, usiamo link come fallback
  -- Se in futuro serve un link_url separato, aggiungere la colonna alla tabella events
  e.link AS link_url,
  e.created_at,
  e.updated_at
FROM public.events e
WHERE 
  e.deleted_at IS NULL
  -- IMPORTANTE: Nessun filtro su starts_at o ends_at - mostra TUTTI gli eventi
  -- (passati e futuri). Il filtro per mostrare solo eventi futuri o passati
  -- deve essere fatto client-side se necessario.
ORDER BY e.starts_at DESC;

COMMENT ON VIEW public.public_site_events IS 
  'View pubblica per gli eventi. Espone TUTTI gli eventi non soft-deleted (passati e futuri). 
   NON filtra per data: mostra sia eventi passati che futuri. Il sito pubblico può filtrare 
   client-side per mostrare solo eventi futuri o passati se necessario. 
   Include: id, title (name), description, image_url, start_date (starts_at), end_date (ends_at), 
   registration_url (link), link_url (link), created_at, updated_at.';

-- ============================================================================
-- 2. GRANTS per accesso pubblico (anon) - già grantati nelle migrations precedenti,
--    ma li rinnoviamo per sicurezza
-- ============================================================================

GRANT SELECT ON public.public_site_events TO anon;
GRANT SELECT ON public.public_site_events TO authenticated;

-- ============================================================================
-- 3. Verifica RLS policy per garantire accesso a tutti gli eventi
-- ============================================================================

-- La policy "events_select_public_for_site_view" creata nella migration 0008
-- dovrebbe già permettere l'accesso a tutti gli eventi non soft-deleted.
-- Verifichiamo che esista e sia corretta.

-- Se la policy non esiste, la creiamo
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'events' 
      AND policyname = 'events_select_public_for_site_view'
  ) THEN
    CREATE POLICY "events_select_public_for_site_view" ON "public"."events" 
      FOR SELECT 
      TO "anon"
      USING (deleted_at IS NULL);
  END IF;
END
$$;

COMMENT ON POLICY "events_select_public_for_site_view" ON "public"."events" IS 
  'RLS: Permette accesso anonimo a TUTTI gli eventi non soft-deleted per la vista public_site_events. 
   Non filtra per is_active o per data (starts_at/ends_at), permettendo di mostrare sia eventi 
   passati che futuri.';

