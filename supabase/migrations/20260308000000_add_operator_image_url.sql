-- Migration: Add image_url column to operators table
--
-- Obiettivo: Permettere agli operatori di avere un'immagine profilo
-- caricata dinamicamente invece di usare immagini statiche nel codice.

-- ============================================================================
-- 1. ADD COLUMN
-- ============================================================================

ALTER TABLE public.operators
ADD COLUMN IF NOT EXISTS image_url text;

COMMENT ON COLUMN public.operators.image_url IS
  'URL pubblico dell''immagine profilo dell''operatore. Le immagini sono caricate nel bucket "operators".';

-- ============================================================================
-- 2. UPDATE VIEW
-- ============================================================================

-- NOTA: DROP necessario perché PostgreSQL non permette di cambiare le colonne
-- da NULL costante a riferimento colonna con CREATE OR REPLACE VIEW.
DROP VIEW IF EXISTS public.public_site_operators;

CREATE VIEW public.public_site_operators AS
SELECT
  o.id,
  o.name,
  o.role,
  o.bio,
  o.image_url,  -- Ora riferisce la colonna reale invece di NULL
  NULL::text AS image_alt,  -- Potrebbe essere aggiunto in futuro
  NULL::integer AS display_order,  -- Potrebbe essere aggiunto in futuro
  o.is_active
FROM public.operators o
WHERE
  o.is_active = true
  AND o.deleted_at IS NULL
ORDER BY o.name ASC;

COMMENT ON VIEW public.public_site_operators IS
  'View pubblica per gli operatori attivi. Espone solo dati pubblici: id, name, role, bio, image_url, is_active.
   NOTA: image_alt e display_order non sono ancora disponibili nella tabella operators.';

-- ============================================================================
-- 3. GRANTS
-- ============================================================================

GRANT SELECT ON public.public_site_operators TO anon;
GRANT SELECT ON public.public_site_operators TO authenticated;

-- ============================================================================
-- 4. CREATE STORAGE BUCKET (PUBLIC)
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'operators',
  'operators',
  true,  -- bucket pubblico (immagini marketing)
  5242880,  -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- 5. STORAGE POLICIES
-- ============================================================================

-- Policy INSERT: Solo staff può caricare immagini
CREATE POLICY "operators_staff_insert" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'operators' AND
  public.is_staff()
);

-- Policy UPDATE: Solo staff può aggiornare immagini
CREATE POLICY "operators_staff_update" ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'operators' AND
  public.is_staff()
)
WITH CHECK (
  bucket_id = 'operators' AND
  public.is_staff()
);

-- Policy DELETE: Solo staff può eliminare immagini
CREATE POLICY "operators_staff_delete" ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'operators' AND
  public.is_staff()
);

-- Policy SELECT: Accesso pubblico in lettura (bucket pubblico)
CREATE POLICY "operators_public_read" ON storage.objects
FOR SELECT TO public
USING (bucket_id = 'operators');
