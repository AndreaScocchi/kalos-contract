-- Migration 0012: Add landing page fields to activities table
--
-- Obiettivo: Aggiungere campi aggiuntivi alla tabella activities per supportare
-- la visualizzazione delle attività nella landing page del sito web. Questi campi
-- permettono di personalizzare meglio la presentazione delle attività.
--
-- I nuovi campi sono tutti nullable per mantenere la compatibilità con le attività
-- esistenti e permettere una migrazione graduale.

-- ============================================================================
-- 1. Aggiungi campi base mancanti (richiesti dal frontend)
-- ============================================================================

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS image_url text;

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now();

COMMENT ON COLUMN public.activities.image_url IS 
  'URL dell''immagine dell''attività. Utilizzato per la visualizzazione sul sito web.';

COMMENT ON COLUMN public.activities.is_active IS 
  'Se false, l''attività non viene mostrata pubblicamente. Default: true.';

COMMENT ON COLUMN public.activities.updated_at IS 
  'Timestamp di ultimo aggiornamento. Aggiornato automaticamente tramite trigger.';

-- ============================================================================
-- 2. Aggiungi campi testuali per la landing page
-- ============================================================================

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS landing_title text;

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS landing_subtitle text;

COMMENT ON COLUMN public.activities.landing_title IS 
  'Titolo principale per la landing page dell''attività. Utilizzato principalmente dal sito web per personalizzare la presentazione dell''attività.';

COMMENT ON COLUMN public.activities.landing_subtitle IS 
  'Sottotitolo per la landing page dell''attività. Utilizzato principalmente dal sito web per personalizzare la presentazione dell''attività.';

-- ============================================================================
-- 3. Aggiungi campi JSONB per dati strutturati
-- ============================================================================

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS active_months jsonb;

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS target_audience jsonb;

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS program_objectives jsonb;

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS why_participate jsonb;

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS journey_structure jsonb;

COMMENT ON COLUMN public.activities.active_months IS 
  'Array di stringhe rappresentanti i mesi in cui l''attività è attiva. Valori: "1" per Gennaio, "2" per Febbraio, ..., "12" per Dicembre. Esempio: ["1", "2", "3", "9", "10", "11", "12"]';

COMMENT ON COLUMN public.activities.target_audience IS 
  'Array di oggetti con struttura {title: string, description: string}[] rappresentante il pubblico target dell''attività. Esempio: [{"title": "Principianti", "description": "Perfetto per chi si avvicina per la prima volta"}]';

COMMENT ON COLUMN public.activities.program_objectives IS 
  'Array di stringhe, ognuna rappresenta un obiettivo del programma. Esempio: ["Ridurre lo stress", "Migliorare la concentrazione"]';

COMMENT ON COLUMN public.activities.why_participate IS 
  'Array di stringhe, ognuna rappresenta un motivo per partecipare. Esempio: ["Impara tecniche pratiche", "Ricevi supporto da istruttori esperti"]';

COMMENT ON COLUMN public.activities.journey_structure IS 
  'Array di stringhe, ognuna rappresenta una fase del "Viaggio di Consapevolezza". Esempio: ["Fase 1: Introduzione", "Fase 2: Pratiche guidate"]';

-- ============================================================================
-- 4. Crea trigger per aggiornare updated_at automaticamente
-- ============================================================================

CREATE TRIGGER update_activities_updated_at
  BEFORE UPDATE ON public.activities
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- 5. Aggiorna la view public_site_activities per includere tutti i campi
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
  'View pubblica per le attività. Espone tutti i campi necessari: id, name, slug, description, discipline, color, duration_minutes, image_url, is_active, campi landing page (landing_title, landing_subtitle, active_months, target_audience, program_objectives, why_participate, journey_structure), created_at, updated_at.';

-- ============================================================================
-- 6. GRANTS per accesso pubblico (anon) - già grantati nella migration 0007,
--    ma li rinnoviamo per sicurezza
-- ============================================================================

GRANT SELECT ON public.public_site_activities TO anon;
GRANT SELECT ON public.public_site_activities TO authenticated;

