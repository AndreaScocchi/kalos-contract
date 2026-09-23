-- Migration 20260924100000: pagamenti online con Stripe (sessione 5)
--
-- La sessione 3 ha preparato le tabelle di Stripe (`stripe_events`, `stripe_payments`,
-- `stripe_refunds`) e il trigger che trasforma la commissione in un'uscita. Qui arriva quello che serve
-- per incassare davvero: la quota associativa dal sito ("Diventa socio") e le donazioni con carta.
--
-- IL PRINCIPIO. Gli eventi di Stripe arrivano in qualunque ordine, anche due volte e anche in
-- parallelo. Per questo il webhook non li usa come dati: ogni evento che riguarda un pagamento fa
-- rileggere da Stripe lo stato completo del PaymentIntent (pagamento, commissione, rimborsi) e lo passa
-- a UNA sola funzione, `stripe_apply_payment_state`, che lo riporta nel database con la riga del
-- pagamento bloccata. Applicare due volte lo stesso stato non cambia nulla; un rimborso che arriva
-- "prima" del pagamento trova il pagamento scritto nello stesso passaggio.
--
-- MAI DATI DI PROVA NEL REGISTRO DI PRODUZIONE. La numerazione delle ricevute non ha buchi: una
-- ricevuta di prova occuperebbe un numero per sempre. Un pagamento in modalità test (`livemode`
-- false) scrive incassi, ricevute e uscite solo se esiste l'interruttore `stripe_test_ledger`, che
-- NON è in nessuna migrazione: lo crea solo il seed locale. In produzione un pagamento di prova resta
-- in `stripe_payments` e basta. Vale anche per il trigger delle commissioni, che prima non lo
-- controllava.
--
-- Il resto:
--   * `issue_receipt` e `staff_refund_transaction` hanno ora un "core" in `internal` condiviso col
--     webhook, che non è staff e non ha un utente. Fuori non cambiano.
--   * `staff_refund_transaction` rifiuta gli incassi online: registrare a mano il rimborso di un
--     pagamento con carta lascerebbe i soldi sulla carta, o li restituirebbe due volte. Quelli si
--     rimborsano da Stripe (`staff_prepare_stripe_refund` + edge function `stripe-refund`).
--   * Un secondo pagamento della stessa quota si registra comunque (il denaro è arrivato), segnato
--     `is_duplicate` e SENZA ricevuta, per non bruciare un numero su soldi da restituire.
--   * `receipts` sa a chi e quando è stata inviata per email, e "prenota" l'invio così due consegne
--     dello stesso evento non mandano due email.
--
-- Compatibilità: additiva. Una colonna perde il NOT NULL (`stripe_payments.payment_intent_id`:
-- Checkout crea il PaymentIntent solo quando la persona paga), colonne, indici, una tabella e
-- funzioni nuove. `issue_receipt` e `staff_refund_transaction` mantengono firma e risposte; la sola
-- risposta nuova è `USE_STRIPE_REFUND`. Nessun consumer legge ancora `stripe_payments`.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 (A5, A7, D1–D4, H5) e kalos-contract/STRIPE_SETUP.md.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tabelle
-- ─────────────────────────────────────────────────────────────────────────────

-- Checkout Session: il PaymentIntent nasce solo al pagamento, quindi la riga esiste prima di lui.
ALTER TABLE "public"."stripe_payments" ALTER COLUMN "payment_intent_id" DROP NOT NULL;

ALTER TABLE "public"."stripe_payments"
    ADD COLUMN IF NOT EXISTS "source"       "public"."transaction_source",
    ADD COLUMN IF NOT EXISTS "metadata"     "jsonb"   DEFAULT '{}'::"jsonb" NOT NULL,
    ADD COLUMN IF NOT EXISTS "is_duplicate" boolean   DEFAULT false NOT NULL;

COMMENT ON COLUMN "public"."stripe_payments"."source" IS
    'Da dove arriva il pagamento (sito o app): diventa la `source` della transazione.';
COMMENT ON COLUMN "public"."stripe_payments"."metadata" IS
    'Dati del momento del checkout: anno della quota, dati del donatore per la ricevuta (`payer`). Quando una sessione di donazione scade senza pagamento, i dati del donatore si cancellano.';
COMMENT ON COLUMN "public"."stripe_payments"."is_duplicate" IS
    'La quota risultava già pagata o esonerata quando è arrivato questo pagamento: l''incasso è registrato, senza ricevuta, ed è da rimborsare.';

CREATE UNIQUE INDEX IF NOT EXISTS "stripe_payments_checkout_session_id_key"
    ON "public"."stripe_payments" ("checkout_session_id") WHERE "checkout_session_id" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "idx_stripe_payments_open_target"
    ON "public"."stripe_payments" ("target_id")
    WHERE "status" = 'created'::"public"."stripe_payment_status";

-- Un pagamento online produce UN incasso, anche con due consegne in parallelo dello stesso evento.
-- Le righe di rimborso non portano `stripe_payment_id` e comunque sono escluse.
CREATE UNIQUE INDEX IF NOT EXISTS "transactions_one_income_per_stripe_payment"
    ON "public"."transactions" ("stripe_payment_id")
    WHERE "stripe_payment_id" IS NOT NULL AND "refund_of_id" IS NULL;

ALTER TABLE "public"."stripe_refunds"
    ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL;

CREATE OR REPLACE TRIGGER "stripe_refunds_updated_at"
    BEFORE UPDATE ON "public"."stripe_refunds"
    FOR EACH ROW EXECUTE FUNCTION "internal"."update_updated_at_column"();

ALTER TABLE "public"."receipts"
    ADD COLUMN IF NOT EXISTS "sent_to"         "text",
    ADD COLUMN IF NOT EXISTS "send_claimed_at" timestamp with time zone,
    ADD COLUMN IF NOT EXISTS "send_error"      "text";

COMMENT ON COLUMN "public"."receipts"."sent_to" IS 'Indirizzo a cui la ricevuta è stata inviata l''ultima volta.';
COMMENT ON COLUMN "public"."receipts"."send_claimed_at" IS
    'Invio in corso: chi sta per mandare l''email lo segna qui prima, così due consegne dello stesso evento non mandano due email. Scade dopo pochi minuti.';
COMMENT ON COLUMN "public"."receipts"."send_error" IS 'Motivo dell''ultimo invio non riuscito, finché un invio non riesce.';

-- Limite ai checkout per indirizzo IP: un modulo di donazione aperto a tutti è un bersaglio classico
-- per chi prova carte rubate. Si salva solo un'impronta dell'IP, mai l'IP.
CREATE TABLE IF NOT EXISTS "public"."stripe_checkout_attempts" (
    "id"            bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    "ip_hash"       "text"  NOT NULL,
    "purpose"       "public"."stripe_purpose" NOT NULL,
    "created_at"    timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "stripe_checkout_attempts_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "public"."stripe_checkout_attempts" OWNER TO "postgres";
COMMENT ON TABLE "public"."stripe_checkout_attempts" IS
    'Tentativi di checkout per impronta dell''IP, per il limite orario delle donazioni. Tabella interna: nessuna app la legge o la scrive; le righe più vecchie di un giorno si cancellano da sole.';

CREATE INDEX IF NOT EXISTS "idx_stripe_checkout_attempts_ip"
    ON "public"."stripe_checkout_attempts" ("ip_hash", "created_at");

-- RLS attivo e nessuna policy né grant: ci arrivano solo le funzioni e service_role.
ALTER TABLE "public"."stripe_checkout_attempts" ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Interruttori
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."payments_enabled"() RETURNS boolean
    LANGUAGE "sql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key = 'payments'), false);
$$;

ALTER FUNCTION "internal"."payments_enabled"() OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."payments_enabled"() IS
    'Interruttore `payments`: se è spento non si apre nessun checkout (il sito nasconde il pagamento online).';

CREATE OR REPLACE FUNCTION "internal"."stripe_ledger_allowed"("p_livemode" boolean) RETURNS boolean
    LANGUAGE "sql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT COALESCE(p_livemode, false)
        OR COALESCE((SELECT enabled FROM public.feature_flags WHERE key = 'stripe_test_ledger'), false);
$$;

ALTER FUNCTION "internal"."stripe_ledger_allowed"(boolean) OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."stripe_ledger_allowed"(boolean) IS
    'Un pagamento Stripe può scrivere incassi, ricevute e uscite? Sì se è vero (livemode); se è di prova, solo dove esiste l''interruttore `stripe_test_ledger`, che crea solo il seed locale. In produzione un pagamento di prova non tocca registro, uscite né numerazione.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. La commissione diventa un'uscita — versione corretta
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Tre correzioni rispetto alla sessione 3:
--   * parte da `succeeded_at`, non dallo stato: se la commissione arriva dopo un rimborso, lo stato è
--     già `refunded` e prima l'uscita non nasceva mai (Stripe la commissione non la restituisce);
--   * rispetta `stripe_ledger_allowed`: una commissione di prova non diventa un'uscita vera;
--   * la nota non diventa NULL quando il PaymentIntent non c'è, e la data è quella italiana.

CREATE OR REPLACE FUNCTION "internal"."record_stripe_fee_expense"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_category_id uuid;
    v_expense_id  uuid;
BEGIN
    IF NEW.succeeded_at IS NULL
       OR COALESCE(NEW.fee_cents, 0) <= 0
       OR NEW.fee_expense_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    IF NOT "internal"."stripe_ledger_allowed"(NEW.livemode) THEN
        RETURN NEW;
    END IF;

    SELECT id INTO v_category_id FROM public.expense_categories WHERE slug = 'commissioni';

    INSERT INTO public.expenses (
        amount_cents, expense_date, category, category_id, notes,
        is_fixed, source, confirmed_at
    ) VALUES (
        NEW.fee_cents,
        (NEW.succeeded_at AT TIME ZONE 'Europe/Rome')::date,
        'other', v_category_id,
        'Commissione Stripe — ' || COALESCE(NEW.payment_intent_id, NEW.checkout_session_id, NEW.id::text),
        false, 'stripe_fee', now()
    )
    RETURNING id INTO v_expense_id;

    UPDATE public.stripe_payments SET fee_expense_id = v_expense_id WHERE id = NEW.id;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION "internal"."record_stripe_fee_expense"() IS
    'Quando un pagamento online è riuscito e la sua commissione è nota, la registra come uscita (H5), una volta sola. Mai per i pagamenti di prova in produzione.';

-- Il trigger esistente guarda solo `status` e `fee_cents`: deve accorgersi anche di `succeeded_at`.
CREATE OR REPLACE TRIGGER "stripe_payments_fee_expense"
    AFTER INSERT OR UPDATE OF "status", "fee_cents", "succeeded_at" ON "public"."stripe_payments"
    FOR EACH ROW EXECUTE FUNCTION "internal"."record_stripe_fee_expense"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Ricevuta: un core condiviso con il webhook
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Il corpo è quello di `issue_receipt` della sessione 4, con due differenze: niente controllo dello
-- staff (lo fa chi lo chiama) e, se l'incasso non ha una scheda cliente (le donazioni dal sito),
-- intestazione presa da `transactions.metadata->'payer'`, cioè da quello che il donatore ha scritto.

CREATE OR REPLACE FUNCTION "internal"."issue_receipt_core"(
    "p_transaction_id" "uuid",
    "p_causale" "text",
    "p_created_by" "uuid"
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_tx            public.transactions%ROWTYPE;
    v_settings      public.association_settings%ROWTYPE;
    v_year          integer;
    v_number        integer;
    v_full_number   text;
    v_name          text;
    v_fiscal_code   text;
    v_address       text;
    v_stamp         integer := 0;
    v_causale       text;
    v_receipt_id    uuid;
BEGIN
    SELECT * INTO v_tx FROM public.transactions WHERE id = p_transaction_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_FOUND');
    END IF;

    IF v_tx.amount_cents <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AN_INCOME');
    END IF;

    IF v_tx.status <> 'paid' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_PAID');
    END IF;

    IF EXISTS (SELECT 1 FROM public.receipts WHERE transaction_id = p_transaction_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'RECEIPT_ALREADY_ISSUED');
    END IF;

    SELECT * INTO v_settings FROM public.association_settings WHERE id = true;

    -- Dati di chi riceve: prima la domanda con cui è entratə nel libro soci; se non è ancora sociə
    -- (la quota si paga prima della delibera), la sua domanda più recente ancora valida.
    SELECT COALESCE(c.full_name, btrim(a.first_name || ' ' || a.last_name)),
           a.fiscal_code,
           NULLIF(concat_ws(', ',
               NULLIF(btrim(a.address_street), ''),
               NULLIF(btrim(concat_ws(' ',
                   NULLIF(btrim(a.address_zip), ''),
                   NULLIF(btrim(a.address_city), ''),
                   CASE WHEN NULLIF(btrim(a.address_province), '') IS NOT NULL
                        THEN '(' || btrim(a.address_province) || ')' END)), '')
           ), '')
      INTO v_name, v_fiscal_code, v_address
      FROM public.clients c
      LEFT JOIN public.members m ON m.client_id = c.id
      LEFT JOIN LATERAL (
          SELECT ap.*
            FROM public.member_applications ap
           WHERE ap.id = m.application_id
              OR (m.application_id IS NULL
                  AND ap.client_id = c.id
                  AND ap.status IN ('pending', 'approved'))
           ORDER BY (ap.id = m.application_id) DESC NULLS LAST, ap.submitted_at DESC
           LIMIT 1
      ) a ON true
     WHERE c.id = v_tx.client_id;

    -- Nessuna scheda cliente (donazione dal sito): i dati che ha scritto chi ha pagato
    IF v_name IS NULL AND jsonb_typeof(v_tx.metadata->'payer') = 'object' THEN
        v_name        := NULLIF(btrim(v_tx.metadata->'payer'->>'name'), '');
        v_fiscal_code := NULLIF(upper(btrim(COALESCE(v_tx.metadata->'payer'->>'fiscal_code', ''))), '');
        v_address     := NULLIF(btrim(COALESCE(v_tx.metadata->'payer'->>'address', '')), '');
    END IF;

    IF v_name IS NULL THEN
        v_name := COALESCE(v_tx.description, 'Non indicato');
    END IF;

    v_year := EXTRACT(YEAR FROM v_tx.occurred_on)::integer;
    v_number := "internal"."next_receipt_number"(v_year);
    v_full_number := COALESCE(NULLIF(v_settings.receipt_prefix, ''), '') || v_number::text || '/' || v_year::text;

    IF v_settings.stamp_duty_threshold_cents > 0
       AND v_tx.amount_cents > v_settings.stamp_duty_threshold_cents THEN
        v_stamp := v_settings.stamp_duty_cents;
    END IF;

    v_causale := COALESCE(NULLIF(btrim(COALESCE(p_causale, '')), ''), CASE v_tx.kind
        WHEN 'membership_fee' THEN 'Quota associativa'
        WHEN 'subscription'   THEN 'Contributo per attività associative'
        WHEN 'event'          THEN 'Contributo per evento o laboratorio'
        WHEN 'trial'          THEN 'Lezione di prova'
        WHEN 'donation'       THEN 'Erogazione liberale'
        WHEN 'commercial'     THEN 'Corrispettivo'
        ELSE 'Contributo'
    END);

    INSERT INTO public.receipts (
        transaction_id, year, number, full_number,
        recipient_name, recipient_fiscal_code, recipient_address,
        issuer_snapshot, causale, amount_cents, stamp_duty_cents, created_by
    ) VALUES (
        p_transaction_id, v_year, v_number, v_full_number,
        v_name, v_fiscal_code, v_address,
        jsonb_build_object(
            'legal_name', v_settings.legal_name,
            'short_legal_name', v_settings.short_legal_name,
            'fiscal_code', v_settings.fiscal_code,
            'vat_number', v_settings.vat_number,
            'address', v_settings.address_street || ', ' || v_settings.address_zip || ' '
                       || v_settings.address_city || ' (' || v_settings.address_province || ')',
            'pec', v_settings.pec,
            'email', v_settings.email,
            'footer', v_settings.receipt_footer
        ),
        v_causale, v_tx.amount_cents, v_stamp, p_created_by
    )
    RETURNING id INTO v_receipt_id;

    RETURN jsonb_build_object(
        'ok', true, 'reason', 'ISSUED',
        'receipt_id', v_receipt_id, 'full_number', v_full_number,
        'number', v_number, 'year', v_year, 'stamp_duty_cents', v_stamp
    );
END;
$$;

ALTER FUNCTION "internal"."issue_receipt_core"("uuid", "text", "uuid") OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."issue_receipt_core"("uuid", "text", "uuid") IS
    'Emette la ricevuta di un incasso, con numero progressivo per anno e i dati del momento congelati dentro. Senza controllo dei permessi: lo fanno `issue_receipt` (staff) e `stripe_apply_payment_state` (webhook).';

-- `issue_receipt` resta la stessa per chi la chiama: controlla lo staff e passa al core.
CREATE OR REPLACE FUNCTION "public"."issue_receipt"("p_transaction_id" "uuid", "p_causale" "text" DEFAULT NULL)
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    RETURN "internal"."issue_receipt_core"(p_transaction_id, p_causale, auth.uid());
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Rimborsi: un core condiviso, e gli incassi online solo da Stripe
-- ─────────────────────────────────────────────────────────────────────────────

-- Ricalcola lo stato di un incasso dai suoi rimborsi validi (quelli `void`, non riusciti, non contano)
-- e porta con sé la quota associativa: rimborsata se il rimborso è totale, di nuovo pagata se un
-- rimborso totale poi non è riuscito.
CREATE OR REPLACE FUNCTION "internal"."recompute_refund_status"(
    "p_transaction_id" "uuid",
    "p_reason" "text" DEFAULT NULL
) RETURNS "public"."transaction_status"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_tx        public.transactions%ROWTYPE;
    v_refunded  integer;
    v_status    public.transaction_status;
BEGIN
    SELECT * INTO v_tx FROM public.transactions WHERE id = p_transaction_id;
    IF NOT FOUND OR v_tx.status IN ('pending', 'void') THEN
        RETURN v_tx.status;
    END IF;

    SELECT COALESCE(SUM(-amount_cents), 0) INTO v_refunded
      FROM public.transactions
     WHERE refund_of_id = p_transaction_id AND status <> 'void';

    v_status := CASE
        WHEN v_refunded <= 0 THEN 'paid'
        WHEN v_refunded >= v_tx.amount_cents THEN 'refunded'
        ELSE 'partially_refunded'
    END::public.transaction_status;

    IF v_status IS DISTINCT FROM v_tx.status THEN
        UPDATE public.transactions SET status = v_status WHERE id = p_transaction_id;
    END IF;

    IF v_tx.member_fee_id IS NOT NULL THEN
        IF v_status = 'refunded' THEN
            UPDATE public.member_fees
               SET status = 'refunded', refunded_at = COALESCE(refunded_at, now()),
                   refund_reason = COALESCE(p_reason, refund_reason)
             WHERE id = v_tx.member_fee_id AND status <> 'refunded';
        ELSE
            UPDATE public.member_fees
               SET status = 'paid', refunded_at = NULL, refund_reason = NULL
             WHERE id = v_tx.member_fee_id AND status = 'refunded' AND transaction_id = p_transaction_id;
        END IF;
    END IF;

    RETURN v_status;
END;
$$;

ALTER FUNCTION "internal"."recompute_refund_status"("uuid", "text") OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."recompute_refund_status"("uuid", "text") IS
    'Stato di un incasso ricalcolato dai suoi rimborsi validi, con la quota associativa collegata.';

CREATE OR REPLACE FUNCTION "internal"."refund_transaction_core"(
    "p_transaction_id" "uuid",
    "p_amount_cents" integer,
    "p_reason" "text",
    "p_created_by" "uuid",
    "p_occurred_on" "date" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_tx        public.transactions%ROWTYPE;
    v_refund_id uuid;
    v_status    public.transaction_status;
BEGIN
    SELECT * INTO v_tx FROM public.transactions WHERE id = p_transaction_id FOR UPDATE;
    IF NOT FOUND OR v_tx.amount_cents <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_FOUND');
    END IF;

    INSERT INTO public.transactions (
        client_id, kind, amount_cents, currency, method, source, status, occurred_on,
        refund_of_id, description, note, created_by
    ) VALUES (
        v_tx.client_id, v_tx.kind, -p_amount_cents, v_tx.currency, v_tx.method, v_tx.source, 'paid',
        COALESCE(p_occurred_on, (now() AT TIME ZONE 'Europe/Rome')::date),
        p_transaction_id, 'Rimborso', p_reason, p_created_by
    )
    RETURNING id INTO v_refund_id;

    v_status := "internal"."recompute_refund_status"(p_transaction_id, p_reason);

    RETURN jsonb_build_object('ok', true, 'reason', 'REFUNDED',
                              'refund_transaction_id', v_refund_id, 'status', v_status);
END;
$$;

ALTER FUNCTION "internal"."refund_transaction_core"("uuid", integer, "text", "uuid", "date") OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."refund_transaction_core"("uuid", integer, "text", "uuid", "date") IS
    'Riga negativa collegata all''incasso e stati ricalcolati. Senza controlli di importo e permessi: li fa chi la chiama (lo staff dalle Finanze, o Stripe che racconta un rimborso già avvenuto).';

CREATE OR REPLACE FUNCTION "public"."staff_refund_transaction"(
    "p_transaction_id" "uuid",
    "p_amount_cents" integer,
    "p_reason" "text"
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_tx        public.transactions%ROWTYPE;
    v_refunded  integer;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    IF COALESCE(btrim(p_reason), '') = '' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'REASON_REQUIRED');
    END IF;

    SELECT * INTO v_tx FROM public.transactions WHERE id = p_transaction_id FOR UPDATE;
    IF NOT FOUND OR v_tx.amount_cents <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_FOUND');
    END IF;

    -- Un pagamento con carta si rimborsa sulla carta, da Stripe: registrarlo qui lascerebbe i soldi
    -- dove sono, oppure li restituirebbe due volte.
    IF v_tx.stripe_payment_id IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'USE_STRIPE_REFUND');
    END IF;

    SELECT COALESCE(SUM(-amount_cents), 0) INTO v_refunded
      FROM public.transactions WHERE refund_of_id = p_transaction_id AND status <> 'void';

    IF p_amount_cents IS NULL OR p_amount_cents <= 0
       OR p_amount_cents > (v_tx.amount_cents - v_refunded) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT',
                                  'refundable_cents', v_tx.amount_cents - v_refunded);
    END IF;

    RETURN "internal"."refund_transaction_core"(p_transaction_id, p_amount_cents, p_reason, auth.uid());
END;
$$;

COMMENT ON FUNCTION "public"."staff_refund_transaction"("uuid", integer, "text") IS
    'Rimborso totale o parziale di un incasso in studio, deciso caso per caso (D4): riga negativa collegata all''originale e stati aggiornati. Gli incassi online si rimborsano da Stripe (USE_STRIPE_REFUND).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Pagare la propria quota online
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."prepare_my_fee_payment"("p_year" integer DEFAULT NULL)
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_year      integer := COALESCE(p_year, EXTRACT(YEAR FROM (now() AT TIME ZONE 'Europe/Rome'))::integer);
    v_year_row  public.association_years%ROWTYPE;
    v_fee       public.member_fees%ROWTYPE;
    v_app       public.member_applications%ROWTYPE;
    v_member    public.members%ROWTYPE;
    v_email     text;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    IF NOT "internal"."payments_enabled"() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PAYMENTS_DISABLED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NO_APPLICATION');
    END IF;

    SELECT * INTO v_year_row FROM public.association_years WHERE year = v_year;
    IF NOT FOUND OR v_year_row.is_open = false THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'YEAR_NOT_OPEN');
    END IF;

    -- La quota la paga chi è sociə, oppure chi ha una domanda in attesa di delibera o appena accolta
    SELECT * INTO v_member FROM public.members WHERE client_id = v_client_id;
    SELECT * INTO v_app FROM public.member_applications
     WHERE client_id = v_client_id AND status IN ('pending', 'approved')
     ORDER BY submitted_at DESC LIMIT 1;

    IF NOT ((v_member.id IS NOT NULL AND v_member.status = 'active') OR v_app.id IS NOT NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NO_APPLICATION');
    END IF;

    -- L'importo lo delibera il Consiglio Direttivo (A8): finché non c'è, online non si paga
    IF v_year_row.fee_cents IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'FEE_AMOUNT_NOT_SET', 'year', v_year);
    END IF;
    IF v_year_row.fee_cents = 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOTHING_TO_PAY', 'year', v_year);
    END IF;

    SELECT * INTO v_fee FROM public.member_fees
     WHERE client_id = v_client_id AND year = v_year
       FOR UPDATE;

    IF FOUND THEN
        IF v_fee.status = 'paid' THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'FEE_ALREADY_PAID', 'year', v_year);
        END IF;
        IF v_fee.status = 'waived' THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'FEE_WAIVED', 'year', v_year);
        END IF;
        -- `due`, oppure `refunded` (domanda respinta e poi ripresentata): l'importo è quello deliberato
        UPDATE public.member_fees SET amount_cents = v_year_row.fee_cents
         WHERE id = v_fee.id AND amount_cents IS DISTINCT FROM v_year_row.fee_cents;
    ELSE
        INSERT INTO public.member_fees (client_id, year, amount_cents, status)
        VALUES (v_client_id, v_year, v_year_row.fee_cents, 'due')
        RETURNING * INTO v_fee;
    END IF;

    SELECT COALESCE(NULLIF(btrim(v_app.email), ''), NULLIF(btrim(c.email), ''), p.email)
      INTO v_email
      FROM public.clients c
      LEFT JOIN public.profiles p ON p.id = auth.uid()
     WHERE c.id = v_client_id;

    RETURN jsonb_build_object(
        'ok', true,
        'member_fee_id', v_fee.id,
        'client_id', v_client_id,
        'year', v_year,
        'amount_cents', v_year_row.fee_cents,
        'email', v_email
    );
END;
$$;

ALTER FUNCTION "public"."prepare_my_fee_payment"(integer) OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."prepare_my_fee_payment"(integer) TO "authenticated";
COMMENT ON FUNCTION "public"."prepare_my_fee_payment"(integer) IS
    'Prima di aprire il checkout della propria quota: controlla che i pagamenti siano accesi, che ci sia una domanda o l''iscrizione, che l''importo sia deliberato e che la quota non sia già pagata o esonerata. Crea la riga della quota se manca. L''importo lo decide il database, mai chi paga.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Lo stato di un pagamento Stripe, riportato nel database
-- ─────────────────────────────────────────────────────────────────────────────
--
-- `p_payload`, costruito dall'edge function con quello che Stripe dice ADESSO:
--   {
--     "stripe_payment_id": "<id della nostra riga, dai metadata>",       (facoltativo)
--     "checkout_session_id": "cs_…",                                     (facoltativo)
--     "payment_intent": {
--        "id", "status", "amount_received", "currency", "livemode",
--        "payment_method_type", "receipt_email", "last_payment_error",
--        "charge": { "created": <unix>, "fee_cents", "net_cents" } | null
--     },
--     "refunds": [ { "id", "amount", "status", "created": <unix>,
--                    "reason", "metadata": { "reason", "created_by" } } ]
--   }

CREATE OR REPLACE FUNCTION "public"."stripe_apply_payment_state"("p_payload" "jsonb")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_pi            jsonb := COALESCE(p_payload->'payment_intent', '{}'::jsonb);
    v_pi_id         text  := NULLIF(v_pi->>'id', '');
    v_pi_status     text  := v_pi->>'status';
    v_charge        jsonb := CASE WHEN jsonb_typeof(v_pi->'charge') = 'object' THEN v_pi->'charge' END;
    v_session_id    text  := NULLIF(p_payload->>'checkout_session_id', '');
    v_sp_ref        text  := NULLIF(p_payload->>'stripe_payment_id', '');
    v_livemode      boolean := COALESCE((v_pi->>'livemode')::boolean, false);
    v_sp            public.stripe_payments%ROWTYPE;
    v_ledger        boolean;
    v_expected      integer;
    v_amount        integer;
    v_currency      text;
    v_paid_at       timestamptz;
    v_tx_id         uuid;
    v_kind          public.transaction_kind;
    v_fee           public.member_fees%ROWTYPE;
    v_link_fee      boolean := false;
    v_duplicate     boolean := false;
    v_year          text;
    v_description   text;
    v_causale       text;
    v_receipt       jsonb;
    v_refund        jsonb;
    v_existing      public.stripe_refunds%ROWTYPE;
    v_r_id          text;
    v_r_status      text;
    v_r_amount      integer;
    v_r_reason      text;
    v_r_by          uuid;
    v_r_on          date;
    v_r_result      jsonb;
    v_r_tx          uuid;
    v_tx_status     public.transaction_status;
    v_receipt_ids   uuid[];
BEGIN
    IF v_pi_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MISSING_PAYMENT_INTENT');
    END IF;

    -- 1. La nostra riga, bloccata: tutte le consegne che riguardano questo pagamento passano di qui una
    --    alla volta.
    IF v_sp_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        SELECT * INTO v_sp FROM public.stripe_payments WHERE id = v_sp_ref::uuid FOR UPDATE;
    END IF;
    IF v_sp.id IS NULL THEN
        SELECT * INTO v_sp FROM public.stripe_payments WHERE payment_intent_id = v_pi_id FOR UPDATE;
    END IF;
    IF v_sp.id IS NULL AND v_session_id IS NOT NULL THEN
        SELECT * INTO v_sp FROM public.stripe_payments WHERE checkout_session_id = v_session_id FOR UPDATE;
    END IF;
    IF v_sp.id IS NULL THEN
        -- Un pagamento che non abbiamo aperto noi (link di pagamento, dashboard): il denaro è arrivato
        -- lo stesso, quindi si registra, come "altro", per chi controlla le Finanze.
        INSERT INTO public.stripe_payments (
            payment_intent_id, checkout_session_id, purpose, amount_cents, currency, livemode,
            status, source, metadata
        ) VALUES (
            v_pi_id, v_session_id, 'other',
            GREATEST(COALESCE((v_pi->>'amount_received')::integer, (v_pi->>'amount')::integer, 1), 1),
            upper(COALESCE(v_pi->>'currency', 'eur')), v_livemode, 'created', 'site',
            jsonb_build_object('unmatched', true)
        )
        RETURNING * INTO v_sp;
    END IF;

    IF v_sp.payment_intent_id IS NOT NULL AND v_sp.payment_intent_id <> v_pi_id THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PAYMENT_INTENT_MISMATCH');
    END IF;

    v_ledger   := "internal"."stripe_ledger_allowed"(v_livemode);
    v_expected := v_sp.amount_cents;
    v_amount   := COALESCE((v_pi->>'amount_received')::integer, 0);
    v_currency := upper(COALESCE(NULLIF(v_pi->>'currency', ''), v_sp.currency, 'EUR'));
    v_paid_at  := CASE WHEN v_charge ? 'created'
                       THEN to_timestamp((v_charge->>'created')::bigint) END;

    -- 2. Il pagamento
    IF v_pi_status = 'succeeded' THEN
        v_paid_at := COALESCE(v_sp.succeeded_at, v_paid_at, now());

        UPDATE public.stripe_payments SET
            payment_intent_id   = v_pi_id,
            checkout_session_id = COALESCE(checkout_session_id, v_session_id),
            amount_cents        = CASE WHEN v_amount > 0 THEN v_amount ELSE amount_cents END,
            currency            = v_currency,
            livemode            = v_livemode,
            payment_method_type = COALESCE(NULLIF(v_pi->>'payment_method_type', ''), payment_method_type),
            receipt_email       = COALESCE(NULLIF(v_pi->>'receipt_email', ''), receipt_email),
            fee_cents           = COALESCE((v_charge->>'fee_cents')::integer, fee_cents),
            net_cents           = COALESCE((v_charge->>'net_cents')::integer, net_cents),
            succeeded_at        = v_paid_at,
            failure_message     = NULL,
            status              = CASE WHEN status IN ('refunded', 'partially_refunded') THEN status
                                       ELSE 'succeeded' END,
            metadata            = CASE WHEN v_amount > 0 AND v_amount <> v_expected
                                       THEN metadata || jsonb_build_object('amount_expected_cents', v_expected)
                                       ELSE metadata END
         WHERE id = v_sp.id
        RETURNING * INTO v_sp;

        -- L'incasso, una volta sola e solo se il pagamento può scrivere nel registro
        IF v_ledger AND v_sp.transaction_id IS NULL THEN
            v_kind := CASE v_sp.purpose
                WHEN 'membership_fee' THEN 'membership_fee'
                WHEN 'subscription'   THEN 'subscription'
                WHEN 'event'          THEN 'event'
                WHEN 'donation'       THEN 'donation'
                ELSE 'other'
            END::public.transaction_kind;

            IF v_sp.purpose = 'membership_fee' THEN
                SELECT * INTO v_fee FROM public.member_fees WHERE id = v_sp.target_id FOR UPDATE;
                IF FOUND AND v_fee.status IN ('due', 'refunded') THEN
                    v_link_fee := true;
                ELSE
                    -- Già pagata (in studio, o con un altro checkout) o esonerata: il denaro va
                    -- registrato comunque, e restituito
                    v_duplicate := true;
                END IF;
                v_year := COALESCE(v_fee.year::text, v_sp.metadata->>'year');
            END IF;

            v_description := CASE v_sp.purpose
                WHEN 'membership_fee' THEN 'Quota associativa' || COALESCE(' ' || v_year, '')
                WHEN 'donation'       THEN 'Donazione'
                ELSE COALESCE(NULLIF(v_sp.metadata->>'description', ''), 'Pagamento online')
            END;

            INSERT INTO public.transactions (
                client_id, kind, amount_cents, currency, method, source, status, occurred_on,
                member_fee_id, stripe_payment_id, description, metadata
            ) VALUES (
                v_sp.client_id, v_kind, v_sp.amount_cents, v_currency, 'stripe',
                COALESCE(v_sp.source, 'site'), 'paid',
                -- La data è quella dell'addebito in Italia: un pagamento del 31/12 riconsegnato dal
                -- webhook il 2/1 resta nell'anno (e nella numerazione) giusto
                (v_paid_at AT TIME ZONE 'Europe/Rome')::date,
                CASE WHEN v_link_fee THEN v_fee.id END,
                v_sp.id, v_description,
                jsonb_strip_nulls(jsonb_build_object(
                    'payer', v_sp.metadata->'payer',
                    'duplicate', CASE WHEN v_duplicate THEN true END,
                    'amount_expected_cents', v_sp.metadata->'amount_expected_cents'
                ))
            )
            RETURNING id INTO v_tx_id;

            IF v_link_fee THEN
                UPDATE public.member_fees
                   SET status = 'paid', paid_at = v_paid_at, transaction_id = v_tx_id,
                       amount_cents = v_sp.amount_cents, refunded_at = NULL, refund_reason = NULL
                 WHERE id = v_fee.id;
            END IF;

            UPDATE public.stripe_payments
               SET transaction_id = v_tx_id, is_duplicate = v_duplicate
             WHERE id = v_sp.id
            RETURNING * INTO v_sp;

            -- Ricevuta, tranne per i doppioni: niente numero bruciato su soldi da restituire
            IF NOT v_duplicate THEN
                v_causale := CASE v_sp.purpose
                    WHEN 'membership_fee' THEN 'Quota associativa' || COALESCE(' ' || v_year, '')
                    WHEN 'donation'       THEN 'Erogazione liberale'
                    ELSE NULL
                END;
                v_receipt := "internal"."issue_receipt_core"(v_tx_id, v_causale, NULL);
                IF COALESCE((v_receipt->>'ok')::boolean, false) = false THEN
                    RAISE EXCEPTION 'Ricevuta non emessa per il pagamento %: %', v_sp.id, v_receipt->>'reason';
                END IF;
            END IF;
        END IF;

    ELSIF v_sp.status NOT IN ('succeeded', 'refunded', 'partially_refunded') THEN
        -- Non ancora riuscito: solo lo stato, il registro non si tocca
        UPDATE public.stripe_payments SET
            payment_intent_id = COALESCE(payment_intent_id, v_pi_id),
            livemode          = v_livemode,
            status            = CASE
                WHEN v_pi_status = 'processing' THEN 'processing'
                WHEN v_pi_status = 'canceled' THEN 'canceled'
                WHEN v_pi_status = 'requires_payment_method' AND NULLIF(v_pi->>'last_payment_error', '') IS NOT NULL
                    THEN 'failed'
                ELSE status
            END::public.stripe_payment_status,
            failure_message   = COALESCE(NULLIF(v_pi->>'last_payment_error', ''), failure_message)
         WHERE id = v_sp.id
        RETURNING * INTO v_sp;
    END IF;

    -- 3. I rimborsi: solo per un incasso già nel registro
    IF v_sp.transaction_id IS NOT NULL AND jsonb_typeof(p_payload->'refunds') = 'array' THEN
        FOR v_refund IN SELECT value FROM jsonb_array_elements(p_payload->'refunds') LOOP
            v_r_id     := NULLIF(v_refund->>'id', '');
            v_r_status := COALESCE(NULLIF(v_refund->>'status', ''), 'succeeded');
            v_r_amount := (v_refund->>'amount')::integer;
            CONTINUE WHEN v_r_id IS NULL OR COALESCE(v_r_amount, 0) <= 0;

            v_r_reason := COALESCE(
                NULLIF(btrim(v_refund->'metadata'->>'reason'), ''),
                'Rimborso da dashboard Stripe' || COALESCE(' (' || NULLIF(v_refund->>'reason', '') || ')', '')
            );
            v_r_by := NULL;
            IF (v_refund->'metadata'->>'created_by') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
                SELECT id INTO v_r_by FROM public.profiles WHERE id = (v_refund->'metadata'->>'created_by')::uuid;
            END IF;
            v_r_on := CASE WHEN v_refund ? 'created'
                           THEN (to_timestamp((v_refund->>'created')::bigint) AT TIME ZONE 'Europe/Rome')::date END;

            SELECT * INTO v_existing FROM public.stripe_refunds WHERE refund_id = v_r_id FOR UPDATE;

            IF NOT FOUND THEN
                v_r_tx := NULL;
                IF v_r_status IN ('pending', 'succeeded', 'requires_action') THEN
                    v_r_result := "internal"."refund_transaction_core"(
                        v_sp.transaction_id, v_r_amount, v_r_reason, v_r_by, v_r_on);
                    v_r_tx := (v_r_result->>'refund_transaction_id')::uuid;
                END IF;
                INSERT INTO public.stripe_refunds (
                    refund_id, stripe_payment_id, amount_cents, reason, status, transaction_id, created_by
                ) VALUES (
                    v_r_id, v_sp.id, v_r_amount, v_r_reason, v_r_status, v_r_tx, v_r_by
                );
            ELSIF v_existing.status IS DISTINCT FROM v_r_status THEN
                UPDATE public.stripe_refunds SET status = v_r_status WHERE id = v_existing.id;

                IF v_r_status IN ('failed', 'canceled') AND v_existing.transaction_id IS NOT NULL THEN
                    -- Il rimborso non è andato a buon fine: il denaro non è uscito, la riga si annulla
                    UPDATE public.transactions
                       SET status = 'void',
                           note = concat_ws(' — ', note, 'rimborso Stripe non riuscito')
                     WHERE id = v_existing.transaction_id AND status <> 'void';
                    PERFORM "internal"."recompute_refund_status"(v_sp.transaction_id, NULL);
                ELSIF v_r_status IN ('pending', 'succeeded', 'requires_action')
                      AND v_existing.transaction_id IS NULL THEN
                    v_r_result := "internal"."refund_transaction_core"(
                        v_sp.transaction_id, v_existing.amount_cents, v_existing.reason, v_existing.created_by, v_r_on);
                    UPDATE public.stripe_refunds
                       SET transaction_id = (v_r_result->>'refund_transaction_id')::uuid
                     WHERE id = v_existing.id;
                END IF;
            END IF;
        END LOOP;

        -- Lo stato del pagamento segue quello dell'incasso
        SELECT status INTO v_tx_status FROM public.transactions WHERE id = v_sp.transaction_id;
        UPDATE public.stripe_payments
           SET status = CASE v_tx_status
                   WHEN 'refunded' THEN 'refunded'
                   WHEN 'partially_refunded' THEN 'partially_refunded'
                   ELSE 'succeeded'
               END::public.stripe_payment_status
         WHERE id = v_sp.id AND status IN ('succeeded', 'refunded', 'partially_refunded')
        RETURNING * INTO v_sp;
    END IF;

    -- 4. Le ricevute ancora da mandare per email
    SELECT COALESCE(array_agg(r.id), '{}') INTO v_receipt_ids
      FROM public.receipts r
     WHERE v_sp.transaction_id IS NOT NULL
       AND r.transaction_id = v_sp.transaction_id
       AND r.sent_at IS NULL AND r.voided_at IS NULL;

    RETURN jsonb_build_object(
        'ok', true,
        'stripe_payment_id', v_sp.id,
        'status', v_sp.status,
        'transaction_id', v_sp.transaction_id,
        'is_duplicate', v_sp.is_duplicate,
        'ledger', v_ledger,
        'receipt_ids', to_jsonb(v_receipt_ids)
    );
END;
$$;

ALTER FUNCTION "public"."stripe_apply_payment_state"("jsonb") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."stripe_apply_payment_state"("jsonb") IS
    'Riporta nel database lo stato di un pagamento come lo dice Stripe in questo momento: incasso, quota, ricevuta, commissione e rimborsi. Idempotente e serializzata sulla riga del pagamento. Solo per le edge function (service_role): nessun GRANT alle app.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Funzioni di servizio del webhook e dell'invio email (solo service_role)
-- ─────────────────────────────────────────────────────────────────────────────

-- Sessione di Checkout scaduta senza pagamento. Per le donazioni i dati di chi voleva donare non
-- servono più: si cancellano.
CREATE OR REPLACE FUNCTION "public"."stripe_checkout_expired"("p_checkout_session_id" "text")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_id uuid;
BEGIN
    UPDATE public.stripe_payments
       SET status = 'canceled',
           metadata = CASE WHEN purpose = 'donation'
                           THEN (metadata - 'payer') || jsonb_build_object('payer_removed', true)
                           ELSE metadata END,
           receipt_email = CASE WHEN purpose = 'donation' THEN NULL ELSE receipt_email END
     WHERE checkout_session_id = p_checkout_session_id
       AND status IN ('created', 'failed')
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('ok', true, 'stripe_payment_id', v_id, 'changed', v_id IS NOT NULL);
END;
$$;

ALTER FUNCTION "public"."stripe_checkout_expired"("text") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."stripe_checkout_expired"("text") IS
    'Sessione di Checkout scaduta senza pagamento: la riga diventa annullata e, per le donazioni, i dati del donatore si cancellano. Solo service_role.';

-- Memoria del webhook: registra l'evento (o conta un nuovo tentativo) e dice se era già elaborato.
-- Si salva solo l'essenziale, niente dati personali.
CREATE OR REPLACE FUNCTION "public"."stripe_event_received"(
    "p_event_id" "text",
    "p_type" "text",
    "p_livemode" boolean,
    "p_object_id" "text"
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_processed timestamptz;
BEGIN
    INSERT INTO public.stripe_events (id, type, payload, livemode, attempts)
    VALUES (p_event_id, p_type, jsonb_build_object('object_id', p_object_id), COALESCE(p_livemode, false), 1)
    ON CONFLICT (id) DO UPDATE SET attempts = public.stripe_events.attempts + 1
    RETURNING processed_at INTO v_processed;

    RETURN jsonb_build_object('ok', true, 'already_processed', v_processed IS NOT NULL);
END;
$$;

ALTER FUNCTION "public"."stripe_event_received"("text", "text", boolean, "text") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."stripe_event_received"("text", "text", boolean, "text") IS
    'Il webhook registra un evento di Stripe (o un nuovo tentativo dello stesso) e scopre se è già stato elaborato. Solo service_role.';

CREATE OR REPLACE FUNCTION "public"."stripe_event_done"("p_event_id" "text", "p_error" "text" DEFAULT NULL)
    RETURNS "void"
    LANGUAGE "sql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    UPDATE public.stripe_events
       SET processed_at  = CASE WHEN p_error IS NULL THEN COALESCE(processed_at, now()) ELSE processed_at END,
           error_message = p_error
     WHERE id = p_event_id;
$$;

ALTER FUNCTION "public"."stripe_event_done"("text", "text") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."stripe_event_done"("text", "text") IS
    'Esito dell''elaborazione di un evento di Stripe: elaborato, oppure l''errore (e Stripe riproverà). Solo service_role.';

-- Limite orario ai checkout per impronta dell'IP. Registra il tentativo e dice se è ammesso.
CREATE OR REPLACE FUNCTION "public"."stripe_register_checkout_attempt"(
    "p_ip_hash" "text",
    "p_purpose" "public"."stripe_purpose",
    "p_limit" integer DEFAULT 10,
    "p_window_minutes" integer DEFAULT 60
) RETURNS boolean
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_count integer;
BEGIN
    DELETE FROM public.stripe_checkout_attempts WHERE created_at < now() - INTERVAL '1 day';

    SELECT count(*) INTO v_count
      FROM public.stripe_checkout_attempts
     WHERE ip_hash = p_ip_hash AND purpose = p_purpose
       AND created_at > now() - make_interval(mins => p_window_minutes);

    IF v_count >= p_limit THEN
        RETURN false;
    END IF;

    INSERT INTO public.stripe_checkout_attempts (ip_hash, purpose) VALUES (p_ip_hash, p_purpose);
    RETURN true;
END;
$$;

ALTER FUNCTION "public"."stripe_register_checkout_attempt"("text", "public"."stripe_purpose", integer, integer) OWNER TO "postgres";
COMMENT ON FUNCTION "public"."stripe_register_checkout_attempt"("text", "public"."stripe_purpose", integer, integer) IS
    'Limite orario ai checkout per impronta dell''IP (contro chi prova carte rubate sul modulo delle donazioni). Solo service_role.';

-- Invio della ricevuta per email: prima si "prenota", poi si registra l'esito. La prenotazione scade
-- dopo due minuti, così un invio interrotto a metà non blocca quelli dopo.
CREATE OR REPLACE FUNCTION "public"."receipt_claim_send"("p_receipt_id" "uuid", "p_resend" boolean DEFAULT false)
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_receipt public.receipts%ROWTYPE;
BEGIN
    SELECT * INTO v_receipt FROM public.receipts WHERE id = p_receipt_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'RECEIPT_NOT_FOUND');
    END IF;
    IF v_receipt.voided_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'RECEIPT_VOIDED');
    END IF;
    IF v_receipt.sent_at IS NOT NULL AND NOT p_resend THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_SENT');
    END IF;
    IF v_receipt.send_claimed_at IS NOT NULL AND v_receipt.send_claimed_at > now() - INTERVAL '2 minutes' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'SEND_IN_PROGRESS');
    END IF;

    UPDATE public.receipts SET send_claimed_at = now() WHERE id = p_receipt_id;
    RETURN jsonb_build_object('ok', true);
END;
$$;

ALTER FUNCTION "public"."receipt_claim_send"("uuid", boolean) OWNER TO "postgres";
COMMENT ON FUNCTION "public"."receipt_claim_send"("uuid", boolean) IS
    'Prenota l''invio di una ricevuta per email: due consegne dello stesso evento non mandano due email. Solo service_role.';

CREATE OR REPLACE FUNCTION "public"."receipt_mark_sent"("p_receipt_id" "uuid", "p_to" "text", "p_error" "text" DEFAULT NULL)
    RETURNS "void"
    LANGUAGE "sql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    UPDATE public.receipts
       SET sent_at         = CASE WHEN p_error IS NULL THEN now() ELSE sent_at END,
           sent_to         = CASE WHEN p_error IS NULL THEN p_to ELSE sent_to END,
           send_error      = p_error,
           send_claimed_at = NULL
     WHERE id = p_receipt_id;
$$;

ALTER FUNCTION "public"."receipt_mark_sent"("uuid", "text", "text") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."receipt_mark_sent"("uuid", "text", "text") IS
    'Esito dell''invio di una ricevuta per email. Solo service_role.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Rimborso di un incasso online, dal gestionale
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_prepare_stripe_refund"(
    "p_transaction_id" "uuid",
    "p_amount_cents" integer
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_tx        public.transactions%ROWTYPE;
    v_sp        public.stripe_payments%ROWTYPE;
    v_refunded  integer;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    SELECT * INTO v_tx FROM public.transactions WHERE id = p_transaction_id;
    IF NOT FOUND OR v_tx.amount_cents <= 0 OR v_tx.refund_of_id IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_FOUND');
    END IF;

    SELECT * INTO v_sp FROM public.stripe_payments WHERE id = v_tx.stripe_payment_id;
    IF NOT FOUND OR v_sp.payment_intent_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_A_STRIPE_PAYMENT');
    END IF;

    IF v_tx.status NOT IN ('paid', 'partially_refunded') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_REFUNDABLE', 'status', v_tx.status);
    END IF;

    SELECT COALESCE(SUM(-amount_cents), 0) INTO v_refunded
      FROM public.transactions WHERE refund_of_id = p_transaction_id AND status <> 'void';

    IF p_amount_cents IS NULL OR p_amount_cents <= 0
       OR p_amount_cents > (v_tx.amount_cents - v_refunded) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT',
                                  'refundable_cents', v_tx.amount_cents - v_refunded);
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'payment_intent_id', v_sp.payment_intent_id,
        'stripe_payment_id', v_sp.id,
        'livemode', v_sp.livemode,
        'refundable_cents', v_tx.amount_cents - v_refunded
    );
END;
$$;

ALTER FUNCTION "public"."staff_prepare_stripe_refund"("uuid", integer) OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_prepare_stripe_refund"("uuid", integer) TO "authenticated";
COMMENT ON FUNCTION "public"."staff_prepare_stripe_refund"("uuid", integer) IS
    'Prima di rimborsare sulla carta un incasso online: solo Finanze, importo entro il rimborsabile. Il rimborso vero lo fa l''edge function `stripe-refund` e lo registra `stripe_apply_payment_state`.';
