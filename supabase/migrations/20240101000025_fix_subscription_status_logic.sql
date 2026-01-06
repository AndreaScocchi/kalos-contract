-- Migration 0025: Fix subscription status logic
--
-- Obiettivo: Correggere la logica degli stati degli abbonamenti secondo i nuovi requisiti:
-- 1. "Completato": se non ha più prenotazioni disponibili (remaining_entries <= 0), 
--    indipendentemente dalla data di scadenza
-- 2. "Scaduto": se ha ancora prenotazioni disponibili MA è passata la data di scadenza
-- 3. "Attivo": se non è ancora scaduto E ha ancora prenotazioni disponibili
-- 4. "Annullato": solo se annullato manualmente (non viene modificato)
--
-- Logica:
-- - Se remaining_entries <= 0 -> 'completed' (indipendentemente da expires_at)
-- - Se remaining_entries > 0 o NULL (illimitato):
--   - Se expires_at < CURRENT_DATE -> 'expired'
--   - Se expires_at >= CURRENT_DATE -> 'active'
-- - Se status = 'canceled' -> non toccare

-- ============================================================================
-- 1. CORREZIONE COMPLETA DI TUTTI GLI ABBONAMENTI
-- ============================================================================

-- Calcola remaining_entries e aggiorna gli stati secondo la nuova logica
WITH usage_totals AS (
  SELECT 
    subscription_id,
    COALESCE(SUM(delta), 0) AS delta_sum
  FROM public.subscription_usages
  GROUP BY subscription_id
),
subscription_data AS (
  SELECT 
    s.id,
    s.status,
    s.expires_at,
    s.custom_entries,
    p.entries AS plan_entries,
    COALESCE(u.delta_sum, 0) AS used_entries
  FROM public.subscriptions s
  LEFT JOIN public.plans p ON p.id = s.plan_id
  LEFT JOIN usage_totals u ON u.subscription_id = s.id
  WHERE s.deleted_at IS NULL
    AND s.status != 'canceled'  -- Preserva i 'canceled'
),
subscription_status_calc AS (
  SELECT 
    id,
    CASE
      -- Se è illimitato (effective_entries IS NULL), calcola in base alla scadenza
      WHEN COALESCE(custom_entries, plan_entries) IS NULL THEN
        CASE
          WHEN expires_at < CURRENT_DATE THEN 'expired'::subscription_status
          ELSE 'active'::subscription_status
        END
      -- Se ha esaurito i posti (remaining_entries <= 0), imposta 'completed' 
      -- indipendentemente dalla data di scadenza
      WHEN (COALESCE(custom_entries, plan_entries) + used_entries) <= 0 THEN 'completed'::subscription_status
      -- Se ha ancora posti disponibili, calcola in base alla scadenza
      ELSE
        CASE
          WHEN expires_at < CURRENT_DATE THEN 'expired'::subscription_status
          ELSE 'active'::subscription_status
        END
    END AS new_status,
    status AS current_status
  FROM subscription_data
)
UPDATE public.subscriptions s
SET status = ssc.new_status
FROM subscription_status_calc ssc
WHERE s.id = ssc.id
  AND ssc.current_status != ssc.new_status;  -- Aggiorna solo se cambia

-- ============================================================================
-- 2. AGGIORNAMENTO FUNZIONE TRIGGER
-- ============================================================================

-- Aggiorna la funzione trigger per applicare la nuova logica
CREATE OR REPLACE FUNCTION "public"."auto_complete_expired_subscriptions"() 
RETURNS "trigger"
LANGUAGE "plpgsql"
SECURITY DEFINER
SET "search_path" TO 'public'
AS $$
DECLARE
  v_effective_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_plan_entries integer;
BEGIN
  -- Preserva lo stato 'canceled' (non modificare abbonamenti annullati manualmente)
  IF NEW.status = 'canceled' THEN
    RETURN NEW;
  END IF;
  
  -- Calcola effective_entries (custom_entries o entries dal plan)
  SELECT entries INTO v_plan_entries
  FROM plans
  WHERE id = NEW.plan_id;
  
  v_effective_entries := COALESCE(NEW.custom_entries, v_plan_entries);
  
  -- Se l'abbonamento è illimitato (effective_entries è NULL)
  IF v_effective_entries IS NULL THEN
    -- Calcola in base alla scadenza
    IF NEW.expires_at < CURRENT_DATE THEN
      NEW.status := 'expired';
    ELSE
      NEW.status := 'active';
    END IF;
    RETURN NEW;
  END IF;
  
  -- Calcola posti usati
  SELECT COALESCE(SUM(delta), 0) INTO v_used_entries
  FROM subscription_usages
  WHERE subscription_id = NEW.id;
  
  -- Calcola posti rimanenti
  v_remaining_entries := v_effective_entries + v_used_entries;
  
  -- Applica la nuova logica:
  -- 1. Se ha esaurito i posti -> 'completed' (indipendentemente dalla scadenza)
  IF v_remaining_entries <= 0 THEN
    NEW.status := 'completed';
  -- 2. Se ha ancora posti disponibili, calcola in base alla scadenza
  ELSIF NEW.expires_at < CURRENT_DATE THEN
    NEW.status := 'expired';
  ELSE
    NEW.status := 'active';
  END IF;
  
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."auto_complete_expired_subscriptions"() OWNER TO "postgres";

-- ============================================================================
-- 3. AGGIORNAMENTO TRIGGER
-- ============================================================================

-- Il trigger deve essere aggiornato per eseguire anche quando cambiano i subscription_usages
-- che potrebbero influenzare i remaining_entries. Per ora manteniamo il trigger esistente
-- che si attiva su INSERT/UPDATE di subscriptions.

-- Nota: Il trigger esistente viene mantenuto, ma la funzione è stata aggiornata
-- con la nuova logica. Per aggiornamenti automatici quando cambiano i subscription_usages,
-- potremmo aggiungere un trigger separato su subscription_usages in futuro se necessario.

-- ============================================================================
-- 4. COMMENTI ESPLICATIVI
-- ============================================================================

COMMENT ON FUNCTION "public"."auto_complete_expired_subscriptions"() IS 
'Funzione trigger che aggiorna automaticamente lo status degli abbonamenti secondo la logica:
- "Completato": se remaining_entries <= 0 (indipendentemente dalla scadenza)
- "Scaduto": se ha ancora prenotazioni disponibili MA è passata la data di scadenza
- "Attivo": se non è ancora scaduto E ha ancora prenotazioni disponibili
- "Annullato": preservato se impostato manualmente (status = canceled)';

-- ============================================================================
-- 5. AGGIORNAMENTO FUNZIONE staff_book_lesson
-- ============================================================================

-- Aggiorna staff_book_lesson per permettere abbonamenti 'expired' per lezioni passate
-- purché abbiano ancora entries disponibili
CREATE OR REPLACE FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_staff_id uuid := auth.uid();
  v_client clients%rowtype;
  v_lesson lessons%rowtype;
  v_sub subscriptions%rowtype;
  v_plan plans%rowtype;
  v_capacity integer;
  v_starts_at timestamptz;
  v_booking_deadline_minutes integer;
  v_is_individual boolean;
  v_assigned_client_id uuid;
  v_booked_count integer;
  v_booking_id uuid;
  v_total_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_reactivate_booking uuid;
  v_has_existing_usage boolean := false;
  v_cancel_restore_exists boolean := false;
  v_now timestamptz := now();
begin
  -- Verifica staff
  if not public.is_staff() then
    return jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
  end if;

  -- Verifica client
  select *
  into v_client
  from clients
  where id = p_client_id and deleted_at is null;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  end if;

  -- Lock lesson
  select capacity, starts_at, booking_deadline_minutes, is_individual, assigned_client_id
  into v_capacity, v_starts_at, v_booking_deadline_minutes, v_is_individual, v_assigned_client_id
  from lessons
  where id = p_lesson_id
    and deleted_at is null
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
  end if;

  -- Verifica lezione individuale
  if v_is_individual then
    if v_assigned_client_id IS NULL then
      return jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_ASSIGNED');
    end if;
    if v_assigned_client_id != p_client_id then
      return jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_ASSIGNED');
    end if;
  end if;

  -- Verifica prenotazione esistente
  select id into v_reactivate_booking
  from bookings
  where lesson_id = p_lesson_id
    and client_id = p_client_id
    and status = 'canceled'
  limit 1;

  -- Verifica capacità (solo per lezioni pubbliche)
  if not v_is_individual then
    select count(*) into v_booked_count
    from bookings
    where lesson_id = p_lesson_id
      and status = 'booked';

    if v_booked_count >= v_capacity then
      return jsonb_build_object('ok', false, 'reason', 'FULL');
    end if;
  end if;

  -- Verifica subscription se fornita
  if p_subscription_id is not null then
    -- Per lezioni passate: permette abbonamenti 'active' o 'expired' (purché abbiano entries disponibili)
    -- Per lezioni future: richiede solo 'active' e non scaduto
    if v_starts_at < v_now then
      -- Lezione passata: permette 'active' o 'expired' (ma non 'completed' o 'canceled')
      select *
      into v_sub
      from subscriptions
      where id = p_subscription_id
        and client_id = p_client_id
        and status IN ('active', 'expired');
    else
      -- Lezione futura: richiede 'active' e non scaduto
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
    update bookings
    set status = 'booked',
        created_at = now(),
        subscription_id = p_subscription_id
    where id = v_reactivate_booking;
    v_booking_id := v_reactivate_booking;
  else
    -- Create new booking
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

COMMENT ON FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid") IS 
'Prenota una lezione per un cliente (staff only). Usa sempre client_id.
Per lezioni passate, permette abbonamenti con status "active" o "expired" purché abbiano entries disponibili.
Per lezioni future, richiede abbonamenti "active" e non scaduti.';

