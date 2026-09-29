-- Migration 20260929120000: notifiche, impostazioni e account nell'app (sessione 11)
--
-- 1. Dove porta una notifica. Una sola regola, qui: `internal.notification_path(categoria, data)`
--    restituisce il percorso dell'app (`/lesson/<id>`, `/subscriptions`, `/journal`, …). Un trigger
--    lo scrive in `data.url` di ogni riga nuova della coda, così arriva uguale alle push web (il
--    service worker apre `data.url`), alle push di iPhone e Android e ai log; `get_my_notifications`
--    lo restituisce come `path`, anche per i log di prima.
-- 2. Il messaggio dopo la prova (F6): quando lo staff segna la presenza a una prova, si accoda
--    `trial_followup` («Com'è andata la prova di …?») con il questionario dell'app, un'ora dopo la
--    fine della lezione e mai di notte. Dietro l'interruttore `trial_followup`, spento: si accende al
--    lancio della nuova app (sessione 12), perché la webapp attuale non ha il questionario.
-- 3. L'eliminazione dell'account dall'app. Prima la faceva l'edge function `delete-account` a
--    pezzi e senza controllare gli errori: cancellava le note dello staff sulla scheda, disdiceva
--    anche le prenotazioni passate non segnate (cambiando Finanze e compensi), lasciava i posti in
--    lista d'attesa senza passarli al successivo e poteva fermarsi a metà (vecchie iscrizioni agli
--    eventi legate all'utente, segnalazioni che restavano senza autore). Ora `delete_account_data`
--    fa tutto in una transazione, solo per chi non è staff: disdice le prenotazioni future (le
--    iscrizioni agli eventi già pagate restano, le decide lo staff), libera la lista d'attesa,
--    cancella diario, pratiche, notifiche e dispositivi, toglie telefono e compleanno, disattiva la
--    scheda con una nota in fondo a quelle dello staff. Restano libro soci, quote, ricevute, incassi
--    e prove: l'iscrizione all'associazione non cambia (per recedere si scrive, art. 5).
--    `internal.handle_new_user`: chi si registra di nuovo con la stessa email ritrova la sua scheda
--    (prima la registrazione falliva sull'indice unico dell'email).
-- 4. I propri dati: `update_my_profile` cambia nome, telefono e compleanno sul profilo e sulla
--    scheda cliente (prima dall'app si cambiava solo il profilo, e la scheda dello staff lo
--    sovrascriveva). `accept_my_legal_documents` registra con l'ora del server che privacy e termini
--    in vigore sono stati accettati (A6: la nuova app li chiede a tuttə al primo accesso).
-- 5. L'interruttore `app_version_gate`, spento: versione minima e consigliata dell'app per iPhone e
--    Android, e dove aggiornarla (serve dalle build della sessione 13).
--
-- Compatibilità: nessuna colonna toccata. `notification_queue.data` riceve una chiave in più
-- (`url`): il service worker della webapp la usa solo se mancano gli id che conosce già.
-- `get_my_notifications` ha un campo in più (`path`), stessa firma. `handle_new_user` cambia solo il
-- caso che prima falliva. Funzioni nuove: due aperte ad `authenticated`, una solo a `service_role`.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 A6, F6 e §0-undecies.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Dove porta una notifica
-- ─────────────────────────────────────────────────────────────────────────────

-- Percorso dell'app per una notifica, dalla categoria e dagli id che porta con sé; NULL se non c'è
-- una pagina dedicata (l'app apre allora il centro notifiche). Un `url` già presente vince, purché
-- sia un percorso dell'app (niente indirizzi esterni né `//dominio`).
CREATE OR REPLACE FUNCTION "internal"."notification_path"(
    "p_category" "public"."notification_category",
    "p_data"     "jsonb"
) RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_url      text := NULLIF(btrim(COALESCE(p_data->>'url', '')), '');
    v_lesson   text := NULLIF(p_data->>'lesson_id', '');
    v_event    text := NULLIF(p_data->>'event_id', '');
    v_trial    text := NULLIF(p_data->>'trial_id', '');
    v_practice text := NULLIF(p_data->>'practice_id', '');
    v_target   text := NULLIF(p_data->>'target_id', '');
BEGIN
    IF v_url ~ '^/([^/\\]|$)' THEN
        RETURN v_url;
    END IF;

    RETURN CASE
        WHEN p_category IN ('lesson_reminder', 'waitlist_promotion', 'trial_booked', 'trial_booked_staff')
             AND v_lesson IS NOT NULL THEN '/lesson/' || v_lesson
        WHEN p_category = 'trial_followup' AND v_trial IS NOT NULL THEN '/feedback/trial/' || v_trial
        WHEN p_category = 'feedback_request' AND v_target IS NOT NULL THEN
            CASE p_data->>'kind'
                WHEN 'lesson'   THEN '/lesson/' || v_target
                WHEN 'event'    THEN '/event/' || v_target
                WHEN 'practice' THEN '/practice/' || v_target
                WHEN 'trial'    THEN '/feedback/trial/' || v_target
            END
        WHEN p_category IN ('subscription_expiry', 'entries_low') THEN '/subscriptions'
        WHEN p_category = 'new_event' AND v_event IS NOT NULL THEN '/event/' || v_event
        WHEN p_category = 'announcement' AND NULLIF(p_data->>'announcement_id', '') IS NOT NULL
             THEN '/announcement/' || (p_data->>'announcement_id')
        WHEN p_category = 'journal_reminder' THEN '/journal'
        WHEN p_category = 'practice_resume' AND v_practice IS NOT NULL THEN '/practice/' || v_practice
        WHEN p_category IN ('practice_reminder', 'practice_resume') THEN '/practices'
        WHEN p_category IN ('birthday', 'milestone', 'first_lesson') THEN '/journey'
        WHEN p_category = 're_engagement' THEN '/calendar'
        WHEN p_category IN ('member_application_decided', 'membership_fee_due') THEN '/membership'
        -- Categorie future o dati diversi: gli id bastano a trovare la pagina
        WHEN v_lesson IS NOT NULL THEN '/lesson/' || v_lesson
        WHEN v_event IS NOT NULL THEN '/event/' || v_event
        ELSE NULL
    END;
END;
$$;

CREATE OR REPLACE FUNCTION "internal"."notification_queue_set_url"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_path text;
BEGIN
    NEW.data := COALESCE(NEW.data, '{}'::jsonb);
    v_path := "internal"."notification_path"(NEW.category, NEW.data);
    IF v_path IS NULL THEN
        NEW.data := NEW.data - 'url';
    ELSE
        NEW.data := NEW.data || jsonb_build_object('url', v_path);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "notification_queue_set_url" ON "public"."notification_queue";
CREATE TRIGGER "notification_queue_set_url"
    BEFORE INSERT ON "public"."notification_queue"
    FOR EACH ROW EXECUTE FUNCTION "internal"."notification_queue_set_url"();

-- Il centro notifiche: come prima, più `path` (il percorso dell'app) per ogni voce. Per gli annunci
-- è la loro pagina; `route` resta com'era (la KMP, archiviata, la usava).
CREATE OR REPLACE FUNCTION "public"."get_my_notifications"(
    "p_limit"  integer DEFAULT 30,
    "p_offset" integer DEFAULT 0
) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client uuid;
  v_items jsonb;
  v_has_more boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_client := public.get_my_client_id();
  IF v_client IS NULL THEN
    -- Utente loggato ma non ancora collegato a un client: feed vuoto (non è un errore).
    RETURN jsonb_build_object('ok', true, 'items', '[]'::jsonb, 'has_more', false);
  END IF;

  WITH feed AS (
    -- Notifiche personali (log ultimi 30 giorni; le 'announcement' sono mostrate dagli annunci).
    SELECT
      nl.id AS id,
      'push'::text AS type,
      nl.category::text AS category,
      nl.title AS title,
      nl.body AS body,
      NULL::text AS image_url,
      nl.sent_at AS sent_at,
      EXISTS (
        SELECT 1 FROM public.notification_reads nr
        WHERE nr.notification_log_id = nl.id AND nr.client_id = v_client
      ) AS is_read,
      COALESCE(
        -- 1) rotta esplicita kalos:// nel payload
        CASE WHEN nl.data->>'route' LIKE 'kalos://%' THEN nl.data->>'route' END,
        -- 2) fallback: deriva dalla categoria + id presenti in `data`
        CASE
          WHEN NULLIF(nl.data->>'lesson_id', '') IS NOT NULL THEN 'kalos://lesson/' || (nl.data->>'lesson_id')
          WHEN NULLIF(nl.data->>'event_id', '') IS NOT NULL THEN 'kalos://event/' || (nl.data->>'event_id')
          WHEN NULLIF(nl.data->>'practice_id', '') IS NOT NULL THEN 'kalos://practice/' || (nl.data->>'practice_id')
          WHEN NULLIF(nl.data->>'promotion_id', '') IS NOT NULL THEN 'kalos://promotion/' || (nl.data->>'promotion_id')
          WHEN nl.category = 'journal_reminder' THEN 'kalos://journal'
          WHEN nl.category IN ('practice_reminder', 'practice_resume') THEN 'kalos://practices'
          WHEN nl.category = 'new_event' THEN 'kalos://explore'
          WHEN nl.category IN ('subscription_expiry', 'entries_low') THEN 'kalos://profile'
          ELSE NULL
        END
      ) AS route,
      "internal"."notification_path"(nl.category, nl.data) AS path
    FROM public.notification_logs nl
    WHERE nl.client_id = v_client
      AND nl.sent_at > now() - interval '30 days'
      AND nl.category <> 'announcement'

    UNION ALL

    -- Annunci broadcast attivi e visibili a questo cliente (test mode incluso solo se mirato).
    SELECT
      a.id,
      'announcement'::text,
      a.category::text,
      a.title,
      a.body,
      a.image_url,
      a.starts_at,
      EXISTS (
        SELECT 1 FROM public.notification_reads nr
        WHERE nr.announcement_id = a.id AND nr.client_id = v_client
      ),
      -- La `route` è SOLO l'eventuale azione dell'annuncio (link_url); `path` è la sua pagina.
      NULLIF(a.link_url, ''),
      '/announcement/' || a.id
    FROM public.announcements a
    WHERE a.is_active = true
      AND a.starts_at <= now()
      AND (a.ends_at IS NULL OR a.ends_at > now())
      AND (a.is_test = false OR a.test_client_id = v_client)
  ),
  lim AS (
    SELECT * FROM feed ORDER BY sent_at DESC OFFSET p_offset LIMIT p_limit + 1
  ),
  ranked AS (
    SELECT *, row_number() OVER (ORDER BY sent_at DESC) AS rn FROM lim
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'type', type,
          'category', category,
          'title', title,
          'body', body,
          'image_url', image_url,
          'sent_at', sent_at,
          'is_read', is_read,
          'route', route,
          'path', path
        ) ORDER BY sent_at DESC
      ) FILTER (WHERE rn <= p_limit),
      '[]'::jsonb
    ),
    (SELECT COUNT(*) FROM lim) > p_limit
  INTO v_items, v_has_more
  FROM ranked;

  RETURN jsonb_build_object('ok', true, 'items', COALESCE(v_items, '[]'::jsonb), 'has_more', COALESCE(v_has_more, false));
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Il messaggio dopo la prova (F6)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO "public"."feature_flags" ("key", "enabled", "description")
VALUES ('trial_followup', false,
        'Messaggio dopo la lezione di prova, con il questionario dell''app. Si accende al lancio della nuova app (sessione 12): la webapp attuale non ha il questionario.')
ON CONFLICT ("key") DO NOTHING;

-- Accoda «Com'è andata la prova?» per una prova frequentata: una volta sola per prova, un'ora dopo
-- la fine della lezione e, se cade di sera o di notte, alle 9 della mattina dopo (ora italiana).
CREATE OR REPLACE FUNCTION "internal"."queue_trial_followup"("p_trial_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_trial    public.trials%ROWTYPE;
    v_client   public.clients%ROWTYPE;
    v_ends_at  timestamptz;
    v_activity text;
    v_channel  public.notification_channel;
    v_at       timestamptz;
    v_local    timestamp;
BEGIN
    IF NOT COALESCE((SELECT enabled FROM public.feature_flags WHERE key = 'trial_followup'), false) THEN
        RETURN;
    END IF;

    SELECT * INTO v_trial FROM public.trials WHERE id = p_trial_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Una volta sola: né un secondo messaggio né uno a chi ha già risposto
    IF EXISTS (SELECT 1 FROM public.notification_queue
                WHERE category = 'trial_followup' AND data->>'trial_id' = p_trial_id::text)
       OR EXISTS (SELECT 1 FROM public.feedback WHERE trial_id = p_trial_id) THEN
        RETURN;
    END IF;

    SELECT * INTO v_client FROM public.clients WHERE id = v_trial.client_id;
    IF NOT FOUND OR v_client.deleted_at IS NOT NULL THEN
        RETURN;
    END IF;

    v_channel := "internal"."get_notification_channel"(v_trial.client_id, 'trial_followup');
    IF v_channel IS NULL OR (v_channel = 'email' AND NULLIF(btrim(COALESCE(v_client.email, '')), '') IS NULL) THEN
        RETURN;
    END IF;

    SELECT ends_at INTO v_ends_at FROM public.lessons WHERE id = v_trial.lesson_id;
    SELECT name INTO v_activity FROM public.activities WHERE id = v_trial.activity_id;

    v_at := GREATEST(now(), COALESCE(v_ends_at, now()) + interval '1 hour');
    v_local := v_at AT TIME ZONE 'Europe/Rome';
    IF extract(hour FROM v_local) >= 21 THEN
        v_at := ((v_local::date + 1) + time '09:00') AT TIME ZONE 'Europe/Rome';
    ELSIF extract(hour FROM v_local) < 9 THEN
        v_at := (v_local::date + time '09:00') AT TIME ZONE 'Europe/Rome';
    END IF;

    INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
    VALUES (
        v_trial.client_id, 'trial_followup', v_channel,
        'Com''è andata la prova' || COALESCE(' di ' || v_activity, '') || '?',
        'Grazie di essere venutə. Ci racconti com''è andata? Sono tre domande, un minuto.'
            || CASE WHEN v_trial.status = 'converted' THEN ''
                    ELSE ' E se vuoi continuare, la prova vale come primo ingresso del tuo abbonamento.'
               END,
        jsonb_build_object('trial_id', v_trial.id, 'lesson_id', v_trial.lesson_id,
                           'activity_id', v_trial.activity_id,
                           'url', '/feedback/trial/' || v_trial.id),
        v_at
    );
END;
$$;

-- La presenza a una prova si segna sulla prenotazione (`bookings_sync_trial_status` aggiorna la
-- prova): da lì parte anche il messaggio, pure per le prove già convertite in abbonamento.
CREATE OR REPLACE FUNCTION "internal"."queue_trial_followup_on_attended"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_trial_id uuid;
BEGIN
    SELECT id INTO v_trial_id FROM public.trials WHERE booking_id = NEW.id;
    IF v_trial_id IS NOT NULL THEN
        PERFORM "internal"."queue_trial_followup"(v_trial_id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "bookings_trial_followup" ON "public"."bookings";
CREATE TRIGGER "bookings_trial_followup"
    AFTER UPDATE OF "status" ON "public"."bookings"
    FOR EACH ROW
    WHEN ("new"."is_trial" AND "new"."status" = 'attended' AND "old"."status" IS DISTINCT FROM 'attended')
    EXECUTE FUNCTION "internal"."queue_trial_followup_on_attended"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Eliminazione dell'account
-- ─────────────────────────────────────────────────────────────────────────────

-- Tutto quello che il database deve fare prima che l'edge function `delete-account` cancelli
-- l'utente di Supabase Auth. Solo `service_role`: la chiama l'edge function col suo client, dopo
-- aver letto l'utente dal token. Si può rilanciare (se la cancellazione dell'utente fallisce, il
-- secondo tentativo ritrova la scheda e non fa danni).
CREATE OR REPLACE FUNCTION "public"."delete_account_data"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_role      public.user_role;
    v_client_id uuid;
    v_lesson_id uuid;
    v_today     text := to_char((now() AT TIME ZONE 'Europe/Rome')::date, 'DD/MM/YYYY');
    v_clients   uuid[] := ARRAY[]::uuid[];
BEGIN
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'USER_NOT_FOUND');
    END IF;

    SELECT role INTO v_role FROM public.profiles WHERE id = p_user_id;
    -- Chi lavora nello studio chiude l'account parlando con un admin: il suo profilo regge lezioni,
    -- compensi, annunci e registri
    IF v_role IS NOT NULL AND v_role <> 'user' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'STAFF_ACCOUNT');
    END IF;

    FOR v_client_id IN SELECT id FROM public.clients WHERE profile_id = p_user_id LOOP
        v_clients := v_clients || v_client_id;

        -- Prenotazioni future: disdette come dall'app (i trigger restituiscono l'ingresso e offrono
        -- il posto a chi è in lista d'attesa). Quelle passate restano: sono presenze e Finanze.
        UPDATE public.bookings b
           SET status = 'canceled'
          FROM public.lessons l
         WHERE l.id = b.lesson_id
           AND b.client_id = v_client_id
           AND b.status = 'booked'
           AND l.starts_at > now();

        -- Iscrizioni a eventi futuri, tranne quelle già pagate: il rimborso lo decide lo staff (D4)
        UPDATE public.event_bookings eb
           SET status = 'canceled'
          FROM public.events e
         WHERE e.id = eb.event_id
           AND eb.client_id = v_client_id
           AND eb.status = 'booked'
           AND e.starts_at > now()
           AND NOT EXISTS (
               SELECT 1 FROM public.transactions t
                WHERE t.event_booking_id = eb.id AND t.status IN ('paid', 'partially_refunded'));

        -- Lista d'attesa: il posto passa a chi viene dopo
        FOR v_lesson_id IN
            UPDATE public.waitlist SET status = 'left'
             WHERE client_id = v_client_id AND status IN ('waiting', 'offered')
            RETURNING lesson_id
        LOOP
            PERFORM "internal"."fill_waitlist_offers"(v_lesson_id);
        END LOOP;

        UPDATE public.bussola_requests SET status = 'cancelled'
         WHERE client_id = v_client_id AND status = 'pending';

        -- I contenuti personali dell'app
        DELETE FROM public.journal_entries          WHERE client_id = v_client_id;
        DELETE FROM public.practice_user_state      WHERE client_id = v_client_id;
        DELETE FROM public.notification_queue       WHERE client_id = v_client_id;
        DELETE FROM public.notification_reads       WHERE client_id = v_client_id;
        DELETE FROM public.notification_logs        WHERE client_id = v_client_id;
        DELETE FROM public.notification_preferences WHERE client_id = v_client_id;
        DELETE FROM public.notification_settings    WHERE client_id = v_client_id;
        DELETE FROM public.device_tokens            WHERE client_id = v_client_id;

        -- La scheda resta (libro soci, quote, ricevute e incassi la usano), senza i dati che non
        -- servono più. Nome ed email restano: chi torna con la stessa email la ritrova.
        UPDATE public.clients
           SET is_active = false,
               deleted_at = COALESCE(deleted_at, now()),
               phone = NULL,
               birthday = NULL,
               newsletter_subscribed = false,
               notes = concat_ws(E'\n', NULLIF(btrim(COALESCE(notes, '')), ''),
                                 'Account dell''app eliminato dalla persona il ' || v_today || '.')
         WHERE id = v_client_id;

        -- Le segnalazioni restano allo staff, intestate alla scheda
        UPDATE public.bug_reports
           SET created_by_client_id = v_client_id, created_by_user_id = NULL
         WHERE created_by_user_id = p_user_id;

        -- Vecchie iscrizioni agli eventi legate all'utente (prima delle schede): passano alla scheda
        UPDATE public.event_bookings
           SET client_id = v_client_id, user_id = NULL
         WHERE user_id = p_user_id;
    END LOOP;

    -- Senza scheda non c'è a chi intestarle: vanno via con l'account
    DELETE FROM public.bug_reports    WHERE created_by_user_id = p_user_id;
    DELETE FROM public.event_bookings WHERE user_id = p_user_id;

    UPDATE public.profiles
       SET deleted_at = COALESCE(deleted_at, now()),
           full_name = 'Account eliminato',
           phone = NULL,
           avatar_url = NULL,
           notes = NULL
     WHERE id = p_user_id;

    RETURN jsonb_build_object('ok', true, 'client_ids', to_jsonb(v_clients));
END;
$$;

-- Registrazione: come prima, più il ritorno di chi aveva eliminato l'account. La sua scheda (senza
-- profilo, disattivata) torna attiva e collegata al nuovo account, con lo storico e l'iscrizione.
CREATE OR REPLACE FUNCTION "internal"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client clients%rowtype;
  v_full_name text;
BEGIN
  -- Cerca se esiste un client con la stessa email
  SELECT * INTO v_client
  FROM clients
  WHERE email = new.email
    AND deleted_at IS NULL
  LIMIT 1;

  -- Altrimenti la scheda di chi aveva eliminato l'account (senza profilo: l'indice unico
  -- dell'email vale anche per le schede disattivate, e una seconda scheda non si potrebbe creare)
  IF NOT FOUND THEN
    SELECT * INTO v_client
    FROM clients
    WHERE email = new.email
      AND deleted_at IS NOT NULL
      AND profile_id IS NULL
    ORDER BY deleted_at DESC
    LIMIT 1;

    IF FOUND THEN
      UPDATE clients
      SET deleted_at = NULL,
          is_active = true,
          notes = concat_ws(E'\n', NULLIF(btrim(COALESCE(notes, '')), ''),
                            'Account dell''app ricreato il '
                              || to_char((now() AT TIME ZONE 'Europe/Rome')::date, 'DD/MM/YYYY') || '.')
      WHERE id = v_client.id
      RETURNING * INTO v_client;
    END IF;
  END IF;

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
    -- Se non esiste un client, crea sia il profilo che il client
    -- Estrai il nome completo dai metadati se disponibile
    v_full_name := COALESCE(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      split_part(new.email, '@', 1),  -- Fallback: parte prima della @ nell'email
      'Utente'  -- Ultimo fallback
    );

    -- Crea il profilo minimale
    INSERT INTO public.profiles (id, email, role)
    VALUES (
      new.id,
      new.email,
      'user'::user_role
    );

    -- Crea un nuovo client collegato al profilo
    INSERT INTO public.clients (
      profile_id,
      email,
      full_name,
      phone,
      is_active
    )
    VALUES (
      new.id,
      new.email,
      v_full_name,
      new.raw_user_meta_data->>'phone',  -- Opzionale, può essere NULL
      true
    );
  END IF;

  RETURN new;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. I propri dati e le accettazioni
-- ─────────────────────────────────────────────────────────────────────────────

-- Nome, telefono e compleanno, sul profilo e sulla scheda cliente insieme. L'email non si cambia
-- dall'app (la usano ricevute, libro soci e accesso: la cambia lo staff).
CREATE OR REPLACE FUNCTION "public"."update_my_profile"(
    "p_full_name" "text",
    "p_phone"     "text",
    "p_birthday"  "date"
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_uid    uuid := auth.uid();
    v_client uuid;
    v_name   text := regexp_replace(btrim(COALESCE(p_full_name, '')), '\s+', ' ', 'g');
    v_phone  text := NULLIF(btrim(COALESCE(p_phone, '')), '');
BEGIN
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;
    IF length(v_name) < 2 OR length(v_name) > 120 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_NAME');
    END IF;
    IF v_phone IS NOT NULL AND v_phone !~ '^\+?[0-9][0-9 ./-]{5,19}$' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_PHONE');
    END IF;
    IF p_birthday IS NOT NULL AND (p_birthday < DATE '1900-01-01' OR p_birthday > CURRENT_DATE) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_BIRTHDAY');
    END IF;

    UPDATE public.profiles SET full_name = v_name, phone = v_phone WHERE id = v_uid;

    v_client := public.get_my_client_id();
    IF v_client IS NOT NULL THEN
        UPDATE public.clients
           SET full_name = v_name, phone = v_phone, birthday = p_birthday
         WHERE id = v_client;
    END IF;

    RETURN jsonb_build_object('ok', true);
END;
$$;

-- Privacy e termini in vigore accettati adesso (ora del server). La data dei testi in vigore sta
-- nell'app (`src/config/association.ts`), come sul sito (`associazione.json`, `legaliAggiornatiAl`).
CREATE OR REPLACE FUNCTION "public"."accept_my_legal_documents"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_at timestamptz := now();
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;
    UPDATE public.profiles
       SET accepted_terms_at = v_at, accepted_privacy_at = v_at
     WHERE id = auth.uid();
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PROFILE_NOT_FOUND');
    END IF;
    RETURN jsonb_build_object('ok', true, 'accepted_at', v_at);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Versione minima dell'app
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO "public"."feature_flags" ("key", "enabled", "description", "payload")
VALUES ('app_version_gate', false,
        'Versione minima (blocca) e consigliata (invita) dell''app su iPhone e Android, con il link allo store. Vale dalle build per gli store (sessione 13).',
        '{"ios": {"min": null, "latest": null, "store_url": null}, "android": {"min": null, "latest": null, "store_url": null}, "message": null}'::jsonb)
ON CONFLICT ("key") DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Permessi: le funzioni nuove nascono chiuse; si aprono solo queste, ad authenticated.
--    `delete_account_data` resta a service_role (la chiama l'edge function `delete-account`).
-- ─────────────────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION "public"."update_my_profile"("text", "text", "date") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."accept_my_legal_documents"() TO "authenticated";
