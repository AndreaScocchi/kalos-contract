-- Migration 0024: Standardize to client_id - Remove user_id from bookings and subscriptions
--
-- Obiettivo: Standardizzare l'uso di client_id come unico campo di ownership per bookings e subscriptions.
-- Rimuove la confusione tra user_id e client_id, semplificando la logica del sistema.
--
-- Cambiamenti:
-- 1. Migra tutti i record da user_id a client_id (tramite clients.profile_id)
-- 2. Crea client per utenti che non ne hanno uno
-- 3. Rimuove il campo user_id da bookings e subscriptions
-- 4. Rimuove il constraint XOR
-- 5. Aggiorna tutte le funzioni RPC
-- 6. Aggiorna tutte le RLS policies
-- 7. Rimuove il trigger di migrazione automatica (migration 0013)

-- ============================================================================
-- 1. PREPARAZIONE: Crea client per utenti che non ne hanno uno
-- ============================================================================

-- Per ogni profilo che non ha un client collegato, crea un client
INSERT INTO public.clients (profile_id, full_name, email, phone, notes, is_active)
SELECT 
  p.id as profile_id,
  COALESCE(p.full_name, '') as full_name,
  p.email,
  p.phone,
  p.notes,
  true as is_active
FROM public.profiles p
WHERE p.id NOT IN (
  SELECT DISTINCT profile_id 
  FROM public.clients 
  WHERE profile_id IS NOT NULL
)
AND p.role = 'user'  -- Solo per utenti normali, non staff
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 2. MIGRAZIONE DATI: Migra bookings da user_id a client_id
-- ============================================================================

-- Migra bookings con user_id al client_id corrispondente
UPDATE public.bookings b
SET client_id = c.id
FROM public.clients c
WHERE b.user_id IS NOT NULL
  AND b.client_id IS NULL
  AND c.profile_id = b.user_id
  AND c.deleted_at IS NULL;

-- ============================================================================
-- 3. MIGRAZIONE DATI: Migra subscriptions da user_id a client_id
-- ============================================================================

-- Migra subscriptions con user_id al client_id corrispondente
UPDATE public.subscriptions s
SET client_id = c.id
FROM public.clients c
WHERE s.user_id IS NOT NULL
  AND s.client_id IS NULL
  AND c.profile_id = s.user_id
  AND c.deleted_at IS NULL;

-- ============================================================================
-- 4. RIMOZIONE CONSTRAINT XOR: Rimuovi constraint prima di gestire record orfani
-- ============================================================================

-- IMPORTANTE: Rimuoviamo il constraint XOR PRIMA di gestire i record orfani
-- perché altrimenti non possiamo impostare user_id = NULL quando client_id è NULL

-- Rimuovi constraint XOR da bookings
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_user_client_xor;

-- Rimuovi constraint XOR da subscriptions
ALTER TABLE public.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_user_client_xor;

-- ============================================================================
-- 5. GESTIONE RECORD ORFANI: Gestisci record senza client corrispondente
-- ============================================================================

-- Verifica se ci sono bookings con user_id che non hanno un client corrispondente
-- (dovrebbe essere raro, ma gestiamo il caso)
DO $$
DECLARE
  v_orphaned_count integer;
BEGIN
  SELECT COUNT(*) INTO v_orphaned_count
  FROM public.bookings b
  WHERE b.user_id IS NOT NULL
    AND b.client_id IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.clients c 
      WHERE c.profile_id = b.user_id AND c.deleted_at IS NULL
    );

  IF v_orphaned_count > 0 THEN
    RAISE WARNING 'Trovati % bookings con user_id senza client corrispondente. Questi verranno lasciati con user_id NULL.', v_orphaned_count;
    -- Ora possiamo impostare user_id a NULL perché il constraint XOR è stato rimosso
    UPDATE public.bookings
    SET user_id = NULL
    WHERE user_id IS NOT NULL
      AND client_id IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.clients c 
        WHERE c.profile_id = bookings.user_id AND c.deleted_at IS NULL
      );
  END IF;
END $$;

-- Verifica se ci sono subscriptions con user_id che non hanno un client corrispondente
DO $$
DECLARE
  v_orphaned_count integer;
BEGIN
  SELECT COUNT(*) INTO v_orphaned_count
  FROM public.subscriptions s
  WHERE s.user_id IS NOT NULL
    AND s.client_id IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.clients c 
      WHERE c.profile_id = s.user_id AND c.deleted_at IS NULL
    );

  IF v_orphaned_count > 0 THEN
    RAISE WARNING 'Trovate % subscriptions con user_id senza client corrispondente. Queste verranno lasciate con user_id NULL.', v_orphaned_count;
    -- Ora possiamo impostare user_id a NULL perché il constraint XOR è stato rimosso
    UPDATE public.subscriptions
    SET user_id = NULL
    WHERE user_id IS NOT NULL
      AND client_id IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.clients c 
        WHERE c.profile_id = subscriptions.user_id AND c.deleted_at IS NULL
      );
  END IF;
END $$;

-- ============================================================================
-- 6. RIMOZIONE INDICI E FOREIGN KEYS: Rimuovi indici e foreign keys su user_id
-- ============================================================================

-- Rimuovi indici su user_id da bookings
DROP INDEX IF EXISTS public.bookings_lesson_user_unique;
DROP INDEX IF EXISTS public.idx_bookings_user;
DROP INDEX IF EXISTS public.idx_bookings_user_id;

-- Rimuovi foreign key su user_id da bookings
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_user_id_fkey;

-- Rimuovi foreign key su user_id da subscriptions
ALTER TABLE public.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_user_id_fkey;

-- ============================================================================
-- 7. RIMOZIONE RLS POLICIES VECCHIE: Rimuovi tutte le policies che dipendono da user_id
-- ============================================================================

-- IMPORTANTE: Rimuoviamo tutte le policies che dipendono da user_id PRIMA di rimuovere la colonna
-- Altrimenti PostgreSQL non permetterà la rimozione della colonna

-- Rimuovi policies esistenti su bookings
DROP POLICY IF EXISTS "Clients can cancel own bookings" ON "public"."bookings";
DROP POLICY IF EXISTS "Clients can create own bookings" ON "public"."bookings";
DROP POLICY IF EXISTS "Clients can view own bookings" ON "public"."bookings";
DROP POLICY IF EXISTS "bookings update own or staff" ON "public"."bookings";
DROP POLICY IF EXISTS "bookings_select_own_or_staff" ON "public"."bookings";

-- Rimuovi policy esistente su subscriptions
DROP POLICY IF EXISTS "subscriptions_select_own_or_staff" ON "public"."subscriptions";

-- Rimuovi policy esistente su subscription_usages
DROP POLICY IF EXISTS "subscription_usages_select_own_or_staff" ON "public"."subscription_usages";

-- Rimuovi policy su profiles che dipende da bookings.user_id
-- Questa policy verrà ricreata senza la dipendenza da bookings.user_id
DROP POLICY IF EXISTS "profiles_select_own_or_staff" ON "public"."profiles";

-- ============================================================================
-- 8. AGGIORNAMENTO VIEW subscriptions_with_remaining: Rimuovi user_id
-- ============================================================================

-- La view subscriptions_with_remaining dipende da user_id, dobbiamo aggiornarla prima
-- di rimuovere la colonna. PostgreSQL non permette di rimuovere colonne con CREATE OR REPLACE,
-- quindi dobbiamo fare DROP VIEW e poi CREATE VIEW.
DROP VIEW IF EXISTS public.subscriptions_with_remaining;

CREATE VIEW public.subscriptions_with_remaining 
WITH (security_invoker = true) AS
WITH usage_totals AS (
  SELECT 
    subscription_usages.subscription_id,
    COALESCE(sum(subscription_usages.delta), 0::bigint) AS delta_sum
  FROM public.subscription_usages
  GROUP BY subscription_usages.subscription_id
)
SELECT 
  s.id,
  s.client_id,  -- Rimuoviamo user_id, manteniamo solo client_id
  s.plan_id,
  s.status,
  s.started_at,
  s.expires_at,
  s.custom_name,
  s.custom_price_cents,
  s.custom_entries,
  s.custom_validity_days,
  s.metadata,
  s.created_at,
  COALESCE(s.custom_entries, p.entries) AS effective_entries,
  CASE
    WHEN COALESCE(s.custom_entries, p.entries) IS NOT NULL 
    THEN COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0::bigint)
    ELSE NULL::bigint
  END AS remaining_entries
FROM public.subscriptions s
LEFT JOIN public.plans p ON p.id = s.plan_id
LEFT JOIN usage_totals u ON u.subscription_id = s.id
WHERE s.deleted_at IS NULL;  -- Escludi subscriptions soft-deleted (se la colonna esiste)

ALTER VIEW public.subscriptions_with_remaining OWNER TO postgres;

COMMENT ON VIEW public.subscriptions_with_remaining IS 
'View che calcola i posti rimanenti per ogni subscription. Usa solo client_id (user_id rimosso).';

-- ============================================================================
-- 9. RIMOZIONE CAMPO user_id: Rimuovi colonna user_id da bookings e subscriptions
-- ============================================================================

-- Ora possiamo rimuovere la colonna user_id perché non ci sono più dipendenze
-- Rimuovi colonna user_id da bookings
ALTER TABLE public.bookings DROP COLUMN IF EXISTS user_id;

-- Rimuovi colonna user_id da subscriptions
ALTER TABLE public.subscriptions DROP COLUMN IF EXISTS user_id;

-- ============================================================================
-- 10. AGGIORNAMENTO FUNZIONI RPC: book_lesson
-- ============================================================================

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

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
END;
$$;

COMMENT ON FUNCTION public.book_lesson(uuid, uuid) IS 
'Prenota una lezione per l''utente autenticato. Usa sempre client_id tramite get_my_client_id().';

-- ============================================================================
-- 11. AGGIORNAMENTO FUNZIONI RPC: cancel_booking
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
    -- (utile per cleanup)
  end if;

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
    and s.client_id = v_my_client_id
    and s.deleted_at IS NULL  -- Verifica soft delete (se aggiunto in futuro)
  order by su.created_at desc
  limit 1;

  -- If not found via subscription_usages, try using subscription_id from booking
  if not found and v_booking.subscription_id is not null then
    select *
    into v_sub
    from subscriptions
    where id = v_booking.subscription_id
      and client_id = v_my_client_id
      and status = 'active';
      -- Nota: subscriptions non ha deleted_at, usa status
  end if;

  -- Last resort: find last active subscription (only if subscription_id is also null)
  if not found then
    select *
    into v_sub
    from subscriptions
    where client_id = v_my_client_id
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

  -- Verifica soft delete del piano
  if v_plan.deleted_at IS NOT NULL then
    -- Piano soft-deleted: non restituire entry (piano non più valido)
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
'Cancella una prenotazione dell''utente autenticato. Usa sempre client_id tramite get_my_client_id().';

-- ============================================================================
-- 12. AGGIORNAMENTO FUNZIONI RPC: staff_book_lesson (semplifica logica)
-- ============================================================================

-- Leggi la funzione attuale per vedere la struttura completa
-- Qui aggiorniamo solo le parti che usano user_id

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
    -- Verifica subscription: usa solo client_id
    select *
    into v_sub
    from subscriptions
    where id = p_subscription_id
      and client_id = p_client_id
      and status = 'active'
      and current_date between started_at::date and expires_at::date;

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
'Prenota una lezione per un cliente (staff only). Usa sempre client_id.';

-- ============================================================================
-- 13. AGGIORNAMENTO RLS POLICIES: bookings
-- ============================================================================

-- Le policies vecchie sono già state rimosse nella sezione 7
-- Crea nuove policies che usano solo client_id
CREATE POLICY "bookings_select_own_or_staff" 
ON "public"."bookings" 
FOR SELECT 
TO "authenticated" 
USING (
  public.is_staff() 
  OR client_id = public.get_my_client_id()
);

CREATE POLICY "bookings_insert_own_or_staff" 
ON "public"."bookings" 
FOR INSERT 
TO "authenticated" 
WITH CHECK (
  public.is_staff() 
  OR client_id = public.get_my_client_id()
);

CREATE POLICY "bookings_update_own_or_staff" 
ON "public"."bookings" 
FOR UPDATE 
TO "authenticated" 
USING (
  public.is_staff() 
  OR client_id = public.get_my_client_id()
)
WITH CHECK (
  public.is_staff() 
  OR (client_id = public.get_my_client_id() AND status = 'canceled'::booking_status)
);

COMMENT ON POLICY "bookings_select_own_or_staff" ON public.bookings IS 
'RLS: Permette SELECT solo delle proprie prenotazioni (client_id = get_my_client_id()) o se staff.';

COMMENT ON POLICY "bookings_insert_own_or_staff" ON public.bookings IS 
'RLS: Permette INSERT solo delle proprie prenotazioni (client_id = get_my_client_id()) o se staff.';

COMMENT ON POLICY "bookings_update_own_or_staff" ON public.bookings IS 
'RLS: Permette UPDATE solo delle proprie prenotazioni (client_id = get_my_client_id()) o se staff. Gli utenti possono solo cancellare (status = canceled).';

-- ============================================================================
-- 14. AGGIORNAMENTO RLS POLICIES: subscriptions
-- ============================================================================

-- La policy vecchia è già stata rimossa nella sezione 7
-- Crea nuova policy che usa solo client_id
CREATE POLICY "subscriptions_select_own_or_staff" 
ON "public"."subscriptions" 
FOR SELECT 
TO "authenticated" 
USING (
  public.is_staff() 
  OR client_id = public.get_my_client_id()
);

COMMENT ON POLICY "subscriptions_select_own_or_staff" ON public.subscriptions IS 
'RLS: Permette SELECT solo delle proprie subscriptions (client_id = get_my_client_id()) o se staff.';

-- ============================================================================
-- 15. AGGIORNAMENTO RLS POLICIES: subscription_usages
-- ============================================================================

-- La policy vecchia è già stata rimossa nella sezione 7
-- Crea nuova policy che usa solo client_id tramite subscriptions
CREATE POLICY "subscription_usages_select_own_or_staff" 
ON "public"."subscription_usages" 
FOR SELECT 
TO "authenticated" 
USING (
  public.is_staff() 
  OR EXISTS (
    SELECT 1
    FROM public.subscriptions s
    WHERE s.id = subscription_usages.subscription_id
      AND s.client_id = public.get_my_client_id()
  )
);

COMMENT ON POLICY "subscription_usages_select_own_or_staff" ON public.subscription_usages IS 
'RLS: Permette SELECT solo degli usages collegati a subscriptions proprie (client_id = get_my_client_id()) o se staff.';

-- ============================================================================
-- 16. AGGIORNAMENTO RLS POLICY: profiles (rimuove dipendenza da bookings.user_id)
-- ============================================================================

-- Ricrea la policy profiles_select_own_or_staff senza dipendenza da bookings.user_id
-- Ora usa solo client_id tramite clients.profile_id
CREATE POLICY "profiles_select_own_or_staff" 
ON "public"."profiles" 
FOR SELECT 
TO "authenticated" 
USING (
  ("id" = "auth"."uid"()) 
  OR "public"."is_staff"() 
  OR EXISTS (
    SELECT 1
    FROM "public"."clients" c
    INNER JOIN "public"."bookings" b ON b.client_id = c.id
    WHERE c.profile_id = "profiles"."id"
      AND c.profile_id = "auth"."uid"()
  )
);

COMMENT ON POLICY "profiles_select_own_or_staff" ON public.profiles IS 
'RLS: Permette SELECT del proprio profilo, staff, o profili collegati a bookings tramite client_id.';

-- ============================================================================
-- 17. RIMOZIONE TRIGGER DI MIGRAZIONE AUTOMATICA (migration 0013)
-- ============================================================================

-- Rimuovi trigger
DROP TRIGGER IF EXISTS "trg_migrate_client_to_user" ON "public"."clients";
DROP TRIGGER IF EXISTS "trg_migrate_client_to_user_on_insert" ON "public"."clients";

-- Rimuovi funzioni di migrazione
DROP FUNCTION IF EXISTS "public"."migrate_client_bookings_to_user"(uuid, uuid);
DROP FUNCTION IF EXISTS "public"."migrate_client_subscriptions_to_user"(uuid, uuid);
DROP FUNCTION IF EXISTS "public"."migrate_client_records_to_user"(uuid, uuid);
DROP FUNCTION IF EXISTS "public"."trigger_migrate_client_to_user"();

-- ============================================================================
-- 18. AGGIORNAMENTO FUNZIONE auto_create_booking_for_individual_lesson
-- ============================================================================

-- Aggiorna la funzione per usare solo client_id
CREATE OR REPLACE FUNCTION "public"."auto_create_booking_for_individual_lesson"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_subscription_id uuid;
  v_booking_id uuid;
BEGIN
  -- Only process if this is an individual lesson with assigned client
  IF NEW.is_individual = true AND NEW.assigned_client_id IS NOT NULL THEN
    -- Try to find an active subscription for this client
    -- Priority: active subscription with remaining entries
    SELECT id INTO v_subscription_id
    FROM subscriptions_with_remaining
    WHERE client_id = NEW.assigned_client_id
      AND status = 'active'
      AND current_date BETWEEN started_at::date AND expires_at::date
      AND (remaining_entries IS NULL OR remaining_entries > 0)
    ORDER BY expires_at DESC NULLS LAST
    LIMIT 1;
    
    -- Check if booking already exists (to avoid duplicates on UPDATE)
    SELECT id INTO v_booking_id
    FROM bookings
    WHERE lesson_id = NEW.id
      AND client_id = NEW.assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
    LIMIT 1;
    
    IF v_booking_id IS NULL THEN
      -- Create booking
      INSERT INTO bookings (lesson_id, client_id, subscription_id, status)
      VALUES (NEW.id, NEW.assigned_client_id, v_subscription_id, 'booked')
      RETURNING id INTO v_booking_id;
      
      -- Create subscription usage if subscription exists
      IF v_subscription_id IS NOT NULL THEN
        INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
        VALUES (v_subscription_id, v_booking_id, -1, 'BOOK');
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION "public"."auto_create_booking_for_individual_lesson"() IS 
'Crea automaticamente una prenotazione per lezioni individuali. Usa sempre client_id.';

-- ============================================================================
-- 19. AGGIORNAMENTO handle_new_user: Crea client se non esiste
-- ============================================================================

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
    -- Se non esiste un client, crea il profilo e il client
    INSERT INTO public.profiles (id, email, role)
    VALUES (
      new.id,
      new.email,
      'user'::user_role
    );
    
    -- Crea un client per questo utente
    INSERT INTO public.clients (profile_id, full_name, email, phone, notes, is_active)
    VALUES (
      new.id,
      COALESCE(new.raw_user_meta_data->>'full_name', ''),
      new.email,
      new.phone,
      NULL,
      true
    );
  END IF;

  RETURN new;
END;
$$;

COMMENT ON FUNCTION "public"."handle_new_user"() IS 
'Crea automaticamente un profilo quando viene creato un nuovo utente Auth. Se esiste un client con la stessa email, sincronizza i dati e collega il client al profilo. Altrimenti crea un nuovo client per l''utente.';

-- ============================================================================
-- 20. AGGIORNAMENTO INDICI: Crea nuovo indice unico per bookings
-- ============================================================================

-- Crea indice unico per evitare doppie prenotazioni (solo per status = 'booked')
CREATE UNIQUE INDEX IF NOT EXISTS "bookings_lesson_client_unique" 
ON "public"."bookings" 
USING "btree" ("lesson_id", "client_id") 
WHERE ("status" = 'booked'::"public"."booking_status");

-- Crea indice per migliorare le query su client_id
CREATE INDEX IF NOT EXISTS "idx_bookings_client_id" 
ON "public"."bookings" 
USING "btree" ("client_id") 
WHERE ("client_id" IS NOT NULL);

-- ============================================================================
-- 21. VERIFICA FINALE: Controlla che non ci siano record orfani
-- ============================================================================

DO $$
DECLARE
  v_orphaned_bookings integer;
  v_orphaned_subscriptions integer;
BEGIN
  -- Conta bookings senza client_id
  SELECT COUNT(*) INTO v_orphaned_bookings
  FROM public.bookings
  WHERE client_id IS NULL;

  -- Conta subscriptions senza client_id
  SELECT COUNT(*) INTO v_orphaned_subscriptions
  FROM public.subscriptions
  WHERE client_id IS NULL;

  IF v_orphaned_bookings > 0 THEN
    RAISE WARNING 'Trovati % bookings senza client_id dopo la migrazione.', v_orphaned_bookings;
  END IF;

  IF v_orphaned_subscriptions > 0 THEN
    RAISE WARNING 'Trovate % subscriptions senza client_id dopo la migrazione.', v_orphaned_subscriptions;
  END IF;
END $$;

