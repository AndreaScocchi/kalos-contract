-- Migration 0039: Add Event Bookings Management
--
-- Obiettivo: Permettere prenotazione interna eventi quando non c'è link esterno
-- e supportare prenotazioni da gestionale per clienti senza account.
--
-- Modifiche:
-- 1. Rendere events.link nullable (NULL = prenotazione interna)
-- 2. Aggiungere client_id a event_bookings con constraint XOR (come bookings)
-- 3. Aggiornare RLS policies per event_bookings
-- 4. Creare RPC functions per prenotare/cancellare eventi

-- ============================================================================
-- 1. MODIFICA TABELLA: events.link nullable
-- ============================================================================

-- Permettere NULL per link quando la prenotazione è interna
ALTER TABLE public.events 
  ALTER COLUMN link DROP NOT NULL;

COMMENT ON COLUMN public.events.link IS 
  'URL esterno per registrazione/partecipazione all''evento. NULL se la prenotazione è gestita internamente tramite event_bookings.';

-- ============================================================================
-- 2. MODIFICA TABELLA: event_bookings - aggiungere client_id
-- ============================================================================

-- Aggiungi colonna client_id (nullable, come user_id)
ALTER TABLE public.event_bookings 
  ADD COLUMN IF NOT EXISTS client_id uuid;

-- Rendere user_id nullable per supportare prenotazioni con solo client_id
-- IMPORTANTE: Questo deve essere fatto PRIMA di aggiungere il constraint XOR
-- e PRIMA di aggiungere la foreign key per client_id
-- La foreign key esistente su user_id permette già NULL, quindi non serve modificarla
DO $$
BEGIN
  -- Verifica se user_id è ancora NOT NULL e rendilo nullable
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'event_bookings' 
      AND column_name = 'user_id' 
      AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE public.event_bookings 
      ALTER COLUMN user_id DROP NOT NULL;
  END IF;
END $$;

-- Aggiungi foreign key verso clients
ALTER TABLE public.event_bookings 
  ADD CONSTRAINT event_bookings_client_id_fkey 
  FOREIGN KEY (client_id) 
  REFERENCES public.clients(id) 
  ON DELETE SET NULL;

-- Aggiungi constraint XOR: user_id e client_id non possono essere entrambi NULL o entrambi NOT NULL
ALTER TABLE public.event_bookings 
  ADD CONSTRAINT event_bookings_user_client_xor 
  CHECK (
    (user_id IS NOT NULL AND client_id IS NULL) OR 
    (user_id IS NULL AND client_id IS NOT NULL)
  );

-- Aggiungi indice per client_id
CREATE INDEX IF NOT EXISTS idx_event_bookings_client 
  ON public.event_bookings(client_id) 
  WHERE client_id IS NOT NULL;

COMMENT ON TABLE public.event_bookings IS 
  'Prenotazioni per eventi. Può essere collegata a un utente (user_id) o a un cliente CRM (client_id), ma non entrambi (XOR constraint).';

COMMENT ON COLUMN public.event_bookings.user_id IS 
  'ID dell''utente con account che ha prenotato. NULL se client_id è impostato.';

COMMENT ON COLUMN public.event_bookings.client_id IS 
  'ID del cliente CRM (senza account) che ha prenotato. NULL se user_id è impostato.';

-- ============================================================================
-- 3. AGGIORNAMENTO RLS POLICIES: event_bookings
-- ============================================================================

-- Rimuovi policies vecchie
DROP POLICY IF EXISTS "event_bookings_insert_own" ON public.event_bookings;
DROP POLICY IF EXISTS "event_bookings_select_own_or_staff" ON public.event_bookings;
DROP POLICY IF EXISTS "event_bookings_update_own" ON public.event_bookings;

-- Policy SELECT: utenti vedono le proprie prenotazioni (via user_id o client_id collegato), staff vede tutto
CREATE POLICY "event_bookings_select_own_or_staff" 
ON public.event_bookings 
FOR SELECT 
TO authenticated 
USING (
  public.is_staff() 
  OR user_id = auth.uid()
  OR client_id = public.get_my_client_id()
);

-- Policy INSERT: utenti possono inserire solo le proprie prenotazioni (via user_id o client_id), staff può inserire qualsiasi
CREATE POLICY "event_bookings_insert_own_or_staff" 
ON public.event_bookings 
FOR INSERT 
TO authenticated 
WITH CHECK (
  public.is_staff() 
  OR (user_id = auth.uid() AND client_id IS NULL)
  OR (client_id = public.get_my_client_id() AND user_id IS NULL)
);

-- Policy UPDATE: utenti possono solo cancellare le proprie prenotazioni (status = canceled), staff può fare qualsiasi modifica
CREATE POLICY "event_bookings_update_own_or_staff" 
ON public.event_bookings 
FOR UPDATE 
TO authenticated 
USING (
  public.is_staff() 
  OR user_id = auth.uid()
  OR client_id = public.get_my_client_id()
)
WITH CHECK (
  public.is_staff() 
  OR (
    (user_id = auth.uid() OR client_id = public.get_my_client_id()) 
    AND status = 'canceled'::booking_status
  )
);

-- Policy DELETE: solo staff può cancellare record (gli utenti usano status = canceled)
-- (già presente come event_bookings_delete_staff, manteniamo)

COMMENT ON POLICY "event_bookings_select_own_or_staff" ON public.event_bookings IS 
  'RLS: Permette SELECT solo delle proprie prenotazioni (user_id = auth.uid() o client_id = get_my_client_id()) o se staff.';

COMMENT ON POLICY "event_bookings_insert_own_or_staff" ON public.event_bookings IS 
  'RLS: Permette INSERT solo delle proprie prenotazioni (user_id = auth.uid() o client_id = get_my_client_id()) o se staff.';

COMMENT ON POLICY "event_bookings_update_own_or_staff" ON public.event_bookings IS 
  'RLS: Permette UPDATE solo delle proprie prenotazioni o se staff. Gli utenti possono solo cancellare (status = canceled).';

-- ============================================================================
-- 4. RPC FUNCTION: book_event (per utenti app)
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

  -- Verifica che non sia già prenotato dall'utente
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

  -- Verifica capacità (se impostata)
  IF v_capacity IS NOT NULL THEN
    -- Conta prenotazioni attive (booked, attended, no_show)
    SELECT count(*) INTO v_booked_count
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND status IN ('booked', 'attended', 'no_show');

    IF v_booked_count >= v_capacity THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;
  END IF;

  -- Crea prenotazione usando user_id o client_id
  INSERT INTO public.event_bookings (event_id, user_id, client_id, status)
  VALUES (
    p_event_id, 
    CASE WHEN v_my_client_id IS NOT NULL THEN NULL ELSE v_user_id END,
    v_my_client_id,
    'booked'
  )
  RETURNING id INTO v_booking_id;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
END;
$$;

COMMENT ON FUNCTION public.book_event(uuid) IS 
  'Prenota un evento per l''utente autenticato. Gestisce capacità e prevenzione doppia prenotazione. Usa user_id se l''utente non è collegato a un cliente, altrimenti usa client_id.';

-- ============================================================================
-- 5. RPC FUNCTION: cancel_event_booking (per utenti app)
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
  IF NOT (
    public.is_staff() 
    OR (v_booking_user_id = v_user_id AND v_booking_client_id IS NULL)
    OR (v_my_client_id IS NOT NULL AND v_booking_client_id = v_my_client_id)
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
  'Cancella una prenotazione evento per l''utente autenticato. Non permette cancellazione di prenotazioni già concluse (attended/no_show).';

-- ============================================================================
-- 6. RPC FUNCTION: staff_book_event (per gestionale)
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
  SELECT deleted_at INTO v_client_deleted_at
  FROM public.clients
  WHERE id = p_client_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  IF v_client_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Verifica che non sia già prenotato dal cliente
  IF EXISTS (
    SELECT 1 FROM public.event_bookings
    WHERE event_id = p_event_id
      AND client_id = p_client_id
      AND status = 'booked'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
  END IF;

  -- Verifica capacità (se impostata)
  IF v_capacity IS NOT NULL THEN
    SELECT count(*) INTO v_booked_count
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND status IN ('booked', 'attended', 'no_show');

    IF v_booked_count >= v_capacity THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;
  END IF;

  -- Crea prenotazione con client_id
  INSERT INTO public.event_bookings (event_id, user_id, client_id, status)
  VALUES (p_event_id, NULL, p_client_id, 'booked')
  RETURNING id INTO v_booking_id;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
END;
$$;

COMMENT ON FUNCTION public.staff_book_event(uuid, uuid) IS 
  'Prenota un evento per un cliente CRM (staff only). Usa sempre client_id. Gestisce capacità e prevenzione doppia prenotazione.';

-- ============================================================================
-- 7. RPC FUNCTION: staff_cancel_event_booking (per gestionale)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.staff_cancel_event_booking(
  p_booking_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_staff_id uuid := auth.uid();
  v_status booking_status;
BEGIN
  -- Check if user is staff
  IF NOT public.is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'UNAUTHORIZED');
  END IF;

  -- Recupera booking con lock
  SELECT status
  INTO v_status
  FROM public.event_bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  END IF;

  -- Verifica che non sia già cancellato
  IF v_status = 'canceled' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_CANCELED');
  END IF;

  -- Staff può cancellare anche prenotazioni concluse (attended/no_show) se necessario

  -- Aggiorna status a canceled
  UPDATE public.event_bookings
  SET status = 'canceled'::booking_status
  WHERE id = p_booking_id;

  RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED');
END;
$$;

COMMENT ON FUNCTION public.staff_cancel_event_booking(uuid) IS 
  'Cancella una prenotazione evento (staff only). Permette cancellazione anche di prenotazioni concluse.';

-- ============================================================================
-- 8. GRANTS per le nuove RPC functions
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.book_event(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_event_booking(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_book_event(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_cancel_event_booking(uuid) TO authenticated;

