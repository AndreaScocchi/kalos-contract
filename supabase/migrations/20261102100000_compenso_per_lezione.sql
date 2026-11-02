-- Migration 20261102100000: il compenso di una singola lezione si può modificare
--
-- Richiesta dell'utente del 02/11/2026: in Finanze → Compensi → Mese → dettaglio, nel ricontrollare
-- il mese le voci del compenso di ogni lezione devono essere modificabili, per le particolarità di
-- quella lezione (la sala era gratis, un'accoglienza in più, un accordo diverso).
--
-- Fino a oggi l'unico modo era creare un modello apposta e assegnarlo per quelle date. Ora, per una
-- persona e una lezione (o un evento), si può cambiare:
--
--   * il modello, solo per quella lezione;
--   * gli incassi su cui si calcola;
--   * le spese della lezione, voce per voce (`costs` sostituisce quelle del modello);
--   * il compenso, scritto a mano (`amount_cents` sostituisce mattoni, scaglioni, tetti e minimo).
--
-- Ciò che non si cambia resta calcolato dal vivo: se si tocca solo l'affitto, il compenso continua a
-- seguire presenze e modello. Presenti e durata non si modificano qui: vengono dalla lezione e si
-- correggono lì. «Allo Studio» è sempre quello che resta meno il compenso.
--
-- Le modifiche stanno in una tabella a parte e non in `compensation_entries`: «Riapri» cancella le
-- righe congelate e le modifiche devono sopravvivere. Quando il mese si chiude il calcolo, con le
-- modifiche, si congela come sempre: `breakdown.override` porta il motivo e i valori di partenza, e
-- resta nella riga congelata anche dopo il pagamento. Congelata o pagata, una riga non si modifica
-- (`LINE_FROZEN`, `LINE_PAID`): prima si riapre il mese o si annulla il pagamento. Come le spese dei
-- modelli, quelle scritte qui servono solo al calcolo e non diventano uscite.
--
-- Il motivo è obbligatorio, come quando si paga un lordo diverso dal calcolato: tra qualche mese
-- deve restare chiaro perché quella lezione ha un importo diverso.
--
-- Compatibilità: una tabella e tre funzioni nuove; `compute_compensation` e
-- `calculate_compensation_v2` mantengono firma e risultato per le lezioni senza modifiche.
--
-- migration-lint:allow revoke — reason: le REVOKE riguardano solo le funzioni nuove di questa migrazione (chiuse ad anon); nessun accesso esistente si restringe

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. La tabella delle modifiche
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."compensation_line_overrides" (
    "id"            "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "operator_id"   "uuid" NOT NULL,
    "lesson_id"     "uuid",
    "event_id"      "uuid",
    "model_id"      "uuid",
    "revenue_cents" bigint,
    "costs"         "jsonb",
    "amount_cents"  bigint,
    "note"          "text" NOT NULL,
    "created_by"    "uuid",
    "updated_by"    "uuid",
    "created_at"    timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"    timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "compensation_line_overrides_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "compensation_line_overrides_operator_id_fkey"
        FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE CASCADE,
    CONSTRAINT "compensation_line_overrides_lesson_id_fkey"
        FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE CASCADE,
    CONSTRAINT "compensation_line_overrides_event_id_fkey"
        FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE,
    CONSTRAINT "compensation_line_overrides_model_id_fkey"
        FOREIGN KEY ("model_id") REFERENCES "public"."compensation_models"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_line_overrides_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_line_overrides_updated_by_fkey"
        FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_line_overrides_lesson_xor_event"
        CHECK (("lesson_id" IS NOT NULL AND "event_id" IS NULL)
            OR ("lesson_id" IS NULL AND "event_id" IS NOT NULL)),
    CONSTRAINT "compensation_line_overrides_revenue_non_negative"
        CHECK ("revenue_cents" IS NULL OR "revenue_cents" >= 0),
    CONSTRAINT "compensation_line_overrides_amount_non_negative"
        CHECK ("amount_cents" IS NULL OR "amount_cents" >= 0),
    CONSTRAINT "compensation_line_overrides_note_present"
        CHECK (length(btrim("note")) BETWEEN 1 AND 500)
);

ALTER TABLE "public"."compensation_line_overrides" OWNER TO "postgres";

COMMENT ON TABLE "public"."compensation_line_overrides" IS
    'Le modifiche al compenso di una singola lezione o evento, per persona. Valgono nel calcolo dal vivo e si congelano con esso; restano se il mese si riapre. Si leggono dalle Finanze e si scrivono solo con staff_save_compensation_override e staff_delete_compensation_override.';
COMMENT ON COLUMN "public"."compensation_line_overrides"."model_id" IS
    'Il modello solo per questa lezione. NULL: quello che vale per la persona (o per l''evento).';
COMMENT ON COLUMN "public"."compensation_line_overrides"."revenue_cents" IS
    'Gli incassi su cui si calcola. NULL: quelli delle prenotazioni.';
COMMENT ON COLUMN "public"."compensation_line_overrides"."costs" IS
    'Le spese di questa lezione, [{note, amount_cents}], al posto di quelle del modello. Vuoto: nessuna spesa. NULL: quelle del modello. Non diventano uscite.';
COMMENT ON COLUMN "public"."compensation_line_overrides"."amount_cents" IS
    'Il compenso scritto a mano, al posto di mattoni, scaglioni, tetti e minimo. NULL: quello calcolato.';
COMMENT ON COLUMN "public"."compensation_line_overrides"."note" IS
    'Il motivo della modifica, obbligatorio.';

CREATE UNIQUE INDEX IF NOT EXISTS "compensation_line_overrides_one_per_lesson"
    ON "public"."compensation_line_overrides" ("operator_id", "lesson_id") WHERE "lesson_id" IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "compensation_line_overrides_one_per_event"
    ON "public"."compensation_line_overrides" ("operator_id", "event_id") WHERE "event_id" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "idx_compensation_line_overrides_lesson"
    ON "public"."compensation_line_overrides" ("lesson_id") WHERE "lesson_id" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "idx_compensation_line_overrides_event"
    ON "public"."compensation_line_overrides" ("event_id") WHERE "event_id" IS NOT NULL;

CREATE OR REPLACE TRIGGER "compensation_line_overrides_updated_at"
    BEFORE UPDATE ON "public"."compensation_line_overrides"
    FOR EACH ROW EXECUTE FUNCTION "internal"."update_updated_at_column"();

ALTER TABLE "public"."compensation_line_overrides" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "compensation_line_overrides_select_finance" ON "public"."compensation_line_overrides";
CREATE POLICY "compensation_line_overrides_select_finance" ON "public"."compensation_line_overrides"
    FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());

GRANT SELECT ON TABLE "public"."compensation_line_overrides" TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Il calcolo, con le modifiche
-- ─────────────────────────────────────────────────────────────────────────────

-- Le spese scritte per una lezione: un elenco di {note, amount_cents}, con nome e importo in centesimi.
CREATE OR REPLACE FUNCTION "internal"."compensation_costs_valid"("p_costs" "jsonb")
    RETURNS boolean
    LANGUAGE "plpgsql"
    IMMUTABLE
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_cost jsonb;
BEGIN
    IF jsonb_typeof(p_costs) IS DISTINCT FROM 'array' OR jsonb_array_length(p_costs) > 20 THEN
        RETURN false;
    END IF;

    FOR v_cost IN SELECT * FROM jsonb_array_elements(p_costs) LOOP
        IF jsonb_typeof(v_cost->'note') IS DISTINCT FROM 'string'
           OR length(btrim(v_cost->>'note')) NOT BETWEEN 1 AND 80
           OR jsonb_typeof(v_cost->'amount_cents') IS DISTINCT FROM 'number' THEN
            RETURN false;
        END IF;
        IF (v_cost->>'amount_cents')::numeric < 0
           OR (v_cost->>'amount_cents')::numeric <> trunc((v_cost->>'amount_cents')::numeric) THEN
            RETURN false;
        END IF;
    END LOOP;

    RETURN true;
END;
$$;

COMMENT ON FUNCTION "internal"."compensation_costs_valid"("jsonb") IS
    'Controlla le spese scritte per una singola lezione: al massimo 20, ognuna con un nome e un importo intero in centesimi, mai negativo.';

-- Il calcolo di sempre (migrazione 20261007100100), con due sostituzioni facoltative: le spese e il
-- compenso scritti per quella lezione.
CREATE OR REPLACE FUNCTION "internal"."compute_compensation_line"(
    "p_model_id" "uuid",
    "p_duration_minutes" integer,
    "p_participants" integer,
    "p_revenue_cents" bigint,
    "p_costs" "jsonb" DEFAULT NULL,
    "p_amount_cents" bigint DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_model         public.compensation_models%ROWTYPE;
    v_c             public.compensation_components%ROWTYPE;
    v_custom        jsonb;
    v_duration      integer := GREATEST(COALESCE(p_duration_minutes, 0), 1);
    v_parts         integer := GREATEST(COALESCE(p_participants, 0), 0);
    v_revenue       numeric := GREATEST(COALESCE(p_revenue_cents, 0), 0);
    v_costs         numeric := 0;
    v_margin        numeric;
    v_total         numeric := 0;
    v_tier          public.compensation_tiers%ROWTYPE;
    v_amount        numeric;
    v_cap           numeric;
    v_cap_kind      text;
    v_cost_details  jsonb := '[]'::jsonb;
    v_details       jsonb := '[]'::jsonb;
    v_amount_cents  bigint;
    v_margin_cents  bigint;
BEGIN
    SELECT * INTO v_model FROM public.compensation_models WHERE id = p_model_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MODEL_NOT_FOUND');
    END IF;

    -- Spese della lezione: si tolgono dagli incassi
    IF p_costs IS NOT NULL THEN
        -- Scritte per questa lezione: prendono il posto di quelle del modello
        FOR v_custom IN SELECT * FROM jsonb_array_elements(p_costs) LOOP
            v_amount := (v_custom->>'amount_cents')::numeric;
            v_costs := v_costs + v_amount;
            v_cost_details := v_cost_details || jsonb_build_object(
                'kind', 'custom', 'note', btrim(v_custom->>'note'), 'amount_cents', round(v_amount)
            );
        END LOOP;
    ELSE
        FOR v_c IN
            SELECT * FROM public.compensation_components
             WHERE model_id = p_model_id
               AND kind IN ('cost_per_lesson', 'cost_per_hour', 'cost_per_participant', 'cost_percent_of_revenue')
             ORDER BY display_order, id
        LOOP
            v_amount := CASE v_c.kind
                WHEN 'cost_per_lesson'         THEN v_c.value_cents
                WHEN 'cost_per_hour'           THEN v_c.value_cents::numeric * v_duration / 60.0
                WHEN 'cost_per_participant'    THEN v_c.value_cents::numeric * v_parts
                WHEN 'cost_percent_of_revenue' THEN v_revenue * v_c.value_percent / 100.0
            END;

            v_costs := v_costs + v_amount;
            v_cost_details := v_cost_details || jsonb_build_object(
                'kind', v_c.kind, 'note', v_c.note, 'amount_cents', round(v_amount)
            );
        END LOOP;
    END IF;

    v_margin := v_revenue - v_costs;

    IF p_amount_cents IS NOT NULL THEN
        -- Scritto a mano: è il compenso, senza mattoni, scaglioni, tetti né minimo
        v_total := GREATEST(p_amount_cents, 0);
        v_details := jsonb_build_array(jsonb_build_object('kind', 'manual', 'amount_cents', round(v_total)));
    ELSE
        -- Compenso: gli altri mattoni si sommano
        FOR v_c IN
            SELECT * FROM public.compensation_components
             WHERE model_id = p_model_id
               AND kind NOT IN ('cost_per_lesson', 'cost_per_hour', 'cost_per_participant', 'cost_percent_of_revenue')
             ORDER BY display_order, id
        LOOP
            v_amount := CASE v_c.kind
                WHEN 'fixed_per_lesson'   THEN v_c.value_cents
                WHEN 'fixed_per_hour'     THEN v_c.value_cents::numeric * v_duration / 60.0
                WHEN 'per_participant'    THEN v_c.value_cents::numeric * v_parts
                WHEN 'percent_of_revenue' THEN v_revenue * v_c.value_percent / 100.0
                -- Se le spese superano gli incassi non resta niente: zero, non un debito che mangia gli altri mattoni
                WHEN 'percent_of_margin'  THEN GREATEST(v_margin, 0) * v_c.value_percent / 100.0
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

        -- Tetti: a lezione e orario (in proporzione alla durata); con entrambi vale il più basso
        IF v_model.max_per_lesson_cents IS NOT NULL THEN
            v_cap := v_model.max_per_lesson_cents;
            v_cap_kind := 'max_lesson_cap';
        END IF;
        IF v_model.max_hourly_cents IS NOT NULL
           AND (v_cap IS NULL OR v_model.max_hourly_cents::numeric * v_duration / 60.0 < v_cap) THEN
            v_cap := v_model.max_hourly_cents::numeric * v_duration / 60.0;
            v_cap_kind := 'max_hourly_cap';
        END IF;
        IF v_cap IS NOT NULL AND v_total > v_cap THEN
            v_details := v_details || jsonb_build_object('kind', v_cap_kind, 'amount_cents', round(v_cap - v_total));
            v_total := v_cap;
        END IF;

        -- Minimo garantito: si applica per ultimo, quindi se è in contrasto coi tetti vince il minimo
        IF v_model.min_guaranteed_cents IS NOT NULL AND v_total < v_model.min_guaranteed_cents THEN
            v_details := v_details || jsonb_build_object(
                'kind', 'min_guaranteed', 'amount_cents', round(v_model.min_guaranteed_cents - v_total));
            v_total := v_model.min_guaranteed_cents;
        END IF;

        -- Un compenso non può essere negativo
        IF v_total < 0 THEN
            v_details := v_details || jsonb_build_object('kind', 'floor_zero', 'amount_cents', round(-v_total));
            v_total := 0;
        END IF;
    END IF;

    v_amount_cents := round(v_total)::bigint;
    v_margin_cents := round(v_margin)::bigint;

    RETURN jsonb_build_object(
        'ok', true,
        'amount_cents', v_amount_cents,
        'model_id', p_model_id,
        'duration_minutes', v_duration,
        'participants', v_parts,
        'revenue_cents', v_revenue::bigint,
        'costs', v_cost_details,
        'costs_cents', round(v_costs)::bigint,
        'margin_cents', v_margin_cents,
        -- Quello che resta allo Studio dopo spese e compenso; negativo se il compenso supera quello che resta
        'studio_cents', v_margin_cents - v_amount_cents,
        'components', v_details
    );
END;
$$;

COMMENT ON FUNCTION "internal"."compute_compensation_line"("uuid", integer, integer, bigint, "jsonb", bigint) IS
    'Incassi − spese = quello che resta; il compenso somma gli altri mattoni, lo scaglione, i tetti e il minimo; allo Studio va il resto. Spese e compenso si possono sostituire per una singola lezione. Funzione interna: la chiamano solo le funzioni delle Finanze.';

-- Una formula sola: la funzione di prima è il calcolo senza sostituzioni
CREATE OR REPLACE FUNCTION "internal"."compute_compensation"(
    "p_model_id" "uuid",
    "p_duration_minutes" integer,
    "p_participants" integer,
    "p_revenue_cents" bigint
) RETURNS "jsonb"
    LANGUAGE "sql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT internal.compute_compensation_line(p_model_id, p_duration_minutes, p_participants, p_revenue_cents);
$$;

-- Il calcolo del mese (ultima versione: migrazione 20260924180000), con le modifiche della lezione.
-- Stessa firma; una lezione modificata ha in più `breakdown.override`, con il motivo, quello che è
-- stato cambiato e i valori di partenza.
CREATE OR REPLACE FUNCTION "public"."calculate_compensation_v2"(
    "p_month_start" "date",
    "p_month_end" "date",
    "p_operator_id" "uuid" DEFAULT NULL
) RETURNS TABLE (
    "operator_id" "uuid",
    "operator_name" "text",
    "lesson_id" "uuid",
    "event_id" "uuid",
    "activity_id" "uuid",
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
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_from  timestamptz := (p_month_start::timestamp AT TIME ZONE 'Europe/Rome');
    v_to    timestamptz := ((p_month_end + 1)::timestamp AT TIME ZONE 'Europe/Rome');
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
                NULLIF((EXTRACT(EPOCH FROM (l.ends_at - l.starts_at)) / 60)::integer, 0),
                a.duration_minutes
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
        WHERE l.starts_at >= v_from
          AND l.starts_at < v_to
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
                NULLIF((EXTRACT(EPOCH FROM (e.ends_at - e.starts_at)) / 60)::integer, 0), 90
            ), 1)               AS duration_minutes,
            COUNT(eb.id) FILTER (WHERE eb.status IN ('booked', 'attended', 'no_show'))::integer AS participants,
            (COALESCE(e.price_cents, 0)::bigint
                * COUNT(eb.id) FILTER (WHERE eb.status IN ('booked', 'attended', 'no_show'))) AS revenue_cents
        FROM public.event_operators eo
        JOIN public.events e ON e.id = eo.event_id
        LEFT JOIN public.event_bookings eb ON eb.event_id = e.id
        WHERE e.starts_at >= v_from
          AND e.starts_at < v_to
          AND e.deleted_at IS NULL
          AND (p_operator_id IS NULL OR eo.operator_id = p_operator_id)
        GROUP BY eo.operator_id, e.id, e.starts_at, e.name, eo.model_id, e.ends_at, e.price_cents
    ),
    resolved AS (
        SELECT lb.operator_id, lb.lesson_id, NULL::uuid AS event_id, lb.activity_id,
               lb.starts_at AS occurred_at, lb.activity_name AS title,
               lb.duration_minutes, lb.participants, lb.revenue_cents,
               internal.resolve_compensation_model(
                   lb.operator_id, lb.activity_id, (lb.starts_at AT TIME ZONE 'Europe/Rome')::date) AS model_id
          FROM lesson_base lb
        UNION ALL
        SELECT eb.operator_id, NULL::uuid, eb.event_id, NULL::uuid,
               eb.starts_at, eb.event_name,
               eb.duration_minutes, eb.participants, eb.revenue_cents,
               COALESCE(eb.override_model_id,
                        internal.resolve_compensation_model(
                            eb.operator_id, NULL, (eb.starts_at AT TIME ZONE 'Europe/Rome')::date))
          FROM event_base eb
    )
    SELECT
        r.operator_id,
        o.name,
        r.lesson_id,
        r.event_id,
        r.activity_id,
        r.occurred_at,
        r.title,
        r.duration_minutes,
        r.participants,
        COALESCE(ov.revenue_cents, r.revenue_cents),
        COALESCE(ov.model_id, r.model_id),
        m.name,
        COALESCE((calc.result->>'amount_cents')::bigint, 0),
        COALESCE(calc.result, jsonb_build_object('ok', false, 'reason', 'NO_MODEL'))
            || CASE WHEN ov.id IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('override', jsonb_build_object(
                   'note', ov.note,
                   'model_id', ov.model_id,
                   'revenue_cents', ov.revenue_cents,
                   'costs', ov.costs,
                   'amount_cents', ov.amount_cents,
                   'updated_at', ov.updated_at,
                   'base', jsonb_build_object(
                       'model_id', r.model_id,
                       'model_name', bm.name,
                       'revenue_cents', r.revenue_cents,
                       'amount_cents', COALESCE((base.result->>'amount_cents')::bigint, 0)
                   )
               )) END
    FROM resolved r
    JOIN public.operators o ON o.id = r.operator_id
    LEFT JOIN public.compensation_line_overrides ov
           ON ov.operator_id = r.operator_id
          AND (ov.lesson_id = r.lesson_id OR ov.event_id = r.event_id)
    LEFT JOIN public.compensation_models m ON m.id = COALESCE(ov.model_id, r.model_id)
    LEFT JOIN public.compensation_models bm ON bm.id = r.model_id
    LEFT JOIN LATERAL (
        SELECT internal.compute_compensation_line(
                   COALESCE(ov.model_id, r.model_id), r.duration_minutes, r.participants,
                   COALESCE(ov.revenue_cents, r.revenue_cents), ov.costs, ov.amount_cents) AS result
        WHERE COALESCE(ov.model_id, r.model_id) IS NOT NULL
    ) calc ON true
    LEFT JOIN LATERAL (
        SELECT internal.compute_compensation(r.model_id, r.duration_minutes, r.participants, r.revenue_cents) AS result
        WHERE ov.id IS NOT NULL AND r.model_id IS NOT NULL
    ) base ON true
    -- I volontari non prendono compensi: solo rimborsi documentati (art. 23)
    WHERE o.engagement_type = 'paid'::public.staff_engagement_type
    ORDER BY r.occurred_at, o.name;
END;
$$;

COMMENT ON FUNCTION "public"."calculate_compensation_v2"("date", "date", "uuid") IS
    'Compensi del periodo, lezione per lezione ed evento per evento, secondo i modelli assegnati e le modifiche della singola lezione (mese in ora italiana). Di sola lettura: non scrive nulla, si può rifare. Esclude chi è volontariə. Solo Finanze.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Provare e salvare una modifica
-- ─────────────────────────────────────────────────────────────────────────────

-- Lo stesso calcolo che userà il mese vero, mentre si scrive: non legge e non scrive la lezione.
CREATE OR REPLACE FUNCTION "public"."preview_compensation_override"(
    "p_model_id" "uuid",
    "p_duration_minutes" integer,
    "p_participants" integer,
    "p_revenue_cents" bigint,
    "p_costs" "jsonb" DEFAULT NULL,
    "p_amount_cents" bigint DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    IF COALESCE(p_revenue_cents, 0) < 0
       OR COALESCE(p_amount_cents, 0) < 0
       OR (p_costs IS NOT NULL AND NOT internal.compensation_costs_valid(p_costs)) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_OVERRIDE');
    END IF;

    RETURN internal.compute_compensation_line(
        p_model_id, p_duration_minutes, p_participants, p_revenue_cents, p_costs, p_amount_cents);
END;
$$;

ALTER FUNCTION "public"."preview_compensation_override"("uuid", integer, integer, bigint, "jsonb", bigint) OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."preview_compensation_override"("uuid", integer, integer, bigint, "jsonb", bigint) FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."preview_compensation_override"("uuid", integer, integer, bigint, "jsonb", bigint) TO "authenticated", "service_role";
COMMENT ON FUNCTION "public"."preview_compensation_override"("uuid", integer, integer, bigint, "jsonb", bigint) IS
    'Prova il compenso di una lezione con le modifiche scritte, senza salvare. Solo Finanze.';

-- Una riga congelata o pagata non si tocca. La blocca, così un pagamento contemporaneo aspetta.
CREATE OR REPLACE FUNCTION "internal"."compensation_line_locked_reason"(
    "p_operator_id" "uuid",
    "p_lesson_id" "uuid",
    "p_event_id" "uuid"
) RETURNS "text"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_status public.compensation_entry_status;
BEGIN
    SELECT e.status INTO v_status
      FROM public.compensation_entries e
     WHERE e.operator_id = p_operator_id
       AND (e.lesson_id = p_lesson_id OR e.event_id = p_event_id)
       FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    RETURN CASE WHEN v_status = 'paid' THEN 'LINE_PAID' ELSE 'LINE_FROZEN' END;
END;
$$;

COMMENT ON FUNCTION "internal"."compensation_line_locked_reason"("uuid", "uuid", "uuid") IS
    'Perché il compenso di una lezione non si può modificare: LINE_FROZEN, LINE_PAID, o NULL se si può.';

CREATE OR REPLACE FUNCTION "public"."staff_save_compensation_override"("p_payload" "jsonb")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_operator      uuid;
    v_lesson        uuid;
    v_event         uuid;
    v_model         uuid;
    v_revenue       bigint;
    v_costs         jsonb;
    v_amount        bigint;
    v_note          text;
    v_occurred_on   date;
    v_activity      uuid;
    v_base_model    uuid;
    v_locked        text;
    v_active        boolean;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    v_operator := NULLIF(p_payload->>'operator_id', '')::uuid;
    v_lesson   := NULLIF(p_payload->>'lesson_id', '')::uuid;
    v_event    := NULLIF(p_payload->>'event_id', '')::uuid;
    v_model    := NULLIF(p_payload->>'model_id', '')::uuid;
    v_revenue  := NULLIF(p_payload->>'revenue_cents', '')::bigint;
    v_amount   := NULLIF(p_payload->>'amount_cents', '')::bigint;
    v_costs    := NULLIF(p_payload->'costs', 'null'::jsonb);
    v_note     := NULLIF(btrim(COALESCE(p_payload->>'note', '')), '');

    IF v_operator IS NULL OR (v_lesson IS NULL) = (v_event IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_OVERRIDE');
    END IF;

    -- La lezione o l'evento devono essere di questa persona, e la persona retribuita
    IF v_lesson IS NOT NULL THEN
        SELECT (l.starts_at AT TIME ZONE 'Europe/Rome')::date, l.activity_id
          INTO v_occurred_on, v_activity
          FROM public.lessons l
          JOIN public.operators o ON o.id = l.operator_id
         WHERE l.id = v_lesson AND l.operator_id = v_operator AND l.deleted_at IS NULL
           AND o.engagement_type = 'paid'::public.staff_engagement_type;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'LINE_NOT_FOUND');
        END IF;
    ELSE
        SELECT (e.starts_at AT TIME ZONE 'Europe/Rome')::date, eo.model_id
          INTO v_occurred_on, v_base_model
          FROM public.event_operators eo
          JOIN public.events e ON e.id = eo.event_id
          JOIN public.operators o ON o.id = eo.operator_id
         WHERE eo.event_id = v_event AND eo.operator_id = v_operator AND e.deleted_at IS NULL
           AND o.engagement_type = 'paid'::public.staff_engagement_type;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'LINE_NOT_FOUND');
        END IF;
    END IF;

    v_locked := internal.compensation_line_locked_reason(v_operator, v_lesson, v_event);
    IF v_locked IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', v_locked);
    END IF;

    IF v_note IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'REASON_REQUIRED');
    END IF;

    IF COALESCE(v_revenue, 0) < 0 OR COALESCE(v_amount, 0) < 0 OR length(v_note) > 500
       OR (v_costs IS NOT NULL AND NOT internal.compensation_costs_valid(v_costs)) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_OVERRIDE');
    END IF;

    IF v_model IS NULL AND v_revenue IS NULL AND v_costs IS NULL AND v_amount IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NO_CHANGES');
    END IF;

    IF v_model IS NOT NULL THEN
        SELECT m.is_active INTO v_active FROM public.compensation_models m WHERE m.id = v_model;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'MODEL_NOT_FOUND');
        END IF;
        -- Un modello disattivato non si sceglie; se la lezione lo usa già, resta
        IF NOT v_active AND NOT EXISTS (
            SELECT 1 FROM public.compensation_line_overrides ov
             WHERE ov.operator_id = v_operator
               AND (ov.lesson_id = v_lesson OR ov.event_id = v_event)
               AND ov.model_id = v_model
        ) THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'MODEL_DISABLED');
        END IF;
    END IF;

    -- Senza un modello la riga non si congelerebbe mai: anche con il compenso scritto a mano ne serve uno
    v_base_model := COALESCE(v_base_model,
        internal.resolve_compensation_model(v_operator, v_activity, v_occurred_on));
    IF COALESCE(v_model, v_base_model) IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MODEL_REQUIRED');
    END IF;

    IF v_lesson IS NOT NULL THEN
        INSERT INTO public.compensation_line_overrides (
            operator_id, lesson_id, model_id, revenue_cents, costs, amount_cents, note, created_by, updated_by
        ) VALUES (v_operator, v_lesson, v_model, v_revenue, v_costs, v_amount, v_note, auth.uid(), auth.uid())
        ON CONFLICT (operator_id, lesson_id) WHERE lesson_id IS NOT NULL DO UPDATE
           SET model_id = EXCLUDED.model_id, revenue_cents = EXCLUDED.revenue_cents, costs = EXCLUDED.costs,
               amount_cents = EXCLUDED.amount_cents, note = EXCLUDED.note, updated_by = EXCLUDED.updated_by;
    ELSE
        INSERT INTO public.compensation_line_overrides (
            operator_id, event_id, model_id, revenue_cents, costs, amount_cents, note, created_by, updated_by
        ) VALUES (v_operator, v_event, v_model, v_revenue, v_costs, v_amount, v_note, auth.uid(), auth.uid())
        ON CONFLICT (operator_id, event_id) WHERE event_id IS NOT NULL DO UPDATE
           SET model_id = EXCLUDED.model_id, revenue_cents = EXCLUDED.revenue_cents, costs = EXCLUDED.costs,
               amount_cents = EXCLUDED.amount_cents, note = EXCLUDED.note, updated_by = EXCLUDED.updated_by;
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'SAVED');
EXCEPTION
    WHEN check_violation OR not_null_violation OR invalid_text_representation OR numeric_value_out_of_range THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_OVERRIDE', 'detail', SQLERRM);
END;
$$;

ALTER FUNCTION "public"."staff_save_compensation_override"("jsonb") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."staff_save_compensation_override"("jsonb") FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."staff_save_compensation_override"("jsonb") TO "authenticated", "service_role";
COMMENT ON FUNCTION "public"."staff_save_compensation_override"("jsonb") IS
    'Modifica il compenso di una lezione o di un evento per una persona: modello, incassi, spese e compenso scritti a mano, con il motivo obbligatorio. Rifiuta le righe congelate o pagate. Solo Finanze.';

CREATE OR REPLACE FUNCTION "public"."staff_delete_compensation_override"(
    "p_operator_id" "uuid",
    "p_lesson_id" "uuid" DEFAULT NULL,
    "p_event_id" "uuid" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_locked text;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    IF p_operator_id IS NULL OR (p_lesson_id IS NULL) = (p_event_id IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_OVERRIDE');
    END IF;

    v_locked := internal.compensation_line_locked_reason(p_operator_id, p_lesson_id, p_event_id);
    IF v_locked IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', v_locked);
    END IF;

    DELETE FROM public.compensation_line_overrides ov
     WHERE ov.operator_id = p_operator_id
       AND (ov.lesson_id = p_lesson_id OR ov.event_id = p_event_id);

    RETURN jsonb_build_object('ok', true, 'reason', 'RESET');
END;
$$;

ALTER FUNCTION "public"."staff_delete_compensation_override"("uuid", "uuid", "uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."staff_delete_compensation_override"("uuid", "uuid", "uuid") FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."staff_delete_compensation_override"("uuid", "uuid", "uuid") TO "authenticated", "service_role";
COMMENT ON FUNCTION "public"."staff_delete_compensation_override"("uuid", "uuid", "uuid") IS
    'Toglie le modifiche al compenso di una lezione o di un evento: torna il calcolo del modello. Rifiuta le righe congelate o pagate. Solo Finanze.';
