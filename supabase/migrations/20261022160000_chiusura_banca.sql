-- Migration 20261022160000: chiusura del mese con l'estratto conto (contract v0.3.20)
--
-- Richiesta dell'utente del 22/10/2026: a fine mese, in Finanze → Banca e Stripe, si carica il PDF
-- dei movimenti scaricato dall'home banking (Relax Banking della BCC, «Movimenti Globali») e il
-- gestionale confronta saldo e movimenti con il registro, proponendo le correzioni.
--
-- Il PDF lo legge il gestionale, nel browser; il confronto e le proposte stanno lì. Qui resta la
-- traccia di ogni chiusura, che non blocca niente (decisione dell'utente: «confronto senza blocco»,
-- i movimenti del periodo restano modificabili):
--
--   bank_closings          un periodo chiuso: dal giorno dopo la chiusura precedente fino a una data
--                          scelta; saldo della banca a inizio e a fine periodo, saldo del gestionale a
--                          fine periodo, nota, il PDF nel bucket privato `estratti-conto`
--   bank_statement_lines   i movimenti del PDF dentro il periodo
--   bank_line_links        a quale movimento del registro corrisponde ogni riga: un incasso,
--                          un'uscita o un accredito di Stripe; più incassi per un versamento di
--                          contanti. Ogni movimento del registro sta al massimo in una riga
--   bank_rules             le spese ricorrenti ricordate (canone, bolli, commissioni): dalla seconda
--                          volta la proposta ha già categoria, fornitore e descrizione
--
-- Il PDF dei «Movimenti Globali» non stampa i saldi: il saldo della banca a fine periodo è quello
-- della chiusura precedente (per la prima, il saldo iniziale del conto al 19/08/2026) più i
-- movimenti del PDF. Per questo i periodi sono contigui e si annulla solo l'ultima chiusura.
--
-- Scritture solo con `finance_save_bank_closing` e `finance_delete_bank_closing` (Finanze); le
-- regole si scrivono direttamente, come le categorie di spesa. Il bucket si crea con
-- `supabase/storage/estratti-conto.sql`.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tabelle
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."bank_closings" (
    "id"               "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "period_from"      "date"      NOT NULL,
    "period_to"        "date"      NOT NULL,
    "account_ref"      "text",
    "opening_cents"    integer     NOT NULL,
    "movements_cents"  integer     NOT NULL,
    "closing_cents"    integer     NOT NULL,
    "ledger_cents"     integer     NOT NULL,
    "note"             "text",
    "file_path"        "text",
    "file_name"        "text",
    "printed_on"       "date",
    "closed_by"        "uuid",
    "closed_at"        timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at"       timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"       timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "bank_closings_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "bank_closings_period_from_key" UNIQUE ("period_from"),
    CONSTRAINT "bank_closings_closed_by_fkey"
        FOREIGN KEY ("closed_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "bank_closings_period" CHECK ("period_to" >= "period_from"),
    CONSTRAINT "bank_closings_balance" CHECK ("closing_cents" = "opening_cents" + "movements_cents")
);

ALTER TABLE "public"."bank_closings" OWNER TO "postgres";

COMMENT ON TABLE "public"."bank_closings" IS
    'Chiusure con l''estratto conto (v0.3.20): un periodo per riga, contiguo alla chiusura precedente. Saldo della banca a inizio (opening) e fine (closing = opening + movimenti del PDF), saldo del gestionale a fine periodo quando si è chiuso (ledger). Non blocca i movimenti. Si scrive solo con finance_save_bank_closing.';
COMMENT ON COLUMN "public"."bank_closings"."account_ref" IS
    'Il numero del rapporto letto dal PDF («Rapporto»): una chiusura dopo deve avere lo stesso.';
COMMENT ON COLUMN "public"."bank_closings"."ledger_cents" IS
    'Il saldo della banca del gestionale (finance_account_balances) a fine periodo, nel momento della chiusura. La differenza con closing_cents sono i movimenti in transito o da verificare.';
COMMENT ON COLUMN "public"."bank_closings"."file_path" IS
    'Il PDF nel bucket privato estratti-conto.';
COMMENT ON COLUMN "public"."bank_closings"."printed_on" IS
    'Il giorno in cui l''home banking ha stampato il PDF.';

CREATE TABLE IF NOT EXISTS "public"."bank_statement_lines" (
    "id"            "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "closing_id"    "uuid"      NOT NULL,
    "position"      integer     NOT NULL,
    "booked_on"     "date"      NOT NULL,
    "value_on"      "date",
    "amount_cents"  integer     NOT NULL,
    "causale"       "text"      DEFAULT '' NOT NULL,
    "description"   "text"      DEFAULT '' NOT NULL,
    "note"          "text",
    "created_at"    timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "bank_statement_lines_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "bank_statement_lines_position_key" UNIQUE ("closing_id", "position"),
    CONSTRAINT "bank_statement_lines_closing_id_fkey"
        FOREIGN KEY ("closing_id") REFERENCES "public"."bank_closings"("id") ON DELETE CASCADE,
    CONSTRAINT "bank_statement_lines_amount_not_zero" CHECK ("amount_cents" <> 0)
);

ALTER TABLE "public"."bank_statement_lines" OWNER TO "postgres";

COMMENT ON TABLE "public"."bank_statement_lines" IS
    'I movimenti dell''estratto conto di una chiusura, in ordine di data contabile. amount_cents positivo = entrato sul conto. note = perché è rimasto senza movimento del registro.';

CREATE INDEX IF NOT EXISTS "idx_bank_statement_lines_booked_on" ON "public"."bank_statement_lines" ("booked_on");

CREATE TABLE IF NOT EXISTS "public"."bank_line_links" (
    "id"              "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "line_id"         "uuid"      NOT NULL,
    "closing_id"      "uuid"      NOT NULL,
    "transaction_id"  "uuid",
    "expense_id"      "uuid",
    "transfer_id"     "uuid",
    "created_at"      timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "bank_line_links_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "bank_line_links_line_id_fkey"
        FOREIGN KEY ("line_id") REFERENCES "public"."bank_statement_lines"("id") ON DELETE CASCADE,
    CONSTRAINT "bank_line_links_closing_id_fkey"
        FOREIGN KEY ("closing_id") REFERENCES "public"."bank_closings"("id") ON DELETE CASCADE,
    CONSTRAINT "bank_line_links_transaction_id_fkey"
        FOREIGN KEY ("transaction_id") REFERENCES "public"."transactions"("id") ON DELETE CASCADE,
    CONSTRAINT "bank_line_links_expense_id_fkey"
        FOREIGN KEY ("expense_id") REFERENCES "public"."expenses"("id") ON DELETE CASCADE,
    CONSTRAINT "bank_line_links_transfer_id_fkey"
        FOREIGN KEY ("transfer_id") REFERENCES "public"."account_transfers"("id") ON DELETE CASCADE,
    CONSTRAINT "bank_line_links_transaction_id_key" UNIQUE ("transaction_id"),
    CONSTRAINT "bank_line_links_expense_id_key" UNIQUE ("expense_id"),
    CONSTRAINT "bank_line_links_transfer_id_key" UNIQUE ("transfer_id"),
    CONSTRAINT "bank_line_links_one_target" CHECK (num_nonnulls("transaction_id", "expense_id", "transfer_id") = 1)
);

ALTER TABLE "public"."bank_line_links" OWNER TO "postgres";

COMMENT ON TABLE "public"."bank_line_links" IS
    'A quale movimento del registro corrisponde una riga dell''estratto: un incasso, un''uscita o un accredito di Stripe (più incassi in contanti per un versamento). Ogni movimento del registro sta in una riga sola. closing_id = la chiusura che ha fatto l''abbinamento, anche per una riga rimasta aperta in una chiusura precedente. Se il movimento si cancella, l''abbinamento sparisce e la riga torna da sistemare.';

CREATE INDEX IF NOT EXISTS "idx_bank_line_links_line_id" ON "public"."bank_line_links" ("line_id");
CREATE INDEX IF NOT EXISTS "idx_bank_line_links_closing_id" ON "public"."bank_line_links" ("closing_id");

CREATE TABLE IF NOT EXISTS "public"."bank_rules" (
    "id"               "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "match_causale"    "text",
    "match_text"       "text",
    "category_id"      "uuid"      NOT NULL,
    "vendor"           "text",
    "notes"            "text",
    "rendiconto_voce"  "text",
    "created_by"       "uuid"      DEFAULT "auth"."uid"(),
    "created_at"       timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"       timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "bank_rules_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "bank_rules_category_id_fkey"
        FOREIGN KEY ("category_id") REFERENCES "public"."expense_categories"("id") ON DELETE CASCADE,
    CONSTRAINT "bank_rules_rendiconto_voce_fkey"
        FOREIGN KEY ("rendiconto_voce") REFERENCES "public"."rendiconto_voci"("code"),
    CONSTRAINT "bank_rules_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "bank_rules_something_to_match"
        CHECK (COALESCE(btrim("match_causale"), '') <> '' OR COALESCE(btrim("match_text"), '') <> '')
);

ALTER TABLE "public"."bank_rules" OWNER TO "postgres";

COMMENT ON TABLE "public"."bank_rules" IS
    'Spese ricorrenti dell''estratto conto ricordate (canone, bolli, commissioni): una riga in uscita con questa causale (uguale, senza maiuscole) e, se c''è, questo testo nella descrizione diventa una proposta di uscita già compilata. Solo uscite.';

CREATE UNIQUE INDEX IF NOT EXISTS "bank_rules_match_key" ON "public"."bank_rules" (
    lower(COALESCE(btrim("match_causale"), '')), lower(COALESCE(btrim("match_text"), ''))
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Permessi: solo Finanze; chiusure, righe e abbinamenti si scrivono con le funzioni
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TRIGGER "bank_closings_updated_at"
    BEFORE UPDATE ON "public"."bank_closings"
    FOR EACH ROW EXECUTE FUNCTION "internal"."update_updated_at_column"();

CREATE OR REPLACE TRIGGER "bank_rules_updated_at"
    BEFORE UPDATE ON "public"."bank_rules"
    FOR EACH ROW EXECUTE FUNCTION "internal"."update_updated_at_column"();

ALTER TABLE "public"."bank_closings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."bank_statement_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."bank_line_links" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."bank_rules" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bank_closings_select_finance" ON "public"."bank_closings";
CREATE POLICY "bank_closings_select_finance" ON "public"."bank_closings"
    FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());

DROP POLICY IF EXISTS "bank_statement_lines_select_finance" ON "public"."bank_statement_lines";
CREATE POLICY "bank_statement_lines_select_finance" ON "public"."bank_statement_lines"
    FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());

DROP POLICY IF EXISTS "bank_line_links_select_finance" ON "public"."bank_line_links";
CREATE POLICY "bank_line_links_select_finance" ON "public"."bank_line_links"
    FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());

DROP POLICY IF EXISTS "bank_rules_all_finance" ON "public"."bank_rules";
CREATE POLICY "bank_rules_all_finance" ON "public"."bank_rules"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

GRANT SELECT ON TABLE "public"."bank_closings" TO "authenticated";
GRANT SELECT ON TABLE "public"."bank_statement_lines" TO "authenticated";
GRANT SELECT ON TABLE "public"."bank_line_links" TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."bank_rules" TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Quanto sposta sul conto un movimento del registro
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Gli stessi movimenti che conta `finance_account_balances` per la banca: incassi pagati (e
-- rimborsi, negativi) non con carta, uscite confermate non trattenute da Stripe, accrediti di
-- Stripe. NULL se il movimento non c'è o non tocca il conto.

CREATE OR REPLACE FUNCTION "internal"."bank_link_cents"(
    "p_transaction_id" "uuid",
    "p_expense_id" "uuid",
    "p_transfer_id" "uuid"
) RETURNS integer
    LANGUAGE "sql"
    STABLE
    SET "search_path" TO 'public'
    AS $$
    SELECT CASE
        WHEN p_transaction_id IS NOT NULL THEN (
            SELECT t.amount_cents
              FROM public.transactions t
              JOIN public.association_settings s ON s.id = true
              LEFT JOIN public.transactions o ON o.id = t.refund_of_id
             WHERE t.id = p_transaction_id
               AND t.status IN ('paid', 'refunded', 'partially_refunded')
               AND (o.id IS NULL OR o.status IN ('paid', 'refunded', 'partially_refunded'))
               AND internal.cash_account_for(t.method) = 'bank'
               AND t.occurred_on >= s.ledger_start_date)
        WHEN p_expense_id IS NOT NULL THEN (
            SELECT -e.amount_cents
              FROM public.expenses e
              JOIN public.association_settings s ON s.id = true
             WHERE e.id = p_expense_id
               AND e.confirmed_at IS NOT NULL
               AND internal.cash_account_for(e.payment_method) = 'bank'
               AND e.expense_date >= s.ledger_start_date)
        WHEN p_transfer_id IS NOT NULL THEN (
            SELECT CASE WHEN a.to_account = 'bank' THEN a.amount_cents
                        WHEN a.from_account = 'bank' THEN -a.amount_cents END
              FROM public.account_transfers a
             WHERE a.id = p_transfer_id)
    END;
$$;

ALTER FUNCTION "internal"."bank_link_cents"("uuid", "uuid", "uuid") OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."bank_link_cents"("uuid", "uuid", "uuid") IS
    'Quanto sposta sul conto corrente un incasso, un''uscita o un giroconto del registro (positivo = entra), con le regole di finance_account_balances. NULL se non esiste o non tocca la banca.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Chiudere un periodo
-- ─────────────────────────────────────────────────────────────────────────────
--
-- p_payload:
--   period_from, period_to   date; period_from = giorno dopo la chiusura precedente (la prima parte
--                            dall'inizio della contabilità); period_to prima di oggi
--   account_ref, printed_on, file_path, file_name, note
--   lines        [{ booked_on, value_on?, amount_cents, causale?, description?, note?,
--                   links: [{ transaction_id | expense_id | transfer_id }] }]
--   carry_links  [{ line_id, transaction_id | expense_id | transfer_id }]: righe rimaste aperte nelle
--                chiusure precedenti e abbinate adesso
--
-- Ogni riga abbinata deve tornare al centesimo con i suoi movimenti; ogni movimento sta in una riga
-- sola. Risposte: SAVED (con closing_id e i saldi), NOT_FINANCE, INVALID_PERIOD, PERIOD_NOT_OVER,
-- PERIOD_NOT_CONTIGUOUS (con expected_from), ACCOUNT_MISMATCH, INVALID_LINE, LINE_OUTSIDE_PERIOD,
-- LINK_NOT_BANK, ALREADY_LINKED, LINE_NOT_OPEN, LINK_AMOUNT_MISMATCH (con position o line_id).

CREATE OR REPLACE FUNCTION "public"."finance_save_bank_closing"("p_payload" "jsonb")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_settings      public.association_settings%ROWTYPE;
    v_prev          public.bank_closings%ROWTYPE;
    v_from          date;
    v_to            date;
    v_account       text := NULLIF(btrim(COALESCE(p_payload->>'account_ref', '')), '');
    v_expected_from date;
    v_opening       bigint;
    v_movements     bigint := 0;
    v_ledger        bigint;
    v_closing_id    uuid;
    v_line          jsonb;
    v_link          jsonb;
    v_line_id       uuid;
    v_position      integer;
    v_amount        integer;
    v_booked        date;
    v_cents         integer;
    v_linked        bigint;
    v_count         integer;
    v_detail        text;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    BEGIN
        v_from := (p_payload->>'period_from')::date;
        v_to   := (p_payload->>'period_to')::date;
    EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_PERIOD');
    END;
    IF v_from IS NULL OR v_to IS NULL OR v_to < v_from
       OR jsonb_typeof(COALESCE(p_payload->'lines', '[]'::jsonb)) <> 'array'
       OR jsonb_typeof(COALESCE(p_payload->'carry_links', '[]'::jsonb)) <> 'array' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_PERIOD');
    END IF;
    -- I movimenti di oggi l'home banking può non averli ancora tutti
    IF v_to >= internal.rome_today() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PERIOD_NOT_OVER');
    END IF;

    -- Una chiusura alla volta: il periodo dipende dall'ultima
    LOCK TABLE public.bank_closings IN SHARE ROW EXCLUSIVE MODE;

    SELECT * INTO v_settings FROM public.association_settings WHERE id = true;
    SELECT * INTO v_prev FROM public.bank_closings ORDER BY period_to DESC LIMIT 1;
    IF FOUND THEN
        v_expected_from := v_prev.period_to + 1;
        v_opening := v_prev.closing_cents;
        IF v_account IS NOT NULL AND v_prev.account_ref IS NOT NULL AND v_account <> v_prev.account_ref THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'ACCOUNT_MISMATCH', 'expected', v_prev.account_ref);
        END IF;
    ELSE
        v_expected_from := v_settings.ledger_start_date;
        v_opening := v_settings.opening_bank_cents;
    END IF;
    IF v_from <> v_expected_from THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PERIOD_NOT_CONTIGUOUS', 'expected_from', v_expected_from);
    END IF;

    v_ledger := (public.finance_account_balances(v_to)->>'bank_cents')::bigint;

    -- Da qui in poi un errore annulla tutto quello che è stato scritto (blocco con EXCEPTION)
    BEGIN
        INSERT INTO public.bank_closings (
            period_from, period_to, account_ref, opening_cents, movements_cents, closing_cents,
            ledger_cents, note, file_path, file_name, printed_on, closed_by
        ) VALUES (
            v_from, v_to, v_account, v_opening, 0, v_opening, v_ledger,
            NULLIF(btrim(COALESCE(p_payload->>'note', '')), ''),
            NULLIF(p_payload->>'file_path', ''),
            NULLIF(p_payload->>'file_name', ''),
            NULLIF(p_payload->>'printed_on', '')::date,
            auth.uid()
        ) RETURNING id INTO v_closing_id;

        v_position := 0;
        FOR v_line IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'lines', '[]'::jsonb))
        LOOP
            v_position := v_position + 1;
            BEGIN
                v_booked := (v_line->>'booked_on')::date;
                v_amount := (v_line->>'amount_cents')::integer;
            EXCEPTION WHEN others THEN
                RAISE EXCEPTION 'INVALID_LINE' USING DETAIL = v_position::text;
            END;
            IF v_booked IS NULL OR v_amount IS NULL OR v_amount = 0
               OR length(COALESCE(v_line->>'description', '')) > 2000
               OR length(COALESCE(v_line->>'causale', '')) > 500
               OR length(COALESCE(v_line->>'note', '')) > 1000 THEN
                RAISE EXCEPTION 'INVALID_LINE' USING DETAIL = v_position::text;
            END IF;
            IF v_booked < v_from OR v_booked > v_to THEN
                RAISE EXCEPTION 'LINE_OUTSIDE_PERIOD' USING DETAIL = v_position::text;
            END IF;

            INSERT INTO public.bank_statement_lines (
                closing_id, position, booked_on, value_on, amount_cents, causale, description, note
            ) VALUES (
                v_closing_id, v_position, v_booked, NULLIF(v_line->>'value_on', '')::date, v_amount,
                COALESCE(btrim(v_line->>'causale'), ''), COALESCE(btrim(v_line->>'description'), ''),
                NULLIF(btrim(COALESCE(v_line->>'note', '')), '')
            ) RETURNING id INTO v_line_id;
            v_movements := v_movements + v_amount;

            v_linked := 0;
            v_count := 0;
            FOR v_link IN SELECT value FROM jsonb_array_elements(COALESCE(v_line->'links', '[]'::jsonb))
            LOOP
                v_cents := internal.bank_link_cents(
                    NULLIF(v_link->>'transaction_id', '')::uuid,
                    NULLIF(v_link->>'expense_id', '')::uuid,
                    NULLIF(v_link->>'transfer_id', '')::uuid);
                IF v_cents IS NULL THEN
                    RAISE EXCEPTION 'LINK_NOT_BANK' USING DETAIL = v_position::text;
                END IF;
                INSERT INTO public.bank_line_links (line_id, closing_id, transaction_id, expense_id, transfer_id)
                VALUES (v_line_id, v_closing_id,
                        NULLIF(v_link->>'transaction_id', '')::uuid,
                        NULLIF(v_link->>'expense_id', '')::uuid,
                        NULLIF(v_link->>'transfer_id', '')::uuid);
                v_linked := v_linked + v_cents;
                v_count := v_count + 1;
            END LOOP;
            IF v_count > 0 AND v_linked <> v_amount THEN
                RAISE EXCEPTION 'LINK_AMOUNT_MISMATCH' USING DETAIL = v_position::text;
            END IF;
        END LOOP;

        -- Righe delle chiusure precedenti rimaste aperte e abbinate adesso
        FOR v_link IN SELECT value FROM jsonb_array_elements(COALESCE(p_payload->'carry_links', '[]'::jsonb))
        LOOP
            v_line_id := NULLIF(v_link->>'line_id', '')::uuid;
            IF v_line_id IS NULL
               OR NOT EXISTS (SELECT 1 FROM public.bank_statement_lines l
                               WHERE l.id = v_line_id AND l.closing_id <> v_closing_id)
               OR EXISTS (SELECT 1 FROM public.bank_line_links k
                           WHERE k.line_id = v_line_id AND k.closing_id <> v_closing_id) THEN
                RAISE EXCEPTION 'LINE_NOT_OPEN' USING DETAIL = COALESCE(v_line_id::text, '');
            END IF;
            v_cents := internal.bank_link_cents(
                NULLIF(v_link->>'transaction_id', '')::uuid,
                NULLIF(v_link->>'expense_id', '')::uuid,
                NULLIF(v_link->>'transfer_id', '')::uuid);
            IF v_cents IS NULL THEN
                RAISE EXCEPTION 'LINK_NOT_BANK' USING DETAIL = v_line_id::text;
            END IF;
            INSERT INTO public.bank_line_links (line_id, closing_id, transaction_id, expense_id, transfer_id)
            VALUES (v_line_id, v_closing_id,
                    NULLIF(v_link->>'transaction_id', '')::uuid,
                    NULLIF(v_link->>'expense_id', '')::uuid,
                    NULLIF(v_link->>'transfer_id', '')::uuid);
        END LOOP;
        FOR v_line_id, v_amount, v_linked IN
            SELECT l.id, l.amount_cents,
                   sum(internal.bank_link_cents(k.transaction_id, k.expense_id, k.transfer_id))
              FROM public.bank_line_links k
              JOIN public.bank_statement_lines l ON l.id = k.line_id
             WHERE k.closing_id = v_closing_id AND l.closing_id <> v_closing_id
             GROUP BY l.id, l.amount_cents
        LOOP
            IF v_linked <> v_amount THEN
                RAISE EXCEPTION 'LINK_AMOUNT_MISMATCH' USING DETAIL = v_line_id::text;
            END IF;
        END LOOP;

        UPDATE public.bank_closings
           SET movements_cents = v_movements, closing_cents = v_opening + v_movements
         WHERE id = v_closing_id;
    EXCEPTION
        WHEN unique_violation THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_LINKED');
        WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_LINE');
        WHEN raise_exception THEN
            -- detail: la posizione della riga nel periodo, o l'id di una riga di una chiusura prima
            GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
            RETURN jsonb_build_object('ok', false, 'reason', SQLERRM, 'detail', NULLIF(v_detail, ''));
    END;

    RETURN jsonb_build_object(
        'ok', true,
        'reason', 'SAVED',
        'closing_id', v_closing_id,
        'opening_cents', v_opening,
        'movements_cents', v_movements,
        'closing_cents', v_opening + v_movements,
        'ledger_cents', v_ledger
    );
END;
$$;

ALTER FUNCTION "public"."finance_save_bank_closing"("jsonb") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."finance_save_bank_closing"("jsonb") TO "authenticated";
COMMENT ON FUNCTION "public"."finance_save_bank_closing"("jsonb") IS
    'Chiude un periodo con l''estratto conto: righe del PDF, abbinamenti col registro (anche per righe rimaste aperte prima), saldi. Periodi contigui, fino a ieri; ogni riga abbinata torna al centesimo. Non blocca i movimenti. Solo Finanze.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Annullare l'ultima chiusura
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Solo l'ultima: il saldo di partenza di ogni chiusura è quello della precedente. Se ne vanno righe
-- e abbinamenti, anche quelli fatti da questa chiusura su righe di chiusure prima (tornano aperte).
-- Il PDF lo cancella il gestionale dal bucket con il percorso restituito.

CREATE OR REPLACE FUNCTION "public"."finance_delete_bank_closing"("p_closing_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_last public.bank_closings%ROWTYPE;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    LOCK TABLE public.bank_closings IN SHARE ROW EXCLUSIVE MODE;

    SELECT * INTO v_last FROM public.bank_closings ORDER BY period_to DESC LIMIT 1;
    IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM public.bank_closings WHERE id = p_closing_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLOSING_NOT_FOUND');
    END IF;
    IF v_last.id <> p_closing_id THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'LAST_ONLY');
    END IF;

    DELETE FROM public.bank_closings WHERE id = p_closing_id;

    RETURN jsonb_build_object('ok', true, 'reason', 'DELETED', 'file_path', v_last.file_path);
END;
$$;

ALTER FUNCTION "public"."finance_delete_bank_closing"("uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."finance_delete_bank_closing"("uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."finance_delete_bank_closing"("uuid") IS
    'Annulla l''ultima chiusura con l''estratto conto (LAST_ONLY per le altre): righe e abbinamenti se ne vanno, i movimenti del registro restano. Restituisce il percorso del PDF da togliere dal bucket. Solo Finanze.';
