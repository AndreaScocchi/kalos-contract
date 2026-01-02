-- Migration 0009: Add duration field to activities table
--
-- Obiettivo: Aggiungere il campo duration_minutes alla tabella activities
-- per indicare la durata consigliata delle lezioni. Questo campo può essere
-- modificato dal gestionale ed è utilizzato principalmente dal sito web
-- per mostrare la durata delle attività.
--
-- Il campo è nullable per permettere alle attività esistenti di non avere
-- una durata specificata inizialmente.

-- ============================================================================
-- 1. Aggiungi campo duration_minutes alla tabella activities
-- ============================================================================

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS duration_minutes integer;

COMMENT ON COLUMN public.activities.duration_minutes IS 
  'Durata consigliata delle lezioni in minuti. Può essere modificata dal gestionale. Utilizzata principalmente dal sito web per mostrare la durata delle attività.';

-- ============================================================================
-- 2. Aggiorna la view public_site_activities per includere duration_minutes
-- ============================================================================

-- NOTA: DROP necessario perché PostgreSQL non permette di cambiare l'ordine delle colonne
-- o aggiungere colonne in mezzo con CREATE OR REPLACE VIEW
DROP VIEW IF EXISTS public.public_site_activities;

CREATE VIEW public.public_site_activities AS
SELECT 
  a.id,
  a.name,
  -- NOTA: Se in futuro serve uno slug per matchare i file JSON activity.{slug}.json,
  -- aggiungere una colonna slug nella tabella activities e includerla qui
  a.description,
  a.discipline,
  a.color,
  a.duration_minutes,
  -- NOTA: Se in futuro serve image_url, aggiungere la colonna nella tabella activities
  a.created_at
FROM public.activities a
WHERE 
  a.deleted_at IS NULL
  -- NOTA: Se in futuro viene aggiunto un campo is_public o is_active per filtrare
  -- le attività pubbliche, aggiungere il filtro qui (es: AND a.is_public = true)
ORDER BY a.name ASC;

COMMENT ON VIEW public.public_site_activities IS 
  'View pubblica per le attività. Espone solo dati minimi necessari: id, name, description, discipline, color, duration_minutes. NOTA: slug e image_url non sono disponibili nella tabella activities attualmente.';

-- ============================================================================
-- 3. GRANTS per accesso pubblico (anon) - già grantati nella migration 0007,
--    ma li rinnoviamo per sicurezza
-- ============================================================================

GRANT SELECT ON public.public_site_activities TO anon;
GRANT SELECT ON public.public_site_activities TO authenticated;

