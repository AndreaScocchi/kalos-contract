-- Migration 20260922150000: Sessione 1 — chiusura delle esposizioni e permessi "tutto chiuso"
--
-- Obiettivo: chiudere le esposizioni trovate nell'audit del 2026-09-22 (docs/PIANO-APS-E-NUOVA-APP.md
-- §0) e riordinare lo strato dei permessi senza cambiare nomi né comportamento delle funzioni usate.
-- Il modello che ne risulta è descritto in ACCESS_MODEL.md; i test in supabase/tests/ lo verificano.
--
--   1. Tabelle: via le policy che aprivano clients, device_tokens e notification_logs ad anon.
--   2. profiles: nessuno può darsi un ruolo staff o cambiare l'email del proprio profilo.
--   3. Prenotazioni: le scritture dirette sono solo dello staff; i clienti passano dalle RPC.
--   4. Funzioni: controllo del ruolo dentro le Finanze e dentro queue_new_event.
--   5. Funzioni: "tutto chiuso" — anon e authenticated eseguono solo un elenco esplicito.
--   6. Default privileges: le funzioni create in futuro nascono chiuse.
--   7. Parità locale: il trigger on_auth_user_created, che in produzione c'è già.
--
-- Compatibilità: sito, gestionale e webapp non usano nulla di ciò che viene chiuso (verificato sul
-- codice di origin/main di ogni repo). Cron (utente postgres), trigger e RPC SECURITY DEFINER non
-- dipendono dai grant di anon/authenticated. Le edge function usano service_role, che mantiene
-- EXECUTE su tutte le funzioni.
--
-- migration-lint:allow revoke — reason: chiusura di esposizioni di sicurezza (audit 2026-09-22); nessun consumer usa gli accessi revocati, verificato su sito, gestionale, webapp ed edge function
-- migration-lint:allow truncate — reason: TRUNCATE compare solo come nome del privilegio revocato (REVOKE TRUNCATE ...), nessun dato viene cancellato

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 1. Tabelle
-- ─────────────────────────────────────────────────────────────────────────────────────────────

-- clients: nomi, email, telefoni, note e compleanni di tutti i clienti erano leggibili senza login.
DROP POLICY IF EXISTS "clients_anon_select" ON "public"."clients";
-- device_tokens: iscrizioni push leggibili e modificabili senza login.
DROP POLICY IF EXISTS "device_tokens_anon_all" ON "public"."device_tokens";
-- notification_logs: storico notifiche (titoli e testi con i nomi) leggibile e modificabile senza login.
DROP POLICY IF EXISTS "notification_logs_anon_all" ON "public"."notification_logs";

-- Nessuna di queste tabelle serve ad anon: la webapp le legge solo da utente loggato, le edge
-- function con service_role. announcements era già vuota per anon (nessuna policy).
REVOKE ALL ON TABLE
  "public"."clients",
  "public"."device_tokens",
  "public"."notification_logs",
  "public"."notification_queue",
  "public"."notification_preferences",
  "public"."announcements"
FROM "anon";

-- Stima delle entrate mensili: con security_invoker la vedeva anche un'operatrice (le Finanze sono
-- solo per admin e Tesoriere). Nessun consumer la usa.
REVOKE ALL ON TABLE "public"."financial_monthly_summary" FROM "anon", "authenticated";

-- Privilegi che l'API non usa mai.
REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA "public" FROM "anon", "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 2. profiles: ruolo ed email protetti
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Prima di questa migrazione chiunque si registrasse poteva scrivere role = 'admin' sul proprio
-- profilo, e cambiandone l'email farsi collegare la scheda cliente di un'altra persona
-- (trigger link_client_to_profile_by_email). La webapp aggiorna solo full_name e phone; il
-- gestionale cambia i ruoli con la RPC promote_profile_to_operator.

CREATE OR REPLACE FUNCTION "public"."guard_profile_privileged_columns"()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- Vale per le scritture fatte direttamente dall'API, dove PostgREST imposta il ruolo anon o
  -- authenticated. Le RPC SECURITY DEFINER e i trigger interni girano come postgres, e hanno i
  -- loro controlli; service_role e supabase_auth_admin sono processi di sistema.
  IF current_user NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.role IS DISTINCT FROM 'user'::"public"."user_role" AND NOT public.is_admin() THEN
      RAISE EXCEPTION 'ROLE_CHANGE_FORBIDDEN: solo un admin può assegnare un ruolo staff'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'ROLE_CHANGE_FORBIDDEN: solo un admin può cambiare il ruolo di un profilo'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.email IS DISTINCT FROM OLD.email AND NOT public.is_staff() THEN
    RAISE EXCEPTION 'EMAIL_CHANGE_FORBIDDEN: l''email del profilo la cambia solo lo staff'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION "public"."guard_profile_privileged_columns"() IS
  'Trigger: sulle scritture dirette dall''API il ruolo lo cambia solo un admin e l''email solo lo staff. Sessione 1, 2026-09-22.';

DROP TRIGGER IF EXISTS "trg_guard_profile_privileged_columns" ON "public"."profiles";
CREATE TRIGGER "trg_guard_profile_privileged_columns"
  BEFORE INSERT OR UPDATE ON "public"."profiles"
  FOR EACH ROW EXECUTE FUNCTION "public"."guard_profile_privileged_columns"();

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 3. Prenotazioni: scritture dirette solo dallo staff
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Un cliente poteva inserire o annullare prenotazioni di eventi saltando book_event e
-- cancel_event_booking (capienza, scadenze). Su bookings il grant lo impediva già; le policy
-- vengono allineate perché dicano la stessa cosa. Webapp e app usano solo le RPC.

DROP POLICY IF EXISTS "bookings_insert_own_or_staff" ON "public"."bookings";
DROP POLICY IF EXISTS "bookings_update_own_or_staff" ON "public"."bookings";
CREATE POLICY "bookings_insert_staff" ON "public"."bookings"
  FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());
CREATE POLICY "bookings_update_staff" ON "public"."bookings"
  FOR UPDATE TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

DROP POLICY IF EXISTS "event_bookings_insert_own_or_staff" ON "public"."event_bookings";
DROP POLICY IF EXISTS "event_bookings_update_own_or_staff" ON "public"."event_bookings";
CREATE POLICY "event_bookings_insert_staff" ON "public"."event_bookings"
  FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());
CREATE POLICY "event_bookings_update_staff" ON "public"."event_bookings"
  FOR UPDATE TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 4. Controlli di ruolo dentro le funzioni
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Corpi identici a quelli di produzione: si aggiungono solo il controllo in testa e il
-- search_path fisso.

CREATE OR REPLACE FUNCTION public.calculate_operator_compensation(p_month_start date, p_month_end date, p_operator_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(operator_id uuid, operator_name text, lesson_id uuid, lesson_date timestamp with time zone, activity_name text, lesson_duration_minutes integer, generated_revenue_cents bigint, revenue_per_hour_cents bigint, room_rental_cents bigint, operator_payout_cents bigint, alice_share_cents bigint, studio_margin_cents bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Sessione 1 (2026-09-22): le Finanze sono solo per admin e Tesoriere (ruolo finance).
  IF NOT public.can_access_finance() THEN
    RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  WITH lesson_revenue AS (
    -- Calculate revenue generated per lesson from bookings
    -- Revenue = sum of (subscription price / entries) for each booking
    -- Priority: custom_price_cents > subscription.discount_percent > plan.discount_percent
    SELECT
      l.id AS lesson_id,
      l.operator_id,
      l.starts_at,
      l.ends_at,
      a.name AS activity_name,
      COALESCE(a.duration_minutes,
        EXTRACT(EPOCH FROM (l.ends_at - l.starts_at)) / 60
      )::INTEGER AS duration_minutes,
      COALESCE(SUM(
        CASE
          -- Custom subscription: use custom price / custom entries
          WHEN s.custom_price_cents IS NOT NULL AND COALESCE(s.custom_entries, 0) > 0
            THEN s.custom_price_cents / s.custom_entries
          -- Subscription discount: use plan price with subscription discount / entries
          WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
               AND p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
            THEN ROUND(p.price_cents * (1 - s.discount_percent / 100.0)) / p.entries
          -- Regular subscription: use plan price (with plan discount) / entries
          WHEN p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
            THEN ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0)) / p.entries
          ELSE 0
        END
      ), 0)::BIGINT AS generated_revenue_cents
    FROM lessons l
    JOIN activities a ON l.activity_id = a.id
    LEFT JOIN bookings b ON b.lesson_id = l.id
      AND b.status IN ('booked', 'attended', 'no_show')
    LEFT JOIN subscriptions s ON b.subscription_id = s.id
    LEFT JOIN plans p ON s.plan_id = p.id
    WHERE l.starts_at >= p_month_start
      AND l.starts_at < (p_month_end + INTERVAL '1 day')
      AND l.deleted_at IS NULL
      AND l.operator_id IS NOT NULL
      AND (p_operator_id IS NULL OR l.operator_id = p_operator_id)
    GROUP BY l.id, l.operator_id, l.starts_at, l.ends_at, a.name, a.duration_minutes
  ),
  compensation_calc AS (
    SELECT
      lr.lesson_id,
      lr.operator_id,
      o.name AS operator_name,
      lr.starts_at AS lesson_date,
      lr.activity_name,
      GREATEST(lr.duration_minutes, 1) AS lesson_duration_minutes, -- Avoid division by zero
      lr.generated_revenue_cents,
      -- Revenue per hour calculation
      CASE
        WHEN lr.duration_minutes > 0
        THEN (lr.generated_revenue_cents * 60 / lr.duration_minutes)::BIGINT
        ELSE lr.generated_revenue_cents
      END AS revenue_per_hour_cents,
      -- Room rental: always 15%
      ROUND(lr.generated_revenue_cents * 0.15)::BIGINT AS room_rental_cents
    FROM lesson_revenue lr
    JOIN operators o ON lr.operator_id = o.id
    WHERE o.deleted_at IS NULL
  )
  SELECT
    cc.operator_id,
    cc.operator_name,
    cc.lesson_id,
    cc.lesson_date,
    cc.activity_name,
    cc.lesson_duration_minutes::INTEGER,
    cc.generated_revenue_cents,
    cc.revenue_per_hour_cents,
    cc.room_rental_cents,
    -- Operator payout calculation
    CASE
      WHEN cc.revenue_per_hour_cents > 4000 -- > 40 EUR/hour (4000 cents)
      THEN ROUND(4000.0 * cc.lesson_duration_minutes / 60.0)::BIGINT -- 40 EUR/hour prorated
      ELSE GREATEST(cc.generated_revenue_cents - cc.room_rental_cents, 0)::BIGINT -- Revenue minus room rental (floor at 0)
    END AS operator_payout_cents,
    -- Alice share calculation (25% of margin, only if > 40/hour)
    CASE
      WHEN cc.revenue_per_hour_cents > 4000 -- > 40 EUR/hour
      THEN ROUND(
        GREATEST(
          cc.generated_revenue_cents
          - cc.room_rental_cents
          - ROUND(4000.0 * cc.lesson_duration_minutes / 60.0),
          0
        ) * 0.25
      )::BIGINT
      ELSE 0::BIGINT
    END AS alice_share_cents,
    -- Studio margin calculation (75% of margin, only if > 40/hour)
    CASE
      WHEN cc.revenue_per_hour_cents > 4000 -- > 40 EUR/hour
      THEN ROUND(
        GREATEST(
          cc.generated_revenue_cents
          - cc.room_rental_cents
          - ROUND(4000.0 * cc.lesson_duration_minutes / 60.0),
          0
        ) * 0.75
      )::BIGINT
      ELSE 0::BIGINT
    END AS studio_margin_cents
  FROM compensation_calc cc
  ORDER BY cc.lesson_date, cc.operator_name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_monthly_revenue_by_client(p_month_start date, p_month_end date)
 RETURNS TABLE(client_id uuid, client_name text, client_email text, total_revenue_cents bigint, subscription_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Sessione 1 (2026-09-22): le Finanze sono solo per admin e Tesoriere (ruolo finance).
  IF NOT public.can_access_finance() THEN
    RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT
    c.id AS client_id,
    c.full_name AS client_name,
    c.email AS client_email,
    COALESCE(SUM(
      CASE
        -- Custom subscription: use custom price
        WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
        -- Subscription discount: use plan price with subscription discount
        WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
          THEN ROUND(p.price_cents * (1 - s.discount_percent / 100.0))
        -- Regular subscription: use plan price with plan discount
        ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
      END
    ), 0)::BIGINT AS total_revenue_cents,
    COUNT(DISTINCT s.id)::INTEGER AS subscription_count
  FROM clients c
  INNER JOIN subscriptions s ON s.client_id = c.id
    AND s.created_at >= p_month_start
    AND s.created_at < (p_month_end + INTERVAL '1 day')
    AND s.deleted_at IS NULL
  LEFT JOIN plans p ON s.plan_id = p.id
  WHERE c.deleted_at IS NULL
  GROUP BY c.id, c.full_name, c.email
  HAVING COALESCE(SUM(
    CASE
      WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
      WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
        THEN ROUND(p.price_cents * (1 - s.discount_percent / 100.0))
      ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
    END
  ), 0) > 0
  ORDER BY total_revenue_cents DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_monthly_revenue_by_plan(p_month_start date, p_month_end date)
 RETURNS TABLE(plan_id uuid, plan_name text, total_revenue_cents bigint, subscription_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Sessione 1 (2026-09-22): le Finanze sono solo per admin e Tesoriere (ruolo finance).
  IF NOT public.can_access_finance() THEN
    RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT
    p.id AS plan_id,
    COALESCE(s.custom_name, p.name) AS plan_name,
    COALESCE(SUM(
      CASE
        -- Custom subscription: use custom price
        WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
        -- Subscription discount: use plan price with subscription discount
        WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
          THEN ROUND(p.price_cents * (1 - s.discount_percent / 100.0))
        -- Regular subscription: use plan price with plan discount
        ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
      END
    ), 0)::BIGINT AS total_revenue_cents,
    COUNT(DISTINCT s.id)::INTEGER AS subscription_count
  FROM subscriptions s
  JOIN plans p ON s.plan_id = p.id
  WHERE s.created_at >= p_month_start
    AND s.created_at < (p_month_end + INTERVAL '1 day')
    AND s.deleted_at IS NULL
  GROUP BY p.id, COALESCE(s.custom_name, p.name)
  HAVING COALESCE(SUM(
    CASE
      WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
      WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
        THEN ROUND(p.price_cents * (1 - s.discount_percent / 100.0))
      ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
    END
  ), 0) > 0
  ORDER BY total_revenue_cents DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.queue_new_event(p_event_id uuid, p_event_name text, p_event_date timestamp with time zone)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count integer := 0;
    v_title text;
BEGIN
    -- Sessione 1 (2026-09-22): solo lo staff può inviare "nuovo evento" a tutti i clienti.
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Permission denied: user is not staff' USING ERRCODE = '42501';
    END IF;
    -- Costruisci il titolo che verrà usato per la deduplicazione
    v_title := 'Nuovo evento: ' || p_event_name;

    -- Accoda notifica nuovo evento a tutti i clienti attivi
    -- DEDUPLICAZIONE: non creare se esiste già una notifica con lo stesso TITOLO
    -- creata negli ultimi 60 secondi (per gestire creazione batch di eventi)
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        'new_event'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 'new_event'),
            'email'::"public"."notification_channel"
        ),
        v_title,
        TO_CHAR(p_event_date AT TIME ZONE 'Europe/Rome', 'DD/MM alle HH24:MI') ||
            ' - I posti sono limitati, iscriviti ora!',
        jsonb_build_object(
            'event_id', p_event_id,
            'event_name', p_event_name,
            'event_date', p_event_date
        ),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      -- DEDUPLICAZIONE: escludi client che hanno già una notifica con stesso titolo
      -- creata negli ultimi 60 secondi (batch creation window)
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = c.id
            AND nq.category = 'new_event'
            AND nq.title = v_title
            AND nq.created_at > NOW() - INTERVAL '60 seconds'
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.queue_new_event(p_event_id uuid, p_event_name text, p_event_date timestamp with time zone, p_send_push boolean DEFAULT true, p_send_email boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_push_count integer := 0;
    v_email_count integer := 0;
    v_title text;
    v_body text;
    v_data jsonb;
BEGIN
    -- Sessione 1 (2026-09-22): solo lo staff può inviare "nuovo evento" a tutti i clienti.
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Permission denied: user is not staff' USING ERRCODE = '42501';
    END IF;
    -- Se nessun canale selezionato, non fare nulla
    IF NOT p_send_push AND NOT p_send_email THEN
        RETURN json_build_object('queued_push', 0, 'queued_email', 0);
    END IF;

    v_title := 'Nuovo evento: ' || p_event_name;
    v_body := TO_CHAR(p_event_date AT TIME ZONE 'Europe/Rome', 'DD/MM alle HH24:MI') ||
              ' - I posti sono limitati, iscriviti ora!';
    v_data := jsonb_build_object(
        'event_id', p_event_id,
        'event_name', p_event_name,
        'event_date', p_event_date
    );

    -- Accoda notifiche PUSH (solo per clienti con token attivi)
    IF p_send_push THEN
        INSERT INTO "public"."notification_queue" (
            client_id, category, channel, title, body, data, scheduled_for
        )
        SELECT
            c.id,
            'new_event'::"public"."notification_category",
            'push'::"public"."notification_channel",
            v_title,
            v_body,
            v_data,
            NOW()
        FROM "public"."clients" c
        WHERE c.deleted_at IS NULL
          AND c.is_active = true
          AND "public"."client_has_active_push_tokens"(c.id)
          -- Deduplicazione: escludi client che hanno già una notifica push con stesso titolo
          AND NOT EXISTS (
              SELECT 1 FROM "public"."notification_queue" nq
              WHERE nq.client_id = c.id
                AND nq.category = 'new_event'
                AND nq.channel = 'push'
                AND nq.title = v_title
                AND nq.created_at > NOW() - INTERVAL '60 seconds'
          );

        GET DIAGNOSTICS v_push_count = ROW_COUNT;
    END IF;

    -- Accoda notifiche EMAIL (solo per clienti con email)
    IF p_send_email THEN
        INSERT INTO "public"."notification_queue" (
            client_id, category, channel, title, body, data, scheduled_for
        )
        SELECT
            c.id,
            'new_event'::"public"."notification_category",
            'email'::"public"."notification_channel",
            v_title,
            v_body,
            v_data,
            NOW()
        FROM "public"."clients" c
        WHERE c.deleted_at IS NULL
          AND c.is_active = true
          AND c.email IS NOT NULL
          AND c.email != ''
          AND COALESCE(c.email_bounced, false) = false
          -- Deduplicazione: escludi client che hanno già una notifica email con stesso titolo
          AND NOT EXISTS (
              SELECT 1 FROM "public"."notification_queue" nq
              WHERE nq.client_id = c.id
                AND nq.category = 'new_event'
                AND nq.channel = 'email'
                AND nq.title = v_title
                AND nq.created_at > NOW() - INTERVAL '60 seconds'
          );

        GET DIAGNOSTICS v_email_count = ROW_COUNT;
    END IF;

    RETURN json_build_object('queued_push', v_push_count, 'queued_email', v_email_count);
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 5. Funzioni: tutto chiuso, poi l'elenco esplicito
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Postgres dà EXECUTE a PUBLIC su ogni funzione nuova: così call_edge_function, le code delle
-- notifiche e le Finanze erano chiamabili da chiunque. Da qui in poi anon e authenticated
-- eseguono solo le funzioni elencate sotto; service_role (edge function) le esegue tutte.
-- Cron, trigger e RPC SECURITY DEFINER girano come postgres e non dipendono da questi grant.

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA "public" FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA "public" TO "service_role";

-- Anon e authenticated. Gli helper usati dalle policy devono restare eseguibili da chi interroga
-- le tabelle (per anon restituiscono false/null); i conteggi degli eventi sono dati pubblici.
GRANT EXECUTE ON FUNCTION
  "public"."is_staff"(),
  "public"."is_admin"(),
  "public"."is_finance"(),
  "public"."can_access_finance"(),
  "public"."get_my_client_id"(),
  "public"."get_event_booking_count"("uuid"),
  "public"."get_events_booking_counts"("uuid"[])
TO "anon", "authenticated";

-- Solo utenti loggati. Ognuna controlla login e ruolo al suo interno.
GRANT EXECUTE ON FUNCTION
  -- cliente: prenotazioni
  "public"."book_lesson"("uuid", "uuid"),
  "public"."cancel_booking"("uuid"),
  "public"."book_event"("uuid"),
  "public"."cancel_event_booking"("uuid"),
  -- cliente: percorso, pratica, notifiche, push, Bussola, feedback
  "public"."get_journey_summary"(),
  "public"."get_journey_timeline"(integer, integer),
  "public"."get_practice_metrics"(),
  "public"."get_my_membership"(),
  "public"."get_my_notification_settings"(),
  "public"."get_my_notifications"(integer, integer),
  "public"."get_unread_notifications_count"(),
  "public"."mark_all_notifications_read"(),
  "public"."mark_notification_read"("uuid", "uuid"),
  "public"."set_notification_quiet_hours"(boolean, time without time zone, time without time zone),
  "public"."register_device_token"("text", "text", "text", "text"),
  "public"."deactivate_device_token"("text"),
  "public"."request_bussola"(timestamp with time zone, "text"),
  "public"."cancel_bussola_request"("uuid"),
  "public"."submit_feedback"("public"."feedback_kind", "uuid", smallint, "text"),
  "public"."queue_feedback_request"("uuid", "public"."feedback_kind", "uuid", timestamp with time zone),
  -- staff (is_staff / is_admin dentro)
  "public"."staff_book_lesson"("uuid", "uuid", "uuid"),
  "public"."staff_cancel_booking"("uuid"),
  "public"."staff_update_booking_status"("uuid", "public"."booking_status"),
  "public"."staff_book_event"("uuid", "uuid"),
  "public"."staff_cancel_event_booking"("uuid"),
  "public"."staff_get_user_email_status"("uuid"),
  "public"."get_auth_email_stats"("uuid"),
  "public"."assign_membership"("uuid", "uuid", "date", integer, "text"),
  "public"."cancel_membership"("uuid"),
  "public"."delete_campaign"("uuid"),
  "public"."promote_profile_to_operator"("uuid"),
  "public"."queue_new_event"("uuid", "text", timestamp with time zone),
  "public"."queue_new_event"("uuid", "text", timestamp with time zone, boolean, boolean),
  "public"."get_activity_booking_counts"(),
  -- Finanze (can_access_finance dentro)
  "public"."calculate_operator_compensation"("date", "date", "uuid"),
  "public"."get_monthly_revenue_by_client"("date", "date"),
  "public"."get_monthly_revenue_by_plan"("date", "date"),
  "public"."get_financial_kpis"("date", "date"),
  "public"."get_revenue_breakdown"("date", "date"),
  -- funzioni pure chiamate dai trigger SECURITY INVOKER su announcements e activities
  "public"."calculate_next_announcement_occurrence"("public"."announcement_recurrence_frequency", smallint, smallint, time without time zone, timestamp with time zone),
  "public"."generate_slug_from_discipline"("text")
TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 6. Le funzioni future nascono chiuse
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Il default di Postgres (EXECUTE a PUBLIC) si toglie solo a livello globale. Lo schema extensions
-- lo riottiene, così un'estensione attivata in futuro funziona come prima. In public ogni nuova
-- funzione va aperta con un GRANT esplicito (regola in ACCESS_MODEL.md, verificata dai test).

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "extensions" GRANT EXECUTE ON FUNCTIONS TO PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE EXECUTE ON FUNCTIONS FROM "anon", "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT EXECUTE ON FUNCTIONS TO "service_role";

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 7. Parità con la produzione: trigger di registrazione
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- In produzione il trigger esiste (creato fuori dalle migrazioni); qui lo si crea solo se manca,
-- così il DB locale si comporta come quello vero alla registrazione. In produzione è un no-op.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'on_auth_user_created' AND tgrelid = 'auth.users'::regclass
  ) THEN
    CREATE TRIGGER "on_auth_user_created"
      AFTER INSERT ON "auth"."users"
      FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_user"();
  END IF;
END;
$$;
