-- Migration 0022: Fix all subscription statuses with correct logic
--
-- Obiettivo: Correggere TUTTI gli abbonamenti esistenti applicando la logica corretta:
-- 1. Se scaduto (expires_at < CURRENT_DATE) E ha esaurito i posti (remaining_entries <= 0) -> 'completed'
-- 2. Se scaduto (expires_at < CURRENT_DATE) ma ha ancora posti (remaining_entries > 0 o NULL) -> 'expired'
-- 3. Se non scaduto (expires_at >= CURRENT_DATE) -> 'active'
--
-- Nota: Preserva lo stato 'canceled' (non modifica abbonamenti cancellati)

-- ============================================================================
-- CORREZIONE COMPLETA DI TUTTI GLI ABBONAMENTI SCADUTI
-- ============================================================================

-- Aggiorna TUTTI gli abbonamenti scaduti in base ai posti rimanenti
-- (tranne quelli 'canceled' che vengono preservati)
WITH usage_totals AS (
  SELECT 
    subscription_id,
    COALESCE(SUM(delta), 0) AS delta_sum
  FROM public.subscription_usages
  GROUP BY subscription_id
),
subscription_data AS (
  SELECT 
    s.id,
    s.status,
    s.expires_at,
    s.custom_entries,
    p.entries AS plan_entries,
    COALESCE(u.delta_sum, 0) AS used_entries
  FROM public.subscriptions s
  LEFT JOIN public.plans p ON p.id = s.plan_id
  LEFT JOIN usage_totals u ON u.subscription_id = s.id
  WHERE s.deleted_at IS NULL
    AND s.status != 'canceled'  -- Preserva i 'canceled'
    AND s.expires_at < CURRENT_DATE  -- Solo quelli scaduti
),
subscription_status_calc AS (
  SELECT 
    id,
    CASE
      -- Se è illimitato (effective_entries IS NULL), imposta 'expired'
      WHEN COALESCE(custom_entries, plan_entries) IS NULL THEN 'expired'::subscription_status
      -- Se ha esaurito i posti (remaining_entries <= 0), imposta 'completed'
      WHEN (COALESCE(custom_entries, plan_entries) + used_entries) <= 0 THEN 'completed'::subscription_status
      -- Altrimenti ha ancora posti, imposta 'expired'
      ELSE 'expired'::subscription_status
    END AS new_status,
    status AS current_status
  FROM subscription_data
)
UPDATE public.subscriptions s
SET status = ssc.new_status
FROM subscription_status_calc ssc
WHERE s.id = ssc.id
  AND ssc.current_status != ssc.new_status;  -- Aggiorna solo se cambia

-- ============================================================================
-- CORREZIONE ABBONAMENTI NON SCADUTI
-- ============================================================================

-- Imposta a 'active' tutti gli abbonamenti non scaduti (tranne 'canceled')
UPDATE public.subscriptions
SET status = 'active'
WHERE expires_at >= CURRENT_DATE
  AND status != 'canceled'  -- Preserva i 'canceled'
  AND status != 'active'    -- Non modificare quelli già 'active'
  AND deleted_at IS NULL;

