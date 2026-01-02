-- Migration 0010: Add slug field to activities table
--
-- Obiettivo: Aggiungere il campo slug alla tabella activities, generato
-- automaticamente dalla colonna discipline. Lo slug viene utilizzato principalmente
-- dal sito web per matchare i file JSON activity.{slug}.json.
--
-- Il campo slug viene popolato automaticamente:
-- - Per le attività esistenti: basandosi sul valore attuale di discipline
-- - Per le nuove attività: tramite trigger quando discipline viene inserito/aggiornato

-- ============================================================================
-- 1. Aggiungi campo slug alla tabella activities
-- ============================================================================

ALTER TABLE public.activities
ADD COLUMN IF NOT EXISTS slug text;

COMMENT ON COLUMN public.activities.slug IS 
  'Slug generato automaticamente dalla colonna discipline. Utilizzato principalmente dal sito web per matchare i file JSON activity.{slug}.json. Viene aggiornato automaticamente quando discipline cambia.';

-- ============================================================================
-- 2. Crea funzione per generare slug da discipline
-- ============================================================================

CREATE OR REPLACE FUNCTION public.generate_slug_from_discipline(discipline_text text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- Converte in lowercase, rimuove caratteri speciali, sostituisce spazi con trattini
  -- Esempio: "Yoga Flow" -> "yoga-flow", "Pilates & Stretching" -> "pilates-stretching"
  RETURN lower(
    regexp_replace(
      regexp_replace(
        regexp_replace(discipline_text, '[^a-zA-Z0-9\s-]', '', 'g'), -- Rimuove caratteri speciali
        '\s+', '-', 'g' -- Sostituisce spazi multipli con un trattino
      ),
      '^-+|-+$', '', 'g' -- Rimuove trattini all'inizio e alla fine
    )
  );
END;
$$;

COMMENT ON FUNCTION public.generate_slug_from_discipline IS 
  'Genera uno slug URL-friendly da un testo discipline. Converte in lowercase, rimuove caratteri speciali e sostituisce spazi con trattini.';

-- ============================================================================
-- 3. Popola slug per le attività esistenti basandosi su discipline
-- ============================================================================

UPDATE public.activities
SET slug = public.generate_slug_from_discipline(discipline)
WHERE slug IS NULL OR slug = '';

-- ============================================================================
-- 4. Crea trigger per aggiornare automaticamente slug quando discipline cambia
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_activity_slug()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Aggiorna lo slug quando discipline viene inserito o modificato
  IF NEW.discipline IS NOT NULL AND NEW.discipline != '' THEN
    NEW.slug := public.generate_slug_from_discipline(NEW.discipline);
  ELSE
    NEW.slug := NULL;
  END IF;
  
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.update_activity_slug IS 
  'Trigger function che aggiorna automaticamente lo slug quando discipline viene inserito o modificato.';

-- Crea il trigger
DROP TRIGGER IF EXISTS trigger_update_activity_slug ON public.activities;
CREATE TRIGGER trigger_update_activity_slug
  BEFORE INSERT OR UPDATE OF discipline ON public.activities
  FOR EACH ROW
  EXECUTE FUNCTION public.update_activity_slug();

-- ============================================================================
-- 5. Aggiorna la view public_site_activities per includere slug
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
  -- NOTA: Se in futuro serve image_url, aggiungere la colonna nella tabella activities
  a.created_at
FROM public.activities a
WHERE 
  a.deleted_at IS NULL
  -- NOTA: Se in futuro viene aggiunto un campo is_public o is_active per filtrare
  -- le attività pubbliche, aggiungere il filtro qui (es: AND a.is_public = true)
ORDER BY a.name ASC;

COMMENT ON VIEW public.public_site_activities IS 
  'View pubblica per le attività. Espone solo dati minimi necessari: id, name, slug, description, discipline, color, duration_minutes. NOTA: image_url non è disponibile nella tabella activities attualmente.';

-- ============================================================================
-- 6. GRANTS per accesso pubblico (anon) - già grantati nella migration 0007,
--    ma li rinnoviamo per sicurezza
-- ============================================================================

GRANT SELECT ON public.public_site_activities TO anon;
GRANT SELECT ON public.public_site_activities TO authenticated;

