-- Migration 0021: Fix subscription status based on expiration and remaining entries
--
-- Obiettivo: Correggere lo status degli abbonamenti esistenti applicando la logica corretta:
-- 1. Se scaduto (expires_at < CURRENT_DATE) E ha esaurito i posti (remaining_entries <= 0) -> 'completed'
-- 2. Se scaduto (expires_at < CURRENT_DATE) ma ha ancora posti (remaining_entries > 0 o NULL) -> 'expired'
-- 3. Se non scaduto (expires_at >= CURRENT_DATE) -> 'active'
--
-- Nota: Questa migration corregge solo gli abbonamenti con status = 'active' per preservare
-- altri stati come 'canceled'. Gli abbonamenti che sono già 'completed' o 'expired' vengono
-- verificati e corretti se necessario.

-- ============================================================================
-- CORREZIONE ABBONAMENTI SCADUTI CON STATUS 'active'
-- ============================================================================

-- Aggiorna gli abbonamenti scaduti con status 'active' in base ai posti rimanenti
WITH subscription_remaining AS (
  SELECT 
    s.id,
    s.status,
    s.expires_at,
    s.custom_entries,
    p.entries AS plan_entries,
    COALESCE(SUM(su.delta), 0) AS used_entries
  FROM public.subscriptions s
  LEFT JOIN public.plans p ON p.id = s.plan_id
  LEFT JOIN public.subscription_usages su ON su.subscription_id = s.id
  WHERE s.deleted_at IS NULL
    AND s.status = 'active'
    AND s.expires_at < CURRENT_DATE
  GROUP BY s.id, s.status, s.expires_at, s.custom_entries, p.entries
),
subscription_status_calc AS (
  SELECT 
    id,
    CASE
      -- Se è illimitato (effective_entries IS NULL), imposta 'expired'
      WHEN COALESCE(custom_entries, plan_entries) IS NULL THEN 'expired'
      -- Se ha esaurito i posti (remaining_entries <= 0), imposta 'completed'
      WHEN (COALESCE(custom_entries, plan_entries) + used_entries) <= 0 THEN 'completed'
      -- Altrimenti ha ancora posti, imposta 'expired'
      ELSE 'expired'
    END AS new_status
  FROM subscription_remaining
)
UPDATE public.subscriptions s
SET status = ssc.new_status
FROM subscription_status_calc ssc
WHERE s.id = ssc.id;

-- ============================================================================
-- CORREZIONE ABBONAMENTI NON SCADUTI CON STATUS ERRATO
-- ============================================================================

-- Ripristina a 'active' gli abbonamenti che non sono scaduti ma hanno status errato
UPDATE public.subscriptions
SET status = 'active'
WHERE expires_at >= CURRENT_DATE
  AND status IN ('completed', 'expired')
  AND deleted_at IS NULL;

-- ============================================================================
-- CORREZIONE ABBONAMENTI SCADUTI CON STATUS 'completed' o 'expired'
-- ============================================================================

-- Verifica e corregge gli abbonamenti già in stato 'completed' o 'expired'
-- che potrebbero essere stati impostati erroneamente
WITH subscription_remaining AS (
  SELECT 
    s.id,
    s.status,
    s.expires_at,
    s.custom_entries,
    p.entries AS plan_entries,
    COALESCE(SUM(su.delta), 0) AS used_entries
  FROM public.subscriptions s
  LEFT JOIN public.plans p ON p.id = s.plan_id
  LEFT JOIN public.subscription_usages su ON su.subscription_id = s.id
  WHERE s.deleted_at IS NULL
    AND s.status IN ('completed', 'expired')
    AND s.expires_at < CURRENT_DATE
  GROUP BY s.id, s.status, s.expires_at, s.custom_entries, p.entries
),
subscription_status_calc AS (
  SELECT 
    id,
    CASE
      -- Se è illimitato (effective_entries IS NULL), deve essere 'expired'
      WHEN COALESCE(custom_entries, plan_entries) IS NULL THEN 'expired'
      -- Se ha esaurito i posti (remaining_entries <= 0), deve essere 'completed'
      WHEN (COALESCE(custom_entries, plan_entries) + used_entries) <= 0 THEN 'completed'
      -- Altrimenti ha ancora posti, deve essere 'expired'
      ELSE 'expired'
    END AS correct_status,
    status AS current_status
  FROM subscription_remaining
)
UPDATE public.subscriptions s
SET status = ssc.correct_status
FROM subscription_status_calc ssc
WHERE s.id = ssc.id
  AND ssc.current_status != ssc.correct_status;
