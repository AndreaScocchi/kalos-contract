-- Migration 0030: Final fix for staff_cancel_booking to restore subscription entries
-- 
-- Obiettivo: Assicurarsi che quando si cancella una prenotazione dal gestionale,
-- il record subscription_usages con delta = +1 venga SEMPRE creato se esiste
-- un record con delta = -1 per quella booking.
--
-- Problema: Gli ingressi non vengono ripristinati quando si cancella una prenotazione
--
-- Soluzione: Migliorare la logica per trovare SEMPRE la subscription corretta
-- e creare il record di ripristino

-- ============================================================================
-- MIGLIORARE staff_cancel_booking - VERSIONE FINALE
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

  -- Get client_id from booking BEFORE updating status
  v_client_id := v_booking.client_id;

  -- Strategy 1: Find subscription via subscription_usages (MOST RELIABLE)
  -- This is the BEST way because it directly links the booking to the subscription
  -- that was used when booking was created
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
  -- Only if we haven't found it yet and client_id is not null
  if not found and v_client_id is not null then
    -- Try to find any active subscription for this client
    -- that has limited entries (not unlimited)
    select s.*
    into v_sub
    from subscriptions s
    left join plans p on p.id = s.plan_id
    where s.client_id = v_client_id
      and s.deleted_at IS NULL
      and (
        s.status = 'active'
        or (s.status = 'expired' and v_lesson.starts_at < now())
      )
      and coalesce(s.custom_entries, p.entries) is not null
    order by 
      case when s.status = 'active' then 1 else 2 end,
      s.created_at desc
    limit 1;
  end if;

  -- Update booking status
  -- Do this AFTER finding the subscription so we have all the info we need
  update bookings
  set status = 'canceled'
  where id = p_booking_id;

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
        -- OR if the trigger already created one
        select exists(
          select 1
          from subscription_usages
          where booking_id = p_booking_id
            and delta = +1
        ) into v_cancel_restore_exists;

        -- Only insert CANCEL_RESTORE if it doesn't already exist
        -- (the trigger might have already created it, but we want to be sure)
        if not v_cancel_restore_exists then
          insert into subscription_usages (subscription_id, booking_id, delta, reason)
          values (v_sub.id, p_booking_id, +1, 'CANCEL_RESTORE');
        end if;
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true, 
    'reason', 'CANCELED',
    'subscription_found', found,
    'subscription_id', case when found then v_sub.id else null end,
    'restore_created', not v_cancel_restore_exists and found,
    'booking_id', p_booking_id,
    'client_id', v_client_id
  );
end;
$$;

COMMENT ON FUNCTION public.staff_cancel_booking(uuid) IS 
'Cancella una prenotazione (solo staff). Ripristina automaticamente gli ingressi dell''abbonamento se presenti. Cerca la subscription tramite subscription_usages (più affidabile), subscription_id, o client_id.';

