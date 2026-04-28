-- Migration: Add is_visible_on_site flag to operators
--
-- Obiettivo: introdurre un controllo indipendente da is_active per decidere
-- se un operatore è mostrato nella sezione team del sito pubblico.
--
-- - is_active           -> stato gestionale (operatore non più attivo / archiviato)
-- - is_visible_on_site  -> visibilità nella sezione team del sito pubblico
--
-- App e gestionale leggono direttamente la tabella operators e non sono
-- influenzati da questo flag. Solo la view public_site_operators lo usa.

-- ============================================================================
-- 1. ADD COLUMN
-- ============================================================================

ALTER TABLE public.operators
ADD COLUMN IF NOT EXISTS is_visible_on_site boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.operators.is_visible_on_site IS
  'Controlla se l''operatore è mostrato nella sezione team del sito pubblico. Indipendente da is_active: un operatore può essere attivo nel gestionale ma non visibile sul sito (es. nuovo arrivato non ancora annunciato).';

-- ============================================================================
-- 2. UPDATE PUBLIC VIEW
-- ============================================================================

DROP VIEW IF EXISTS public.public_site_operators;

CREATE VIEW public.public_site_operators AS
SELECT
  o.id,
  o.name,
  o.role,
  o.bio,
  o.image_url,
  NULL::text AS image_alt,
  o.display_order,
  o.is_active
FROM public.operators o
WHERE
  o.is_active = true
  AND o.is_visible_on_site = true
  AND o.deleted_at IS NULL
ORDER BY
  o.display_order ASC NULLS LAST,
  o.name ASC;

COMMENT ON VIEW public.public_site_operators IS
  'View pubblica per gli operatori visibili sul sito. Filtra per is_active = true AND is_visible_on_site = true AND deleted_at IS NULL.';

-- ============================================================================
-- 3. GRANTS
-- ============================================================================

GRANT SELECT ON public.public_site_operators TO anon;
GRANT SELECT ON public.public_site_operators TO authenticated;
