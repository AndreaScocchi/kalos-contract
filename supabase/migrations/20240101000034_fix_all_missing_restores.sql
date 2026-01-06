-- Migration 0034: Fix ALL missing restore entries for canceled bookings
-- 
-- Obiettivo: Trovare e correggere TUTTE le prenotazioni cancellate che hanno
-- un record subscription_usages con delta = -1 ma NON hanno un record con delta = +1.
--
-- Questo corregge i dati storici che sono stati danneggiati.

-- ============================================================================
-- CORREZIONE MASSIVA DI TUTTI I RECORD MANCANTI
-- ============================================================================

-- Trova tutte le prenotazioni cancellate con delta = -1 ma senza delta = +1
-- e crea i record di ripristino mancanti
INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
SELECT DISTINCT
  su.subscription_id,
  b.id as booking_id,
  +1 as delta,
  'CANCEL_RESTORE_FIX' as reason
FROM bookings b
INNER JOIN subscription_usages su ON su.booking_id = b.id
WHERE b.status = 'canceled'
  AND su.delta = -1
  AND NOT EXISTS (
    SELECT 1
    FROM subscription_usages su2
    WHERE su2.booking_id = b.id
      AND su2.delta = +1
  )
  -- Verifica che la subscription esista e non sia soft-deleted
  AND EXISTS (
    SELECT 1
    FROM subscriptions s
    LEFT JOIN plans p ON p.id = s.plan_id
    WHERE s.id = su.subscription_id
      AND s.deleted_at IS NULL
      AND COALESCE(s.custom_entries, p.entries) IS NOT NULL
  )
ON CONFLICT DO NOTHING;

-- ============================================================================
-- VERIFICA RISULTATI
-- ============================================================================

DO $$
DECLARE
  v_fixed_count integer;
  v_total_canceled integer;
  v_with_restore integer;
  v_without_restore integer;
BEGIN
  -- Conta quanti record sono stati corretti
  SELECT COUNT(*)
  INTO v_fixed_count
  FROM subscription_usages
  WHERE reason = 'CANCEL_RESTORE_FIX';

  -- Conta tutte le prenotazioni cancellate con usage
  SELECT COUNT(DISTINCT b.id)
  INTO v_total_canceled
  FROM bookings b
  INNER JOIN subscription_usages su ON su.booking_id = b.id
  WHERE b.status = 'canceled'
    AND su.delta = -1;

  -- Conta quelle con restore
  SELECT COUNT(DISTINCT b.id)
  INTO v_with_restore
  FROM bookings b
  INNER JOIN subscription_usages su1 ON su1.booking_id = b.id
  INNER JOIN subscription_usages su2 ON su2.booking_id = b.id
  WHERE b.status = 'canceled'
    AND su1.delta = -1
    AND su2.delta = +1;

  -- Conta quelle senza restore
  SELECT COUNT(DISTINCT b.id)
  INTO v_without_restore
  FROM bookings b
  INNER JOIN subscription_usages su ON su.booking_id = b.id
  WHERE b.status = 'canceled'
    AND su.delta = -1
    AND NOT EXISTS (
      SELECT 1
      FROM subscription_usages su2
      WHERE su2.booking_id = b.id
        AND su2.delta = +1
    );

  RAISE NOTICE '========================================';
  RAISE NOTICE 'CORREZIONE RECORD MANCANTI COMPLETATA';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Record corretti in questa migration: %', v_fixed_count;
  RAISE NOTICE 'Totale prenotazioni cancellate con usage: %', v_total_canceled;
  RAISE NOTICE 'Prenotazioni con restore: %', v_with_restore;
  RAISE NOTICE 'Prenotazioni senza restore: %', v_without_restore;
  RAISE NOTICE '========================================';
END;
$$;

