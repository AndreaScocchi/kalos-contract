-- Migration 0001: Functions and Triggers

CREATE OR REPLACE FUNCTION "public"."auto_create_booking_for_individual_lesson"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client_profile_id uuid;
  v_subscription_id uuid;
  v_booking_id uuid;
BEGIN
  -- Only process if this is an individual lesson with assigned client
  IF NEW.is_individual = true AND NEW.assigned_client_id IS NOT NULL THEN
    -- Get client's profile_id if available
    SELECT profile_id INTO v_client_profile_id
    FROM clients
    WHERE id = NEW.assigned_client_id AND deleted_at IS NULL;
    
    -- Try to find an active subscription for this client
    -- Priority: active subscription with remaining entries
    IF v_client_profile_id IS NOT NULL THEN
      -- Client has account: check both client_id and user_id subscriptions
      SELECT id INTO v_subscription_id
      FROM subscriptions_with_remaining
      WHERE (
        (client_id = NEW.assigned_client_id) OR (user_id = v_client_profile_id)
      )
      AND status = 'active'
      AND current_date BETWEEN started_at::date AND expires_at::date
      AND (remaining_entries IS NULL OR remaining_entries > 0)
      ORDER BY expires_at DESC NULLS LAST
      LIMIT 1;
    ELSE
      -- Client without account: check only client_id subscriptions
      SELECT id INTO v_subscription_id
      FROM subscriptions_with_remaining
      WHERE client_id = NEW.assigned_client_id
      AND status = 'active'
      AND current_date BETWEEN started_at::date AND expires_at::date
      AND (remaining_entries IS NULL OR remaining_entries > 0)
      ORDER BY expires_at DESC NULLS LAST
      LIMIT 1;
    END IF;
    
    -- Check if booking already exists (to avoid duplicates on UPDATE)
    SELECT id INTO v_booking_id
    FROM bookings
    WHERE lesson_id = NEW.id
    AND (
      (client_id = NEW.assigned_client_id) OR
      (v_client_profile_id IS NOT NULL AND user_id = v_client_profile_id)
    )
    AND status IN ('booked', 'attended', 'no_show')
    LIMIT 1;
    
    -- Create booking if it doesn't exist
    IF v_booking_id IS NULL THEN
      INSERT INTO bookings (lesson_id, client_id, subscription_id, status)
      VALUES (NEW.id, NEW.assigned_client_id, v_subscription_id, 'booked')
      RETURNING id INTO v_booking_id;
      
      -- Handle subscription usage if subscription was found
      IF v_subscription_id IS NOT NULL THEN
        -- Check if subscription has limited entries
        DECLARE
          v_total_entries integer;
        BEGIN
          SELECT COALESCE(s.custom_entries, p.entries) INTO v_total_entries
          FROM subscriptions s
          LEFT JOIN plans p ON p.id = s.plan_id
          WHERE s.id = v_subscription_id;
          
          -- Only create usage record if subscription has limited entries
          IF v_total_entries IS NOT NULL THEN
            INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
            VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_auto_booking');
          END IF;
        END;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;
ALTER FUNCTION "public"."auto_create_booking_for_individual_lesson"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  SELECT capacity, starts_at, booking_deadline_minutes, is_individual, assigned_client_id
  INTO v_capacity, v_starts_at, v_booking_deadline_minutes, v_is_individual, v_assigned_client_id
  FROM public.lessons
  WHERE id = p_lesson_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  END IF;

  v_my_client_id := public.get_my_client_id();

  -- =========================
  -- INDIVIDUAL LESSON
  -- =========================
  IF v_is_individual = true THEN
    IF v_assigned_client_id IS NULL
       OR v_my_client_id IS DISTINCT FROM v_assigned_client_id THEN
      -- non leakare informazioni
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
      AND user_id = v_user_id
      AND status = 'booked'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
  END IF;

  SELECT count(*) INTO v_booked_count
  FROM public.bookings
  WHERE lesson_id = p_lesson_id
    AND status = 'booked';

  IF v_booked_count >= v_capacity THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
  END IF;

  INSERT INTO public.bookings (lesson_id, user_id, subscription_id, status)
  VALUES (p_lesson_id, v_user_id, p_subscription_id, 'booked')
  RETURNING id INTO v_booking_id;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
END;
$$;
ALTER FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."can_access_finance"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    return exists (
        select 1 from public.profiles
        where id = auth.uid()
        and role in ('admin', 'finance')
    );
end;
$$;
ALTER FUNCTION "public"."can_access_finance"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_booking bookings%rowtype;
  v_lesson lessons%rowtype;
  v_now timestamptz := now();
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_total_entries integer;
  v_cancel_restore_exists boolean := false;
begin
  select *
  into v_booking
  from bookings
  where id = p_booking_id
    and user_id = auth.uid();

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

  if v_now > v_lesson.starts_at - make_interval(mins => coalesce(v_lesson.cancel_deadline_minutes, 120)) then
    return jsonb_build_object('ok', false, 'reason', 'CANCEL_DEADLINE_PASSED');
  end if;

  update bookings
  set status = 'canceled'
  where id = p_booking_id;

  -- First, try to find subscription via subscription_usages (most reliable)
  select s.*
  into v_sub
  from subscription_usages su
  join subscriptions s on s.id = su.subscription_id
  where su.booking_id = p_booking_id
    and su.delta = -1
    and s.user_id = auth.uid()
  order by su.created_at desc
  limit 1;

  -- If not found via subscription_usages, try using subscription_id from booking
  if not found and v_booking.subscription_id is not null then
    select *
    into v_sub
    from subscriptions
    where id = v_booking.subscription_id
      and user_id = auth.uid()
      and status = 'active';
  end if;

  -- Last resort: find last active subscription (only if subscription_id is also null)
  if not found then
    select *
    into v_sub
    from subscriptions
    where user_id = auth.uid()
      and status = 'active'
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
ALTER FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."create_user_profile"("user_id" "uuid", "full_name" "text", "phone" "text" DEFAULT NULL::"text", "role" "public"."user_role" DEFAULT 'user'::"public"."user_role") RETURNS "public"."profiles"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  new_profile profiles;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() 
    AND role IN ('operator', 'admin')
  ) THEN
    RAISE EXCEPTION 'Solo operatori e amministratori possono creare profili utente';
  END IF;

  -- Use UPSERT: insert or update if already exists (from trigger)
  INSERT INTO profiles (id, full_name, email, phone, role)
  VALUES (user_id, full_name, (SELECT email FROM auth.users WHERE id = user_id), phone, role)
  ON CONFLICT (id) DO UPDATE
  SET
    full_name = excluded.full_name,
    email = excluded.email,
    phone = excluded.phone,
    role = excluded.role
  RETURNING * INTO new_profile;

  RETURN new_profile;
END;
$$;
ALTER FUNCTION "public"."create_user_profile"("user_id" "uuid", "full_name" "text", "phone" "text", "role" "public"."user_role") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."get_financial_kpis"("p_month_start" "date" DEFAULT ("date_trunc"('month'::"text", (CURRENT_DATE)::timestamp with time zone))::"date", "p_month_end" "date" DEFAULT (("date_trunc"('month'::"text", (CURRENT_DATE)::timestamp with time zone) + '1 mon -1 days'::interval))::"date") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_result json;
    v_revenue_from_lessons numeric := 0;
    v_revenue_from_events numeric := 0;
    v_revenue_from_subscriptions numeric := 0;
    v_total_revenue numeric;
    v_expenses numeric;
    v_fixed_expenses numeric;
    v_variable_expenses numeric;
    v_margin numeric;
    v_payments_count integer;
begin
    -- Check access
    if not can_access_finance() then
        raise exception 'Access denied: finance role required';
    end if;

    -- Revenue from lessons: bookings with subscriptions
    -- Calculation: subscription custom_price_cents / custom_entries OR plan.price_cents / plan.entries
    select coalesce(sum(lesson_revenue), 0) into v_revenue_from_lessons
    from (
        select 
            case 
                when s.custom_price_cents is not null 
                     and s.custom_entries is not null 
                     and s.custom_entries > 0
                    then round(s.custom_price_cents::numeric / s.custom_entries)
                when p.price_cents is not null 
                     and p.entries is not null 
                     and p.entries > 0
                    then round(p.price_cents::numeric / p.entries)
                else 0
            end as lesson_revenue
        from bookings b
        join lessons l on l.id = b.lesson_id
        left join subscriptions s on s.id = b.subscription_id
        left join plans p on p.id = s.plan_id
        where b.status in ('booked', 'attended', 'no_show')
          and l.starts_at >= p_month_start::timestamp
          and l.starts_at < (p_month_end + interval '1 day')::timestamp
          and b.subscription_id is not null
    ) lesson_revenues;

    -- Revenue from events: event_bookings * event.price_cents
    select coalesce(sum(e.price_cents), 0) into v_revenue_from_events
    from event_bookings eb
    join events e on e.id = eb.event_id
    where eb.status in ('booked', 'attended', 'no_show')
      and e.starts_at >= p_month_start::timestamp
      and e.starts_at < (p_month_end + interval '1 day')::timestamp
      and e.price_cents is not null;

    -- Revenue from new subscriptions created in the month
    -- This counts the full subscription price when it's purchased/started
    select coalesce(sum(
        case 
            when s.custom_price_cents is not null then s.custom_price_cents
            when p.price_cents is not null then p.price_cents
            else 0
        end
    ), 0) into v_revenue_from_subscriptions
    from subscriptions s
    left join plans p on p.id = s.plan_id
    where s.started_at >= p_month_start::timestamp
      and s.started_at < (p_month_end + interval '1 day')::timestamp;

    v_total_revenue := v_revenue_from_lessons + v_revenue_from_events + v_revenue_from_subscriptions;

    -- Expenses (from expenses table - still manual)
    select coalesce(sum(amount_cents), 0) into v_expenses
    from expenses
    where expense_date >= p_month_start
      and expense_date <= p_month_end;

    select coalesce(sum(amount_cents), 0) into v_fixed_expenses
    from expenses
    where expense_date >= p_month_start
      and expense_date <= p_month_end
      and is_fixed = true;

    select coalesce(sum(amount_cents), 0) into v_variable_expenses
    from expenses
    where expense_date >= p_month_start
      and expense_date <= p_month_end
      and is_fixed = false;

    v_margin := v_total_revenue - v_expenses;

    -- Count of "payments" (bookings + events + subscriptions)
    select 
        (select count(distinct b.id) 
         from bookings b 
         join lessons l on l.id = b.lesson_id
         where b.status in ('booked', 'attended', 'no_show')
           and l.starts_at >= p_month_start::timestamp
           and l.starts_at < (p_month_end + interval '1 day')::timestamp
           and b.subscription_id is not null)
        +
        (select count(distinct eb.id) 
         from event_bookings eb 
         join events e on e.id = eb.event_id
         where eb.status in ('booked', 'attended', 'no_show')
           and e.starts_at >= p_month_start::timestamp
           and e.starts_at < (p_month_end + interval '1 day')::timestamp)
        +
        (select count(*) 
         from subscriptions 
         where started_at >= p_month_start::timestamp
           and started_at < (p_month_end + interval '1 day')::timestamp)
    into v_payments_count;

    select json_build_object(
        'revenue_cents', v_total_revenue::integer,
        'expenses_cents', v_expenses::integer,
        'fixed_expenses_cents', v_fixed_expenses::integer,
        'variable_expenses_cents', v_variable_expenses::integer,
        'margin_cents', v_margin::integer,
        'completed_payments_count', v_payments_count
    ) into v_result;

    return v_result;
end;
$$;
ALTER FUNCTION "public"."get_financial_kpis"("p_month_start" "date", "p_month_end" "date") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."get_my_client_id"() RETURNS "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT c.id
  FROM public.clients c
  WHERE c.profile_id = auth.uid()
  ORDER BY c.created_at DESC NULLS LAST
  LIMIT 1
$$;
ALTER FUNCTION "public"."get_my_client_id"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."get_revenue_breakdown"("p_month_start" "date" DEFAULT ("date_trunc"('month'::"text", (CURRENT_DATE)::timestamp with time zone))::"date", "p_month_end" "date" DEFAULT (("date_trunc"('month'::"text", (CURRENT_DATE)::timestamp with time zone) + '1 mon -1 days'::interval))::"date") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
    v_result json;
begin
    -- Check access
    if not can_access_finance() then
        raise exception 'Access denied: finance role required';
    end if;

    select json_build_object(
        'by_lesson', coalesce(
            (select json_agg(json_build_object(
                'lesson_id', lesson_id,
                'activity_name', activity_name,
                'total_cents', total_cents,
                'count', booking_count
            ))
            from (
                select 
                    l.id as lesson_id,
                    a.name as activity_name,
                    sum(case 
                        when s.custom_price_cents is not null 
                             and s.custom_entries is not null 
                             and s.custom_entries > 0
                            then round(s.custom_price_cents::numeric / s.custom_entries)
                        when p.price_cents is not null 
                             and p.entries is not null 
                             and p.entries > 0
                            then round(p.price_cents::numeric / p.entries)
                        else 0
                    end)::integer as total_cents,
                    count(b.id) as booking_count
                from bookings b
                join lessons l on l.id = b.lesson_id
                join activities a on a.id = l.activity_id
                left join subscriptions s on s.id = b.subscription_id
                left join plans p on p.id = s.plan_id
                where b.status in ('booked', 'attended', 'no_show')
                  and l.starts_at >= p_month_start::timestamp
                  and l.starts_at < (p_month_end + interval '1 day')::timestamp
                  and b.subscription_id is not null
                group by l.id, a.name
            ) lesson_revenue), '[]'::json),
        'by_event', coalesce(
            (select json_agg(json_build_object(
                'event_id', event_id,
                'event_name', event_name,
                'total_cents', total_cents,
                'count', booking_count
            ))
            from (
                select 
                    e.id as event_id,
                    e.name as event_name,
                    sum(e.price_cents)::integer as total_cents,
                    count(eb.id) as booking_count
                from event_bookings eb
                join events e on e.id = eb.event_id
                where eb.status in ('booked', 'attended', 'no_show')
                  and e.starts_at >= p_month_start::timestamp
                  and e.starts_at < (p_month_end + interval '1 day')::timestamp
                  and e.price_cents is not null
                group by e.id, e.name
            ) event_revenue), '[]'::json),
        'by_subscription', coalesce(
            (select json_agg(json_build_object(
                'subscription_id', subscription_id,
                'subscription_name', subscription_name,
                'total_cents', total_cents,
                'count', 1
            ))
            from (
                select 
                    s.id as subscription_id,
                    coalesce(s.custom_name, p.name, 'Abbonamento') as subscription_name,
                    case 
                        when s.custom_price_cents is not null then s.custom_price_cents
                        when p.price_cents is not null then p.price_cents
                        else 0
                    end as total_cents
                from subscriptions s
                left join plans p on p.id = s.plan_id
                where s.started_at >= p_month_start::timestamp
                  and s.started_at < (p_month_end + interval '1 day')::timestamp
            ) subscription_revenue), '[]'::json)
    ) into v_result;

    return v_result;
end;
$$;
ALTER FUNCTION "public"."get_revenue_breakdown"("p_month_start" "date", "p_month_end" "date") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."handle_individual_lesson_update"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client_profile_id uuid;
  v_subscription_id uuid;
  v_booking_id uuid;
  v_old_booking_id uuid;
BEGIN
  -- If lesson is being changed from individual to non-individual, clean up
  IF OLD.is_individual = true AND NEW.is_individual = false THEN
    -- Set assigned_client_id to NULL (this will be enforced by constraint)
    NEW.assigned_client_id := NULL;
    -- Note: We don't delete existing bookings, just remove the assignment
    -- Staff can manually manage bookings if needed
    RETURN NEW;
  END IF;
  
  -- If assigned_client_id is changing on an individual lesson
  IF NEW.is_individual = true AND NEW.assigned_client_id IS NOT NULL THEN
    -- If client changed, delete old booking and create new one
    IF OLD.assigned_client_id IS DISTINCT FROM NEW.assigned_client_id AND OLD.assigned_client_id IS NOT NULL THEN
      -- Find and delete old booking
      SELECT id INTO v_old_booking_id
      FROM bookings
      WHERE lesson_id = NEW.id
      AND client_id = OLD.assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
      LIMIT 1;
      
      IF v_old_booking_id IS NOT NULL THEN
        -- Cancel the old booking (this will restore subscription entries if applicable)
        -- We use the cancel_booking logic but as staff
        UPDATE bookings
        SET status = 'canceled'
        WHERE id = v_old_booking_id;
        
        -- Restore subscription entry if it was used
        UPDATE subscription_usages
        SET delta = +1, reason = 'individual_lesson_client_changed'
        WHERE booking_id = v_old_booking_id
        AND delta = -1
        AND NOT EXISTS (
          SELECT 1 FROM subscription_usages
          WHERE booking_id = v_old_booking_id
          AND delta = +1
          AND reason = 'individual_lesson_client_changed'
        );
      END IF;
    END IF;
    
    -- Create booking for new assigned client (if not exists)
    SELECT profile_id INTO v_client_profile_id
    FROM clients
    WHERE id = NEW.assigned_client_id AND deleted_at IS NULL;
    
    -- Check if booking already exists for new client
    IF v_client_profile_id IS NOT NULL THEN
      SELECT id INTO v_booking_id
      FROM bookings
      WHERE lesson_id = NEW.id
      AND (
        (client_id = NEW.assigned_client_id) OR (user_id = v_client_profile_id)
      )
      AND status IN ('booked', 'attended', 'no_show')
      LIMIT 1;
    ELSE
      SELECT id INTO v_booking_id
      FROM bookings
      WHERE lesson_id = NEW.id
      AND client_id = NEW.assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
      LIMIT 1;
    END IF;
    
    -- Create booking if it doesn't exist
    IF v_booking_id IS NULL THEN
      -- Find subscription for new client
      IF v_client_profile_id IS NOT NULL THEN
        SELECT id INTO v_subscription_id
        FROM subscriptions_with_remaining
        WHERE (
          (client_id = NEW.assigned_client_id) OR (user_id = v_client_profile_id)
        )
        AND status = 'active'
        AND current_date BETWEEN started_at::date AND expires_at::date
        AND (remaining_entries IS NULL OR remaining_entries > 0)
        ORDER BY expires_at DESC NULLS LAST
        LIMIT 1;
      ELSE
        SELECT id INTO v_subscription_id
        FROM subscriptions_with_remaining
        WHERE client_id = NEW.assigned_client_id
        AND status = 'active'
        AND current_date BETWEEN started_at::date AND expires_at::date
        AND (remaining_entries IS NULL OR remaining_entries > 0)
        ORDER BY expires_at DESC NULLS LAST
        LIMIT 1;
      END IF;
      
      INSERT INTO bookings (lesson_id, client_id, subscription_id, status)
      VALUES (NEW.id, NEW.assigned_client_id, v_subscription_id, 'booked')
      RETURNING id INTO v_booking_id;
      
      -- Handle subscription usage
      IF v_subscription_id IS NOT NULL THEN
        DECLARE
          v_total_entries integer;
        BEGIN
          SELECT COALESCE(s.custom_entries, p.entries) INTO v_total_entries
          FROM subscriptions s
          LEFT JOIN plans p ON p.id = s.plan_id
          WHERE s.id = v_subscription_id;
          
          IF v_total_entries IS NOT NULL THEN
            INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
            VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_auto_booking');
          END IF;
        END;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;
ALTER FUNCTION "public"."handle_individual_lesson_update"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client clients%rowtype;
BEGIN
  -- Cerca se esiste un client con la stessa email
  SELECT * INTO v_client
  FROM clients
  WHERE email = new.email
    AND deleted_at IS NULL
  LIMIT 1;

  -- Se esiste un client con la stessa email, sincronizza i dati
  IF FOUND THEN
    -- Inserisci il profilo con i dati dal client
    INSERT INTO public.profiles (
      id, 
      email, 
      role,
      full_name,
      phone,
      notes
    )
    VALUES (
      new.id,
      new.email,
      'user'::user_role,
      v_client.full_name,
      v_client.phone,
      v_client.notes
    );

    -- Aggiorna il client con il profile_id per collegarli
    UPDATE clients
    SET profile_id = new.id
    WHERE id = v_client.id;
  ELSE
    -- Se non esiste un client, crea solo il profilo minimale
    INSERT INTO public.profiles (id, email, role)
    VALUES (
      new.id,
      new.email,
      'user'::user_role
    );
  END IF;

  RETURN new;
END;
$$;
ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_role user_role;
begin
  -- Se non c'è un utente autenticato, ritorna false
  if auth.uid() is null then
    return false;
  end if;

  -- Recupera il ruolo dell'utente
  select role into v_role
  from profiles
  where id = auth.uid();

  -- Ritorna true solo se è admin
  return v_role = 'admin';
end;
$$;
ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."is_finance"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    return exists (
        select 1 from public.profiles
        where id = auth.uid()
        and role = 'finance'
    );
end;
$$;
ALTER FUNCTION "public"."is_finance"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."is_staff"() RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_role user_role;
begin
  -- Se non c'è un utente autenticato, ritorna false
  if auth.uid() is null then
    return false;
  end if;

  -- Recupera il ruolo dell'utente
  select role into v_role
  from profiles
  where id = auth.uid();

  -- Ritorna true se è operator o admin
  return v_role in ('operator', 'admin');
end;
$$;
ALTER FUNCTION "public"."is_staff"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."link_client_to_profile_by_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  -- se non c'è email sul profilo, non fare nulla
  if new.email is null then
    return new;
  end if;

  -- collega (solo se esiste un client con quella email e non è già collegato)
  update public.clients c
  set profile_id = new.id,
      updated_at = now()
  where c.email = new.email
    and c.deleted_at is null
    and (c.profile_id is null or c.profile_id <> new.id);

  return new;
end;
$$;
ALTER FUNCTION "public"."link_client_to_profile_by_email"() OWNER TO "postgres";
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

  -- Check booking deadline
  if v_booking_deadline_minutes is not null and v_booking_deadline_minutes > 0 then
    if v_now > (v_starts_at - (v_booking_deadline_minutes || ' minutes')::interval) then
      return jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
    end if;
  end if;

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
ALTER FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."staff_cancel_booking"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
  -- For now, we'll still enforce it, but this could be made configurable
  if v_lesson.cancel_deadline_minutes is not null then
    if v_now > v_lesson.starts_at - make_interval(mins => v_lesson.cancel_deadline_minutes) then
      -- Staff can still cancel, but log that deadline passed
      -- (we'll allow it but could return a warning)
    end if;
  end if;

  -- Update booking status
  update bookings
  set status = 'canceled'
  where id = p_booking_id;

  -- Handle subscription usage accounting if subscription exists
  if v_booking.subscription_id is not null then
    select *
    into v_sub
    from subscriptions
    where id = v_booking.subscription_id;

    if found then
      select *
      into v_plan
      from plans
      where id = v_sub.plan_id;

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
    end if;
  end if;

  return jsonb_build_object('ok', true, 'reason', 'CANCELED');
end;
$$;
ALTER FUNCTION "public"."staff_cancel_booking"("p_booking_id" "uuid") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."staff_update_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_staff_id uuid := auth.uid();
  v_booking bookings%rowtype;
begin
  -- Check if user is staff
  if not is_staff() then
    return jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
  end if;

  -- Get booking
  select *
  into v_booking
  from bookings
  where id = p_booking_id;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  end if;

  -- Validate status
  if p_status not in ('booked', 'attended', 'no_show', 'canceled') then
    return jsonb_build_object('ok', false, 'reason', 'INVALID_STATUS');
  end if;

  -- Note: For cancellations, we should use cancel_booking RPC to ensure proper
  -- subscription_usages accounting. But we'll allow it here for staff flexibility.
  -- If you want to enforce this, uncomment the check below:
  -- if p_status = 'canceled' then
  --   return jsonb_build_object('ok', false, 'reason', 'USE_CANCEL_BOOKING_RPC');
  -- end if;

  -- Update booking status
  update bookings
  set status = p_status
  where id = p_booking_id;

  return jsonb_build_object(
    'ok', true,
    'reason', 'UPDATED',
    'booking_id', p_booking_id
  );
end;
$$;
ALTER FUNCTION "public"."staff_update_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status") OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."sync_profile_from_client"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Se il client ha un profile_id, sincronizza i dati al profilo
  IF NEW.profile_id IS NOT NULL THEN
    UPDATE public.profiles
    SET 
      full_name = NEW.full_name,
      phone = NEW.phone,
      notes = NEW.notes,
      email = COALESCE(NEW.email, profiles.email) -- Mantieni l'email del profilo se il client non ha email
    WHERE id = NEW.profile_id;
  END IF;

  RETURN NEW;
END;
$$;
ALTER FUNCTION "public"."sync_profile_from_client"() OWNER TO "postgres";
CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;
ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";

