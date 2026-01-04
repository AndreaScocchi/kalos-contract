-- Migration 0018: Remove booking deadline check from staff_book_lesson
--
-- Obiettivo: Permettere allo staff di aggiungere prenotazioni anche per lezioni passate,
-- bypassando il controllo della booking deadline. Questo consente di registrare prenotazioni
-- retroattive o correggere errori.
--
-- Modifiche:
-- - Rimosso il controllo della booking deadline dalla funzione staff_book_lesson
-- - Lo staff può ora prenotare lezioni anche se la deadline è passata
-- - Gli altri controlli (capacità, abbonamento, ingressi disponibili) rimangono invariati

CREATE OR REPLACE FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_staff_id uuid := auth.uid();
  v_capacity integer;
  v_starts_at timestamptz;
  v_booking_deadline_minutes integer;
  v_now timestamptz := now();
  v_booked integer;
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_booking_id uuid;
  v_reactivate_booking uuid;
  v_has_existing_usage boolean := false;
  v_cancel_restore_exists boolean := false;
  v_total_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_client_profile_id uuid;
  v_is_individual boolean;
  v_assigned_client_id uuid;
begin
  -- Check if user is staff
  if not is_staff() then
    return jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
  end if;

  -- Validate client exists and get profile_id if available
  select profile_id into v_client_profile_id
  from clients
  where id = p_client_id and deleted_at is null;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  end if;

  -- Get lesson info including individual lesson fields
  select capacity, starts_at, booking_deadline_minutes, is_individual, assigned_client_id
  into v_capacity, v_starts_at, v_booking_deadline_minutes, v_is_individual, v_assigned_client_id
  from lessons
  where id = p_lesson_id
    and deleted_at is null
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  end if;

  -- Block booking if lesson is individual and client is not the assigned one
  if v_is_individual = true then
    if v_assigned_client_id IS NULL then
      return jsonb_build_object('ok', false, 'reason', 'INDIVIDUAL_LESSON_NO_CLIENT');
    end if;
    if v_assigned_client_id != p_client_id then
      -- Also check if client has profile_id that matches
      if v_client_profile_id IS NULL OR (
        -- Check if assigned client has a profile_id that matches
        NOT EXISTS (
          SELECT 1 FROM clients
          WHERE id = v_assigned_client_id
          AND profile_id = v_client_profile_id
        )
      ) then
        return jsonb_build_object('ok', false, 'reason', 'INDIVIDUAL_LESSON_WRONG_CLIENT');
      end if;
    end if;
  end if;

  -- Booking deadline check removed: staff can book past lessons
  -- The booking deadline check has been removed to allow staff to add bookings
  -- for past lessons, enabling retroactive booking and error corrections.

  -- Check if already booked
  -- If client has account, check both client_id and user_id (profile_id)
  if v_client_profile_id is not null then
    if exists (
      select 1 from bookings
      where lesson_id = p_lesson_id
        and (
          (client_id = p_client_id) or (user_id = v_client_profile_id)
        )
        and status = 'booked'
    ) then
      return jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    end if;
  else
    if exists (
      select 1 from bookings
      where lesson_id = p_lesson_id
        and client_id = p_client_id
        and status = 'booked'
    ) then
      return jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    end if;
  end if;

  -- Check capacity (for individual lessons, this should always be 1)
  select count(*)
  into v_booked
  from bookings
  where lesson_id = p_lesson_id
    and status = 'booked';

  if v_booked >= v_capacity then
    return jsonb_build_object('ok', false, 'reason', 'FULL');
  end if;

  -- Check for reactivated booking
  -- If client has account, check both client_id and user_id (profile_id)
  if v_client_profile_id is not null then
    select id
    into v_reactivate_booking
    from bookings
    where lesson_id = p_lesson_id
      and (
        (client_id = p_client_id) or (user_id = v_client_profile_id)
      )
      and status = 'canceled'
    for update
    limit 1;
  else
    select id
    into v_reactivate_booking
    from bookings
    where lesson_id = p_lesson_id
      and client_id = p_client_id
      and status = 'canceled'
    for update
    limit 1;
  end if;

  -- Handle subscription if provided
  if p_subscription_id is not null then
    -- Check subscription: if client has profile_id, check both client_id and user_id
    if v_client_profile_id is not null then
      -- Client has account: check both client_id and user_id (profile_id)
      select *
      into v_sub
      from subscriptions
      where id = p_subscription_id
        and (
          (client_id = p_client_id) or (user_id = v_client_profile_id)
        )
        and status = 'active'
        and current_date between started_at::date and expires_at::date;
    else
      -- Client without account: check only client_id
      select *
      into v_sub
      from subscriptions
      where id = p_subscription_id
        and client_id = p_client_id
        and status = 'active'
        and current_date between started_at::date and expires_at::date;
    end if;

    if not found then
      return jsonb_build_object('ok', false, 'reason', 'SUBSCRIPTION_NOT_FOUND_OR_INACTIVE');
    end if;

    -- Get plan info
    select *
    into v_plan
    from plans
    where id = v_sub.plan_id;

    v_total_entries := coalesce(v_sub.custom_entries, v_plan.entries);

    -- For unlimited subscriptions (v_total_entries is null), skip entry check
    if v_total_entries is not null then
      select coalesce(sum(delta), 0)
      into v_used_entries
      from subscription_usages
      where subscription_id = v_sub.id;

      v_remaining_entries := v_total_entries + v_used_entries;

      if v_remaining_entries <= 0 then
        return jsonb_build_object('ok', false, 'reason', 'NO_ENTRIES_LEFT');
      end if;
    end if;
  end if;

  -- Create or reactivate booking
  if v_reactivate_booking is not null then
    -- Reactivate existing canceled booking
    -- Keep the original user_id or client_id from the canceled booking
    -- (bookings table has XOR constraint: either user_id OR client_id, not both)
    update bookings
    set status = 'booked',
        created_at = now(),
        subscription_id = p_subscription_id
    where id = v_reactivate_booking;
    v_booking_id := v_reactivate_booking;
  else
    -- Create new booking
    -- For staff bookings, always use client_id (even if client has account)
    insert into bookings (lesson_id, client_id, subscription_id, status)
    values (p_lesson_id, p_client_id, p_subscription_id, 'booked')
    returning id into v_booking_id;
  end if;

  -- Handle subscription usage accounting (skip for unlimited subscriptions)
  if p_subscription_id is not null and v_total_entries is not null then
    if v_reactivate_booking is not null and v_has_existing_usage and v_cancel_restore_exists then
      -- Remove the restore entry if reactivating
      delete from subscription_usages
      where id = (
        select su.id
        from subscription_usages su
        where su.booking_id = v_reactivate_booking
          and su.delta = +1
        order by su.created_at desc
        limit 1
      );
    else
      insert into subscription_usages (subscription_id, booking_id, delta, reason)
      values (p_subscription_id, v_booking_id, -1, 'BOOK');
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
end;
$$;

