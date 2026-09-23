-- Migration 20260923160700: lezioni di prova e lista d'attesa (sessione 3, blocco 7)
--
-- PROVE (F1–F7). Nel database non esiste alcun concetto di prova. Le regole decise:
--   * una prova per ATTIVITÀ (Yoga e poi Meditazione), anche per chi ha già un abbonamento;
--   * gratuita se poi non si compra nulla; se si compra un abbonamento, la prova DIVENTA il primo
--     ingresso e quindi l'abbonamento ha un ingresso in meno;
--   * nessun limite di tempo fra prova e acquisto, e lo staff può correggere a mano;
--   * nessun limite di posti: la prova occupa un posto come gli altri, fino alla capienza;
--   * la disponibilità si imposta per attività (`activities.trial_enabled`);
--   * la prova ai non soci è un interruttore, di partenza SPENTO, in attesa della risposta 1.2 del
--     commercialista.
--
-- La scelta che il piano lasciava aperta: la prova si scala SOLO da un abbonamento che copre
-- l'attività provata, e ne scala UNA sola per abbonamento. Se qualcunə ha due prove in due attività
-- diverse e compra un pacchetto che le copre entrambe, ne converte una e l'altra resta a disposizione
-- dello staff: consumare due ingressi senza dirlo sarebbe una sorpresa sgradevole.
--
-- LISTA D'ATTESA (H5). La tabella `waitlist` esiste dal principio, non la usa nessuno e ha `user_id`
-- invece di `client_id`. Qui prende le colonne che servono e delle regole, che non erano scritte da
-- nessuna parte:
--   * chi si iscrive prende un numero d'ordine;
--   * quando si libera un posto, il primo della fila riceve un'OFFERTA valida 2 ore (e comunque non
--     oltre la scadenza delle prenotazioni), con una notifica. Non si prenota da soli al posto suo:
--     va scelto l'abbonamento, e nessuno vuole trovarsi prenotato a sua insaputa;
--   * se l'offerta scade, passa al successivo. La scadenza si verifica al momento, senza bisogno di
--     un cron nuovo.
--
-- Compatibilità: colonne nuove sempre NULL o con DEFAULT, tabelle e funzioni nuove. `book_lesson` e
-- le altre RPC esistenti non vengono toccate qui.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 F1–F7, H5.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enum
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
    CREATE TYPE "public"."trial_status" AS ENUM (
        'booked',       -- prenotata
        'attended',     -- fatta
        'no_show',      -- non si è presentatə
        'canceled',     -- disdetta
        'converted'     -- ha comprato un abbonamento: è diventata il primo ingresso
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE "public"."waitlist_status" AS ENUM (
        'waiting',      -- in fila
        'offered',      -- si è liberato un posto: ha la precedenza fino alla scadenza
        'booked',       -- ha prenotato
        'expired',      -- non ha risposto in tempo
        'left'          -- si è tolto dalla fila
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Prove
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."activities"
    ADD COLUMN IF NOT EXISTS "trial_enabled" boolean DEFAULT true NOT NULL;

COMMENT ON COLUMN "public"."activities"."trial_enabled" IS
    'Se questa attività si può provare. Di partenza sì per tutte le lezioni di gruppo (F3); le individuali restano comunque escluse.';

ALTER TABLE "public"."bookings"
    ADD COLUMN IF NOT EXISTS "is_trial" boolean DEFAULT false NOT NULL;

COMMENT ON COLUMN "public"."bookings"."is_trial" IS
    'Prenotazione fatta come lezione di prova: non consuma ingressi e non richiede un abbonamento.';

CREATE TABLE IF NOT EXISTS "public"."trials" (
    "id"                        "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id"                 "uuid"  NOT NULL,
    "activity_id"               "uuid"  NOT NULL,
    "lesson_id"                 "uuid",
    "booking_id"                "uuid",
    "status"                    "public"."trial_status" DEFAULT 'booked'::"public"."trial_status" NOT NULL,
    "booked_at"                 timestamp with time zone DEFAULT "now"() NOT NULL,
    "converted_subscription_id" "uuid",
    "converted_at"              timestamp with time zone,
    "converted_by"              "uuid",
    "was_member_at_booking"     boolean DEFAULT true NOT NULL,
    "note"                      "text",
    "created_by"                "uuid",
    "created_at"                timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"                timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "trials_pkey" PRIMARY KEY ("id"),
    -- Una prova per attività, per sempre (F3)
    CONSTRAINT "trials_client_activity_key" UNIQUE ("client_id", "activity_id"),
    CONSTRAINT "trials_client_id_fkey"
        FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE,
    CONSTRAINT "trials_activity_id_fkey"
        FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE CASCADE,
    CONSTRAINT "trials_lesson_id_fkey"
        FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE SET NULL,
    CONSTRAINT "trials_booking_id_fkey"
        FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL,
    CONSTRAINT "trials_converted_subscription_id_fkey"
        FOREIGN KEY ("converted_subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE SET NULL,
    CONSTRAINT "trials_converted_by_fkey"
        FOREIGN KEY ("converted_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "trials_converted_consistency"
        CHECK (("status" = 'converted'::"public"."trial_status"
                AND "converted_subscription_id" IS NOT NULL AND "converted_at" IS NOT NULL)
            OR ("status" <> 'converted'::"public"."trial_status"))
);

ALTER TABLE "public"."trials" OWNER TO "postgres";

COMMENT ON TABLE "public"."trials" IS
    'Lezioni di prova. Una per persona e per attività: il vincolo di unicità è la regola, non una convenzione. La conversione in primo ingresso avviene quando si compra un abbonamento che copre l''attività provata.';
COMMENT ON COLUMN "public"."trials"."was_member_at_booking" IS
    'Se al momento della prenotazione la persona era già sociə. Serve a misurare quanto porta la prova ai non soci, se verrà accesa (F3).';

CREATE INDEX IF NOT EXISTS "idx_trials_status" ON "public"."trials" ("status", "booked_at");
CREATE INDEX IF NOT EXISTS "idx_trials_client" ON "public"."trials" ("client_id");

CREATE OR REPLACE TRIGGER "trials_updated_at"
    BEFORE UPDATE ON "public"."trials"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Lista d'attesa: colonne nuove
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."waitlist"
    ADD COLUMN IF NOT EXISTS "client_id" "uuid",
    ADD COLUMN IF NOT EXISTS "status" "public"."waitlist_status"
        DEFAULT 'waiting'::"public"."waitlist_status" NOT NULL,
    ADD COLUMN IF NOT EXISTS "position" integer,
    ADD COLUMN IF NOT EXISTS "offered_at" timestamp with time zone,
    ADD COLUMN IF NOT EXISTS "expires_at" timestamp with time zone,
    ADD COLUMN IF NOT EXISTS "notified_at" timestamp with time zone,
    ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL;

DO $$ BEGIN
    ALTER TABLE "public"."waitlist" ADD CONSTRAINT "waitlist_client_id_fkey"
        FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN "public"."waitlist"."client_id" IS
    'Scheda cliente in fila. La vecchia colonna `user_id` resta: la tabella non è mai stata usata da nessuna app, ma toglierla sarebbe distruttivo.';
COMMENT ON COLUMN "public"."waitlist"."expires_at" IS
    'Fino a quando vale l''offerta: due ore, e comunque non oltre la scadenza delle prenotazioni della lezione.';

CREATE UNIQUE INDEX IF NOT EXISTS "waitlist_one_active_per_lesson_client"
    ON "public"."waitlist" ("lesson_id", "client_id")
    WHERE ("client_id" IS NOT NULL
           AND "status" IN ('waiting'::"public"."waitlist_status", 'offered'::"public"."waitlist_status"));

CREATE INDEX IF NOT EXISTS "idx_waitlist_lesson_status"
    ON "public"."waitlist" ("lesson_id", "status", "position");

CREATE OR REPLACE TRIGGER "waitlist_updated_at"
    BEFORE UPDATE ON "public"."waitlist"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RLS e grant
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."trials" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "trials_select_own_or_staff" ON "public"."trials";
CREATE POLICY "trials_select_own_or_staff" ON "public"."trials"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"() OR "client_id" = "public"."get_my_client_id"());

DROP POLICY IF EXISTS "trials_write_staff" ON "public"."trials";
CREATE POLICY "trials_write_staff" ON "public"."trials"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."trials" TO "authenticated";

-- `waitlist` aveva RLS attivo e nessuna policy: dall'API era irraggiungibile. Ora serve.
ALTER TABLE "public"."waitlist" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "waitlist_select_own_or_staff" ON "public"."waitlist";
CREATE POLICY "waitlist_select_own_or_staff" ON "public"."waitlist"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"() OR "client_id" = "public"."get_my_client_id"());

DROP POLICY IF EXISTS "waitlist_write_staff" ON "public"."waitlist";
CREATE POLICY "waitlist_write_staff" ON "public"."waitlist"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."waitlist" TO "authenticated";

-- Interruttore della prova ai non soci, SPENTO finché il commercialista non risponde (1.2).
INSERT INTO "public"."feature_flags" ("key", "enabled", "description") VALUES
    ('trial_for_non_members', false,
     'Permette la lezione di prova anche a chi non è ancora sociə. Spento in attesa della conferma del commercialista (domanda 1.2).')
ON CONFLICT ("key") DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Funzioni: prove
-- ─────────────────────────────────────────────────────────────────────────────

-- 5.1 — Motore comune: registra la prova e la prenotazione. Interna.
CREATE OR REPLACE FUNCTION "public"."create_trial_booking"(
    "p_lesson_id" "uuid",
    "p_client_id" "uuid",
    "p_created_by" "uuid",
    "p_skip_deadline" boolean DEFAULT false
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_lesson        public.lessons%ROWTYPE;
    v_activity      public.activities%ROWTYPE;
    v_booked_count  integer;
    v_booking_id    uuid;
    v_trial_id      uuid;
    v_is_member     boolean;
BEGIN
    SELECT * INTO v_lesson FROM public.lessons WHERE id = p_lesson_id FOR UPDATE;
    IF NOT FOUND OR v_lesson.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    -- Le individuali non si provano: sono assegnate a una persona precisa
    IF v_lesson.is_individual THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRIAL_NOT_AVAILABLE');
    END IF;

    SELECT * INTO v_activity FROM public.activities WHERE id = v_lesson.activity_id;
    IF NOT FOUND OR v_activity.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    IF v_activity.trial_enabled = false THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRIAL_NOT_AVAILABLE');
    END IF;

    IF EXISTS (SELECT 1 FROM public.trials
                WHERE client_id = p_client_id AND activity_id = v_activity.id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRIAL_ALREADY_USED');
    END IF;

    IF NOT p_skip_deadline
       AND now() > v_lesson.starts_at - make_interval(mins => COALESCE(v_lesson.booking_deadline_minutes, 30)) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
    END IF;

    IF EXISTS (SELECT 1 FROM public.bookings
                WHERE lesson_id = p_lesson_id AND client_id = p_client_id AND status = 'booked') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    -- La prova occupa un posto come tutti gli altri (F3)
    SELECT count(*) INTO v_booked_count
      FROM public.bookings WHERE lesson_id = p_lesson_id AND status = 'booked';
    IF v_booked_count >= v_lesson.capacity THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;

    INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status, is_trial)
    VALUES (p_lesson_id, p_client_id, NULL, 'booked', true)
    ON CONFLICT (lesson_id, client_id) WHERE status = 'booked' AND client_id IS NOT NULL
    DO NOTHING
    RETURNING id INTO v_booking_id;

    IF v_booking_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    v_is_member := EXISTS (SELECT 1 FROM public.members
                            WHERE client_id = p_client_id AND status = 'active');

    INSERT INTO public.trials (client_id, activity_id, lesson_id, booking_id,
                               was_member_at_booking, created_by)
    VALUES (p_client_id, v_activity.id, p_lesson_id, v_booking_id, v_is_member, p_created_by)
    RETURNING id INTO v_trial_id;

    RETURN jsonb_build_object('ok', true, 'reason', 'BOOKED',
                              'booking_id', v_booking_id, 'trial_id', v_trial_id);
END;
$$;

ALTER FUNCTION "public"."create_trial_booking"("uuid", "uuid", "uuid", boolean) OWNER TO "postgres";
COMMENT ON FUNCTION "public"."create_trial_booking"("uuid", "uuid", "uuid", boolean) IS
    'Motore della prenotazione di prova: capienza, scadenza, una prova per attività. Funzione interna, la chiamano le RPC qui sotto.';

-- 5.2 — La persona prenota la propria prova dall'app.
CREATE OR REPLACE FUNCTION "public"."book_trial_lesson"("p_lesson_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    RETURN public.create_trial_booking(p_lesson_id, v_client_id, auth.uid(), false);
END;
$$;

ALTER FUNCTION "public"."book_trial_lesson"("uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."book_trial_lesson"("uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."book_trial_lesson"("uuid") IS
    'Prenota la propria lezione di prova. Una per attività, occupa un posto come le altre prenotazioni.';

-- 5.3 — Lo staff aggiunge una prova dalla pagina della lezione (F5).
CREATE OR REPLACE FUNCTION "public"."staff_book_trial"("p_lesson_id" "uuid", "p_client_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clients WHERE id = p_client_id AND deleted_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    -- Allo staff la scadenza non si applica: sta parlando con la persona di persona
    RETURN public.create_trial_booking(p_lesson_id, p_client_id, auth.uid(), true);
END;
$$;

ALTER FUNCTION "public"."staff_book_trial"("uuid", "uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_book_trial"("uuid", "uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_book_trial"("uuid", "uuid") IS
    'Aggiunge una lezione di prova dal gestionale, senza obbligo di abbonamento (F5).';

-- 5.4 — Chi non è ancora in anagrafica: si crea la scheda e si prenota la prova (F5).
CREATE OR REPLACE FUNCTION "public"."staff_create_client_and_book_trial"(
    "p_lesson_id" "uuid",
    "p_first_name" "text",
    "p_last_name" "text",
    "p_phone" "text",
    "p_email" "text"
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_full_name text;
    v_email     text := NULLIF(btrim(lower(COALESCE(p_email, ''))), '');
    v_result    jsonb;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF COALESCE(btrim(p_first_name), '') = '' OR COALESCE(btrim(p_last_name), '') = '' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MISSING_REQUIRED_FIELDS');
    END IF;

    v_full_name := btrim(p_first_name) || ' ' || btrim(p_last_name);

    -- Se quell'email esiste già si riusa la scheda, invece di crearne una doppia
    IF v_email IS NOT NULL THEN
        SELECT id INTO v_client_id FROM public.clients
         WHERE lower(email) = v_email AND deleted_at IS NULL LIMIT 1;
    END IF;

    IF v_client_id IS NULL THEN
        INSERT INTO public.clients (full_name, email, phone)
        VALUES (v_full_name, v_email, NULLIF(btrim(COALESCE(p_phone, '')), ''))
        RETURNING id INTO v_client_id;
    END IF;

    v_result := public.create_trial_booking(p_lesson_id, v_client_id, auth.uid(), true);
    RETURN v_result || jsonb_build_object('client_id', v_client_id);
END;
$$;

ALTER FUNCTION "public"."staff_create_client_and_book_trial"("uuid", "text", "text", "text", "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_create_client_and_book_trial"("uuid", "text", "text", "text", "text") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_create_client_and_book_trial"("uuid", "text", "text", "text", "text") IS
    'Crea al volo la scheda cliente di chi non è ancora in anagrafica e le prenota la prova (F5). Se l''email esiste già, riusa la scheda invece di duplicarla.';

-- 5.5 — Conversione automatica: l'abbonamento nuovo assorbe la prova (F2, F4).
CREATE OR REPLACE FUNCTION "public"."convert_trial_on_new_subscription"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_trial public.trials%ROWTYPE;
BEGIN
    IF NEW.client_id IS NULL OR NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- La prova più vecchia ancora da convertire, fra quelle coperte dall'abbonamento.
    -- Una sola per abbonamento: scalarne due senza dirlo sarebbe una sorpresa.
    SELECT t.* INTO v_trial
      FROM public.trials t
     WHERE t.client_id = NEW.client_id
       AND t.status IN ('booked', 'attended', 'no_show')
       AND public.subscription_covers_activity(NEW.id, t.activity_id)
     ORDER BY t.booked_at
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
    VALUES (NEW.id, v_trial.booking_id, -1, 'TRIAL');

    UPDATE public.trials
       SET status = 'converted',
           converted_subscription_id = NEW.id,
           converted_at = now()
     WHERE id = v_trial.id;

    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."convert_trial_on_new_subscription"() OWNER TO "postgres";
COMMENT ON FUNCTION "public"."convert_trial_on_new_subscription"() IS
    'Quando nasce un abbonamento che copre un''attività già provata, la prova diventa il primo ingresso: una riga in `subscription_usages` e la prova passa a "convertita" (F2).';

CREATE OR REPLACE TRIGGER "subscriptions_convert_trial"
    AFTER INSERT ON "public"."subscriptions"
    FOR EACH ROW EXECUTE FUNCTION "public"."convert_trial_on_new_subscription"();

-- 5.6 — Correzione a mano (F4).
CREATE OR REPLACE FUNCTION "public"."staff_unconvert_trial"("p_trial_id" "uuid", "p_reason" "text")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_trial public.trials%ROWTYPE;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    SELECT * INTO v_trial FROM public.trials WHERE id = p_trial_id FOR UPDATE;
    IF NOT FOUND OR v_trial.status <> 'converted' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRIAL_NOT_CONVERTED');
    END IF;

    DELETE FROM public.subscription_usages
     WHERE subscription_id = v_trial.converted_subscription_id
       AND reason = 'TRIAL'
       AND (booking_id = v_trial.booking_id OR (booking_id IS NULL AND v_trial.booking_id IS NULL));

    UPDATE public.trials
       SET status = 'attended',
           converted_subscription_id = NULL,
           converted_at = NULL,
           converted_by = auth.uid(),
           note = COALESCE(note || ' · ', '') || 'Conversione annullata: ' || COALESCE(p_reason, '')
     WHERE id = p_trial_id;

    RETURN jsonb_build_object('ok', true, 'reason', 'UNCONVERTED');
END;
$$;

ALTER FUNCTION "public"."staff_unconvert_trial"("uuid", "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_unconvert_trial"("uuid", "text") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_unconvert_trial"("uuid", "text") IS
    'Annulla la conversione di una prova e restituisce l''ingresso all''abbonamento. Serve a correggere, perché la conversione è automatica (F4).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Funzioni: lista d'attesa
-- ─────────────────────────────────────────────────────────────────────────────

-- 6.1 — Mettersi in fila.
CREATE OR REPLACE FUNCTION "public"."join_waitlist"("p_lesson_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_lesson    public.lessons%ROWTYPE;
    v_booked    integer;
    v_position  integer;
    v_id        uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    SELECT * INTO v_lesson FROM public.lessons WHERE id = p_lesson_id FOR UPDATE;
    IF NOT FOUND OR v_lesson.deleted_at IS NOT NULL OR v_lesson.is_individual THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    IF now() > v_lesson.starts_at - make_interval(mins => COALESCE(v_lesson.booking_deadline_minutes, 30)) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
    END IF;

    IF EXISTS (SELECT 1 FROM public.bookings
                WHERE lesson_id = p_lesson_id AND client_id = v_client_id AND status = 'booked') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;

    -- Ci si mette in lista solo se la lezione è piena: altrimenti si prenota e basta
    SELECT count(*) INTO v_booked
      FROM public.bookings WHERE lesson_id = p_lesson_id AND status = 'booked';
    IF v_booked < v_lesson.capacity THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FULL');
    END IF;

    IF EXISTS (SELECT 1 FROM public.waitlist
                WHERE lesson_id = p_lesson_id AND client_id = v_client_id
                  AND status IN ('waiting', 'offered')) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_IN_WAITLIST');
    END IF;

    SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
      FROM public.waitlist WHERE lesson_id = p_lesson_id;

    INSERT INTO public.waitlist (lesson_id, client_id, user_id, status, position)
    VALUES (p_lesson_id, v_client_id, auth.uid(), 'waiting', v_position)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('ok', true, 'reason', 'JOINED',
                              'waitlist_id', v_id, 'position', v_position);
END;
$$;

ALTER FUNCTION "public"."join_waitlist"("uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."join_waitlist"("uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."join_waitlist"("uuid") IS
    'Si mette in lista d''attesa per una lezione piena, prendendo un numero d''ordine.';

-- 6.2 — Uscire dalla fila.
CREATE OR REPLACE FUNCTION "public"."leave_waitlist"("p_lesson_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();

    UPDATE public.waitlist
       SET status = 'left'
     WHERE lesson_id = p_lesson_id AND client_id = v_client_id
       AND status IN ('waiting', 'offered');

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_IN_WAITLIST');
    END IF;

    PERFORM public.promote_from_waitlist(p_lesson_id);
    RETURN jsonb_build_object('ok', true, 'reason', 'LEFT');
END;
$$;

ALTER FUNCTION "public"."leave_waitlist"("uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."leave_waitlist"("uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."leave_waitlist"("uuid") IS
    'Esce dalla lista d''attesa e, se aveva un''offerta in corso, la passa al successivo.';

-- 6.3 — Offre il posto libero al primo della fila. Interna: la chiamano le disdette.
CREATE OR REPLACE FUNCTION "public"."promote_from_waitlist"("p_lesson_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_lesson    public.lessons%ROWTYPE;
    v_booked    integer;
    v_offered   integer;
    v_next      public.waitlist%ROWTYPE;
    v_expires   timestamptz;
    v_channel   public.notification_channel;
    v_activity  text;
BEGIN
    SELECT * INTO v_lesson FROM public.lessons WHERE id = p_lesson_id;
    IF NOT FOUND OR v_lesson.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LESSON_NOT_FOUND');
    END IF;

    -- Prima si chiudono le offerte scadute: così non serve un cron dedicato
    UPDATE public.waitlist
       SET status = 'expired'
     WHERE lesson_id = p_lesson_id AND status = 'offered' AND expires_at < now();

    -- Oltre la scadenza delle prenotazioni non ha senso offrire nulla
    IF now() > v_lesson.starts_at - make_interval(mins => COALESCE(v_lesson.booking_deadline_minutes, 30)) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_DEADLINE_PASSED');
    END IF;

    SELECT count(*) INTO v_booked
      FROM public.bookings WHERE lesson_id = p_lesson_id AND status = 'booked';
    SELECT count(*) INTO v_offered
      FROM public.waitlist WHERE lesson_id = p_lesson_id AND status = 'offered';

    -- Un'offerta è un posto già impegnato: si offre solo se ne restano davvero
    IF (v_booked + v_offered) >= v_lesson.capacity THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NO_FREE_SEAT');
    END IF;

    SELECT * INTO v_next
      FROM public.waitlist
     WHERE lesson_id = p_lesson_id AND status = 'waiting'
     ORDER BY position, created_at
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'WAITLIST_EMPTY');
    END IF;

    v_expires := LEAST(
        now() + INTERVAL '2 hours',
        v_lesson.starts_at - make_interval(mins => COALESCE(v_lesson.booking_deadline_minutes, 30))
    );

    UPDATE public.waitlist
       SET status = 'offered', offered_at = now(), expires_at = v_expires, notified_at = now()
     WHERE id = v_next.id;

    SELECT a.name INTO v_activity FROM public.activities a WHERE a.id = v_lesson.activity_id;
    v_channel := public.get_notification_channel(v_next.client_id, 'waitlist_promotion');

    IF v_channel IS NOT NULL THEN
        INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
        VALUES (
            v_next.client_id, 'waitlist_promotion', v_channel,
            'Si è liberato un posto',
            'Si è liberato un posto per ' || COALESCE(v_activity, 'la lezione')
                || ' del ' || to_char(v_lesson.starts_at AT TIME ZONE 'Europe/Rome', 'DD/MM alle HH24:MI')
                || '. Hai tempo fino alle '
                || to_char(v_expires AT TIME ZONE 'Europe/Rome', 'HH24:MI') || ' per prenotare.',
            jsonb_build_object('lesson_id', p_lesson_id, 'expires_at', v_expires),
            now()
        );
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'OFFERED',
                              'client_id', v_next.client_id, 'expires_at', v_expires);
END;
$$;

ALTER FUNCTION "public"."promote_from_waitlist"("uuid") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."promote_from_waitlist"("uuid") IS
    'Offre il posto liberatosi al primo della lista, per due ore e comunque non oltre la scadenza delle prenotazioni, con una notifica. Non prenota al posto suo: l''abbonamento lo sceglie la persona.';

-- 6.4 — Chiude le offerte scadute ovunque e riparte con le fila che ne hanno bisogno.
CREATE OR REPLACE FUNCTION "public"."expire_waitlist_offers"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_lesson_id uuid;
    v_expired   integer := 0;
BEGIN
    FOR v_lesson_id IN
        SELECT DISTINCT lesson_id FROM public.waitlist
         WHERE status = 'offered' AND expires_at < now()
    LOOP
        UPDATE public.waitlist
           SET status = 'expired'
         WHERE lesson_id = v_lesson_id AND status = 'offered' AND expires_at < now();
        v_expired := v_expired + 1;
        PERFORM public.promote_from_waitlist(v_lesson_id);
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'lessons_processed', v_expired);
END;
$$;

ALTER FUNCTION "public"."expire_waitlist_offers"() OWNER TO "postgres";
COMMENT ON FUNCTION "public"."expire_waitlist_offers"() IS
    'Chiude le offerte scadute e passa al successivo. Funzione interna, pensata per essere agganciata al cron delle notifiche.';

-- 6.5 — Quando una prenotazione viene disdetta, il posto si offre a chi è in fila.
CREATE OR REPLACE FUNCTION "public"."offer_waitlist_on_booking_cancel"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    PERFORM public.promote_from_waitlist(NEW.lesson_id);
    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."offer_waitlist_on_booking_cancel"() OWNER TO "postgres";
COMMENT ON FUNCTION "public"."offer_waitlist_on_booking_cancel"() IS
    'Alla disdetta di una prenotazione offre il posto al primo della lista d''attesa.';

CREATE OR REPLACE TRIGGER "bookings_offer_waitlist_on_cancel"
    AFTER UPDATE OF "status" ON "public"."bookings"
    FOR EACH ROW
    WHEN (OLD."status" = 'booked'::"public"."booking_status"
          AND NEW."status" = 'canceled'::"public"."booking_status")
    EXECUTE FUNCTION "public"."offer_waitlist_on_booking_cancel"();
