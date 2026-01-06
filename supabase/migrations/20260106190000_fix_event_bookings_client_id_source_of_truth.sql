-- Migration: Fix Event Bookings to Use client_id as Source of Truth
--
-- Problema: Nelle prenotazioni eventi, user_id e client_id non vengono usati propriamente.
-- client_id deve essere la fonte di verità quando disponibile.
--
-- Soluzione:
-- 1. book_event: Se l'utente ha un client_id, usare SEMPRE client_id (user_id = NULL)
-- 2. cancel_event_booking: Verificare ownership usando client_id come fonte di verità
-- 3. Le verifiche di prenotazione esistente devono usare client_id quando disponibile

-- ============================================================================
-- 1. AGGIORNAMENTO: book_event (per utenti app)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.book_event(
  p_event_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_my_client_id uuid;
  v_capacity integer;
  v_starts_at timestamptz;
  v_now timestamptz := now();
  v_booked_count integer;
  v_booking_id uuid;
  v_event_deleted_at timestamptz;
  v_link text;
  v_reactivate_booking_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();

  -- Lock event row per prevenire race conditions
  SELECT 
    capacity, 
    starts_at, 
    deleted_at,
    link
  INTO 
    v_capacity, 
    v_starts_at, 
    v_event_deleted_at,
    v_link
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_FOUND');
  END IF;

  -- Verifica soft delete
  IF v_event_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_FOUND');
  END IF;

  -- Verifica che l'evento sia attivo
  IF NOT EXISTS (
    SELECT 1 FROM public.events 
    WHERE id = p_event_id AND is_active = true
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_ACTIVE');
  END IF;

  -- Verifica che non sia già prenotato
  -- client_id è la fonte di verità: se l'utente ha un client_id, controlla solo quello
  -- Altrimenti controlla user_id
  IF v_my_client_id IS NOT NULL THEN
    -- Utente con client_id: controlla solo client_id (fonte di verità)
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id
        AND client_id = v_my_client_id
        AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  ELSE
    -- Utente senza client_id: controlla user_id
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id
        AND user_id = v_user_id
        AND client_id IS NULL
        AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  END IF;

  -- Cerca se esiste una prenotazione cancellata da riattivare
  -- client_id è la fonte di verità: se l'utente ha un client_id, cerca solo quello
  IF v_my_client_id IS NOT NULL THEN
    SELECT id
    INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND client_id = v_my_client_id
      AND status = 'canceled'
    FOR UPDATE
    LIMIT 1;
  ELSE
    SELECT id
    INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND user_id = v_user_id
      AND client_id IS NULL
      AND status = 'canceled'
    FOR UPDATE
    LIMIT 1;
  END IF;

  -- Verifica capacità (se impostata)
  -- Se stiamo riattivando, la capacità è già stata "liberata" quando è stata cancellata
  -- quindi non dobbiamo verificare di nuovo. Se creiamo una nuova prenotazione, verifichiamo.
  IF v_reactivate_booking_id IS NULL AND v_capacity IS NOT NULL THEN
    -- Conta prenotazioni attive (booked, attended, no_show)
    SELECT count(*) INTO v_booked_count
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND status IN ('booked', 'attended', 'no_show');

    IF v_booked_count >= v_capacity THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;
  END IF;

  -- Riattiva prenotazione esistente o crea nuova
  -- client_id è la fonte di verità: se l'utente ha un client_id, usare SEMPRE client_id (user_id = NULL)
  IF v_reactivate_booking_id IS NOT NULL THEN
    -- Riattiva prenotazione cancellata
    UPDATE public.event_bookings
    SET status = 'booked',
        created_at = now()
    WHERE id = v_reactivate_booking_id;
    v_booking_id := v_reactivate_booking_id;
  ELSE
    -- Crea nuova prenotazione
    -- client_id è la fonte di verità: se disponibile, usare SEMPRE client_id (user_id = NULL)
    INSERT INTO public.event_bookings (event_id, user_id, client_id, status)
    VALUES (
      p_event_id, 
      CASE WHEN v_my_client_id IS NOT NULL THEN NULL ELSE v_user_id END,
      v_my_client_id,
      'booked'
    )
    RETURNING id INTO v_booking_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
END;
$$;

COMMENT ON FUNCTION public.book_event(uuid) IS 
  'Prenota un evento per l''utente autenticato. Gestisce capacità e prevenzione doppia prenotazione. Riattiva prenotazioni cancellate invece di crearne di nuove. client_id è la fonte di verità: se l''utente ha un client_id, viene sempre usato client_id (user_id = NULL).';

-- ============================================================================
-- 2. AGGIORNAMENTO: cancel_event_booking (per utenti app)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cancel_event_booking(
  p_booking_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_my_client_id uuid;
  v_booking_user_id uuid;
  v_booking_client_id uuid;
  v_status booking_status;
  v_event_starts_at timestamptz;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();

  -- Recupera booking con lock
  SELECT user_id, client_id, status
  INTO v_booking_user_id, v_booking_client_id, v_status
  FROM public.event_bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  END IF;

  -- Verifica ownership
  -- client_id è la fonte di verità: se l'utente ha un client_id, verificare solo quello
  -- Altrimenti verificare user_id
  IF NOT (
    public.is_staff() 
    OR (
      -- Se l'utente ha un client_id, verificare solo client_id (fonte di verità)
      (v_my_client_id IS NOT NULL AND v_booking_client_id = v_my_client_id)
      OR
      -- Se l'utente non ha client_id, verificare user_id
      (v_my_client_id IS NULL AND v_booking_user_id = v_user_id AND v_booking_client_id IS NULL)
    )
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'UNAUTHORIZED');
  END IF;

  -- Verifica che non sia già cancellato
  IF v_status = 'canceled' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_CANCELED');
  END IF;

  -- Verifica che non sia già concluso
  IF v_status IN ('attended', 'no_show') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CANNOT_CANCEL_CONCLUDED');
  END IF;

  -- Recupera starts_at dell'evento per verifiche future (se necessario)
  SELECT starts_at INTO v_event_starts_at
  FROM public.events
  WHERE id = (SELECT event_id FROM public.event_bookings WHERE id = p_booking_id);

  -- Aggiorna status a canceled
  UPDATE public.event_bookings
  SET status = 'canceled'::booking_status
  WHERE id = p_booking_id;

  RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED');
END;
$$;

COMMENT ON FUNCTION public.cancel_event_booking(uuid) IS 
  'Cancella una prenotazione evento per l''utente autenticato. Non permette cancellazione di prenotazioni già concluse (attended/no_show). client_id è la fonte di verità per la verifica ownership: se l''utente ha un client_id, viene verificato solo quello.';

