-- Migration 0036: Fix cancel_booking to use client_id instead of user_id
-- 
-- Problema: La funzione cancel_booking potrebbe ancora usare s.user_id che non esiste più 
-- nella tabella subscriptions (rimossa nella migration 20240101000024_standardize_to_client_id.sql)
-- 
-- Soluzione: Assicurarsi che la funzione usi sempre s.client_id con get_my_client_id()
-- per ottenere il client_id dell'utente autenticato.
--
-- Questa migration ricrea la funzione cancel_booking con la logica corretta che usa client_id.

CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id uuid) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
declare
  v_booking bookings%rowtype;
  v_lesson lessons%rowtype;
  v_now timestamptz := now();
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_total_entries integer;
  v_cancel_restore_exists boolean := false;
  v_my_client_id uuid;
begin
  v_my_client_id := public.get_my_client_id();
  
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  select *
  into v_booking
  from bookings
  where id = p_booking_id
    and client_id = v_my_client_id;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  end if;

  if v_booking.status <> 'booked' then
    return jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_BOOKED');
  end if;

  select *
  into v_lesson
  from lessons
  where id = v_booking.lesson_id;

  -- Verifica soft delete della lezione
  if v_lesson.deleted_at IS NOT NULL then
    -- Se la lezione è soft-deleted, permettere comunque la cancellazione
  end if;

  if v_now > v_lesson.starts_at - make_interval(mins => coalesce(v_lesson.cancel_deadline_minutes, 120)) then
    return jsonb_build_object('ok', false, 'reason', 'CANCEL_DEADLINE_PASSED');
  end if;

  update bookings
  set status = 'canceled'
  where id = p_booking_id;

  -- Strategy 1: Find subscription via subscription_usages (most reliable)
  select s.*
  into v_sub
  from subscription_usages su
  join subscriptions s on s.id = su.subscription_id
  where su.booking_id = p_booking_id
    and su.delta = -1
    and s.client_id = v_my_client_id
    and s.deleted_at IS NULL
  order by su.created_at desc
  limit 1;

  -- Strategy 2: If not found via subscription_usages, try using subscription_id from booking
  if not found and v_booking.subscription_id is not null then
    select *
    into v_sub
    from subscriptions
    where id = v_booking.subscription_id
      and client_id = v_my_client_id
      and status = 'active'
      and deleted_at IS NULL;
  end if;

  -- Strategy 3: Last resort - find last active subscription
  if not found then
    select *
    into v_sub
    from subscriptions
    where (
      client_id = v_my_client_id
    )
      and status = 'active'
      and deleted_at IS NULL
      and current_date between started_at::date and expires_at::date
    order by created_at desc
    limit 1;
  end if;

  if not found then
    return jsonb_build_object('ok', true, 'reason', 'CANCELED_NO_SUBSCRIPTION');
  end if;

  select *
  into v_plan
  from plans
  where id = v_sub.plan_id;

  -- Verifica soft delete del piano
  if v_plan.deleted_at IS NOT NULL then
    return jsonb_build_object('ok', true, 'reason', 'CANCELED_PLAN_DELETED');
  end if;

  v_total_entries := coalesce(v_sub.custom_entries, v_plan.entries);

  if v_total_entries is not null then
    -- Check if CANCEL_RESTORE already exists for this booking
    select exists(
      select 1
      from subscription_usages
      where booking_id = p_booking_id
        and delta = +1
        and reason = 'CANCEL_RESTORE'
    ) into v_cancel_restore_exists;

    -- Only insert CANCEL_RESTORE if it doesn't already exist
    if not v_cancel_restore_exists then
      insert into subscription_usages (subscription_id, booking_id, delta, reason)
      values (v_sub.id, p_booking_id, +1, 'CANCEL_RESTORE');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'reason', 'CANCELED');
end;
$$;

COMMENT ON FUNCTION public.cancel_booking(uuid) IS 
'Cancella una prenotazione dell''utente autenticato. Usa sempre client_id tramite get_my_client_id(). Ripristina automaticamente gli ingressi dell''abbonamento se presenti. Cerca la subscription tramite subscription_usages, subscription_id, o client_id.';

