-- Script per verificare abbonamenti con stato errato
-- Data: 2026-01-20
--
-- Logica corretta degli stati:
-- - "active": expires_at >= CURRENT_DATE E remaining_entries > 0 (o illimitato)
-- - "expired": expires_at < CURRENT_DATE E remaining_entries > 0 (o illimitato)
-- - "completed": remaining_entries <= 0 (indipendentemente dalla scadenza)
-- - "canceled": preservato, non modificato automaticamente

-- ============================================================================
-- 1. CALCOLO STATO CORRETTO vs STATO ATTUALE
-- ============================================================================

WITH usage_totals AS (
  SELECT
    subscription_id,
    COALESCE(SUM(delta), 0) AS delta_sum
  FROM public.subscription_usages
  GROUP BY subscription_id
),
subscription_analysis AS (
  SELECT
    s.id,
    c.full_name AS client_name,
    COALESCE(s.custom_name, p.name) AS subscription_name,
    s.status AS current_status,
    s.started_at,
    s.expires_at,
    COALESCE(s.custom_entries, p.entries) AS effective_entries,
    COALESCE(u.delta_sum, 0) AS used_delta,
    CASE
      WHEN COALESCE(s.custom_entries, p.entries) IS NULL THEN NULL  -- illimitato
      ELSE COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)
    END AS remaining_entries,
    -- Calcolo stato corretto
    CASE
      -- Preserva 'canceled'
      WHEN s.status = 'canceled' THEN 'canceled'::subscription_status
      -- Se illimitato, calcola in base alla scadenza
      WHEN COALESCE(s.custom_entries, p.entries) IS NULL THEN
        CASE
          WHEN s.expires_at < CURRENT_DATE THEN 'expired'::subscription_status
          ELSE 'active'::subscription_status
        END
      -- Se ha esaurito i posti -> 'completed'
      WHEN (COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)) <= 0 THEN 'completed'::subscription_status
      -- Se ha ancora posti, calcola in base alla scadenza
      ELSE
        CASE
          WHEN s.expires_at < CURRENT_DATE THEN 'expired'::subscription_status
          ELSE 'active'::subscription_status
        END
    END AS expected_status
  FROM public.subscriptions s
  LEFT JOIN public.plans p ON p.id = s.plan_id
  LEFT JOIN public.clients c ON c.id = s.client_id
  LEFT JOIN usage_totals u ON u.subscription_id = s.id
  WHERE s.deleted_at IS NULL
)
SELECT
  id,
  client_name,
  subscription_name,
  current_status,
  expected_status,
  CASE
    WHEN remaining_entries IS NULL THEN 'illimitato'
    ELSE remaining_entries::text
  END AS remaining_entries,
  started_at,
  expires_at,
  CASE
    WHEN expires_at < CURRENT_DATE THEN 'SCADUTO'
    ELSE 'VALIDO'
  END AS validity_status
FROM subscription_analysis
WHERE current_status != expected_status
ORDER BY expires_at DESC;

-- ============================================================================
-- 2. CONTEGGIO PER TIPO DI ERRORE
-- ============================================================================

WITH usage_totals AS (
  SELECT
    subscription_id,
    COALESCE(SUM(delta), 0) AS delta_sum
  FROM public.subscription_usages
  GROUP BY subscription_id
),
subscription_analysis AS (
  SELECT
    s.id,
    s.status AS current_status,
    s.expires_at,
    COALESCE(s.custom_entries, p.entries) AS effective_entries,
    COALESCE(u.delta_sum, 0) AS used_delta,
    CASE
      WHEN COALESCE(s.custom_entries, p.entries) IS NULL THEN NULL
      ELSE COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)
    END AS remaining_entries,
    CASE
      WHEN s.status = 'canceled' THEN 'canceled'::subscription_status
      WHEN COALESCE(s.custom_entries, p.entries) IS NULL THEN
        CASE
          WHEN s.expires_at < CURRENT_DATE THEN 'expired'::subscription_status
          ELSE 'active'::subscription_status
        END
      WHEN (COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)) <= 0 THEN 'completed'::subscription_status
      ELSE
        CASE
          WHEN s.expires_at < CURRENT_DATE THEN 'expired'::subscription_status
          ELSE 'active'::subscription_status
        END
    END AS expected_status
  FROM public.subscriptions s
  LEFT JOIN public.plans p ON p.id = s.plan_id
  LEFT JOIN usage_totals u ON u.subscription_id = s.id
  WHERE s.deleted_at IS NULL
)
SELECT
  current_status || ' -> ' || expected_status AS error_type,
  COUNT(*) AS count
FROM subscription_analysis
WHERE current_status != expected_status
GROUP BY current_status, expected_status
ORDER BY count DESC;

-- ============================================================================
-- 3. RIEPILOGO TOTALE
-- ============================================================================

WITH usage_totals AS (
  SELECT
    subscription_id,
    COALESCE(SUM(delta), 0) AS delta_sum
  FROM public.subscription_usages
  GROUP BY subscription_id
),
subscription_analysis AS (
  SELECT
    s.id,
    s.status AS current_status,
    CASE
      WHEN s.status = 'canceled' THEN 'canceled'::subscription_status
      WHEN COALESCE(s.custom_entries, p.entries) IS NULL THEN
        CASE
          WHEN s.expires_at < CURRENT_DATE THEN 'expired'::subscription_status
          ELSE 'active'::subscription_status
        END
      WHEN (COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)) <= 0 THEN 'completed'::subscription_status
      ELSE
        CASE
          WHEN s.expires_at < CURRENT_DATE THEN 'expired'::subscription_status
          ELSE 'active'::subscription_status
        END
    END AS expected_status
  FROM public.subscriptions s
  LEFT JOIN public.plans p ON p.id = s.plan_id
  LEFT JOIN usage_totals u ON u.subscription_id = s.id
  WHERE s.deleted_at IS NULL
)
SELECT
  'Totale abbonamenti' AS metric,
  COUNT(*)::text AS value
FROM subscription_analysis
UNION ALL
SELECT
  'Con stato CORRETTO' AS metric,
  COUNT(*)::text AS value
FROM subscription_analysis
WHERE current_status = expected_status
UNION ALL
SELECT
  'Con stato ERRATO' AS metric,
  COUNT(*)::text AS value
FROM subscription_analysis
WHERE current_status != expected_status;
