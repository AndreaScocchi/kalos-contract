-- Migration 0032: Fix missing CANCEL_RESTORE entries for canceled bookings
-- 
-- Obiettivo: Trovare tutte le prenotazioni cancellate che hanno un record
-- subscription_usages con delta = -1 ma NON hanno un record con delta = +1,
-- e creare i record mancanti.
--
-- Problema: Le prenotazioni cancellate non hanno i record di ripristino,
-- quindi gli ingressi non vengono ripristinati correttamente.

-- ============================================================================
-- 1. FUNZIONE PER CORREGGERE I RECORD MANCANTI
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fix_missing_cancel_restore_entries()
RETURNS TABLE(
  booking_id uuid,
  subscription_id uuid,
  restored boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_booking_record RECORD;
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_total_entries integer;
  v_restore_exists boolean;
BEGIN
  -- Trova tutte le prenotazioni cancellate che hanno un usage con delta = -1
  -- ma NON hanno un usage con delta = +1
  FOR v_booking_record IN
    SELECT DISTINCT
      b.id as booking_id,
      su.subscription_id
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
  LOOP
    -- Verifica che la subscription esista e non sia soft-deleted
    SELECT *
    INTO v_sub
    FROM subscriptions
    WHERE id = v_booking_record.subscription_id
      AND deleted_at IS NULL;

    -- Se la subscription esiste, verifica il piano e crea il record di ripristino
    IF FOUND THEN
      SELECT *
      INTO v_plan
      FROM plans
      WHERE id = v_sub.plan_id;

      -- Verifica che il piano non sia soft-deleted
      IF v_plan.deleted_at IS NULL THEN
        v_total_entries := coalesce(v_sub.custom_entries, v_plan.entries);

        -- Solo se la subscription ha ingressi limitati (non unlimited)
        IF v_total_entries IS NOT NULL THEN
          -- Verifica che non esista già un record di ripristino
          SELECT EXISTS(
            SELECT 1
            FROM subscription_usages
            WHERE booking_id = v_booking_record.booking_id
              AND delta = +1
          ) INTO v_restore_exists;

          -- Crea il record di ripristino se non esiste
          IF NOT v_restore_exists THEN
            INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
            VALUES (v_booking_record.subscription_id, v_booking_record.booking_id, +1, 'CANCEL_RESTORE_FIX')
            ON CONFLICT DO NOTHING;

            -- Return the fixed record
            booking_id := v_booking_record.booking_id;
            subscription_id := v_booking_record.subscription_id;
            restored := true;
            RETURN NEXT;
          END IF;
        END IF;
      END IF;
    END IF;
  END LOOP;

  RETURN;
END;
$$;

COMMENT ON FUNCTION public.fix_missing_cancel_restore_entries() IS 
'Trova e corregge tutte le prenotazioni cancellate che hanno un record subscription_usages con delta = -1 ma NON hanno un record con delta = +1. Crea i record mancanti per ripristinare gli ingressi.';

-- ============================================================================
-- 2. ESEGUI LA CORREZIONE AUTOMATICAMENTE
-- ============================================================================

-- Esegui la funzione per correggere tutti i record mancanti
SELECT * FROM public.fix_missing_cancel_restore_entries();

-- ============================================================================
-- 3. VERIFICA QUANTI RECORD SONO STATI CORRETTI
-- ============================================================================

-- Query di verifica: mostra tutte le prenotazioni cancellate con usages
-- Dovrebbero avere sia delta = -1 che delta = +1
DO $$
DECLARE
  v_total_canceled integer;
  v_with_restore integer;
  v_without_restore integer;
BEGIN
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

  RAISE NOTICE 'Prenotazioni cancellate con usage: %', v_total_canceled;
  RAISE NOTICE 'Prenotazioni con restore: %', v_with_restore;
  RAISE NOTICE 'Prenotazioni senza restore: %', v_without_restore;
END;
$$;

