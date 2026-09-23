-- Migration 20260923160100: modello soci dell'APS (sessione 3, blocco 1)
--
-- Obiettivo: dare al database il concetto di SOCIO come lo descrive lo statuto registrato l'11/09/2026,
-- che oggi non esiste da nessuna parte:
--   1. `association_years`   — la quota per ANNO SOLARE (art. 5): importo e data di decadenza li
--                              delibera il Consiglio Direttivo ogni anno, quindi sono DATI, non codice.
--   2. `member_applications` — la domanda di ammissione (art. 4) come "accettazione registrata":
--                              dati anagrafici, spunte di statuto e privacy, data, ora e dispositivo.
--                              Minorenni con dati e consenso di chi esercita la responsabilità.
--   3. `members`             — il libro soci (art. 22): numero, data di ammissione, data della delibera,
--                              cessazione con causale. Un socio per scheda cliente.
--   4. `member_fees`         — la quota dovuta/pagata per anno, una riga per socio e per anno.
--
-- Perché tabelle nuove e non `memberships`: il Community Pass (`memberships`, `pass_tiers`,
-- `pass_tier_benefits`, migrazione 20260603140000) è un tesseramento commerciale a livelli, valido 365
-- giorni dall'attivazione. Lo statuto vuole l'anno solare e vieta differenze di trattamento fra soci
-- (art. 5). Sono due cose diverse: il Pass resta intatto e inutilizzato (flag `community_pass` spento)
-- e qui nasce il modello vero. Decisione presa il 2026-09-23, docs/PIANO-APS-E-NUOVA-APP.md §3 A4.
--
-- Il PDF della domanda, i documenti e la tessera digitale sono file: qui si conserva solo il percorso.
--
-- Compatibilità: SOLO nuovi enum, nuove tabelle, nuove funzioni. Nessuna tabella, colonna, RPC o
-- constraint esistente viene toccata → website, gestionale e webapp restano identici.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §1-bis e §3 (A4, A7, A8), ACCESS_MODEL.md.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enum
-- ─────────────────────────────────────────────────────────────────────────────

-- Stato della domanda di ammissione. Lo statuto (art. 4) vuole che un rifiuto sia motivato entro 30
-- giorni: per questo `rejected` obbliga a scrivere il motivo.
DO $$ BEGIN
    CREATE TYPE "public"."member_application_status" AS ENUM (
        'pending',      -- inviata, in attesa della delibera del Consiglio Direttivo
        'approved',     -- ammessə: nasce la riga in `members`
        'rejected',     -- respinta, con motivazione obbligatoria
        'withdrawn'     -- ritirata dalla persona o annullata dallo staff
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Stato del socio. In `members` si usano solo `active` e `ceased`: `pending_admission` esiste per la
-- risposta sintetica di `get_my_membership_status()`, che descrive anche chi ha una domanda aperta e
-- quindi non ha ancora una riga qui.
DO $$ BEGIN
    CREATE TYPE "public"."member_status" AS ENUM (
        'pending_admission',
        'active',
        'ceased'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Causali di cessazione previste dallo statuto (art. 5).
DO $$ BEGIN
    CREATE TYPE "public"."member_cease_reason" AS ENUM (
        'recesso',
        'esclusione',
        'decadenza',
        'mancato_pagamento',
        'decesso'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Stato della quota di un anno. `refunded` serve al caso della domanda respinta (statuto: la quota non
-- si rimborsa, ma chi è respintə non è mai diventatə sociə — docs/PIANO-APS-E-NUOVA-APP.md §3 D4).
DO $$ BEGIN
    CREATE TYPE "public"."member_fee_status" AS ENUM (
        'due',
        'paid',
        'waived',
        'refunded'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Da dove arriva la domanda.
DO $$ BEGIN
    CREATE TYPE "public"."member_application_channel" AS ENUM (
        'app',
        'site',
        'paper'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. association_years — la quota, un anno per riga
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."association_years" (
    "year"          integer     NOT NULL,
    "fee_cents"     integer,
    "fee_due_date"  date,
    "is_open"       boolean     DEFAULT true NOT NULL,
    "notes"         "text",
    "created_by"    "uuid",
    "created_at"    timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"    timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "association_years_pkey" PRIMARY KEY ("year"),
    CONSTRAINT "association_years_year_range" CHECK ("year" BETWEEN 2026 AND 2100),
    CONSTRAINT "association_years_fee_non_negative" CHECK ("fee_cents" IS NULL OR "fee_cents" >= 0),
    CONSTRAINT "association_years_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL
);

ALTER TABLE "public"."association_years" OWNER TO "postgres";

COMMENT ON TABLE "public"."association_years" IS
    'Anno associativo (anno solare, 1 gennaio–31 dicembre, art. 5 dello statuto). Importo della quota e data di decadenza li delibera il Consiglio Direttivo, quindi sono dati modificabili dal gestionale.';
COMMENT ON COLUMN "public"."association_years"."fee_cents" IS
    'Importo della quota in centesimi. NULL finché il Consiglio Direttivo non delibera.';
COMMENT ON COLUMN "public"."association_years"."fee_due_date" IS
    'Data oltre la quale chi non ha pagato decade da sociə (art. 5). Di partenza il 31 marzo, così il libro soci è in ordine prima dell''assemblea che approva il rendiconto entro il 30 aprile (art. 18).';
COMMENT ON COLUMN "public"."association_years"."is_open" IS
    'false chiude l''anno: non si accettano più domande né quote per quell''anno.';

-- Il 31 marzo è solo il valore di partenza: non si può esprimere come DEFAULT perché dipende da `year`.
CREATE OR REPLACE FUNCTION "public"."set_association_year_default_due_date"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NEW.fee_due_date IS NULL THEN
        NEW.fee_due_date := make_date(NEW.year, 3, 31);
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."set_association_year_default_due_date"() OWNER TO "postgres";
COMMENT ON FUNCTION "public"."set_association_year_default_due_date"() IS
    'Se non indicata, la data di decadenza dell''anno è il 31 marzo di quell''anno.';

CREATE OR REPLACE TRIGGER "association_years_default_due_date"
    BEFORE INSERT ON "public"."association_years"
    FOR EACH ROW EXECUTE FUNCTION "public"."set_association_year_default_due_date"();

CREATE OR REPLACE TRIGGER "association_years_updated_at"
    BEFORE UPDATE ON "public"."association_years"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- L'associazione esiste dal 19/08/2026: il primo anno è il 2026, il secondo serve già per le domande
-- di fine anno. Importo NULL = non ancora deliberato.
INSERT INTO "public"."association_years" ("year", "fee_cents", "notes")
VALUES
    (2026, NULL, 'Primo esercizio, dal 19/08/2026 al 31/12/2026. Importo da deliberare.'),
    (2027, NULL, 'Importo da deliberare.')
ON CONFLICT ("year") DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. member_applications — la domanda di ammissione
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."member_applications" (
    "id"                        "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id"                 "uuid",
    "profile_id"                "uuid",
    "year"                      integer     NOT NULL,
    "channel"                   "public"."member_application_channel" NOT NULL,
    "status"                    "public"."member_application_status" DEFAULT 'pending'::"public"."member_application_status" NOT NULL,

    -- Anagrafica richiesta dal libro soci (domanda 1.4 al commercialista)
    "first_name"                "text"      NOT NULL,
    "last_name"                 "text"      NOT NULL,
    "fiscal_code"               "text",
    "birth_date"                "date"      NOT NULL,
    "birth_place"               "text",
    "birth_province"            "text",
    "address_street"            "text",
    "address_city"              "text",
    "address_zip"               "text",
    "address_province"          "text",
    "email"                     "text",
    "phone"                     "text",

    -- Minorenni (A7): si iscrivono con i dati e il consenso di un genitore
    "minor_at_submission"       boolean     DEFAULT false NOT NULL,
    "guardian_full_name"        "text",
    "guardian_fiscal_code"      "text",
    "guardian_relationship"     "text",
    "guardian_email"            "text",
    "guardian_phone"            "text",
    "guardian_consent_at"       timestamp with time zone,

    -- Accettazione registrata: cosa ha accettato, quando e da dove
    "accepted_statute_at"       timestamp with time zone NOT NULL,
    "accepted_privacy_at"       timestamp with time zone NOT NULL,
    "image_release"             boolean,
    "health_declaration"        boolean,
    "submitted_at"              timestamp with time zone DEFAULT "now"() NOT NULL,
    "submitted_ip"              "inet",
    "submitted_user_agent"      "text",

    -- Esito della delibera del Consiglio Direttivo
    "decided_at"                timestamp with time zone,
    "decided_by"                "uuid",
    "resolution_date"           "date",
    "decision_note"             "text",
    "rejection_reason"          "text",

    "pdf_path"                  "text",
    "metadata"                  "jsonb"     DEFAULT '{}'::"jsonb",
    "created_at"                timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"                timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "member_applications_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "member_applications_client_id_fkey"
        FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL,
    CONSTRAINT "member_applications_profile_id_fkey"
        FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "member_applications_year_fkey"
        FOREIGN KEY ("year") REFERENCES "public"."association_years"("year") ON DELETE RESTRICT,
    CONSTRAINT "member_applications_decided_by_fkey"
        FOREIGN KEY ("decided_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "member_applications_names_not_empty"
        CHECK ("length"("btrim"("first_name")) > 0 AND "length"("btrim"("last_name")) > 0),
    CONSTRAINT "member_applications_fiscal_code_format"
        CHECK ("fiscal_code" IS NULL OR "fiscal_code" ~ '^[A-Za-z0-9]{11,16}$'),
    -- Minorenne: senza i dati e il consenso di chi esercita la responsabilità la domanda non sta in piedi
    CONSTRAINT "member_applications_guardian_required_for_minors"
        CHECK (
            "minor_at_submission" = false
            OR ("guardian_full_name" IS NOT NULL AND "guardian_consent_at" IS NOT NULL)
        ),
    -- Un rifiuto va motivato (art. 4)
    CONSTRAINT "member_applications_rejection_needs_reason"
        CHECK (
            "status" <> 'rejected'::"public"."member_application_status"
            OR "length"("btrim"(COALESCE("rejection_reason", ''))) > 0
        ),
    -- Una decisione ha sempre una data
    CONSTRAINT "member_applications_decision_needs_date"
        CHECK (
            "status" NOT IN ('approved'::"public"."member_application_status",
                             'rejected'::"public"."member_application_status")
            OR "decided_at" IS NOT NULL
        )
);

ALTER TABLE "public"."member_applications" OWNER TO "postgres";

COMMENT ON TABLE "public"."member_applications" IS
    'Domanda di ammissione a sociə (art. 4 dello statuto), nella forma dell''accettazione registrata: dati, spunte, data, ora e dispositivo. Se il commercialista chiederà una firma, si aggiunge dopo senza toccare questa tabella.';
COMMENT ON COLUMN "public"."member_applications"."client_id" IS
    'Scheda cliente collegata. NULL solo per una domanda su carta inserita prima di creare la scheda.';
COMMENT ON COLUMN "public"."member_applications"."minor_at_submission" IS
    'Minorenne alla data di invio: si calcola una volta sola, perché la persona compie gli anni ma la domanda resta quella.';
COMMENT ON COLUMN "public"."member_applications"."resolution_date" IS
    'Data della delibera del Consiglio Direttivo, da annotare nel libro soci.';
COMMENT ON COLUMN "public"."member_applications"."pdf_path" IS
    'Percorso del PDF della domanda nello Storage. Non un URL: gli URL si firmano al momento.';

-- Una sola domanda aperta per persona e per anno; dopo un rifiuto se ne può presentare un'altra.
CREATE UNIQUE INDEX IF NOT EXISTS "member_applications_one_pending_per_client_year"
    ON "public"."member_applications" ("client_id", "year")
    WHERE ("status" = 'pending'::"public"."member_application_status" AND "client_id" IS NOT NULL);

CREATE INDEX IF NOT EXISTS "idx_member_applications_status"
    ON "public"."member_applications" ("status", "submitted_at");
CREATE INDEX IF NOT EXISTS "idx_member_applications_client"
    ON "public"."member_applications" ("client_id") WHERE "client_id" IS NOT NULL;

CREATE OR REPLACE TRIGGER "member_applications_updated_at"
    BEFORE UPDATE ON "public"."member_applications"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. members — il libro soci
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."members" (
    "id"                "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id"         "uuid"      NOT NULL,
    "member_number"     "text"      NOT NULL,
    "application_id"    "uuid",
    "admitted_on"       "date"      NOT NULL,
    "resolution_date"   "date",
    "status"            "public"."member_status" DEFAULT 'active'::"public"."member_status" NOT NULL,
    "ceased_on"         "date",
    "cease_reason"      "public"."member_cease_reason",
    "cease_note"        "text",
    "card_token"        "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at"        timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"        timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "members_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "members_client_id_key" UNIQUE ("client_id"),
    CONSTRAINT "members_member_number_key" UNIQUE ("member_number"),
    CONSTRAINT "members_card_token_key" UNIQUE ("card_token"),
    CONSTRAINT "members_client_id_fkey"
        FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE,
    CONSTRAINT "members_application_id_fkey"
        FOREIGN KEY ("application_id") REFERENCES "public"."member_applications"("id") ON DELETE SET NULL,
    CONSTRAINT "members_status_not_pending"
        CHECK ("status" <> 'pending_admission'::"public"."member_status"),
    CONSTRAINT "members_ceased_consistency"
        CHECK (
            ("status" = 'ceased'::"public"."member_status" AND "ceased_on" IS NOT NULL AND "cease_reason" IS NOT NULL)
            OR ("status" <> 'ceased'::"public"."member_status" AND "ceased_on" IS NULL)
        ),
    CONSTRAINT "members_ceased_after_admission"
        CHECK ("ceased_on" IS NULL OR "ceased_on" >= "admitted_on")
);

ALTER TABLE "public"."members" OWNER TO "postgres";

COMMENT ON TABLE "public"."members" IS
    'Libro soci (art. 22 dello statuto). Una riga per persona ammessa, con numero, data di ammissione, data della delibera e cessazione. `pending_admission` non si usa qui: chi attende la delibera ha solo la domanda.';
COMMENT ON COLUMN "public"."members"."member_number" IS
    'Numero di sociə, progressivo per anno di ammissione, formato AAAA-NNNN. Compare sulla tessera digitale.';
COMMENT ON COLUMN "public"."members"."card_token" IS
    'Segreto della tessera digitale: è il contenuto del codice QR. Non è l''id, così si può rigenerare senza toccare il resto.';

CREATE INDEX IF NOT EXISTS "idx_members_status" ON "public"."members" ("status");

CREATE OR REPLACE TRIGGER "members_updated_at"
    BEFORE UPDATE ON "public"."members"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- Numerazione: una riga per anno, presa con lock di riga così due ammissioni insieme non collidono.
CREATE TABLE IF NOT EXISTS "public"."member_number_sequences" (
    "year"          integer NOT NULL,
    "last_number"   integer DEFAULT 0 NOT NULL,
    CONSTRAINT "member_number_sequences_pkey" PRIMARY KEY ("year"),
    CONSTRAINT "member_number_sequences_non_negative" CHECK ("last_number" >= 0)
);

ALTER TABLE "public"."member_number_sequences" OWNER TO "postgres";
COMMENT ON TABLE "public"."member_number_sequences" IS
    'Contatore dei numeri di sociə per anno. Tabella interna: nessuna app la legge o la scrive.';

CREATE OR REPLACE FUNCTION "public"."next_member_number"("p_year" integer) RETURNS "text"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_next integer;
BEGIN
    INSERT INTO public.member_number_sequences (year, last_number)
    VALUES (p_year, 0)
    ON CONFLICT (year) DO NOTHING;

    UPDATE public.member_number_sequences
       SET last_number = last_number + 1
     WHERE year = p_year
    RETURNING last_number INTO v_next;

    RETURN p_year::text || '-' || lpad(v_next::text, 4, '0');
END;
$$;

ALTER FUNCTION "public"."next_member_number"(integer) OWNER TO "postgres";
COMMENT ON FUNCTION "public"."next_member_number"(integer) IS
    'Prossimo numero di sociə per l''anno indicato. Funzione interna: la chiamano solo altre funzioni, nessun GRANT alle app.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. member_fees — la quota dovuta e pagata, per anno
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."member_fees" (
    "id"                "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id"         "uuid"      NOT NULL,
    "year"              integer     NOT NULL,
    "amount_cents"      integer,
    "status"            "public"."member_fee_status" DEFAULT 'due'::"public"."member_fee_status" NOT NULL,
    "paid_at"           timestamp with time zone,
    "transaction_id"    "uuid",
    "waived_reason"     "text",
    "refunded_at"       timestamp with time zone,
    "refund_reason"     "text",
    "note"              "text",
    "created_by"        "uuid",
    "created_at"        timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"        timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "member_fees_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "member_fees_client_year_key" UNIQUE ("client_id", "year"),
    CONSTRAINT "member_fees_client_id_fkey"
        FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE,
    CONSTRAINT "member_fees_year_fkey"
        FOREIGN KEY ("year") REFERENCES "public"."association_years"("year") ON DELETE RESTRICT,
    CONSTRAINT "member_fees_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "member_fees_amount_non_negative"
        CHECK ("amount_cents" IS NULL OR "amount_cents" >= 0),
    CONSTRAINT "member_fees_paid_needs_date"
        CHECK ("status" <> 'paid'::"public"."member_fee_status" OR "paid_at" IS NOT NULL),
    CONSTRAINT "member_fees_refunded_needs_date"
        CHECK ("status" <> 'refunded'::"public"."member_fee_status" OR "refunded_at" IS NOT NULL)
);

ALTER TABLE "public"."member_fees" OWNER TO "postgres";

COMMENT ON TABLE "public"."member_fees" IS
    'Quota associativa dovuta o pagata, una riga per persona e per anno solare. Chi si iscrive durante l''anno paga la quota intera, valida fino al 31 dicembre (A8).';
COMMENT ON COLUMN "public"."member_fees"."amount_cents" IS
    'Importo effettivamente dovuto. NULL finché il Consiglio Direttivo non delibera la quota dell''anno.';
COMMENT ON COLUMN "public"."member_fees"."transaction_id" IS
    'Incasso collegato in `transactions`. Il vincolo di chiave esterna lo aggiunge la migrazione delle transazioni, che crea quella tabella.';
COMMENT ON COLUMN "public"."member_fees"."refunded_at" IS
    'La quota non si rimborsa (art. 5), tranne a chi si vede respingere la domanda: non è mai diventatə sociə (D4).';

CREATE INDEX IF NOT EXISTS "idx_member_fees_year_status"
    ON "public"."member_fees" ("year", "status");

CREATE OR REPLACE TRIGGER "member_fees_updated_at"
    BEFORE UPDATE ON "public"."member_fees"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. RLS e grant
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."association_years"        ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."member_applications"      ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."members"                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."member_fees"              ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."member_number_sequences"  ENABLE ROW LEVEL SECURITY;

-- L'importo della quota lo deve vedere anche chi si sta iscrivendo: non è un dato personale.
DROP POLICY IF EXISTS "association_years_select_authenticated" ON "public"."association_years";
CREATE POLICY "association_years_select_authenticated" ON "public"."association_years"
    FOR SELECT TO "authenticated" USING (true);

DROP POLICY IF EXISTS "association_years_write_admin" ON "public"."association_years";
CREATE POLICY "association_years_write_admin" ON "public"."association_years"
    FOR ALL TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());

DROP POLICY IF EXISTS "member_applications_select_own_or_staff" ON "public"."member_applications";
CREATE POLICY "member_applications_select_own_or_staff" ON "public"."member_applications"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"() OR "client_id" = "public"."get_my_client_id"() OR "profile_id" = "auth"."uid"());

DROP POLICY IF EXISTS "member_applications_write_staff" ON "public"."member_applications";
CREATE POLICY "member_applications_write_staff" ON "public"."member_applications"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

DROP POLICY IF EXISTS "members_select_own_or_staff" ON "public"."members";
CREATE POLICY "members_select_own_or_staff" ON "public"."members"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"() OR "client_id" = "public"."get_my_client_id"());

DROP POLICY IF EXISTS "members_write_staff" ON "public"."members";
CREATE POLICY "members_write_staff" ON "public"."members"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

DROP POLICY IF EXISTS "member_fees_select_own_or_staff" ON "public"."member_fees";
CREATE POLICY "member_fees_select_own_or_staff" ON "public"."member_fees"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"() OR "client_id" = "public"."get_my_client_id"());

DROP POLICY IF EXISTS "member_fees_write_staff" ON "public"."member_fees";
CREATE POLICY "member_fees_write_staff" ON "public"."member_fees"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- `member_number_sequences` resta senza policy e senza grant: RLS attivo più nessuna policy significa
-- che dall'API non è raggiungibile. Ci arrivano solo le funzioni SECURITY DEFINER e service_role.

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."association_years"   TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."member_applications" TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."members"             TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."member_fees"         TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. View: libro soci
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW "public"."member_registry"
    WITH ("security_invoker" = true) AS
SELECT
    m.id                                AS member_id,
    m.member_number,
    m.client_id,
    c.full_name,
    a.fiscal_code,
    a.birth_date,
    a.birth_place,
    a.birth_province,
    a.address_street,
    a.address_city,
    a.address_zip,
    a.address_province,
    COALESCE(a.email, c.email)          AS email,
    COALESCE(a.phone, c.phone)          AS phone,
    m.admitted_on,
    m.resolution_date,
    m.status,
    m.ceased_on,
    m.cease_reason,
    -- Vota chi è iscrittə da almeno 3 mesi ed è ancora sociə (art. 9)
    (m.status = 'active'::public.member_status
        AND m.admitted_on <= (CURRENT_DATE - INTERVAL '3 months')) AS can_vote
FROM public.members m
JOIN public.clients c ON c.id = m.client_id
LEFT JOIN public.member_applications a ON a.id = m.application_id;

ALTER VIEW "public"."member_registry" OWNER TO "postgres";
COMMENT ON VIEW "public"."member_registry" IS
    'Libro soci pronto da esportare (art. 22). `security_invoker`: vede solo chi ha già il permesso sulle tabelle sotto, cioè lo staff e ciascunə sociə su di sé.';

GRANT SELECT ON TABLE "public"."member_registry" TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. RPC
-- ─────────────────────────────────────────────────────────────────────────────

-- 8.1 — La persona invia la propria domanda dall'app o dal sito.
-- Se non ha ancora una scheda cliente, qui nasce: `get_my_client_id()` non la crea, e senza scheda
-- non si può prenotare nulla.
CREATE OR REPLACE FUNCTION "public"."submit_member_application"("p_payload" "jsonb")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_profile_id        uuid := auth.uid();
    v_client_id         uuid;
    v_year              integer := COALESCE((p_payload->>'year')::integer, EXTRACT(YEAR FROM CURRENT_DATE)::integer);
    v_year_row          public.association_years%ROWTYPE;
    v_birth_date        date;
    v_is_minor          boolean;
    v_full_name         text;
    v_application_id    uuid;
BEGIN
    IF v_profile_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    SELECT * INTO v_year_row FROM public.association_years WHERE year = v_year;
    IF NOT FOUND OR v_year_row.is_open = false THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'YEAR_NOT_OPEN');
    END IF;

    IF COALESCE(btrim(p_payload->>'first_name'), '') = ''
       OR COALESCE(btrim(p_payload->>'last_name'), '') = ''
       OR (p_payload->>'birth_date') IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MISSING_REQUIRED_FIELDS');
    END IF;

    IF (p_payload->>'accepted_statute') IS DISTINCT FROM 'true'
       OR (p_payload->>'accepted_privacy') IS DISTINCT FROM 'true' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ACCEPTANCE_REQUIRED');
    END IF;

    v_birth_date := (p_payload->>'birth_date')::date;
    v_is_minor := v_birth_date > (CURRENT_DATE - INTERVAL '18 years');

    IF v_is_minor AND (
        COALESCE(btrim(p_payload->>'guardian_full_name'), '') = ''
        OR (p_payload->>'guardian_consent') IS DISTINCT FROM 'true'
    ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'GUARDIAN_REQUIRED');
    END IF;

    v_full_name := btrim(p_payload->>'first_name') || ' ' || btrim(p_payload->>'last_name');

    -- Scheda cliente: la propria, oppure una nuova collegata al profilo
    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        INSERT INTO public.clients (full_name, email, phone, profile_id)
        SELECT v_full_name,
               COALESCE(NULLIF(btrim(p_payload->>'email'), ''), p.email),
               NULLIF(btrim(p_payload->>'phone'), ''),
               v_profile_id
        FROM public.profiles p WHERE p.id = v_profile_id
        RETURNING id INTO v_client_id;
    END IF;

    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.member_applications
        WHERE client_id = v_client_id AND year = v_year AND status = 'pending'
    ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'APPLICATION_ALREADY_PENDING');
    END IF;

    IF EXISTS (SELECT 1 FROM public.members WHERE client_id = v_client_id AND status = 'active') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_MEMBER');
    END IF;

    INSERT INTO public.member_applications (
        client_id, profile_id, year, channel, status,
        first_name, last_name, fiscal_code, birth_date, birth_place, birth_province,
        address_street, address_city, address_zip, address_province, email, phone,
        minor_at_submission, guardian_full_name, guardian_fiscal_code, guardian_relationship,
        guardian_email, guardian_phone, guardian_consent_at,
        accepted_statute_at, accepted_privacy_at, image_release, health_declaration,
        submitted_ip, submitted_user_agent
    )
    VALUES (
        v_client_id, v_profile_id, v_year,
        COALESCE(NULLIF(p_payload->>'channel', ''), 'app')::public.member_application_channel,
        'pending',
        btrim(p_payload->>'first_name'), btrim(p_payload->>'last_name'),
        NULLIF(btrim(upper(COALESCE(p_payload->>'fiscal_code', ''))), ''),
        v_birth_date,
        NULLIF(btrim(p_payload->>'birth_place'), ''), NULLIF(btrim(p_payload->>'birth_province'), ''),
        NULLIF(btrim(p_payload->>'address_street'), ''), NULLIF(btrim(p_payload->>'address_city'), ''),
        NULLIF(btrim(p_payload->>'address_zip'), ''), NULLIF(btrim(p_payload->>'address_province'), ''),
        NULLIF(btrim(p_payload->>'email'), ''), NULLIF(btrim(p_payload->>'phone'), ''),
        v_is_minor,
        NULLIF(btrim(p_payload->>'guardian_full_name'), ''),
        NULLIF(btrim(upper(COALESCE(p_payload->>'guardian_fiscal_code', ''))), ''),
        NULLIF(btrim(p_payload->>'guardian_relationship'), ''),
        NULLIF(btrim(p_payload->>'guardian_email'), ''),
        NULLIF(btrim(p_payload->>'guardian_phone'), ''),
        CASE WHEN v_is_minor THEN now() ELSE NULL END,
        now(), now(),
        CASE WHEN (p_payload->>'image_release') IS NULL THEN NULL
             ELSE (p_payload->>'image_release') = 'true' END,
        CASE WHEN (p_payload->>'health_declaration') IS NULL THEN NULL
             ELSE (p_payload->>'health_declaration') = 'true' END,
        NULLIF(p_payload->>'ip', '')::inet,
        NULLIF(p_payload->>'user_agent', '')
    )
    RETURNING id INTO v_application_id;

    -- La quota dell'anno diventa dovuta
    INSERT INTO public.member_fees (client_id, year, amount_cents, status)
    VALUES (v_client_id, v_year, v_year_row.fee_cents, 'due')
    ON CONFLICT (client_id, year) DO NOTHING;

    RETURN jsonb_build_object(
        'ok', true,
        'reason', 'SUBMITTED',
        'application_id', v_application_id,
        'client_id', v_client_id,
        'year', v_year,
        'fee_cents', v_year_row.fee_cents
    );
END;
$$;

ALTER FUNCTION "public"."submit_member_application"("jsonb") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."submit_member_application"("jsonb") TO "authenticated";
COMMENT ON FUNCTION "public"."submit_member_application"("jsonb") IS
    'Invia la propria domanda di ammissione dall''app o dal sito. Crea la scheda cliente se manca, registra le accettazioni e apre la quota dell''anno.';

-- 8.2 — Lo staff inserisce una domanda arrivata su carta.
CREATE OR REPLACE FUNCTION "public"."staff_create_member_application"(
    "p_client_id" "uuid",
    "p_payload" "jsonb"
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_year              integer := COALESCE((p_payload->>'year')::integer, EXTRACT(YEAR FROM CURRENT_DATE)::integer);
    v_year_row          public.association_years%ROWTYPE;
    v_birth_date        date;
    v_is_minor          boolean;
    v_application_id    uuid;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clients WHERE id = p_client_id AND deleted_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    SELECT * INTO v_year_row FROM public.association_years WHERE year = v_year;
    IF NOT FOUND OR v_year_row.is_open = false THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'YEAR_NOT_OPEN');
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.member_applications
        WHERE client_id = p_client_id AND year = v_year AND status = 'pending'
    ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'APPLICATION_ALREADY_PENDING');
    END IF;

    v_birth_date := (p_payload->>'birth_date')::date;
    IF v_birth_date IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MISSING_REQUIRED_FIELDS');
    END IF;
    v_is_minor := v_birth_date > (CURRENT_DATE - INTERVAL '18 years');

    INSERT INTO public.member_applications (
        client_id, year, channel, status,
        first_name, last_name, fiscal_code, birth_date, birth_place, birth_province,
        address_street, address_city, address_zip, address_province, email, phone,
        minor_at_submission, guardian_full_name, guardian_fiscal_code, guardian_relationship,
        guardian_email, guardian_phone, guardian_consent_at,
        accepted_statute_at, accepted_privacy_at, image_release, health_declaration,
        submitted_at
    )
    VALUES (
        p_client_id, v_year, 'paper', 'pending',
        btrim(p_payload->>'first_name'), btrim(p_payload->>'last_name'),
        NULLIF(btrim(upper(COALESCE(p_payload->>'fiscal_code', ''))), ''),
        v_birth_date,
        NULLIF(btrim(p_payload->>'birth_place'), ''), NULLIF(btrim(p_payload->>'birth_province'), ''),
        NULLIF(btrim(p_payload->>'address_street'), ''), NULLIF(btrim(p_payload->>'address_city'), ''),
        NULLIF(btrim(p_payload->>'address_zip'), ''), NULLIF(btrim(p_payload->>'address_province'), ''),
        NULLIF(btrim(p_payload->>'email'), ''), NULLIF(btrim(p_payload->>'phone'), ''),
        v_is_minor,
        NULLIF(btrim(p_payload->>'guardian_full_name'), ''),
        NULLIF(btrim(upper(COALESCE(p_payload->>'guardian_fiscal_code', ''))), ''),
        NULLIF(btrim(p_payload->>'guardian_relationship'), ''),
        NULLIF(btrim(p_payload->>'guardian_email'), ''),
        NULLIF(btrim(p_payload->>'guardian_phone'), ''),
        CASE WHEN v_is_minor THEN COALESCE((p_payload->>'guardian_consent_at')::timestamptz, now()) ELSE NULL END,
        COALESCE((p_payload->>'accepted_statute_at')::timestamptz, now()),
        COALESCE((p_payload->>'accepted_privacy_at')::timestamptz, now()),
        CASE WHEN (p_payload->>'image_release') IS NULL THEN NULL
             ELSE (p_payload->>'image_release') = 'true' END,
        CASE WHEN (p_payload->>'health_declaration') IS NULL THEN NULL
             ELSE (p_payload->>'health_declaration') = 'true' END,
        COALESCE((p_payload->>'submitted_at')::timestamptz, now())
    )
    RETURNING id INTO v_application_id;

    INSERT INTO public.member_fees (client_id, year, amount_cents, status, created_by)
    VALUES (p_client_id, v_year, v_year_row.fee_cents, 'due', auth.uid())
    ON CONFLICT (client_id, year) DO NOTHING;

    RETURN jsonb_build_object('ok', true, 'reason', 'CREATED', 'application_id', v_application_id);
END;
$$;

ALTER FUNCTION "public"."staff_create_member_application"("uuid", "jsonb") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_create_member_application"("uuid", "jsonb") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_create_member_application"("uuid", "jsonb") IS
    'Inserisce una domanda di ammissione arrivata su carta, per conto di una persona già in anagrafica.';

-- 8.3 — Il Consiglio Direttivo delibera, anche su più domande insieme.
CREATE OR REPLACE FUNCTION "public"."staff_decide_member_applications"(
    "p_application_ids" "uuid"[],
    "p_approve" boolean,
    "p_resolution_date" "date" DEFAULT NULL,
    "p_note" "text" DEFAULT NULL,
    "p_rejection_reason" "text" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_id            uuid;
    v_app           public.member_applications%ROWTYPE;
    v_resolution    date := COALESCE(p_resolution_date, CURRENT_DATE);
    v_decided       integer := 0;
    v_skipped       integer := 0;
    v_member_number text;
    v_results       jsonb := '[]'::jsonb;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF p_approve = false AND COALESCE(btrim(p_rejection_reason), '') = '' THEN
        -- Lo statuto (art. 4) vuole che il rifiuto sia motivato
        RETURN jsonb_build_object('ok', false, 'reason', 'REJECTION_REASON_REQUIRED');
    END IF;

    FOREACH v_id IN ARRAY p_application_ids LOOP
        SELECT * INTO v_app FROM public.member_applications WHERE id = v_id FOR UPDATE;

        IF NOT FOUND OR v_app.status <> 'pending' OR v_app.client_id IS NULL THEN
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        IF p_approve THEN
            UPDATE public.member_applications
               SET status = 'approved', decided_at = now(), decided_by = auth.uid(),
                   resolution_date = v_resolution, decision_note = p_note
             WHERE id = v_id;

            -- Chi era già sociə ed è rientratə mantiene il numero: si riattiva la riga esistente.
            IF EXISTS (SELECT 1 FROM public.members WHERE client_id = v_app.client_id) THEN
                UPDATE public.members
                   SET status = 'active', ceased_on = NULL, cease_reason = NULL, cease_note = NULL,
                       application_id = v_app.id, resolution_date = v_resolution
                 WHERE client_id = v_app.client_id
                RETURNING member_number INTO v_member_number;
            ELSE
                v_member_number := public.next_member_number(EXTRACT(YEAR FROM v_resolution)::integer);
                INSERT INTO public.members (client_id, member_number, application_id, admitted_on, resolution_date)
                VALUES (v_app.client_id, v_member_number, v_app.id, v_resolution, v_resolution);
            END IF;
        ELSE
            UPDATE public.member_applications
               SET status = 'rejected', decided_at = now(), decided_by = auth.uid(),
                   resolution_date = v_resolution, decision_note = p_note,
                   rejection_reason = p_rejection_reason
             WHERE id = v_id;
            v_member_number := NULL;
        END IF;

        v_decided := v_decided + 1;
        v_results := v_results || jsonb_build_object(
            'application_id', v_id,
            'client_id', v_app.client_id,
            'member_number', v_member_number
        );
    END LOOP;

    RETURN jsonb_build_object(
        'ok', true,
        'reason', CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
        'decided', v_decided,
        'skipped', v_skipped,
        'resolution_date', v_resolution,
        'results', v_results
    );
END;
$$;

ALTER FUNCTION "public"."staff_decide_member_applications"("uuid"[], boolean, "date", "text", "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_decide_member_applications"("uuid"[], boolean, "date", "text", "text") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_decide_member_applications"("uuid"[], boolean, "date", "text", "text") IS
    'Delibera del Consiglio Direttivo su una o più domande. In caso di ammissione crea (o riattiva) la riga del libro soci con il numero di sociə.';

-- 8.4 — Lo staff registra o corregge la quota di un anno.
CREATE OR REPLACE FUNCTION "public"."staff_set_member_fee"(
    "p_client_id" "uuid",
    "p_year" integer,
    "p_status" "public"."member_fee_status",
    "p_amount_cents" integer DEFAULT NULL,
    "p_note" "text" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_amount integer;
    v_fee_id uuid;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.association_years WHERE year = p_year) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'YEAR_NOT_FOUND');
    END IF;

    SELECT COALESCE(p_amount_cents, fee_cents) INTO v_amount
    FROM public.association_years WHERE year = p_year;

    INSERT INTO public.member_fees (client_id, year, amount_cents, status, paid_at, refunded_at, note, created_by)
    VALUES (
        p_client_id, p_year, v_amount, p_status,
        CASE WHEN p_status = 'paid' THEN now() ELSE NULL END,
        CASE WHEN p_status = 'refunded' THEN now() ELSE NULL END,
        p_note, auth.uid()
    )
    ON CONFLICT (client_id, year) DO UPDATE SET
        amount_cents = COALESCE(EXCLUDED.amount_cents, public.member_fees.amount_cents),
        status       = EXCLUDED.status,
        paid_at      = CASE WHEN EXCLUDED.status = 'paid'
                            THEN COALESCE(public.member_fees.paid_at, now()) ELSE public.member_fees.paid_at END,
        refunded_at  = CASE WHEN EXCLUDED.status = 'refunded'
                            THEN COALESCE(public.member_fees.refunded_at, now()) ELSE public.member_fees.refunded_at END,
        note         = COALESCE(EXCLUDED.note, public.member_fees.note)
    RETURNING id INTO v_fee_id;

    RETURN jsonb_build_object('ok', true, 'reason', 'SAVED', 'fee_id', v_fee_id, 'amount_cents', v_amount);
END;
$$;

ALTER FUNCTION "public"."staff_set_member_fee"("uuid", integer, "public"."member_fee_status", integer, "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_set_member_fee"("uuid", integer, "public"."member_fee_status", integer, "text") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_set_member_fee"("uuid", integer, "public"."member_fee_status", integer, "text") IS
    'Registra o corregge la quota associativa di una persona per un anno. L''incasso vero e la ricevuta li crea `staff_register_payment`.';

-- 8.5 — Lo stato della propria iscrizione, per app e sito.
CREATE OR REPLACE FUNCTION "public"."get_my_membership_status"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_year      integer := EXTRACT(YEAR FROM CURRENT_DATE)::integer;
    v_member    public.members%ROWTYPE;
    v_fee       public.member_fees%ROWTYPE;
    v_app       public.member_applications%ROWTYPE;
    v_status    text;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', true, 'status', 'none', 'year', v_year);
    END IF;

    SELECT * INTO v_member FROM public.members WHERE client_id = v_client_id;
    SELECT * INTO v_fee    FROM public.member_fees WHERE client_id = v_client_id AND year = v_year;
    SELECT * INTO v_app    FROM public.member_applications
     WHERE client_id = v_client_id ORDER BY submitted_at DESC LIMIT 1;

    v_status := CASE
        WHEN v_member.id IS NOT NULL AND v_member.status = 'active' THEN 'active'
        WHEN v_member.id IS NOT NULL AND v_member.status = 'ceased' THEN 'ceased'
        WHEN v_app.id IS NOT NULL AND v_app.status = 'pending' THEN 'pending_admission'
        WHEN v_app.id IS NOT NULL AND v_app.status = 'rejected' THEN 'rejected'
        ELSE 'none'
    END;

    RETURN jsonb_build_object(
        'ok', true,
        'status', v_status,
        'year', v_year,
        'member_number', v_member.member_number,
        'admitted_on', v_member.admitted_on,
        'application_id', v_app.id,
        'application_status', v_app.status,
        'fee_status', COALESCE(v_fee.status::text, 'none'),
        'fee_cents', v_fee.amount_cents
    );
END;
$$;

ALTER FUNCTION "public"."get_my_membership_status"() OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."get_my_membership_status"() TO "authenticated";
COMMENT ON FUNCTION "public"."get_my_membership_status"() IS
    'Stato della propria iscrizione: nessuna domanda, in attesa di delibera, sociə attivə, cessatə o respintə, più lo stato della quota dell''anno.';

-- 8.6 — La tessera digitale.
CREATE OR REPLACE FUNCTION "public"."get_my_member_card"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_year      integer := EXTRACT(YEAR FROM CURRENT_DATE)::integer;
    v_row       record;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_A_MEMBER');
    END IF;

    SELECT m.member_number, m.status, m.admitted_on, m.card_token, c.full_name,
           f.status AS fee_status
      INTO v_row
      FROM public.members m
      JOIN public.clients c ON c.id = m.client_id
      LEFT JOIN public.member_fees f ON f.client_id = m.client_id AND f.year = v_year
     WHERE m.client_id = v_client_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_A_MEMBER');
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'member_number', v_row.member_number,
        'full_name', v_row.full_name,
        'status', v_row.status,
        'admitted_on', v_row.admitted_on,
        'year', v_year,
        'fee_status', COALESCE(v_row.fee_status::text, 'none'),
        'card_token', v_row.card_token
    );
END;
$$;

ALTER FUNCTION "public"."get_my_member_card"() OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."get_my_member_card"() TO "authenticated";
COMMENT ON FUNCTION "public"."get_my_member_card"() IS
    'Tessera digitale: numero di sociə, nome, anno, stato della quota e il segreto per il codice QR.';
