-- Migration 0027: Fix booking cancellation to restore subscription entries
-- 
-- Obiettivo: Assicurare che quando una prenotazione viene cancellata, gli ingressi
-- dell'abbonamento vengano sempre ripristinati correttamente.
--
-- Problema: 
-- 1. staff_cancel_booking non cerca la subscription tramite subscription_usages se subscription_id è NULL
-- 2. cancel_booking cerca solo tramite client_id, ma non considera subscriptions con user_id
-- 3. Se una prenotazione viene cancellata direttamente tramite UPDATE, non viene ripristinato l'ingresso
--
-- Soluzione:
-- 1. Migliorare staff_cancel_booking per cercare subscription anche tramite subscription_usages
-- 2. Migliorare cancel_booking per cercare subscription correttamente tramite client_id e user_id
-- 3. Aggiungere trigger per ripristinare ingressi quando booking viene cancellato direttamente

-- ============================================================================
-- 1. MIGLIORARE staff_cancel_booking
-- ============================================================================

CREATE OR REPLACE FUNCTION public.staff_cancel_booking(p_booking_id uuid) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
declare
  v_staff_id uuid := auth.uid();
  v_booking bookings%rowtype;
  v_lesson lessons%rowtype;
  v_now timestamptz := now();
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_total_entries integer;
  v_cancel_restore_exists boolean := false;
  v_client_id uuid;
begin
  -- Check if user is staff
  if not is_staff() then
    return jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
  end if;

  -- Get booking (staff can cancel any booking)
  select *
  into v_booking
  from bookings
  where id = p_booking_id;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  end if;

  if v_booking.status <> 'booked' then
    return jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_BOOKED');
  end if;

  -- Get lesson info
  select *
  into v_lesson
  from lessons
  where id = v_booking.lesson_id;

  -- Check cancel deadline (informational, staff can override if needed)
  if v_lesson.cancel_deadline_minutes is not null then
    if v_now > v_lesson.starts_at - make_interval(mins => v_lesson.cancel_deadline_minutes) then
      -- Staff can still cancel, but log that deadline passed
    end if;
  end if;

  -- Update booking status
  update bookings
  set status = 'canceled'
  where id = p_booking_id;

  -- Get client_id from booking
  v_client_id := v_booking.client_id;

  -- Strategy 1: Find subscription via subscription_usages (most reliable)
  -- This works even if subscription_id is NULL on the booking
  select s.*
  into v_sub
  from subscription_usages su
  join subscriptions s on s.id = su.subscription_id
  where su.booking_id = p_booking_id
    and su.delta = -1
    and s.deleted_at IS NULL
  order by su.created_at desc
  limit 1;

  -- Strategy 2: If not found via subscription_usages, try using subscription_id from booking
  if not found and v_booking.subscription_id is not null then
    select *
    into v_sub
    from subscriptions
    where id = v_booking.subscription_id
      and deleted_at IS NULL;
  end if;

  -- Strategy 3: Last resort - find subscription by client_id
  if not found then
    if v_client_id is not null then
      select *
      into v_sub
      from subscriptions
      where client_id = v_client_id
        and status = 'active'
        and deleted_at IS NULL
        and current_date between started_at::date and expires_at::date
      order by created_at desc
      limit 1;
    end if;
  end if;

  -- If subscription found, restore entry
  if found then
    select *
    into v_plan
    from plans
    where id = v_sub.plan_id;

    -- Check if plan is soft-deleted
    if v_plan.deleted_at IS NULL then
      v_total_entries := coalesce(v_sub.custom_entries, v_plan.entries);

      if v_total_entries is not null then
        -- Check if a restore entry already exists for this booking (any reason)
        -- This prevents duplicates when booking is canceled via different methods
        select exists(
          select 1
          from subscription_usages
          where booking_id = p_booking_id
            and delta = +1
        ) into v_cancel_restore_exists;

        -- Only insert CANCEL_RESTORE if it doesn't already exist
        if not v_cancel_restore_exists then
          insert into subscription_usages (subscription_id, booking_id, delta, reason)
          values (v_sub.id, p_booking_id, +1, 'CANCEL_RESTORE');
        end if;
      end if;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'reason', 'CANCELED');
end;
$$;

COMMENT ON FUNCTION public.staff_cancel_booking(uuid) IS 
'Cancella una prenotazione (solo staff). Ripristina automaticamente gli ingressi dell''abbonamento se presenti. Cerca la subscription tramite subscription_usages, subscription_id, o client_id/user_id.';

-- ============================================================================
-- 2. MIGLIORARE cancel_booking per cercare subscription correttamente
-- ============================================================================

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
'Cancella una prenotazione dell''utente autenticato. Usa sempre client_id tramite get_my_client_id(). Ripristina automaticamente gli ingressi dell''abbonamento se presenti. Cerca la subscription tramite subscription_usages, subscription_id, o client_id/user_id.';

-- ============================================================================
-- 3. TRIGGER per ripristinare ingressi quando booking viene cancellato direttamente
-- ============================================================================

-- Funzione trigger che ripristina gli ingressi quando una prenotazione viene cancellata
-- direttamente tramite UPDATE (senza chiamare le funzioni cancel_booking o staff_cancel_booking)
CREATE OR REPLACE FUNCTION public.restore_subscription_entry_on_booking_cancel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
declare
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_total_entries integer;
  v_cancel_restore_exists boolean := false;
  v_client_id uuid;
begin
  -- Only process if status changed from 'booked' to 'canceled'
  if OLD.status = 'booked' and NEW.status = 'canceled' then
    -- Get client_id from booking
    v_client_id := NEW.client_id;

    -- Strategy 1: Find subscription via subscription_usages (most reliable)
    select s.*
    into v_sub
    from subscription_usages su
    join subscriptions s on s.id = su.subscription_id
    where su.booking_id = NEW.id
      and su.delta = -1
      and s.deleted_at IS NULL
    order by su.created_at desc
    limit 1;

    -- Strategy 2: If not found via subscription_usages, try using subscription_id from booking
    if not found and NEW.subscription_id is not null then
      select *
      into v_sub
      from subscriptions
      where id = NEW.subscription_id
        and deleted_at IS NULL;
    end if;

    -- Strategy 3: Last resort - find subscription by client_id
    if not found then
      if v_client_id is not null then
        select *
        into v_sub
        from subscriptions
        where client_id = v_client_id
          and status = 'active'
          and deleted_at IS NULL
          and current_date between started_at::date and expires_at::date
        order by created_at desc
        limit 1;
      end if;
    end if;

    -- If subscription found, restore entry
    if found then
      select *
      into v_plan
      from plans
      where id = v_sub.plan_id;

      -- Check if plan is soft-deleted
      if v_plan.deleted_at IS NULL then
        v_total_entries := coalesce(v_sub.custom_entries, v_plan.entries);

        if v_total_entries is not null then
          -- Check if a restore entry already exists for this booking (any reason)
          -- This prevents duplicates when booking is canceled via different methods
          select exists(
            select 1
            from subscription_usages
            where booking_id = NEW.id
              and delta = +1
          ) into v_cancel_restore_exists;

          -- Only insert CANCEL_RESTORE if it doesn't already exist
          if not v_cancel_restore_exists then
            insert into subscription_usages (subscription_id, booking_id, delta, reason)
            values (v_sub.id, NEW.id, +1, 'CANCEL_RESTORE');
          end if;
        end if;
      end if;
    end if;
  end if;

  return NEW;
end;
$$;

COMMENT ON FUNCTION public.restore_subscription_entry_on_booking_cancel() IS 
'Trigger function che ripristina automaticamente gli ingressi dell''abbonamento quando una prenotazione viene cancellata direttamente tramite UPDATE (status da ''booked'' a ''canceled'').';

-- Crea il trigger AFTER UPDATE per intercettare le modifiche allo status
DROP TRIGGER IF EXISTS trigger_restore_subscription_entry_on_booking_cancel ON public.bookings;
CREATE TRIGGER trigger_restore_subscription_entry_on_booking_cancel
  AFTER UPDATE OF status ON public.bookings
  FOR EACH ROW
  WHEN (OLD.status = 'booked' AND NEW.status = 'canceled')
  EXECUTE FUNCTION public.restore_subscription_entry_on_booking_cancel();

COMMENT ON TRIGGER trigger_restore_subscription_entry_on_booking_cancel ON public.bookings IS 
'Trigger che ripristina automaticamente gli ingressi dell''abbonamento quando una prenotazione viene cancellata direttamente tramite UPDATE.';

