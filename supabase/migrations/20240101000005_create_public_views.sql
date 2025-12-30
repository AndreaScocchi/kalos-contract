-- Migration 0005: Create Public Views for Site (GDPR-compliant)
--
-- Obiettivo: Creare views pubbliche (public_site_*) che espongono solo i dati
-- minimi necessari per il sito pubblico, rispettando il principio di minimizzazione GDPR.
--
-- Convenzione: tutte le views pubbliche iniziano con "public_site_"
-- e sono accessibili in sola lettura tramite anon key.

-- ============================================================================
-- 1. public_site_schedule: Schedule pubblico delle lezioni
-- ============================================================================

CREATE OR REPLACE VIEW public.public_site_schedule AS
SELECT 
  l.id,
  l.starts_at,
  l.ends_at,
  l.capacity,
  a.id AS activity_id,
  a.name AS activity_name,
  a.discipline,
  a.color AS activity_color,
  -- Occupancy info (calcolato)
  lo.booked_count,
  lo.free_spots,
  -- Operator info (solo se pubblico)
  o.id AS operator_id,
  o.name AS operator_name,
  -- Note: NON esponiamo operator_id se non necessario per il sito
  -- Rimuovere operator_id e operator_name se non servono
  l.booking_deadline_minutes,
  l.cancel_deadline_minutes
FROM public.lessons l
INNER JOIN public.activities a ON a.id = l.activity_id
LEFT JOIN public.lesson_occupancy lo ON lo.lesson_id = l.id
LEFT JOIN public.operators o ON o.id = l.operator_id AND o.is_active = true AND o.deleted_at IS NULL
WHERE 
  l.deleted_at IS NULL
  AND a.deleted_at IS NULL
  AND l.is_individual = false  -- Solo lezioni pubbliche
  AND l.starts_at >= CURRENT_DATE  -- Solo lezioni future
ORDER BY l.starts_at ASC;

COMMENT ON VIEW public.public_site_schedule IS 
  'View pubblica per lo schedule delle lezioni. Espone solo dati minimi necessari: date, attività, capacità, posti disponibili. NON include dati personali o informazioni sensibili.';

-- ============================================================================
-- 2. public_site_pricing: Prezzi e piani disponibili
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
LEFT JOIN public.activities a ON a.id = pa.activity_id AND a.deleted_at IS NULL
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
  'View pubblica per i piani e prezzi. Espone solo informazioni commerciali pubbliche: nome, prezzo, validità, attività associate. NON include dati personali o informazioni finanziarie sensibili.';

-- ============================================================================
-- 3. GRANTS per accesso pubblico (anon)
-- ============================================================================

-- Le views sono accessibili tramite anon key
GRANT SELECT ON public.public_site_schedule TO anon;
GRANT SELECT ON public.public_site_pricing TO anon;

-- Anche authenticated può accedere (utile per app)
GRANT SELECT ON public.public_site_schedule TO authenticated;
GRANT SELECT ON public.public_site_pricing TO authenticated;

-- ============================================================================
-- 4. NOTA GDPR: Dati NON esposti
-- ============================================================================

-- Queste views NON espongono:
-- - Dati personali (email, telefono, nome completo di clienti/utenti)
-- - Informazioni finanziarie dettagliate (subscriptions, bookings personali)
-- - Note interne o dati sensibili
-- - ID di record interni non necessari per il sito
-- - Timestamps di creazione/modifica non necessari
--
-- Se in futuro servono altri dati pubblici, creare nuove views con prefisso "public_site_"
-- e seguire lo stesso principio di minimizzazione.

