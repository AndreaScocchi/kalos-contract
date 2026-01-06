-- Migration 0037: Fix book_lesson to deduct subscription entries
-- 
-- Problema: La funzione book_lesson non scala gli ingressi dell'abbonamento quando viene
-- creata una prenotazione con subscription_id. Questo causa un disallineamento tra:
-- - La booking che ha subscription_id
-- - La view subscriptions_with_remaining che non vede il decremento degli ingressi
--
-- Soluzione: Aggiungere la logica per:
-- 1. Verificare che la subscription sia valida e appartenga al client
-- 2. Verificare che abbia ingressi disponibili
-- 3. Inserire un record in subscription_usages con delta = -1 dopo aver creato la booking
--    (solo se la subscription ha ingressi limitati, non illimitata)

CREATE OR REPLACE FUNCTION public.book_lesson(
  p_lesson_id uuid,
  p_subscription_id uuid DEFAULT NULL
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
  v_booking_deadline_minutes integer;
  v_now timestamptz := now();
  v_is_individual boolean;
  v_assigned_client_id uuid;
  v_booked_count integer;
  v_booking_id uuid;
  v_lesson_deleted_at timestamptz;
  v_activity_deleted_at timestamptz;
  -- Variabili per gestione subscription
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_total_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  -- Ottieni client_id dell'utente autenticato
  v_my_client_id := public.get_my_client_id();
  
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Lock lesson row per prevenire race conditions
  SELECT 
    capacity, 
    starts_at, 
    booking_deadline_minutes, 
    is_individual, 
    assigned_client_id,
    deleted_at
  INTO 
    v_capacity, 
    v_starts_at, 
    v_booking_deadline_minutes, 
    v_is_individual, 
    v_assigned_client_id,
    v_lesson_deleted_at
  FROM public.lessons
  WHERE id = p_lesson_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  -- Verifica soft delete
  IF v_lesson_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  -- Verifica che l'attività non sia soft-deleted
  SELECT a.deleted_at INTO v_activity_deleted_at
  FROM public.lessons l
  INNER JOIN public.activities a ON a.id = l.activity_id
  WHERE l.id = p_lesson_id;

  IF v_activity_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  -- Verifica subscription se fornita (prima di creare la booking)
  IF p_subscription_id IS NOT NULL THEN
    -- Verifica subscription: deve appartenere al client
    SELECT *
    INTO v_sub
    FROM subscriptions
    WHERE id = p_subscription_id
      AND client_id = v_my_client_id
      AND status = 'active'
      AND current_date BETWEEN started_at::date AND expires_at::date;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_NOT_FOUND_OR_INACTIVE');
    END IF;

    -- Get plan info
    SELECT *
    INTO v_plan
    FROM plans
    WHERE id = v_sub.plan_id;

    -- Verifica soft delete del piano
    IF v_plan.deleted_at IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'PLAN_NOT_FOUND');
    END IF;

    v_total_entries := COALESCE(v_sub.custom_entries, v_plan.entries);

    -- For unlimited subscriptions (v_total_entries is null), skip entry check
    IF v_total_entries IS NOT NULL THEN
      SELECT COALESCE(SUM(delta), 0)
      INTO v_used_entries
      FROM subscription_usages
      WHERE subscription_id = v_sub.id;

      v_remaining_entries := v_total_entries + v_used_entries;

      IF v_remaining_entries <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NO_ENTRIES_LEFT');
      END IF;
    END IF;
  END IF;

  -- =========================
  -- INDIVIDUAL LESSON
  -- =========================
  IF v_is_individual = true THEN
    IF v_assigned_client_id IS NULL
       OR v_my_client_id IS DISTINCT FROM v_assigned_client_id THEN
      -- Non leakare informazioni
      RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    -- Booking già creato (auto-booking)
    SELECT id INTO v_booking_id
    FROM public.bookings
    WHERE lesson_id = p_lesson_id
      AND client_id = v_assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
    LIMIT 1;

    IF v_booking_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'ok', true,
        'reason', 'ALREADY_BOOKED',
        'booking_id', v_booking_id
      );
    END IF;

    -- Fallback: crea booking
    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
    VALUES (p_lesson_id, v_assigned_client_id, p_subscription_id, 'booked')
    RETURNING id INTO v_booking_id;

    -- Handle subscription usage accounting (skip for unlimited subscriptions)
    IF p_subscription_id IS NOT NULL AND v_total_entries IS NOT NULL THEN
      INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
      VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');
    END IF;

    RETURN jsonb_build_object(
      'ok', true,
      'reason', 'BOOKED',
      'booking_id', v_booking_id
    );
  END IF;

  -- =========================
  -- PUBLIC LESSON
  -- =========================
  IF v_booking_deadline_minutes IS NOT NULL
     AND v_booking_deadline_minutes > 0
     AND v_now > (v_starts_at - (v_booking_deadline_minutes || ' minutes')::interval) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.bookings
    WHERE lesson_id = p_lesson_id
      AND client_id = v_my_client_id
      AND status = 'booked'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
  END IF;

  -- Conta prenotazioni con lock per evitare race conditions
  SELECT count(*) INTO v_booked_count
  FROM public.bookings
  WHERE lesson_id = p_lesson_id
    AND status = 'booked';

  IF v_booked_count >= v_capacity THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
  END IF;

  INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
  VALUES (p_lesson_id, v_my_client_id, p_subscription_id, 'booked')
  RETURNING id INTO v_booking_id;

  -- Handle subscription usage accounting (skip for unlimited subscriptions)
  IF p_subscription_id IS NOT NULL AND v_total_entries IS NOT NULL THEN
    INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
    VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
END;
$$;

COMMENT ON FUNCTION public.book_lesson(uuid, uuid) IS 
'Prenota una lezione per l''utente autenticato. Usa sempre client_id tramite get_my_client_id(). Scala automaticamente gli ingressi dell''abbonamento se fornito e se ha ingressi limitati.';

