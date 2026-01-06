-- Migration 0033: Fix cancel restore - VERSIONE SEMPLICE E DIRETTA
-- 
-- Obiettivo: Quando una prenotazione viene cancellata, se esiste un record
-- subscription_usages con delta = -1 per quella booking, creare SEMPRE
-- un record con delta = +1, senza fare troppe verifiche.
--
-- Problema: I record delta = +1 non vengono creati quando si cancella una prenotazione
--
-- Soluzione: Semplificare al massimo - se c'è un delta = -1, creare un delta = +1

-- ============================================================================
-- 1. TRIGGER SEMPLIFICATO CHE FUNZIONA SEMPRE
-- ============================================================================

-- Elimina il trigger esistente
DROP TRIGGER IF EXISTS trigger_restore_subscription_entry_on_booking_cancel ON public.bookings;

-- Ricrea la funzione trigger in modo SEMPLICE
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
    
    -- Trova il subscription_id dal record subscription_usages con delta = -1
    -- Questo è il modo più diretto e affidabile
    SELECT su.subscription_id
    INTO v_subscription_id
    FROM subscription_usages su
    WHERE su.booking_id = NEW.id
      AND su.delta = -1
    ORDER BY su.created_at DESC
    LIMIT 1;

    -- Se non trovato tramite subscription_usages, prova con subscription_id sulla booking
    IF v_subscription_id IS NULL AND NEW.subscription_id IS NOT NULL THEN
      v_subscription_id := NEW.subscription_id;
    END IF;

    -- Se abbiamo trovato una subscription, verifica se ha ingressi limitati
    IF v_subscription_id IS NOT NULL THEN
      -- Verifica se la subscription ha ingressi limitati (non unlimited)
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
'Trigger function SEMPLIFICATA che ripristina automaticamente gli ingressi quando una prenotazione viene cancellata. Funziona sia se viene chiamata staff_cancel_booking che staff_update_booking_status.';

-- ============================================================================
-- 2. AGGIORNA staff_cancel_booking PER ESSERE PIÙ DIRETTA
-- ============================================================================

CREATE OR REPLACE FUNCTION public.staff_cancel_booking(p_booking_id uuid) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_booking bookings%rowtype;
  v_subscription_id uuid;
  v_total_entries integer;
  v_plan_entries integer;
  v_custom_entries integer;
  v_restore_exists boolean;
BEGIN
  -- Check if user is staff
  IF NOT is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
  END IF;

  -- Get booking
  SELECT *
  INTO v_booking
  FROM bookings
  WHERE id = p_booking_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  END IF;

  IF v_booking.status <> 'booked' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_BOOKED');
  END IF;

  -- Trova subscription_id dal record subscription_usages con delta = -1
  SELECT su.subscription_id
  INTO v_subscription_id
  FROM subscription_usages su
  WHERE su.booking_id = p_booking_id
    AND su.delta = -1
  ORDER BY su.created_at DESC
  LIMIT 1;

  -- Se non trovato, usa subscription_id dalla booking
  IF v_subscription_id IS NULL AND v_booking.subscription_id IS NOT NULL THEN
    v_subscription_id := v_booking.subscription_id;
  END IF;

  -- Update booking status (questo attiverà anche il trigger)
  UPDATE bookings
  SET status = 'canceled'
  WHERE id = p_booking_id;

  -- Se abbiamo trovato una subscription, crea il record di ripristino
  -- (il trigger lo farà comunque, ma facciamolo anche qui per sicurezza)
  IF v_subscription_id IS NOT NULL THEN
    -- Verifica se ha ingressi limitati
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

    IF FOUND THEN
      v_total_entries := COALESCE(v_custom_entries, v_plan_entries);

      IF v_total_entries IS NOT NULL THEN
        -- Verifica che non esista già
        SELECT EXISTS(
          SELECT 1
          FROM subscription_usages
          WHERE booking_id = p_booking_id
            AND delta = +1
        ) INTO v_restore_exists;

        IF NOT v_restore_exists THEN
          INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
          VALUES (v_subscription_id, p_booking_id, +1, 'CANCEL_RESTORE')
          ON CONFLICT DO NOTHING;
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'CANCELED',
    'subscription_id', v_subscription_id,
    'restore_created', NOT v_restore_exists AND v_subscription_id IS NOT NULL
  );
END;
$$;

-- ============================================================================
-- 3. AGGIORNA staff_update_booking_status PER GESTIRE LE CANCELLAZIONI
-- ============================================================================

CREATE OR REPLACE FUNCTION public.staff_update_booking_status(
  p_booking_id uuid,
  p_status booking_status
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_booking bookings%rowtype;
BEGIN
  -- Check if user is staff
  IF NOT is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
  END IF;

  -- Get booking
  SELECT *
  INTO v_booking
  FROM bookings
  WHERE id = p_booking_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  END IF;

  -- Validate status
  IF p_status NOT IN ('booked', 'attended', 'no_show', 'canceled') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_STATUS');
  END IF;

  -- Update booking status
  -- Se si sta cancellando (status = 'canceled'), il trigger gestirà il ripristino
  UPDATE bookings
  SET status = p_status
  WHERE id = p_booking_id;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'UPDATED',
    'booking_id', p_booking_id
  );
END;
$$;

COMMENT ON FUNCTION public.staff_update_booking_status(uuid, booking_status) IS 
'Aggiorna lo stato di una prenotazione. Se si cancella (status = canceled), il trigger ripristina automaticamente gli ingressi.';

