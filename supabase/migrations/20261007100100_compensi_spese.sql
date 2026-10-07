-- Migration 20261007100100: spese della lezione e tetto a lezione nei modelli di compenso
--
-- Il calcolo diventa quello di un contenitore, come lo fa la tesoreria sul foglio di Yoga e
-- Meditazione:
--
--   incassi della lezione
--   − spese della lezione (mattoni `cost_*`: affitto sala, usura materiali, accoglienza…)
--   = quello che resta
--   compenso = somma degli altri mattoni (fra cui `percent_of_margin`, una percentuale di quello che
--              resta), più lo scaglione, poi i tetti (a lezione e orario: vale il più basso), poi il
--              minimo garantito, mai sotto zero
--   allo Studio = quello che resta − compenso
--
-- Esempio della richiesta: 4 persone con l'abbonamento da 52 € per 4 ingressi = 52 € di incassi;
-- spese 4 + 3 + 1 = 8 €; restano 44 €; all'insegnante il 100% di quello che resta, con il tetto di
-- 40 € a lezione = 40 €; allo Studio 4 €.
--
-- Le spese servono solo al calcolo: non diventano uscite. L'affitto vero, i materiali e il resto si
-- registrano in Uscite come sempre, altrimenti si conterebbero due volte.
--
-- Cambia il significato della vecchia «Trattenuta sala» (`room_fee_percent`, ora
-- `cost_percent_of_revenue`): prima si sottraeva dal compenso, ora dagli incassi, e tocca il compenso
-- solo attraverso `percent_of_margin`. Il modello di prima «100% degli incassi − 15% di sala» si
-- scrive «spesa 15% sugli incassi + 100% di quello che resta» e dà lo stesso importo. In produzione
-- non c'è ancora nessun modello né compenso congelato (verificato il 07/10): nessun dato da
-- convertire.
--
-- Compatibilità: una colonna nuova facoltativa, stesse funzioni con la stessa firma; il dettaglio del
-- calcolo (`breakdown`) ha dei campi in più (`costs`, `costs_cents`, `margin_cents`, `studio_cents`).
--
-- migration-lint:allow drop-constraint — reason: il vincolo sul tipo di valore dei mattoni si toglie solo per rimetterlo subito con i tipi nuovi, più largo; le righe che lo rispettavano lo rispettano ancora (in produzione nessuna riga)

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tetto a lezione
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."compensation_models"
    ADD COLUMN IF NOT EXISTS "max_per_lesson_cents" integer;

DO $$ BEGIN
    ALTER TABLE "public"."compensation_models"
        ADD CONSTRAINT "compensation_models_max_per_lesson_non_negative"
        CHECK ("max_per_lesson_cents" IS NULL OR "max_per_lesson_cents" >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN "public"."compensation_models"."max_per_lesson_cents" IS
    'Tetto a lezione (o evento), qualunque sia la durata. Con anche il tetto orario vale il più basso.';
COMMENT ON COLUMN "public"."compensation_models"."max_hourly_cents" IS
    'Tetto orario, riproporzionato sulla durata effettiva della lezione. Con anche il tetto a lezione vale il più basso.';
COMMENT ON COLUMN "public"."compensation_models"."min_guaranteed_cents" IS
    'Minimo garantito per lezione. Si applica DOPO i tetti: se sono in contrasto, vince il minimo.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Mattoni: spese e compenso
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."compensation_components"
    DROP CONSTRAINT IF EXISTS "compensation_components_value_matches_kind";

ALTER TABLE "public"."compensation_components"
    ADD CONSTRAINT "compensation_components_value_matches_kind" CHECK (
        ("kind" IN ('fixed_per_lesson'::"public"."compensation_component_kind",
                    'fixed_per_hour'::"public"."compensation_component_kind",
                    'per_participant'::"public"."compensation_component_kind",
                    'cost_per_lesson'::"public"."compensation_component_kind",
                    'cost_per_hour'::"public"."compensation_component_kind",
                    'cost_per_participant'::"public"."compensation_component_kind")
         AND "value_cents" IS NOT NULL AND "value_cents" >= 0 AND "value_percent" IS NULL)
        OR
        ("kind" IN ('percent_of_revenue'::"public"."compensation_component_kind",
                    'percent_of_margin'::"public"."compensation_component_kind",
                    'cost_percent_of_revenue'::"public"."compensation_component_kind")
         AND "value_percent" IS NOT NULL AND "value_percent" >= 0 AND "value_percent" <= 100
         AND "value_cents" IS NULL)
    );

COMMENT ON TABLE "public"."compensation_components" IS
    'I mattoni di un modello. Le spese (`cost_*`) si tolgono dagli incassi della lezione e non diventano uscite; gli altri si sommano e fanno il compenso. `percent_of_margin` è una percentuale di quello che resta dopo le spese.';
COMMENT ON COLUMN "public"."compensation_components"."note" IS
    'Per le spese, il nome che si legge nel calcolo (Affitto sala, Usura materiali, Accoglienza).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Il calcolo
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."compute_compensation"(
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
    v_model         public.compensation_models%ROWTYPE;
    v_c             public.compensation_components%ROWTYPE;
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

    v_margin := v_revenue - v_costs;

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

COMMENT ON FUNCTION "internal"."compute_compensation"("uuid", integer, integer, bigint) IS
    'Incassi − spese = quello che resta; il compenso somma gli altri mattoni, lo scaglione, i tetti e il minimo; allo Studio va il resto. Restituisce importo e dettaglio. Funzione interna: la chiamano solo le funzioni delle Finanze.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Salvataggio del modello: anche il tetto a lezione
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_save_compensation_model"("p_payload" "jsonb")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_id        uuid := NULLIF(p_payload->>'id', '')::uuid;
    v_name      text := NULLIF(btrim(COALESCE(p_payload->>'name', '')), '');
    v_c         jsonb;
    v_t         jsonb;
    v_i         integer := 0;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    IF v_name IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NAME_REQUIRED');
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO public.compensation_models (
            name, description, min_guaranteed_cents, max_hourly_cents, max_per_lesson_cents, is_active, created_by
        )
        VALUES (
            v_name,
            NULLIF(btrim(COALESCE(p_payload->>'description', '')), ''),
            NULLIF(p_payload->>'min_guaranteed_cents', '')::integer,
            NULLIF(p_payload->>'max_hourly_cents', '')::integer,
            NULLIF(p_payload->>'max_per_lesson_cents', '')::integer,
            COALESCE((p_payload->>'is_active')::boolean, true),
            auth.uid()
        )
        RETURNING id INTO v_id;
    ELSE
        UPDATE public.compensation_models
           SET name = v_name,
               description = NULLIF(btrim(COALESCE(p_payload->>'description', '')), ''),
               min_guaranteed_cents = NULLIF(p_payload->>'min_guaranteed_cents', '')::integer,
               max_hourly_cents = NULLIF(p_payload->>'max_hourly_cents', '')::integer,
               max_per_lesson_cents = NULLIF(p_payload->>'max_per_lesson_cents', '')::integer,
               is_active = COALESCE((p_payload->>'is_active')::boolean, true)
         WHERE id = v_id;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'MODEL_NOT_FOUND');
        END IF;
        DELETE FROM public.compensation_components WHERE model_id = v_id;
        DELETE FROM public.compensation_tiers WHERE model_id = v_id;
    END IF;

    FOR v_c IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'components', '[]'::jsonb)) LOOP
        v_i := v_i + 1;
        INSERT INTO public.compensation_components (model_id, kind, value_cents, value_percent, display_order, note)
        VALUES (
            v_id,
            (v_c->>'kind')::public.compensation_component_kind,
            NULLIF(v_c->>'value_cents', '')::integer,
            NULLIF(v_c->>'value_percent', '')::numeric,
            v_i * 10,
            NULLIF(btrim(COALESCE(v_c->>'note', '')), '')
        );
    END LOOP;

    FOR v_t IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'tiers', '[]'::jsonb)) LOOP
        INSERT INTO public.compensation_tiers (model_id, min_participants, max_participants, amount_cents, note)
        VALUES (
            v_id,
            (v_t->>'min_participants')::integer,
            NULLIF(v_t->>'max_participants', '')::integer,
            (v_t->>'amount_cents')::integer,
            NULLIF(btrim(COALESCE(v_t->>'note', '')), '')
        );
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'reason', 'SAVED', 'model_id', v_id);
EXCEPTION
    WHEN check_violation OR not_null_violation OR invalid_text_representation OR numeric_value_out_of_range THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_MODEL', 'detail', SQLERRM);
END;
$$;

COMMENT ON FUNCTION "public"."staff_save_compensation_model"("jsonb") IS
    'Crea o modifica un modello di compenso con spese, mattoni, scaglioni e tetti, tutto o niente. Le modifiche valgono per i mesi non ancora congelati. Solo Finanze.';
