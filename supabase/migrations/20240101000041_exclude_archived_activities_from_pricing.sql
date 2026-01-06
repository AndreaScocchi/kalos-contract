-- Migration 0041: Exclude Archived Activities from Pricing View
--
-- Obiettivo: Aggiornare la view public_site_pricing per escludere le attività
-- archiviate (deleted_at IS NOT NULL o is_active = false) dalla lista delle
-- attività associate ai pacchetti.
--
-- Problema: L'app cliente mostrava attività archiviate nella card dei pacchetti
-- perché la view public_site_pricing filtrava solo per deleted_at IS NULL ma non
-- per is_active = true.
--
-- Soluzione: Aggiungere il filtro COALESCE(a.is_active, true) = true al JOIN
-- con la tabella activities per escludere anche le attività disattivate.

-- ============================================================================
-- 1. Aggiorna public_site_pricing per escludere attività archiviate
-- ============================================================================

CREATE OR REPLACE VIEW public.public_site_pricing AS
SELECT 
  p.id,
  p.name,
  p.discipline,
  p.price_cents,
  p.currency,
  p.entries,
  p.validity_days,
  p.description,
  p.discount_percent,
  -- Attività associate (solo ID e nome)
  -- Esclude attività con deleted_at IS NOT NULL o is_active = false
  COALESCE(
    json_agg(
      json_build_object(
        'id', pa.activity_id,
        'name', a.name,
        'discipline', a.discipline
      )
    ) FILTER (WHERE pa.activity_id IS NOT NULL),
    '[]'::json
  ) AS activities
FROM public.plans p
LEFT JOIN public.plan_activities pa ON pa.plan_id = p.id
LEFT JOIN public.activities a ON a.id = pa.activity_id 
  AND a.deleted_at IS NULL 
  AND COALESCE(a.is_active, true) = true
WHERE 
  p.deleted_at IS NULL
  AND p.is_active = true
GROUP BY 
  p.id, 
  p.name, 
  p.discipline, 
  p.price_cents, 
  p.currency, 
  p.entries, 
  p.validity_days, 
  p.description, 
  p.discount_percent
ORDER BY p.price_cents ASC;

COMMENT ON VIEW public.public_site_pricing IS 
  'View pubblica per i piani e prezzi. Espone solo informazioni commerciali pubbliche: nome, prezzo, validità, attività associate. NON include dati personali o informazioni finanziarie sensibili. Le attività archiviate (deleted_at IS NOT NULL) o disattivate (is_active = false) vengono escluse dalla lista delle attività.';

-- ============================================================================
-- 2. GRANTS per accesso pubblico (anon) - già grantati nella migration 0005,
--    ma li rinnoviamo per sicurezza
-- ============================================================================

GRANT SELECT ON public.public_site_pricing TO anon;
GRANT SELECT ON public.public_site_pricing TO authenticated;

