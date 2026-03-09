-- Add display_order column to operators and set correct ordering
-- Alice Tentor should be first, Anita Miceu second

-- ============================================================================
-- 1. ADD COLUMN
-- ============================================================================

ALTER TABLE public.operators
ADD COLUMN IF NOT EXISTS display_order integer;

COMMENT ON COLUMN public.operators.display_order IS
  'Ordine di visualizzazione degli operatori nel sito pubblico. Valori più bassi = posizioni più alte.';

-- ============================================================================
-- 2. SET DISPLAY ORDER VALUES
-- ============================================================================

-- Set Alice Tentor as first (display_order = 1)
UPDATE public.operators
SET display_order = 1
WHERE name ILIKE '%Alice Tentor%';

-- Set Anita Miceu as second (display_order = 2)
UPDATE public.operators
SET display_order = 2
WHERE name ILIKE '%Anita Miceu%';

-- Set Chiara as third (display_order = 3)
UPDATE public.operators
SET display_order = 3
WHERE name ILIKE '%Chiara%';

-- Set default order for any other operators (display_order = 99)
UPDATE public.operators
SET display_order = 99
WHERE display_order IS NULL;

-- ============================================================================
-- 3. UPDATE VIEW
-- ============================================================================

-- Ricreo la vista per usare la colonna reale invece di NULL
DROP VIEW IF EXISTS public.public_site_operators;

CREATE VIEW public.public_site_operators AS
SELECT
  o.id,
  o.name,
  o.role,
  o.bio,
  o.image_url,
  NULL::text AS image_alt,  -- Potrebbe essere aggiunto in futuro
  o.display_order,  -- Ora usa la colonna reale
  o.is_active
FROM public.operators o
WHERE
  o.is_active = true
  AND o.deleted_at IS NULL
ORDER BY
  o.display_order ASC NULLS LAST,
  o.name ASC;

COMMENT ON VIEW public.public_site_operators IS
  'View pubblica per gli operatori attivi. Espone solo dati pubblici: id, name, role, bio, image_url, display_order, is_active.';

-- ============================================================================
-- 4. GRANTS
-- ============================================================================

GRANT SELECT ON public.public_site_operators TO anon;
GRANT SELECT ON public.public_site_operators TO authenticated;
