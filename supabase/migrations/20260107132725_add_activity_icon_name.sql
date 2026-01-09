-- Migration: Add icon_name field to activities table
--
-- Obiettivo: Aggiungere il campo icon_name alla tabella activities per permettere
-- la gestione automatica delle icone. Il campo contiene il nome esatto dell'icona
-- della libreria iconsax-react (https://iconsax-react.pages.dev/).
--
-- Questo campo permette di:
-- 1. Eliminare il mapping statico delle icone nell'app
-- 2. Permettere al gestionale di selezionare l'icona per ogni attività
-- 3. Rendere le icone gestibili direttamente dal database senza modifiche al codice

-- ============================================================================
-- 1. Aggiungi campo icon_name alla tabella activities
-- ============================================================================

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS icon_name text;

COMMENT ON COLUMN public.activities.icon_name IS 
  'Nome esatto dell''icona della libreria iconsax-react. Utilizzato per visualizzare l''icona dell''attività nell''app e nel gestionale. Il nome deve corrispondere esattamente a quello disponibile su https://iconsax-react.pages.dev/';

-- ============================================================================
-- 2. Aggiorna la view public_site_activities per includere icon_name
-- ============================================================================

-- NOTA: DROP necessario perché PostgreSQL non permette di cambiare l'ordine delle colonne
-- o aggiungere colonne in mezzo con CREATE OR REPLACE VIEW
DROP VIEW IF EXISTS public.public_site_activities;

CREATE VIEW public.public_site_activities AS
SELECT 
  a.id,
  a.name,
  a.slug,
  a.description,
  a.discipline,
  a.color,
  a.icon_name,
  a.duration_minutes,
  a.image_url,
  a.is_active,
  -- Campi landing page
  a.landing_title,
  a.landing_subtitle,
  a.active_months,
  a.target_audience,
  a.program_objectives,
  a.why_participate,
  a.journey_structure,
  a.created_at,
  a.updated_at
FROM public.activities a
WHERE 
  a.deleted_at IS NULL
  -- NOTA: Non filtriamo per is_active = true per permettere al frontend di decidere
  -- se mostrare o meno le attività inattive. Se necessario, aggiungere: AND a.is_active = true
ORDER BY a.name ASC;

COMMENT ON VIEW public.public_site_activities IS 
  'View pubblica per le attività. Espone tutti i campi necessari: id, name, slug, description, discipline, color, icon_name, duration_minutes, image_url, is_active, campi landing page (landing_title, landing_subtitle, active_months, target_audience, program_objectives, why_participate, journey_structure), created_at, updated_at.';

-- ============================================================================
-- 3. GRANTS per accesso pubblico (anon) - già grantati, ma li rinnoviamo per sicurezza
-- ============================================================================

GRANT SELECT ON public.public_site_activities TO anon;
GRANT SELECT ON public.public_site_activities TO authenticated;

