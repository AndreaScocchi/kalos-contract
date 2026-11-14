-- Calendario collegato (14/11/2026, richiesta dell'utente).
--
-- Le prenotazioni di una persona nel calendario del telefono o in Google Calendar, aggiornate da
-- sole: l'app dà a ciascunə un indirizzo segreto (`webcal://…/calendar-feed/<token>.ics`); il
-- calendario lo rilegge ogni tanto e l'edge function `calendar-feed` risponde con le lezioni e gli
-- eventi prenotati (decisione dell'utente: solo le proprie prenotazioni).
--
-- - `internal.calendar_feeds`: un indirizzo per scheda cliente. Fuori dall'API: lo leggono solo
--   le funzioni qui sotto. Il token è in chiaro perché l'app lo deve poter mostrare di nuovo (per
--   collegare un altro dispositivo); chi lo conosce vede le prenotazioni, per questo si può cambiare.
-- - `get_my_calendar_feed()` (cliente): il proprio token, creato la prima volta.
-- - `reset_my_calendar_feed()` (cliente): un token nuovo; i calendari collegati col vecchio smettono
--   di aggiornarsi.
-- - `calendar_feed_items(p_token)` (solo service_role): le prenotazioni per l'edge function.
-- - Se la scheda perde o cambia l'account (eliminazione dell'account), l'indirizzo si cancella.

-- migration-lint:allow revoke — reason: le REVOKE riguardano solo la tabella e le funzioni nuove di questa migrazione (chiuse ad anon e, dove serve, ad authenticated).

CREATE TABLE "internal"."calendar_feeds" (
    "client_id" "uuid" NOT NULL,
    "token" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_read_at" timestamp with time zone,
    CONSTRAINT "calendar_feeds_pkey" PRIMARY KEY ("client_id"),
    CONSTRAINT "calendar_feeds_token_key" UNIQUE ("token"),
    CONSTRAINT "calendar_feeds_token_format" CHECK ("token" ~ '^[0-9a-f]{64}$'),
    CONSTRAINT "calendar_feeds_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE
);

COMMENT ON TABLE "internal"."calendar_feeds" IS
    'Calendario collegato: l''indirizzo segreto di ogni scheda cliente per il calendario del telefono o Google Calendar (edge function calendar-feed). `last_read_at`: ultima lettura, al più una scrittura all''ora.';

ALTER TABLE "internal"."calendar_feeds" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON "internal"."calendar_feeds" FROM PUBLIC, "anon", "authenticated";


-- 64 cifre esadecimali da due UUID casuali (244 bit casuali): niente estensioni.
CREATE FUNCTION "internal"."new_calendar_token"() RETURNS "text"
    LANGUAGE "sql" VOLATILE
    SET "search_path" TO 'public'
    AS $$
    SELECT replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
$$;

ALTER FUNCTION "internal"."new_calendar_token"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "internal"."new_calendar_token"() FROM PUBLIC, "anon", "authenticated";


CREATE FUNCTION "public"."get_my_calendar_feed"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_token text;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;
    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    SELECT token INTO v_token FROM internal.calendar_feeds WHERE client_id = v_client_id;
    IF v_token IS NULL THEN
        INSERT INTO internal.calendar_feeds (client_id, token)
        VALUES (v_client_id, internal.new_calendar_token())
        ON CONFLICT (client_id) DO NOTHING;
        SELECT token INTO v_token FROM internal.calendar_feeds WHERE client_id = v_client_id;
    END IF;

    RETURN jsonb_build_object('ok', true, 'token', v_token);
END;
$$;

ALTER FUNCTION "public"."get_my_calendar_feed"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."get_my_calendar_feed"() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."get_my_calendar_feed"() TO "authenticated", "service_role";

COMMENT ON FUNCTION "public"."get_my_calendar_feed"() IS
    'Calendario collegato: il token della propria scheda, creato la prima volta. {ok, token} oppure {ok: false, reason: NOT_AUTHENTICATED | CLIENT_NOT_FOUND}.';


CREATE FUNCTION "public"."reset_my_calendar_feed"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_token text := internal.new_calendar_token();
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;
    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    INSERT INTO internal.calendar_feeds (client_id, token)
    VALUES (v_client_id, v_token)
    ON CONFLICT (client_id) DO UPDATE SET token = EXCLUDED.token, created_at = now(), last_read_at = NULL;

    RETURN jsonb_build_object('ok', true, 'token', v_token);
END;
$$;

ALTER FUNCTION "public"."reset_my_calendar_feed"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."reset_my_calendar_feed"() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."reset_my_calendar_feed"() TO "authenticated", "service_role";

COMMENT ON FUNCTION "public"."reset_my_calendar_feed"() IS
    'Calendario collegato: un token nuovo per la propria scheda; i calendari collegati col vecchio smettono di aggiornarsi. {ok, token}.';


-- Le prenotazioni dell'indirizzo: lezioni ed eventi non disdetti, dagli ultimi 60 giorni in poi.
-- Il luogo di una lezione è il suo, o quello predefinito dell'attività (come l'app); quello di un
-- evento il luogo collegato, o il testo scritto dallo staff. Un evento senza fine dura due ore.
CREATE FUNCTION "public"."calendar_feed_items"("p_token" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_from timestamptz := now() - interval '60 days';
    v_items jsonb;
BEGIN
    IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
        RETURN jsonb_build_object('found', false);
    END IF;

    SELECT f.client_id INTO v_client_id
    FROM internal.calendar_feeds f
    JOIN public.clients c ON c.id = f.client_id
    WHERE f.token = p_token
      AND c.deleted_at IS NULL
      AND c.profile_id IS NOT NULL;
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('found', false);
    END IF;

    UPDATE internal.calendar_feeds
    SET last_read_at = now()
    WHERE client_id = v_client_id
      AND (last_read_at IS NULL OR last_read_at < now() - interval '1 hour');

    SELECT COALESCE(jsonb_agg(item ORDER BY item->>'starts_at'), '[]'::jsonb) INTO v_items
    FROM (
        SELECT jsonb_build_object(
            'uid', 'booking-' || b.id,
            'kind', 'lesson',
            'id', l.id,
            'title', a.name,
            'is_trial', b.is_trial,
            'starts_at', l.starts_at,
            'ends_at', l.ends_at,
            'place', loc.name,
            'address', concat_ws(', ', NULLIF(loc.address_street, ''), NULLIF(concat_ws(' ', NULLIF(loc.address_zip, ''), loc.city), ''), NULLIF(loc.province, '')),
            'operator', o.name,
            'booked_at', b.created_at
        ) AS item
        FROM public.bookings b
        JOIN public.lessons l ON l.id = b.lesson_id
        JOIN public.activities a ON a.id = l.activity_id
        LEFT JOIN public.locations loc ON loc.id = COALESCE(l.location_id, a.default_location_id)
        LEFT JOIN public.operators o ON o.id = l.operator_id
        WHERE b.client_id = v_client_id
          AND b.status <> 'canceled'
          AND l.deleted_at IS NULL
          AND l.starts_at >= v_from

        UNION ALL

        SELECT jsonb_build_object(
            'uid', 'event-booking-' || eb.id,
            'kind', 'event',
            'id', e.id,
            'title', e.name,
            'is_trial', false,
            'starts_at', e.starts_at,
            'ends_at', COALESCE(e.ends_at, e.starts_at + interval '2 hours'),
            'place', COALESCE(loc.name, NULLIF(e.location, '')),
            'address', CASE WHEN loc.id IS NULL THEN NULL ELSE concat_ws(', ', NULLIF(loc.address_street, ''), NULLIF(concat_ws(' ', NULLIF(loc.address_zip, ''), loc.city), ''), NULLIF(loc.province, '')) END,
            'operator', NULL,
            'booked_at', eb.created_at
        )
        FROM public.event_bookings eb
        JOIN public.events e ON e.id = eb.event_id
        LEFT JOIN public.locations loc ON loc.id = e.location_id
        WHERE eb.client_id = v_client_id
          AND eb.status <> 'canceled'
          AND e.deleted_at IS NULL
          AND e.is_active
          AND e.starts_at >= v_from
    ) items;

    RETURN jsonb_build_object('found', true, 'items', v_items);
END;
$$;

ALTER FUNCTION "public"."calendar_feed_items"("text") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."calendar_feed_items"("text") FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON FUNCTION "public"."calendar_feed_items"("text") TO "service_role";

COMMENT ON FUNCTION "public"."calendar_feed_items"("text") IS
    'Calendario collegato, solo service_role (edge function calendar-feed): le prenotazioni non disdette dagli ultimi 60 giorni in poi del token. {found: false} per un token sconosciuto, di una scheda eliminata o senza account.';


-- Una scheda che perde o cambia l'account (eliminazione dell'account, scheda unita a un'altra
-- persona) perde anche l'indirizzo: chi tornasse con lo stesso account ne riceve uno nuovo.
CREATE FUNCTION "internal"."clients_drop_calendar_feed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    DELETE FROM internal.calendar_feeds WHERE client_id = NEW.id;
    RETURN NEW;
END;
$$;

ALTER FUNCTION "internal"."clients_drop_calendar_feed"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "internal"."clients_drop_calendar_feed"() FROM PUBLIC, "anon", "authenticated";

CREATE TRIGGER "clients_drop_calendar_feed"
    AFTER UPDATE OF "profile_id", "deleted_at" ON "public"."clients"
    FOR EACH ROW
    WHEN ((OLD."profile_id" IS DISTINCT FROM NEW."profile_id") OR (OLD."deleted_at" IS NULL AND NEW."deleted_at" IS NOT NULL))
    EXECUTE FUNCTION "internal"."clients_drop_calendar_feed"();
