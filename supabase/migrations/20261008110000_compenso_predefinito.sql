-- Migration 20261008110000: il modello di compenso predefinito
--
-- Richiesta dell'utente del 07/10/2026: fra tutte le combinazioni possibili ne serve una che valga
-- di base, senza doverla assegnare a ogni persona:
--
--   «Dagli incassi della lezione si tolgono affitto sala, usura dei materiali e accoglienza; quello
--    che resta va all'insegnante fino a 40,00 € a lezione, il resto rimane all'Associazione.»
--
-- Fino a oggi, senza un'assegnazione in `compensation_assignments`, una lezione restava «senza
-- modello»: compenso zero e niente da congelare. Ora:
--
--   * un modello può essere il PREDEFINITO (`compensation_models.is_default`, al massimo uno, sempre
--     attivo);
--   * `internal.resolve_compensation_model` lo usa quando per quella persona, attività e data non c'è
--     nessuna assegnazione. Le assegnazioni (per persona o per attività) e il modello scelto per un
--     evento continuano a vincere: per fare diversamente si crea un altro modello e lo si assegna;
--   * il predefinito si cambia con `staff_set_default_compensation_model` (solo Finanze), e non si
--     disattiva finché è il predefinito.
--
-- La migrazione non crea modelli e non sceglie il predefinito: il modello della richiesta è già
-- stato creato dal gestionale l'08/10 («Compenso Standard»), e il predefinito è un dato che si
-- sceglie da lì (Finanze → Compensi → Modelli). Finché nessun modello è predefinito il calcolo resta
-- quello di prima.
--
-- Effetto sui dati, quando un predefinito c'è: i mesi non ancora congelati si calcolano con quel
-- modello per tutte le persone retribuite senza assegnazione, anche per gli eventi che tengono; i
-- volontari restano esclusi. I compensi già congelati non cambiano.
--
-- Compatibilità: una colonna nuova con default, una funzione nuova; `resolve_compensation_model` e
-- `staff_save_compensation_model` mantengono la firma.
--
-- migration-lint:allow revoke — reason: la REVOKE riguarda solo la funzione nuova di questa migrazione (chiusa ad anon); nessun accesso esistente si restringe

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Il segno del predefinito
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."compensation_models"
    ADD COLUMN IF NOT EXISTS "is_default" boolean DEFAULT false NOT NULL;

COMMENT ON COLUMN "public"."compensation_models"."is_default" IS
    'Il modello che vale per chi non ha un modello assegnato (persona, attività o evento). Al massimo uno, sempre attivo; si cambia con staff_set_default_compensation_model.';

CREATE UNIQUE INDEX IF NOT EXISTS "compensation_models_one_default"
    ON "public"."compensation_models" ((true)) WHERE "is_default";

DO $$ BEGIN
    ALTER TABLE "public"."compensation_models"
        ADD CONSTRAINT "compensation_models_default_is_active" CHECK (NOT "is_default" OR "is_active");
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Quale modello vale: prima le assegnazioni, poi il predefinito
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."resolve_compensation_model"(
    "p_operator_id" "uuid",
    "p_activity_id" "uuid",
    "p_on_date" "date"
) RETURNS "uuid"
    LANGUAGE "sql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT COALESCE(
        (SELECT a.model_id
           FROM public.compensation_assignments a
          WHERE a.operator_id = p_operator_id
            AND (a.activity_id IS NULL OR a.activity_id = p_activity_id)
            AND a.valid_from <= p_on_date
            AND (a.valid_to IS NULL OR a.valid_to >= p_on_date)
          ORDER BY (a.activity_id IS NOT NULL) DESC, a.valid_from DESC
          LIMIT 1),
        (SELECT m.id FROM public.compensation_models m WHERE m.is_default)
    );
$$;

COMMENT ON FUNCTION "internal"."resolve_compensation_model"("uuid", "uuid", "date") IS
    'Il modello da usare: prima l''assegnazione specifica per l''attività, poi quella generale (a parità, la più recente fra quelle valide quel giorno); se non ce n''è nessuna, il modello predefinito.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Cambiare il predefinito
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_set_default_compensation_model"("p_model_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_model public.compensation_models%ROWTYPE;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    -- Due cambi insieme non devono incrociarsi sull'indice del predefinito
    PERFORM pg_advisory_xact_lock(hashtext('compensation_models.is_default'));

    SELECT * INTO v_model FROM public.compensation_models WHERE id = p_model_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MODEL_NOT_FOUND');
    END IF;
    IF NOT v_model.is_active THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MODEL_INACTIVE');
    END IF;

    -- Prima si toglie il segno al vecchio, poi lo si mette al nuovo: l'indice unico si controlla riga per riga
    UPDATE public.compensation_models SET is_default = false WHERE is_default AND id <> p_model_id;
    UPDATE public.compensation_models SET is_default = true WHERE id = p_model_id AND NOT is_default;

    RETURN jsonb_build_object('ok', true, 'reason', 'SAVED', 'model_id', p_model_id);
END;
$$;

ALTER FUNCTION "public"."staff_set_default_compensation_model"("uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."staff_set_default_compensation_model"("uuid") FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."staff_set_default_compensation_model"("uuid") TO "authenticated", "service_role";
COMMENT ON FUNCTION "public"."staff_set_default_compensation_model"("uuid") IS
    'Rende predefinito un modello attivo (vale per chi non ha un modello assegnato) e toglie il segno a quello di prima. I mesi già congelati non cambiano. Solo Finanze.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Salvataggio del modello: il predefinito non si disattiva
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
    v_active    boolean := COALESCE((p_payload->>'is_active')::boolean, true);
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
            v_active,
            auth.uid()
        )
        RETURNING id INTO v_id;
    ELSE
        IF NOT v_active AND EXISTS (SELECT 1 FROM public.compensation_models WHERE id = v_id AND is_default) THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'DEFAULT_MODEL_ACTIVE');
        END IF;

        UPDATE public.compensation_models
           SET name = v_name,
               description = NULLIF(btrim(COALESCE(p_payload->>'description', '')), ''),
               min_guaranteed_cents = NULLIF(p_payload->>'min_guaranteed_cents', '')::integer,
               max_hourly_cents = NULLIF(p_payload->>'max_hourly_cents', '')::integer,
               max_per_lesson_cents = NULLIF(p_payload->>'max_per_lesson_cents', '')::integer,
               is_active = v_active
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
    'Crea o modifica un modello di compenso con spese, mattoni, scaglioni e tetti, tutto o niente. Le modifiche valgono per i mesi non ancora congelati. Il predefinito non si disattiva (DEFAULT_MODEL_ACTIVE). Solo Finanze.';

