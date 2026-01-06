-- Migration: Reactivate Canceled Event Bookings
--
-- Obiettivo: Quando si prenota un evento dopo averlo cancellato, 
-- riattivare la prenotazione esistente invece di crearne una nuova.
--
-- Modifiche:
-- 1. book_event: cerca prenotazioni cancellate e le riattiva
-- 2. staff_book_event: cerca prenotazioni cancellate e le riattiva

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

  -- Verifica che non sia già prenotato dall'utente (solo prenotazioni attive)
  IF EXISTS (
    SELECT 1 FROM public.event_bookings
    WHERE event_id = p_event_id
      AND (
        (user_id = v_user_id AND client_id IS NULL) OR
        (v_my_client_id IS NOT NULL AND client_id = v_my_client_id)
      )
      AND status = 'booked'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
  END IF;

  -- Cerca se esiste una prenotazione cancellata da riattivare
  SELECT id
  INTO v_reactivate_booking_id
  FROM public.event_bookings
  WHERE event_id = p_event_id
    AND (
      (user_id = v_user_id AND client_id IS NULL) OR
      (v_my_client_id IS NOT NULL AND client_id = v_my_client_id)
    )
    AND status = 'canceled'
  FOR UPDATE
  LIMIT 1;

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
  IF v_reactivate_booking_id IS NOT NULL THEN
    -- Riattiva prenotazione cancellata
    UPDATE public.event_bookings
    SET status = 'booked',
        created_at = now()
    WHERE id = v_reactivate_booking_id;
    v_booking_id := v_reactivate_booking_id;
  ELSE
    -- Crea nuova prenotazione usando user_id o client_id
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
  'Prenota un evento per l''utente autenticato. Gestisce capacità e prevenzione doppia prenotazione. Riattiva prenotazioni cancellate invece di crearne di nuove. Usa user_id se l''utente non è collegato a un cliente, altrimenti usa client_id.';

-- ============================================================================
-- 2. AGGIORNAMENTO: staff_book_event (per gestionale)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.staff_book_event(
  p_event_id uuid,
  p_client_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_staff_id uuid := auth.uid();
  v_capacity integer;
  v_starts_at timestamptz;
  v_now timestamptz := now();
  v_booked_count integer;
  v_booking_id uuid;
  v_event_deleted_at timestamptz;
  v_client_deleted_at timestamptz;
  v_reactivate_booking_id uuid;
  v_client_profile_id uuid;
BEGIN
  -- Check if user is staff
  IF NOT public.is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'UNAUTHORIZED');
  END IF;

  -- Lock event row
  SELECT 
    capacity, 
    starts_at, 
    deleted_at
  INTO 
    v_capacity, 
    v_starts_at, 
    v_event_deleted_at
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_FOUND');
  END IF;

  -- Verifica soft delete evento
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

  -- Verifica che il cliente esista e non sia soft-deleted
  SELECT deleted_at, profile_id
  INTO v_client_deleted_at, v_client_profile_id
  FROM public.clients
  WHERE id = p_client_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  IF v_client_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Verifica che non sia già prenotato dal cliente (solo prenotazioni attive)
  -- Se il cliente ha un account, controlla sia client_id che user_id (profile_id)
  IF v_client_profile_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id
        AND (
          client_id = p_client_id OR
          user_id = v_client_profile_id
        )
        AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id
        AND client_id = p_client_id
        AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  END IF;

  -- Cerca se esiste una prenotazione cancellata da riattivare
  -- Se il cliente ha un account, controlla sia client_id che user_id (profile_id)
  IF v_client_profile_id IS NOT NULL THEN
    SELECT id
    INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND (
        client_id = p_client_id OR
        user_id = v_client_profile_id
      )
      AND status = 'canceled'
    FOR UPDATE
    LIMIT 1;
  ELSE
    SELECT id
    INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND client_id = p_client_id
      AND status = 'canceled'
    FOR UPDATE
    LIMIT 1;
  END IF;

  -- Verifica capacità (se impostata)
  -- Se stiamo riattivando, la capacità è già stata "liberata" quando è stata cancellata
  -- quindi non dobbiamo verificare di nuovo. Se creiamo una nuova prenotazione, verifichiamo.
  IF v_reactivate_booking_id IS NULL AND v_capacity IS NOT NULL THEN
    SELECT count(*) INTO v_booked_count
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND status IN ('booked', 'attended', 'no_show');

    IF v_booked_count >= v_capacity THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;
  END IF;

  -- Riattiva prenotazione esistente o crea nuova
  IF v_reactivate_booking_id IS NOT NULL THEN
    -- Riattiva prenotazione cancellata
    -- Mantiene il client_id o user_id originale dalla prenotazione cancellata
    UPDATE public.event_bookings
    SET status = 'booked',
        created_at = now()
    WHERE id = v_reactivate_booking_id;
    v_booking_id := v_reactivate_booking_id;
  ELSE
    -- Crea nuova prenotazione con client_id
    INSERT INTO public.event_bookings (event_id, user_id, client_id, status)
    VALUES (p_event_id, NULL, p_client_id, 'booked')
    RETURNING id INTO v_booking_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
END;
$$;

COMMENT ON FUNCTION public.staff_book_event(uuid, uuid) IS 
  'Prenota un evento per un cliente CRM (staff only). Usa sempre client_id. Gestisce capacità e prevenzione doppia prenotazione. Riattiva prenotazioni cancellate invece di crearne di nuove.';

