-- Migration 20260923160500: compensi a mattoni (sessione 3, blocco 5)
--
-- Obiettivo: oggi il modello dei compensi è SCRITTO NEL CODICE SQL di `calculate_operator_compensation`
-- — trattenuta sala 15%, fino a 40 €/h all'operatrice, il margine oltre diviso 25% a una persona e 75%
-- allo studio. Due problemi:
--   * cambiarlo richiede una migrazione, mentre il modello vero non è ancora deciso (domanda 3.1 al
--     commercialista) e la quota del 25% a un membro del Consiglio Direttivo va verificata contro il
--     divieto di distribuire utili anche in modo indiretto (art. 17 dello statuto);
--   * non sa fare nient'altro: niente fisso a lezione, niente a partecipante, niente eventi.
--
-- Qui il modello diventa DATI. Un modello è un insieme di mattoni che si sommano:
--   fisso a lezione · fisso a ora · a partecipante · percentuale sugli incassi · trattenuta sala
-- più gli scaglioni per numero di presenti, un minimo garantito e un tetto orario.
-- Ogni modello si assegna a una persona (ed eventualmente a un'attività) e vale DA UNA DATA.
--
-- Il calcolo si può rifare quante volte si vuole (`calculate_compensation_v2`, di sola lettura), e
-- quando il mese si chiude si CONGELA in `compensation_entries`: da lì in poi l'importo non cambia
-- più, anche se il modello viene modificato. Un compenso segnato pagato diventa un'uscita (E7).
--
-- La funzione vecchia `calculate_operator_compensation` NON viene toccata: il gestionale la usa ancora
-- e passerà alla nuova nella sessione 7. Nessun modello viene preimpostato: i mattoni ci sono, la
-- ricetta la scriverete voi da interfaccia quando il commercialista avrà risposto.
--
-- Compatibilità: solo nuovi enum, tabelle e funzioni con nomi nuovi.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 E6, E7 e docs/DOMANDE-COMMERCIALISTA.md 3.1–3.3.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enum
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
    CREATE TYPE "public"."compensation_component_kind" AS ENUM (
        'fixed_per_lesson',     -- importo fisso per lezione
        'fixed_per_hour',       -- importo fisso all'ora, in proporzione alla durata
        'per_participant',      -- importo per ogni persona che ha occupato un posto
        'percent_of_revenue',   -- percentuale sugli incassi generati dalla lezione
        'room_fee_percent'      -- trattenuta per la sala: percentuale sugli incassi, in negativo
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE "public"."compensation_entry_status" AS ENUM (
        'pending',      -- calcolato e congelato, da approvare
        'approved',     -- approvato, da pagare
        'paid'          -- pagato: è diventato un'uscita
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. compensation_models e i suoi mattoni
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."compensation_models" (
    "id"                    "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "name"                  "text"  NOT NULL,
    "description"           "text",
    "min_guaranteed_cents"  integer,
    "max_hourly_cents"      integer,
    "is_active"             boolean DEFAULT true NOT NULL,
    "created_by"            "uuid",
    "created_at"            timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"            timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "compensation_models_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "compensation_models_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_models_name_not_empty" CHECK ("length"("btrim"("name")) > 0),
    CONSTRAINT "compensation_models_min_non_negative"
        CHECK ("min_guaranteed_cents" IS NULL OR "min_guaranteed_cents" >= 0),
    CONSTRAINT "compensation_models_max_non_negative"
        CHECK ("max_hourly_cents" IS NULL OR "max_hourly_cents" >= 0)
);

ALTER TABLE "public"."compensation_models" OWNER TO "postgres";

COMMENT ON TABLE "public"."compensation_models" IS
    'Un modo di calcolare il compenso di una lezione o di un evento, fatto di mattoni che si sommano. Vale solo per chi è retribuitə: ai volontari spettano solo rimborsi documentati (art. 23).';
COMMENT ON COLUMN "public"."compensation_models"."min_guaranteed_cents" IS
    'Minimo garantito per lezione. Si applica DOPO il tetto orario: se sono in contrasto, vince il minimo.';
COMMENT ON COLUMN "public"."compensation_models"."max_hourly_cents" IS
    'Tetto orario, riproporzionato sulla durata effettiva della lezione.';

CREATE OR REPLACE TRIGGER "compensation_models_updated_at"
    BEFORE UPDATE ON "public"."compensation_models"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

CREATE TABLE IF NOT EXISTS "public"."compensation_components" (
    "id"                "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "model_id"          "uuid"  NOT NULL,
    "kind"              "public"."compensation_component_kind" NOT NULL,
    "value_cents"       integer,
    "value_percent"     numeric(6,3),
    "display_order"     integer DEFAULT 0 NOT NULL,
    "note"              "text",
    "created_at"        timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "compensation_components_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "compensation_components_model_id_fkey"
        FOREIGN KEY ("model_id") REFERENCES "public"."compensation_models"("id") ON DELETE CASCADE,
    -- Ogni mattone usa il proprio tipo di valore: o centesimi o percentuale, mai entrambi
    CONSTRAINT "compensation_components_value_matches_kind" CHECK (
        ("kind" IN ('fixed_per_lesson'::"public"."compensation_component_kind",
                    'fixed_per_hour'::"public"."compensation_component_kind",
                    'per_participant'::"public"."compensation_component_kind")
         AND "value_cents" IS NOT NULL AND "value_cents" >= 0 AND "value_percent" IS NULL)
        OR
        ("kind" IN ('percent_of_revenue'::"public"."compensation_component_kind",
                    'room_fee_percent'::"public"."compensation_component_kind")
         AND "value_percent" IS NOT NULL AND "value_percent" >= 0 AND "value_percent" <= 100
         AND "value_cents" IS NULL)
    )
);

ALTER TABLE "public"."compensation_components" OWNER TO "postgres";

COMMENT ON TABLE "public"."compensation_components" IS
    'I mattoni di un modello. Si sommano tutti; `room_fee_percent` è l''unico che sottrae, perché è una trattenuta.';

CREATE INDEX IF NOT EXISTS "idx_compensation_components_model"
    ON "public"."compensation_components" ("model_id", "display_order");

CREATE TABLE IF NOT EXISTS "public"."compensation_tiers" (
    "id"                "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "model_id"          "uuid"  NOT NULL,
    "min_participants"  integer NOT NULL,
    "max_participants"  integer,
    "amount_cents"      integer NOT NULL,
    "note"              "text",
    "created_at"        timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "compensation_tiers_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "compensation_tiers_model_id_fkey"
        FOREIGN KEY ("model_id") REFERENCES "public"."compensation_models"("id") ON DELETE CASCADE,
    CONSTRAINT "compensation_tiers_min_non_negative" CHECK ("min_participants" >= 0),
    CONSTRAINT "compensation_tiers_max_after_min"
        CHECK ("max_participants" IS NULL OR "max_participants" >= "min_participants"),
    CONSTRAINT "compensation_tiers_amount_non_negative" CHECK ("amount_cents" >= 0)
);

ALTER TABLE "public"."compensation_tiers" OWNER TO "postgres";

COMMENT ON TABLE "public"."compensation_tiers" IS
    'Scaglioni per numero di presenti: se il numero cade nella fascia, l''importo si somma agli altri mattoni. `max_participants` NULL significa "da qui in su". Se più scaglioni combaciano vince quello con la soglia minima più alta.';

CREATE INDEX IF NOT EXISTS "idx_compensation_tiers_model"
    ON "public"."compensation_tiers" ("model_id", "min_participants");

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. compensation_assignments — chi usa quale modello, e da quando
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."compensation_assignments" (
    "id"            "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "operator_id"   "uuid"  NOT NULL,
    "activity_id"   "uuid",
    "model_id"      "uuid"  NOT NULL,
    "valid_from"    "date"  NOT NULL,
    "valid_to"      "date",
    "note"          "text",
    "created_by"    "uuid",
    "created_at"    timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"    timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "compensation_assignments_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "compensation_assignments_operator_id_fkey"
        FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE CASCADE,
    CONSTRAINT "compensation_assignments_activity_id_fkey"
        FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE CASCADE,
    CONSTRAINT "compensation_assignments_model_id_fkey"
        FOREIGN KEY ("model_id") REFERENCES "public"."compensation_models"("id") ON DELETE RESTRICT,
    CONSTRAINT "compensation_assignments_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_assignments_valid_range"
        CHECK ("valid_to" IS NULL OR "valid_to" >= "valid_from")
);

ALTER TABLE "public"."compensation_assignments" OWNER TO "postgres";

COMMENT ON TABLE "public"."compensation_assignments" IS
    'Assegna un modello a una persona, eventualmente solo per un''attività, a partire da una data. Per una lezione si sceglie l''assegnazione valida quel giorno: prima quella specifica per l''attività, poi quella generale; a parità, la più recente.';
COMMENT ON COLUMN "public"."compensation_assignments"."activity_id" IS
    'NULL significa tutte le attività. Un''assegnazione con attività batte quella generale.';

CREATE INDEX IF NOT EXISTS "idx_compensation_assignments_operator"
    ON "public"."compensation_assignments" ("operator_id", "valid_from");

CREATE OR REPLACE TRIGGER "compensation_assignments_updated_at"
    BEFORE UPDATE ON "public"."compensation_assignments"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. event_operators — chi tiene un evento
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."event_operators" (
    "id"            "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id"      "uuid"  NOT NULL,
    "operator_id"   "uuid"  NOT NULL,
    "role"          "text",
    "model_id"      "uuid",
    "created_at"    timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "event_operators_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "event_operators_event_operator_key" UNIQUE ("event_id", "operator_id"),
    CONSTRAINT "event_operators_event_id_fkey"
        FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE,
    CONSTRAINT "event_operators_operator_id_fkey"
        FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE CASCADE,
    CONSTRAINT "event_operators_model_id_fkey"
        FOREIGN KEY ("model_id") REFERENCES "public"."compensation_models"("id") ON DELETE SET NULL
);

ALTER TABLE "public"."event_operators" OWNER TO "postgres";

COMMENT ON TABLE "public"."event_operators" IS
    'Operatrici collegate a un evento o laboratorio: agli eventi il compenso si calcola con gli stessi mattoni delle lezioni (E6). `model_id` permette un modello diverso solo per quell''evento.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. compensation_entries — il calcolato, congelato
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."compensation_entries" (
    "id"                "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "operator_id"       "uuid"  NOT NULL,
    "period_month"      "date"  NOT NULL,
    "lesson_id"         "uuid",
    "event_id"          "uuid",
    "model_id"          "uuid",
    "occurred_at"       timestamp with time zone NOT NULL,
    "duration_minutes"  integer NOT NULL,
    "participants"      integer DEFAULT 0 NOT NULL,
    "revenue_cents"     bigint  DEFAULT 0 NOT NULL,
    "amount_cents"      bigint  NOT NULL,
    "breakdown"         "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status"            "public"."compensation_entry_status"
                        DEFAULT 'pending'::"public"."compensation_entry_status" NOT NULL,
    "approved_by"       "uuid",
    "approved_at"       timestamp with time zone,
    "paid_at"           timestamp with time zone,
    "expense_id"        "uuid",
    "note"              "text",
    "created_by"        "uuid",
    "created_at"        timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"        timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "compensation_entries_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "compensation_entries_operator_id_fkey"
        FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE RESTRICT,
    CONSTRAINT "compensation_entries_lesson_id_fkey"
        FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_entries_event_id_fkey"
        FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_entries_model_id_fkey"
        FOREIGN KEY ("model_id") REFERENCES "public"."compensation_models"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_entries_expense_id_fkey"
        FOREIGN KEY ("expense_id") REFERENCES "public"."expenses"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_entries_approved_by_fkey"
        FOREIGN KEY ("approved_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_entries_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    -- O una lezione o un evento, mai entrambi e mai nessuno dei due
    CONSTRAINT "compensation_entries_lesson_xor_event"
        CHECK (("lesson_id" IS NOT NULL AND "event_id" IS NULL)
            OR ("lesson_id" IS NULL AND "event_id" IS NOT NULL)),
    CONSTRAINT "compensation_entries_amount_non_negative" CHECK ("amount_cents" >= 0),
    CONSTRAINT "compensation_entries_duration_positive" CHECK ("duration_minutes" > 0),
    CONSTRAINT "compensation_entries_paid_needs_date"
        CHECK ("status" <> 'paid'::"public"."compensation_entry_status" OR "paid_at" IS NOT NULL)
);

ALTER TABLE "public"."compensation_entries" OWNER TO "postgres";

COMMENT ON TABLE "public"."compensation_entries" IS
    'Compenso calcolato e CONGELATO per una lezione o un evento. Una volta qui l''importo non cambia più, anche se il modello viene modificato dopo: un mese chiuso deve restare quello che è stato pagato.';
COMMENT ON COLUMN "public"."compensation_entries"."breakdown" IS
    'Il dettaglio del calcolo, mattone per mattone: serve a spiegare l''importo a chi lo riceve.';

CREATE UNIQUE INDEX IF NOT EXISTS "compensation_entries_one_per_lesson"
    ON "public"."compensation_entries" ("operator_id", "lesson_id") WHERE "lesson_id" IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "compensation_entries_one_per_event"
    ON "public"."compensation_entries" ("operator_id", "event_id") WHERE "event_id" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "idx_compensation_entries_month"
    ON "public"."compensation_entries" ("period_month", "operator_id");

CREATE OR REPLACE TRIGGER "compensation_entries_updated_at"
    BEFORE UPDATE ON "public"."compensation_entries"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. RLS e grant — tutto dietro can_access_finance() (E3)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."compensation_models"      ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."compensation_components"  ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."compensation_tiers"       ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."compensation_assignments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."compensation_entries"     ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."event_operators"          ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "compensation_models_all_finance" ON "public"."compensation_models";
CREATE POLICY "compensation_models_all_finance" ON "public"."compensation_models"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

DROP POLICY IF EXISTS "compensation_components_all_finance" ON "public"."compensation_components";
CREATE POLICY "compensation_components_all_finance" ON "public"."compensation_components"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

DROP POLICY IF EXISTS "compensation_tiers_all_finance" ON "public"."compensation_tiers";
CREATE POLICY "compensation_tiers_all_finance" ON "public"."compensation_tiers"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

DROP POLICY IF EXISTS "compensation_assignments_all_finance" ON "public"."compensation_assignments";
CREATE POLICY "compensation_assignments_all_finance" ON "public"."compensation_assignments"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

DROP POLICY IF EXISTS "compensation_entries_all_finance" ON "public"."compensation_entries";
CREATE POLICY "compensation_entries_all_finance" ON "public"."compensation_entries"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

-- Chi tiene un evento è un'informazione organizzativa, non economica: la gestisce tutto lo staff.
DROP POLICY IF EXISTS "event_operators_select_staff" ON "public"."event_operators";
CREATE POLICY "event_operators_select_staff" ON "public"."event_operators"
    FOR SELECT TO "authenticated" USING ("public"."is_staff"());

DROP POLICY IF EXISTS "event_operators_write_staff" ON "public"."event_operators";
CREATE POLICY "event_operators_write_staff" ON "public"."event_operators"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."compensation_models"      TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."compensation_components"  TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."compensation_tiers"       TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."compensation_assignments" TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."compensation_entries"     TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."event_operators"          TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Il calcolo
-- ─────────────────────────────────────────────────────────────────────────────

-- 7.1 — Somma i mattoni di un modello. Funzione pura: stessi ingressi, stesso risultato, nessuna
-- lettura di contesto. È quella su cui si appoggiano i test.
CREATE OR REPLACE FUNCTION "public"."compute_compensation"(
    "p_model_id" "uuid",
    "p_duration_minutes" integer,
    "p_participants" integer,
    "p_revenue_cents" bigint
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_model     public.compensation_models%ROWTYPE;
    v_c         public.compensation_components%ROWTYPE;
    v_total     numeric := 0;
    v_duration  integer := GREATEST(COALESCE(p_duration_minutes, 0), 1);
    v_parts     integer := GREATEST(COALESCE(p_participants, 0), 0);
    v_revenue   numeric := GREATEST(COALESCE(p_revenue_cents, 0), 0);
    v_tier      public.compensation_tiers%ROWTYPE;
    v_amount    numeric;
    v_cap       numeric;
    v_details   jsonb := '[]'::jsonb;
BEGIN
    SELECT * INTO v_model FROM public.compensation_models WHERE id = p_model_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MODEL_NOT_FOUND');
    END IF;

    FOR v_c IN
        SELECT * FROM public.compensation_components
         WHERE model_id = p_model_id ORDER BY display_order, id
    LOOP
        v_amount := CASE v_c.kind
            WHEN 'fixed_per_lesson'   THEN v_c.value_cents
            WHEN 'fixed_per_hour'     THEN v_c.value_cents::numeric * v_duration / 60.0
            WHEN 'per_participant'    THEN v_c.value_cents::numeric * v_parts
            WHEN 'percent_of_revenue' THEN v_revenue * v_c.value_percent / 100.0
            WHEN 'room_fee_percent'   THEN -1 * v_revenue * v_c.value_percent / 100.0
        END;

        v_total := v_total + v_amount;
        v_details := v_details || jsonb_build_object(
            'kind', v_c.kind, 'amount_cents', round(v_amount)
        );
    END LOOP;

    -- Scaglione per numero di presenti: se più fasce combaciano vince quella con la soglia più alta
    SELECT * INTO v_tier
      FROM public.compensation_tiers
     WHERE model_id = p_model_id
       AND min_participants <= v_parts
       AND (max_participants IS NULL OR v_parts <= max_participants)
     ORDER BY min_participants DESC
     LIMIT 1;

    IF FOUND THEN
        v_total := v_total + v_tier.amount_cents;
        v_details := v_details || jsonb_build_object(
            'kind', 'tier', 'amount_cents', v_tier.amount_cents,
            'min_participants', v_tier.min_participants, 'max_participants', v_tier.max_participants
        );
    END IF;

    -- Tetto orario, in proporzione alla durata
    IF v_model.max_hourly_cents IS NOT NULL THEN
        v_cap := v_model.max_hourly_cents::numeric * v_duration / 60.0;
        IF v_total > v_cap THEN
            v_details := v_details || jsonb_build_object('kind', 'max_hourly_cap', 'amount_cents', round(v_cap - v_total));
            v_total := v_cap;
        END IF;
    END IF;

    -- Minimo garantito: si applica per ultimo, quindi se è in contrasto col tetto vince il minimo
    IF v_model.min_guaranteed_cents IS NOT NULL AND v_total < v_model.min_guaranteed_cents THEN
        v_details := v_details || jsonb_build_object(
            'kind', 'min_guaranteed', 'amount_cents', round(v_model.min_guaranteed_cents - v_total));
        v_total := v_model.min_guaranteed_cents;
    END IF;

    -- Un compenso non può essere negativo: se le trattenute superano il resto, è zero
    IF v_total < 0 THEN
        v_details := v_details || jsonb_build_object('kind', 'floor_zero', 'amount_cents', round(-v_total));
        v_total := 0;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'amount_cents', round(v_total)::bigint,
        'model_id', p_model_id,
        'duration_minutes', v_duration,
        'participants', v_parts,
        'revenue_cents', v_revenue::bigint,
        'components', v_details
    );
END;
$$;

ALTER FUNCTION "public"."compute_compensation"("uuid", integer, integer, bigint) OWNER TO "postgres";
COMMENT ON FUNCTION "public"."compute_compensation"("uuid", integer, integer, bigint) IS
    'Somma i mattoni di un modello e restituisce importo e dettaglio. Funzione interna: la chiamano solo le funzioni delle Finanze.';

-- 7.2 — Il modello che vale per una persona, un'attività e una data.
CREATE OR REPLACE FUNCTION "public"."resolve_compensation_model"(
    "p_operator_id" "uuid",
    "p_activity_id" "uuid",
    "p_on_date" "date"
) RETURNS "uuid"
    LANGUAGE "sql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT a.model_id
      FROM public.compensation_assignments a
     WHERE a.operator_id = p_operator_id
       AND (a.activity_id IS NULL OR a.activity_id = p_activity_id)
       AND a.valid_from <= p_on_date
       AND (a.valid_to IS NULL OR a.valid_to >= p_on_date)
     ORDER BY (a.activity_id IS NOT NULL) DESC, a.valid_from DESC
     LIMIT 1;
$$;

ALTER FUNCTION "public"."resolve_compensation_model"("uuid", "uuid", "date") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."resolve_compensation_model"("uuid", "uuid", "date") IS
    'Il modello da usare: prima l''assegnazione specifica per l''attività, poi quella generale; a parità, la più recente fra quelle valide quel giorno.';

-- 7.3 — Il calcolo del mese, di sola lettura. Si può rifare quante volte si vuole.
CREATE OR REPLACE FUNCTION "public"."calculate_compensation_v2"(
    "p_month_start" "date",
    "p_month_end" "date",
    "p_operator_id" "uuid" DEFAULT NULL
) RETURNS TABLE (
    "operator_id" "uuid",
    "operator_name" "text",
    "lesson_id" "uuid",
    "event_id" "uuid",
    "occurred_at" timestamp with time zone,
    "title" "text",
    "duration_minutes" integer,
    "participants" integer,
    "revenue_cents" bigint,
    "model_id" "uuid",
    "model_name" "text",
    "amount_cents" bigint,
    "breakdown" "jsonb"
)
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.can_access_finance() THEN
        RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH lesson_base AS (
        SELECT
            l.id                AS lesson_id,
            l.operator_id,
            l.starts_at,
            l.activity_id,
            a.name              AS activity_name,
            GREATEST(COALESCE(
                a.duration_minutes,
                (EXTRACT(EPOCH FROM (l.ends_at - l.starts_at)) / 60)::integer
            ), 1)               AS duration_minutes,
            COUNT(b.id) FILTER (WHERE b.status IN ('booked', 'attended', 'no_show'))::integer AS participants,
            COALESCE(SUM(
                CASE
                    WHEN s.custom_price_cents IS NOT NULL AND COALESCE(s.custom_entries, 0) > 0
                        THEN s.custom_price_cents::numeric / s.custom_entries
                    WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
                         AND p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
                        THEN round(p.price_cents * (1 - s.discount_percent / 100.0)) / p.entries
                    WHEN p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
                        THEN round(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0)) / p.entries
                    ELSE 0
                END
            ) FILTER (WHERE b.status IN ('booked', 'attended', 'no_show')), 0)::bigint AS revenue_cents
        FROM public.lessons l
        JOIN public.activities a ON a.id = l.activity_id
        LEFT JOIN public.bookings b ON b.lesson_id = l.id
        LEFT JOIN public.subscriptions s ON s.id = b.subscription_id
        LEFT JOIN public.plans p ON p.id = s.plan_id
        WHERE l.starts_at >= p_month_start
          AND l.starts_at < (p_month_end + INTERVAL '1 day')
          AND l.deleted_at IS NULL
          AND l.operator_id IS NOT NULL
          AND (p_operator_id IS NULL OR l.operator_id = p_operator_id)
        GROUP BY l.id, l.operator_id, l.starts_at, l.activity_id, a.name, a.duration_minutes, l.ends_at
    ),
    event_base AS (
        SELECT
            eo.operator_id,
            e.id                AS event_id,
            e.starts_at,
            e.name              AS event_name,
            eo.model_id         AS override_model_id,
            GREATEST(COALESCE(
                (EXTRACT(EPOCH FROM (e.ends_at - e.starts_at)) / 60)::integer, 90
            ), 1)               AS duration_minutes,
            COUNT(eb.id) FILTER (WHERE eb.status IN ('booked', 'attended', 'no_show'))::integer AS participants,
            (COALESCE(e.price_cents, 0)::bigint
                * COUNT(eb.id) FILTER (WHERE eb.status IN ('booked', 'attended', 'no_show'))) AS revenue_cents
        FROM public.event_operators eo
        JOIN public.events e ON e.id = eo.event_id
        LEFT JOIN public.event_bookings eb ON eb.event_id = e.id
        WHERE e.starts_at >= p_month_start
          AND e.starts_at < (p_month_end + INTERVAL '1 day')
          AND e.deleted_at IS NULL
          AND (p_operator_id IS NULL OR eo.operator_id = p_operator_id)
        GROUP BY eo.operator_id, e.id, e.starts_at, e.name, eo.model_id, e.ends_at, e.price_cents
    ),
    resolved AS (
        SELECT lb.operator_id, lb.lesson_id, NULL::uuid AS event_id, lb.starts_at AS occurred_at,
               lb.activity_name AS title, lb.duration_minutes, lb.participants, lb.revenue_cents,
               public.resolve_compensation_model(lb.operator_id, lb.activity_id, lb.starts_at::date) AS model_id
          FROM lesson_base lb
        UNION ALL
        SELECT eb.operator_id, NULL::uuid, eb.event_id, eb.starts_at,
               eb.event_name, eb.duration_minutes, eb.participants, eb.revenue_cents,
               COALESCE(eb.override_model_id,
                        public.resolve_compensation_model(eb.operator_id, NULL, eb.starts_at::date))
          FROM event_base eb
    )
    SELECT
        r.operator_id,
        o.name,
        r.lesson_id,
        r.event_id,
        r.occurred_at,
        r.title,
        r.duration_minutes,
        r.participants,
        r.revenue_cents,
        r.model_id,
        m.name,
        COALESCE((calc.result->>'amount_cents')::bigint, 0),
        COALESCE(calc.result, jsonb_build_object('ok', false, 'reason', 'NO_MODEL'))
    FROM resolved r
    JOIN public.operators o ON o.id = r.operator_id
    LEFT JOIN public.compensation_models m ON m.id = r.model_id
    LEFT JOIN LATERAL (
        SELECT public.compute_compensation(r.model_id, r.duration_minutes, r.participants, r.revenue_cents) AS result
        WHERE r.model_id IS NOT NULL
    ) calc ON true
    -- I volontari non prendono compensi: solo rimborsi documentati (art. 23)
    WHERE o.deleted_at IS NULL
      AND o.engagement_type = 'paid'::public.staff_engagement_type
    ORDER BY r.occurred_at, o.name;
END;
$$;

ALTER FUNCTION "public"."calculate_compensation_v2"("date", "date", "uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."calculate_compensation_v2"("date", "date", "uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."calculate_compensation_v2"("date", "date", "uuid") IS
    'Compensi del periodo, lezione per lezione ed evento per evento, secondo i modelli assegnati. Di sola lettura: non scrive nulla, si può rifare. Esclude chi è volontariə. Sostituirà `calculate_operator_compensation` nella sessione 7.';

-- 7.4 — Congela il mese.
CREATE OR REPLACE FUNCTION "public"."staff_freeze_compensation"(
    "p_month_start" "date",
    "p_month_end" "date",
    "p_operator_id" "uuid" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_month     date := date_trunc('month', p_month_start)::date;
    v_inserted  integer := 0;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    INSERT INTO public.compensation_entries (
        operator_id, period_month, lesson_id, event_id, model_id, occurred_at,
        duration_minutes, participants, revenue_cents, amount_cents, breakdown, created_by
    )
    SELECT c.operator_id, v_month, c.lesson_id, c.event_id, c.model_id, c.occurred_at,
           c.duration_minutes, c.participants, c.revenue_cents, c.amount_cents, c.breakdown, auth.uid()
      FROM public.calculate_compensation_v2(p_month_start, p_month_end, p_operator_id) c
     WHERE c.model_id IS NOT NULL
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    RETURN jsonb_build_object('ok', true, 'reason', 'FROZEN',
                              'month', v_month, 'inserted', v_inserted);
END;
$$;

ALTER FUNCTION "public"."staff_freeze_compensation"("date", "date", "uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_freeze_compensation"("date", "date", "uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_freeze_compensation"("date", "date", "uuid") IS
    'Congela i compensi calcolati del periodo. Le righe già congelate restano come sono: chiudere due volte lo stesso mese non cambia gli importi.';

-- 7.5 — Un compenso pagato diventa un'uscita (E7).
CREATE OR REPLACE FUNCTION "public"."staff_mark_compensation_paid"("p_entry_ids" "uuid"[])
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_id            uuid;
    v_entry         public.compensation_entries%ROWTYPE;
    v_category_id   uuid;
    v_expense_id    uuid;
    v_paid          integer := 0;
    v_skipped       integer := 0;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    SELECT id INTO v_category_id FROM public.expense_categories WHERE slug = 'compensi';

    FOREACH v_id IN ARRAY p_entry_ids LOOP
        SELECT * INTO v_entry FROM public.compensation_entries WHERE id = v_id FOR UPDATE;

        IF NOT FOUND OR v_entry.status = 'paid' OR v_entry.amount_cents <= 0 THEN
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        INSERT INTO public.expenses (
            amount_cents, expense_date, category, category_id, operator_id,
            lesson_id, event_id, notes, is_fixed, source, confirmed_at, created_by
        )
        SELECT v_entry.amount_cents::integer,
               (v_entry.period_month + INTERVAL '1 month - 1 day')::date,
               'staff_compensation', v_category_id, v_entry.operator_id,
               v_entry.lesson_id, v_entry.event_id,
               'Compenso ' || o.name || ' — ' || to_char(v_entry.period_month, 'MM/YYYY'),
               false, 'payout', now(), auth.uid()
          FROM public.operators o WHERE o.id = v_entry.operator_id
        RETURNING id INTO v_expense_id;

        UPDATE public.compensation_entries
           SET status = 'paid', paid_at = now(), expense_id = v_expense_id,
               approved_at = COALESCE(approved_at, now()),
               approved_by = COALESCE(approved_by, auth.uid())
         WHERE id = v_id;

        v_paid := v_paid + 1;
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'reason', 'PAID', 'paid', v_paid, 'skipped', v_skipped);
END;
$$;

ALTER FUNCTION "public"."staff_mark_compensation_paid"("uuid"[]) OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_mark_compensation_paid"("uuid"[]) TO "authenticated";
COMMENT ON FUNCTION "public"."staff_mark_compensation_paid"("uuid"[]) IS
    'Segna pagati uno o più compensi congelati e crea per ciascuno l''uscita nella categoria compensi (E7).';
