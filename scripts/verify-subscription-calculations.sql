-- Script per verificare il calcolo degli ingressi rimanenti
-- 
-- Sostituisci SUBSCRIPTION_ID con l'ID dell'abbonamento problematico

-- ============================================================================
-- 1. INFORMAZIONI ABBONAMENTO
-- ============================================================================

SELECT 
  s.id,
  s.client_id,
  s.status,
  s.custom_entries,
  p.entries as plan_entries,
  COALESCE(s.custom_entries, p.entries) as effective_entries,
  s.deleted_at
FROM subscriptions s
LEFT JOIN plans p ON p.id = s.plan_id
WHERE s.id = 'SUBSCRIPTION_ID'; -- SOSTITUISCI QUI

-- ============================================================================
-- 2. TUTTI I RECORD subscription_usages (dettagliati)
-- ============================================================================

SELECT 
  su.id,
  su.booking_id,
  su.delta,
  su.reason,
  su.created_at,
  b.status as booking_status,
  b.client_id as booking_client_id,
  CASE 
    WHEN su.delta = -1 THEN 'PRENOTAZIONE'
    WHEN su.delta = +1 THEN 'RIPRISTINO'
    ELSE 'ALTRO'
  END as tipo
FROM subscription_usages su
LEFT JOIN bookings b ON b.id = su.booking_id
WHERE su.subscription_id = 'SUBSCRIPTION_ID' -- SOSTITUISCI QUI
ORDER BY su.created_at;

-- ============================================================================
-- 3. SOMMA DEI DELTA (dovrebbe essere 0 se tutte le cancellazioni hanno restore)
-- ============================================================================

SELECT 
  subscription_id,
  SUM(delta) as total_delta,
  COUNT(*) FILTER (WHERE delta = -1) as bookings_count,
  COUNT(*) FILTER (WHERE delta = +1) as restores_count,
  COUNT(*) FILTER (WHERE delta = -1 AND reason = 'BOOK') as bookings_book,
  COUNT(*) FILTER (WHERE delta = -1 AND reason LIKE 'individual_lesson%') as bookings_individual,
  COUNT(*) FILTER (WHERE delta = +1 AND reason = 'CANCEL_RESTORE') as restores_cancel,
  COUNT(*) FILTER (WHERE delta = +1 AND reason = 'CANCEL_RESTORE_FIX') as restores_fix
FROM subscription_usages
WHERE subscription_id = 'SUBSCRIPTION_ID' -- SOSTITUISCI QUI
GROUP BY subscription_id;

-- ============================================================================
-- 4. CALCOLO MANUALE vs VIEW
-- ============================================================================

WITH subscription_info AS (
  SELECT 
    s.id,
    COALESCE(s.custom_entries, p.entries) as effective_entries
  FROM subscriptions s
  LEFT JOIN plans p ON p.id = s.plan_id
  WHERE s.id = 'SUBSCRIPTION_ID' -- SOSTITUISCI QUI
),
usage_totals AS (
  SELECT 
    subscription_id,
    COALESCE(SUM(delta), 0) as delta_sum,
    COUNT(*) FILTER (WHERE delta = -1) as minus_count,
    COUNT(*) FILTER (WHERE delta = +1) as plus_count
  FROM subscription_usages
  WHERE subscription_id = 'SUBSCRIPTION_ID' -- SOSTITUISCI QUI
  GROUP BY subscription_id
)
SELECT 
  si.id,
  si.effective_entries,
  COALESCE(ut.delta_sum, 0) as used_entries_sum,
  si.effective_entries + COALESCE(ut.delta_sum, 0) as calculated_remaining,
  swr.remaining_entries as view_remaining,
  ut.minus_count,
  ut.plus_count,
  CASE 
    WHEN si.effective_entries + COALESCE(ut.delta_sum, 0) = swr.remaining_entries 
    THEN 'OK' 
    ELSE 'ERRORE!' 
  END as match_status
FROM subscription_info si
LEFT JOIN usage_totals ut ON ut.subscription_id = si.id
LEFT JOIN subscriptions_with_remaining swr ON swr.id = si.id;

-- ============================================================================
-- 5. PRENOTAZIONI CANCELLATE SENZA RESTORE (dovrebbero essere 0)
-- ============================================================================

SELECT 
  b.id as booking_id,
  b.status,
  b.client_id,
  su.subscription_id,
  su.delta,
  su.reason,
  su.created_at
FROM bookings b
INNER JOIN subscription_usages su ON su.booking_id = b.id
WHERE b.status = 'canceled'
  AND su.subscription_id = 'SUBSCRIPTION_ID' -- SOSTITUISCI QUI
  AND su.delta = -1
  AND NOT EXISTS (
    SELECT 1
    FROM subscription_usages su2
    WHERE su2.booking_id = b.id
      AND su2.delta = +1
  )
ORDER BY su.created_at;

