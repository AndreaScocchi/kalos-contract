-- Migration 0035: Fix staff_cancel_booking - VERSIONE SEMPLIFICATA E CORRETTA
-- 
-- Obiettivo: Implementare la versione corretta e semplificata di staff_cancel_booking
-- che non fa riferimento a user_id e ripristina correttamente gli ingressi.
--
-- Problema: 
-- 1. Errore runtime: riferimento a NEW.user_id che non esiste più
-- 2. Bug logico: gli ingressi non vengono ripristinati quando si cancella una prenotazione
--
-- Soluzione: Versione semplificata che usa solo subscription_id dalla booking

-- ============================================================================
-- 1. FUNZIONE staff_cancel_booking SEMPLIFICATA
-- ============================================================================

CREATE OR REPLACE FUNCTION public.staff_cancel_booking(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
BEGIN
  -- Verifica che l'utente sia staff
  IF NOT is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
  END IF;

  -- Recupera la booking
  SELECT *
  INTO v_booking
  FROM bookings
  WHERE id = p_booking_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  END IF;

  -- Verifica che la booking sia in stato "booked" (non può cancellare se già attended/no_show/canceled)
  IF v_booking.status <> 'booked' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_BOOKED');
  END IF;

  -- Aggiorna lo stato a canceled
  UPDATE bookings
  SET status = 'canceled'
  WHERE id = p_booking_id;

  -- Se la booking aveva un abbonamento, restituisci l'ingresso consumato
  -- Prima verifica se esiste già un record di ripristino per evitare duplicati
  IF v_booking.subscription_id IS NOT NULL THEN
    -- Verifica che non esista già un record di ripristino
    IF NOT EXISTS (
      SELECT 1
      FROM subscription_usages
      WHERE booking_id = p_booking_id
        AND delta = +1
    ) THEN
      -- Verifica che la subscription esista e abbia ingressi limitati
      IF EXISTS (
        SELECT 1
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        WHERE s.id = v_booking.subscription_id
          AND s.deleted_at IS NULL
          AND COALESCE(s.custom_entries, p.entries) IS NOT NULL
      ) THEN
        INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
        VALUES (v_booking.subscription_id, p_booking_id, +1, 'CANCEL')
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED');
END;
$$;

COMMENT ON FUNCTION public.staff_cancel_booking(uuid) IS 
'Cancella una prenotazione (solo staff). Ripristina automaticamente gli ingressi dell''abbonamento se presenti. Versione semplificata che usa solo subscription_id dalla booking.';

-- ============================================================================
-- 2. VERIFICA E CORREZIONE TRIGGER SU bookings
-- ============================================================================

-- Verifica se ci sono trigger che fanno riferimento a user_id
-- Il trigger restore_subscription_entry_on_booking_cancel dovrebbe essere già corretto
-- ma verifichiamo che non ci siano riferimenti a user_id

-- Ricrea il trigger per assicurarsi che sia corretto
DROP TRIGGER IF EXISTS trigger_restore_subscription_entry_on_booking_cancel ON public.bookings;

CREATE OR REPLACE FUNCTION public.restore_subscription_entry_on_booking_cancel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_subscription_id uuid;
  v_total_entries integer;
  v_plan_entries integer;
  v_custom_entries integer;
BEGIN
  -- Solo se status passa da 'booked' a 'canceled'
  IF OLD.status = 'booked' AND NEW.status = 'canceled' THEN
    
    -- Usa subscription_id dalla booking (più semplice e diretto)
    v_subscription_id := NEW.subscription_id;

    -- Se non c'è subscription_id sulla booking, prova a trovarlo da subscription_usages
    IF v_subscription_id IS NULL THEN
      SELECT su.subscription_id
      INTO v_subscription_id
      FROM subscription_usages su
      WHERE su.booking_id = NEW.id
        AND su.delta = -1
      ORDER BY su.created_at DESC
      LIMIT 1;
    END IF;

    -- Se abbiamo trovato una subscription, verifica se ha ingressi limitati
    IF v_subscription_id IS NOT NULL THEN
      SELECT 
        s.custom_entries,
        p.entries
      INTO 
        v_custom_entries,
        v_plan_entries
      FROM subscriptions s
      LEFT JOIN plans p ON p.id = s.plan_id
      WHERE s.id = v_subscription_id
        AND s.deleted_at IS NULL;

      -- Se la subscription esiste e non è soft-deleted
      IF FOUND THEN
        v_total_entries := COALESCE(v_custom_entries, v_plan_entries);

        -- Solo se ha ingressi limitati (non unlimited)
        IF v_total_entries IS NOT NULL THEN
          -- Verifica che non esista già un record di ripristino
          IF NOT EXISTS (
            SELECT 1
            FROM subscription_usages
            WHERE booking_id = NEW.id
              AND delta = +1
          ) THEN
            -- Crea il record di ripristino
            INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
            VALUES (v_subscription_id, NEW.id, +1, 'CANCEL_RESTORE')
            ON CONFLICT DO NOTHING;
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Ricrea il trigger
CREATE TRIGGER trigger_restore_subscription_entry_on_booking_cancel
  AFTER UPDATE OF status ON public.bookings
  FOR EACH ROW
  WHEN (OLD.status = 'booked' AND NEW.status = 'canceled')
  EXECUTE FUNCTION public.restore_subscription_entry_on_booking_cancel();

COMMENT ON FUNCTION public.restore_subscription_entry_on_booking_cancel() IS 
'Trigger function che ripristina automaticamente gli ingressi quando una prenotazione viene cancellata. Usa solo client_id e subscription_id, nessun riferimento a user_id.';

-- ============================================================================
-- 3. VERIFICA staff_update_booking_status
-- ============================================================================

-- La funzione staff_update_booking_status dovrebbe essere già corretta (migration 33)
-- ma verifichiamo che non faccia riferimento a user_id
-- Il trigger gestirà automaticamente il ripristino quando status = 'canceled'

-- ============================================================================
-- 4. VERIFICA ALTRI TRIGGER SU bookings
-- ============================================================================

-- Lista tutti i trigger su bookings per verifica manuale
DO $$
DECLARE
  v_trigger_record RECORD;
BEGIN
  RAISE NOTICE 'Trigger su bookings:';
  FOR v_trigger_record IN
    SELECT 
      trigger_name,
      event_manipulation,
      action_statement
    FROM information_schema.triggers
    WHERE event_object_table = 'bookings'
      AND event_object_schema = 'public'
  LOOP
    RAISE NOTICE '  - %: %', v_trigger_record.trigger_name, v_trigger_record.action_statement;
  END LOOP;
END;
$$;

