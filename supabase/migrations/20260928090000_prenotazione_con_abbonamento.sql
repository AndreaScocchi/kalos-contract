-- Migration 20260928090000: da unə cliente, la prenotazione di una lezione richiede un abbonamento
--
-- `book_lesson` accettava `p_subscription_id` NULL e in quel caso non controllava nulla: la lezione
-- si prenotava senza abbonamento e senza scalare ingressi. A impedirlo era solo l'interfaccia della
-- webapp, che mostra «Prenota» solo a chi ha un abbonamento valido (altrimenti «Consulta i piani»).
-- Ora il controllo sta nel database: senza abbonamento la risposta è `SUBSCRIPTION_REQUIRED`.
--
-- Nessuna app cambia comportamento: la webapp passa sempre un abbonamento; lo staff prenota con
-- `staff_book_lesson` (che resta libera, con l'incasso «da saldare»); le prove con
-- `book_trial_lesson`; le lezioni individuali le prenota il trigger all'assegnazione.
-- Il resto della funzione è identico alla versione della sessione 6 (20260924150100).

CREATE OR REPLACE FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid" DEFAULT NULL::"uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_member_gate text;
  v_my_client_id uuid;
  v_booking_id uuid;
  v_lesson lessons%ROWTYPE;
  v_sub subscriptions%ROWTYPE;
  v_plan plans%ROWTYPE;
  v_activity_id uuid;
  v_starts_at timestamptz;
  v_capacity integer;
  v_is_individual boolean;
  v_assigned_client_id uuid;
  v_total_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_booked_count integer;
  v_has_plan_activities boolean;
BEGIN
  -- Auth check
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Regola "solo soci" (H2): con l'interruttore acceso si prenota solo da sociə.
  -- Chi ha pagato la quota prenota subito, anche prima della delibera del Consiglio Direttivo (A7).
  IF "internal"."members_only_enabled"() THEN
    v_member_gate := "internal"."member_booking_status"(v_my_client_id);
    IF v_member_gate NOT IN ('ok', 'fee_due_grace', 'pending_admission') THEN
      RETURN jsonb_build_object(
        'ok', false,
        'reason', CASE WHEN v_member_gate IN ('fee_unpaid', 'fee_overdue')
                       THEN 'MEMBERSHIP_FEE_DUE' ELSE 'NOT_A_MEMBER' END,
        'member_status', v_member_gate);
    END IF;
  END IF;

  -- Lock the lesson row to prevent race conditions on capacity check
  SELECT * INTO v_lesson
  FROM public.lessons
  WHERE id = p_lesson_id
  FOR UPDATE;

  IF NOT FOUND OR v_lesson.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  v_activity_id := v_lesson.activity_id;
  v_starts_at := v_lesson.starts_at;
  v_capacity := v_lesson.capacity;
  v_is_individual := v_lesson.is_individual;
  v_assigned_client_id := v_lesson.assigned_client_id;

  -- Verify activity not deleted
  IF v_activity_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.activities WHERE id = v_activity_id AND deleted_at IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  -- Dalla sessione 8: unə cliente prenota sempre con un abbonamento. Il controllo prima stava solo
  -- nell'interfaccia della webapp. Senza abbonamento prenota solo lo staff (staff_book_lesson,
  -- con l'incasso da saldare); le prove passano da book_trial_lesson.
  IF p_subscription_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_REQUIRED');
  END IF;

  -- Validate subscription if provided
  IF p_subscription_id IS NOT NULL THEN
    SELECT * INTO v_sub
    FROM public.subscriptions
    WHERE id = p_subscription_id
      AND client_id = v_my_client_id
      AND status = 'active'
      AND v_starts_at::date BETWEEN started_at::date AND expires_at::date;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_NOT_FOUND_OR_INACTIVE');
    END IF;

    SELECT * INTO v_plan FROM public.plans WHERE id = v_sub.plan_id;
    IF v_plan.deleted_at IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'PLAN_NOT_FOUND');
    END IF;

    -- Validate discipline coverage
    SELECT EXISTS(
      SELECT 1 FROM public.plan_activities pa WHERE pa.plan_id = v_sub.plan_id
    ) INTO v_has_plan_activities;

    IF v_has_plan_activities THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.plan_activities pa
        WHERE pa.plan_id = v_sub.plan_id AND pa.activity_id = v_activity_id
      ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_DISCIPLINE_MISMATCH');
      END IF;
    END IF;

    -- Remaining entries check
    v_total_entries := COALESCE(v_sub.custom_entries, v_plan.entries);
    IF v_total_entries IS NOT NULL THEN
      SELECT COALESCE(SUM(delta), 0) INTO v_used_entries
      FROM public.subscription_usages WHERE subscription_id = v_sub.id;
      v_remaining_entries := v_total_entries + v_used_entries;
      IF v_remaining_entries <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NO_ENTRIES_LEFT');
      END IF;
    END IF;
  END IF;

  -- Individual lesson: honor assigned client
  IF v_is_individual = true THEN
    IF v_assigned_client_id IS NULL OR v_my_client_id IS DISTINCT FROM v_assigned_client_id THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    -- Check existing booking first
    IF EXISTS (
      SELECT 1 FROM public.bookings
      WHERE lesson_id = p_lesson_id AND client_id = v_my_client_id AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    -- Insert with ON CONFLICT for race condition safety
    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
    VALUES (p_lesson_id, v_my_client_id, p_subscription_id, 'booked')
    ON CONFLICT (lesson_id, client_id) WHERE status = 'booked' AND client_id IS NOT NULL
    DO NOTHING
    RETURNING id INTO v_booking_id;

    IF v_booking_id IS NULL THEN
      -- Race condition: another request inserted just before us
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

  ELSE
    -- Public lesson: check deadline
    IF now() > v_starts_at - make_interval(mins => COALESCE(v_lesson.booking_deadline_minutes, 30)) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
    END IF;

    -- Check already booked first
    IF EXISTS (
      SELECT 1 FROM public.bookings
      WHERE lesson_id = p_lesson_id AND client_id = v_my_client_id AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    -- Capacity check (lesson is locked with FOR UPDATE, so this is atomic).
    -- Un posto offerto a chi è in lista d'attesa è occupato, tranne per chi l'ha ricevuto.
    SELECT count(*) INTO v_booked_count
    FROM public.bookings
    WHERE lesson_id = p_lesson_id AND status = 'booked';

    IF v_booked_count + "internal"."waitlist_seats_held"(p_lesson_id, v_my_client_id) >= v_capacity THEN
      RETURN "internal"."full_response"(p_lesson_id, v_my_client_id, v_booked_count, v_capacity);
    END IF;

    -- Insert with ON CONFLICT for race condition safety (double booking prevention)
    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
    VALUES (p_lesson_id, v_my_client_id, p_subscription_id, 'booked')
    ON CONFLICT (lesson_id, client_id) WHERE status = 'booked' AND client_id IS NOT NULL
    DO NOTHING
    RETURNING id INTO v_booking_id;

    IF v_booking_id IS NULL THEN
      -- Race condition: user already has a booking
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  END IF;

  -- Usage accounting: track ALL subscriptions (including unlimited)
  IF p_subscription_id IS NOT NULL THEN
    INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
    VALUES (p_subscription_id, v_booking_id, -1, 'BOOK');
  END IF;

  RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED', 'booking_id', v_booking_id);
END;
$$;
