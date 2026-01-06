-- Migration 0038: Fix staff_cancel_booking to find subscription via subscription_usages
-- 
-- Problema: La funzione staff_cancel_booking cerca la subscription solo tramite 
-- subscription_id sulla booking. Se la booking è stata creata prima della fix di 
-- book_lesson (migration 37), potrebbe non avere subscription_id anche se esiste 
-- un record in subscription_usages con delta = -1.
--
-- Soluzione: Migliorare la logica di ricerca della subscription per usare la stessa
-- strategia di cancel_booking:
-- 1. Cercare tramite subscription_usages (più affidabile)
-- 2. Se non trovata, usare subscription_id dalla booking
-- 3. Verificare che la subscription abbia ingressi limitati prima di ripristinare

CREATE OR REPLACE FUNCTION public.staff_cancel_booking(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_sub subscriptions%ROWTYPE;
  v_plan plans%ROWTYPE;
  v_total_entries integer;
  v_cancel_restore_exists boolean := false;
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

  -- Strategy 1: Find subscription via subscription_usages (most reliable)
  -- Questo funziona anche se la booking non ha subscription_id ma ha un record di utilizzo
  SELECT s.*
  INTO v_sub
  FROM subscription_usages su
  JOIN subscriptions s ON s.id = su.subscription_id
  WHERE su.booking_id = p_booking_id
    AND su.delta = -1
    AND s.deleted_at IS NULL
  ORDER BY su.created_at DESC
  LIMIT 1;

  -- Strategy 2: If not found via subscription_usages, try using subscription_id from booking
  IF NOT FOUND AND v_booking.subscription_id IS NOT NULL THEN
    SELECT *
    INTO v_sub
    FROM subscriptions
    WHERE id = v_booking.subscription_id
      AND deleted_at IS NULL;
  END IF;

  -- Se abbiamo trovato una subscription, verifica se ha ingressi limitati e ripristina
  IF FOUND THEN
    -- Get plan info
    SELECT *
    INTO v_plan
    FROM plans
    WHERE id = v_sub.plan_id;

    -- Verifica soft delete del piano
    IF v_plan.deleted_at IS NOT NULL THEN
      -- Piano soft-deleted: non restituire entry (piano non più valido)
      RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED_PLAN_DELETED');
    END IF;

    v_total_entries := COALESCE(v_sub.custom_entries, v_plan.entries);

    -- Solo se ha ingressi limitati (non unlimited)
    IF v_total_entries IS NOT NULL THEN
      -- Verifica che non esista già un record di ripristino
      SELECT EXISTS(
        SELECT 1
        FROM subscription_usages
        WHERE booking_id = p_booking_id
          AND delta = +1
          AND reason IN ('CANCEL_RESTORE', 'CANCEL')
      ) INTO v_cancel_restore_exists;

      -- Solo se non esiste già un record di ripristino
      IF NOT v_cancel_restore_exists THEN
        INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
        VALUES (v_sub.id, p_booking_id, +1, 'CANCEL_RESTORE')
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED');
END;
$$;

COMMENT ON FUNCTION public.staff_cancel_booking(uuid) IS 
'Cancella una prenotazione (solo staff). Ripristina automaticamente gli ingressi dell''abbonamento se presenti. Cerca la subscription tramite subscription_usages (più affidabile) o subscription_id dalla booking.';

