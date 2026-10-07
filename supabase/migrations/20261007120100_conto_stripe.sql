-- Migration 20261007120100: Stripe è un conto, gli accrediti sono giroconti (contract v0.3.15)
--
-- Fino a qui (sessione 7) un pagamento con carta contava «in banca» dal giorno del pagamento. Ma i
-- soldi restano sul saldo di Stripe finché Stripe non li accredita sul conto, raggruppando più
-- pagamenti e già tolte le commissioni: «In banca» nel gestionale non coincideva con l'estratto conto
-- (07/10/2026: 867,10 € in banca nel gestionale, di cui 891,50 € ancora su Stripe).
--
-- Ora i conti sono tre:
--   cassa   contanti
--   banca   conto corrente: deve coincidere con l'estratto conto
--   stripe  pagamenti con carta incassati e non ancora accreditati: deve coincidere con il saldo di
--           Stripe (disponibile + in arrivo) più gli accrediti partiti e non ancora arrivati
--
--   - `internal.cash_account_for`: il metodo `stripe` va sul conto Stripe. Lo usano
--     `finance_income_lines` e `finance_account_balances`; le commissioni (`expenses.source =
--     'stripe_fee'`) hanno già `payment_method = 'stripe'` e quindi escono da Stripe.
--   - Un accredito di Stripe sul conto è un giroconto Stripe → banca (`account_transfers` con
--     `stripe_payout_id`), con la data di arrivo in banca. Lo scrive solo
--     `stripe_apply_payout_state`, chiamata dal webhook (eventi `payout.*`) e dall'edge function
--     `stripe-reconcile`, che rilegge gli accrediti da Stripe quando si apre Cassa e banca. Un
--     accredito fallito o annullato toglie il giroconto: i soldi sono tornati su Stripe.
--   - Dall'interfaccia non si scrive a mano un giroconto che tocca Stripe, né si cambia o cancella un
--     accredito automatico (`AUTOMATIC_TRANSFER`): finirebbe contato due volte.
--   - `finance_account_balances` restituisce anche `stripe_cents`, e `total_cents` lo comprende.
--     `bank_cents` cambia significato: ora è solo il conto corrente.
--
-- Il rendiconto (Modello D) non cambia: il saldo di Stripe a fine anno sta nei «Depositi bancari e
-- postali» insieme alla banca, come si fa di solito per i conti di pagamento (PayPal, Stripe). Lo
-- somma il gestionale.
--
-- Compatibilità: colonna nuova facoltativa, un campo in più nella risposta di
-- `finance_account_balances`, una funzione nuova solo service_role. Il gestionale di prima mostra
-- in banca solo il conto corrente e non vede i movimenti di Stripe nella prima nota finché non si
-- aggiorna (stesso rilascio).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Il conto di un metodo di pagamento
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."cash_account_for"("p_method" "public"."payment_method")
    RETURNS "public"."cash_account"
    LANGUAGE "sql"
    IMMUTABLE
    AS $$
    SELECT CASE p_method
               WHEN 'cash'   THEN 'cash'
               WHEN 'stripe' THEN 'stripe'
               ELSE 'bank'
           END::public.cash_account;
$$;

ALTER FUNCTION "internal"."cash_account_for"("public"."payment_method") OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."cash_account_for"("public"."payment_method") IS
    'Il conto su cui arriva o da cui esce il denaro: contanti → cassa, Stripe → conto Stripe (fino all''accredito), tutto il resto → banca.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Gli accrediti di Stripe sono giroconti
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."account_transfers"
    ADD COLUMN IF NOT EXISTS "stripe_payout_id" "text";

COMMENT ON COLUMN "public"."account_transfers"."stripe_payout_id" IS
    'L''accredito di Stripe (po_…) da cui nasce il giroconto Stripe → banca. Lo scrive solo stripe_apply_payout_state.';

CREATE UNIQUE INDEX IF NOT EXISTS "account_transfers_stripe_payout_id_key"
    ON "public"."account_transfers" ("stripe_payout_id")
    WHERE "stripe_payout_id" IS NOT NULL;

-- Un giroconto tocca il conto Stripe se e solo se è un accredito di Stripe
-- migration-lint:allow drop-constraint — reason: il vincolo nasce in questa migrazione; il DROP IF EXISTS serve solo a poterla rilanciare, e le righe che esistono (tutte fra cassa e banca, senza accredito) lo rispettano
ALTER TABLE "public"."account_transfers" DROP CONSTRAINT IF EXISTS "account_transfers_stripe_only_payouts";
ALTER TABLE "public"."account_transfers"
    ADD CONSTRAINT "account_transfers_stripe_only_payouts" CHECK (
        ("stripe_payout_id" IS NOT NULL) = ("from_account" = 'stripe' OR "to_account" = 'stripe')
    );

COMMENT ON TABLE "public"."account_transfers" IS
    'Giroconti fra i conti (i contanti versati sul conto, un prelievo, gli accrediti di Stripe sul conto). Non sono né entrate né uscite: spostano denaro fra conti che nel rendiconto stanno in «Cassa e banca».';

-- SECURITY INVOKER di proposito, come `internal.expenses_before_write`: `current_user` distingue chi
-- scrive dall'API (authenticated) dalle funzioni (postgres) e dalle edge function (service_role).
CREATE OR REPLACE FUNCTION "internal"."account_transfers_before_write"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF current_user NOT IN ('authenticated', 'anon') THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.stripe_payout_id IS NOT NULL THEN
        IF TG_OP = 'DELETE' OR (
               NEW.occurred_on      IS DISTINCT FROM OLD.occurred_on
            OR NEW.from_account     IS DISTINCT FROM OLD.from_account
            OR NEW.to_account       IS DISTINCT FROM OLD.to_account
            OR NEW.amount_cents     IS DISTINCT FROM OLD.amount_cents
            OR NEW.stripe_payout_id IS DISTINCT FROM OLD.stripe_payout_id
        ) THEN
            RAISE EXCEPTION 'AUTOMATIC_TRANSFER'
                USING ERRCODE = 'P0001',
                      DETAIL = 'Gli accrediti di Stripe si registrano da soli: importo e data li dà Stripe.';
        END IF;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE')
       AND (NEW.stripe_payout_id IS NOT NULL OR 'stripe' IN (NEW.from_account, NEW.to_account))
       AND (TG_OP = 'INSERT' OR OLD.stripe_payout_id IS NULL) THEN
        RAISE EXCEPTION 'AUTOMATIC_TRANSFER'
            USING ERRCODE = 'P0001',
                  DETAIL = 'I movimenti del conto Stripe si registrano da soli: i giroconti a mano sono fra cassa e banca.';
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

ALTER FUNCTION "internal"."account_transfers_before_write"() OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."account_transfers_before_write"() IS
    'Dall''API non si scrive un giroconto che tocca il conto Stripe e non si cambia né cancella un accredito di Stripe (si può solo cambiarne la nota).';

DROP TRIGGER IF EXISTS "account_transfers_before_write" ON "public"."account_transfers";
CREATE TRIGGER "account_transfers_before_write"
    BEFORE INSERT OR UPDATE OR DELETE ON "public"."account_transfers"
    FOR EACH ROW EXECUTE FUNCTION "internal"."account_transfers_before_write"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Lo stato di un accredito, riletto da Stripe
-- ─────────────────────────────────────────────────────────────────────────────
--
-- p_payout: { id, status, amount, currency, arrival_date (unix), livemode }, come lo dà Stripe.
-- Idempotente: si può chiamare quante volte si vuole con lo stesso accredito. Risponde
-- { ok, action: recorded | updated | unchanged | removed | waiting | ignored, transfer_id? }.

CREATE OR REPLACE FUNCTION "public"."stripe_apply_payout_state"("p_payout" "jsonb")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_id        text    := p_payout->>'id';
    v_status    text    := p_payout->>'status';
    v_currency  text    := lower(COALESCE(p_payout->>'currency', ''));
    v_livemode  boolean := COALESCE((p_payout->>'livemode')::boolean, false);
    v_amount    bigint;
    v_arrival   date;
    v_from      public.cash_account;
    v_to        public.cash_account;
    v_existing  public.account_transfers%ROWTYPE;
    v_transfer  uuid;
BEGIN
    IF v_id IS NULL OR v_id !~ '^po_' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_PAYOUT');
    END IF;

    -- Mai accrediti di prova nel registro vero (come i pagamenti: `stripe_test_ledger` solo in locale)
    IF NOT internal.stripe_ledger_allowed(v_livemode) THEN
        RETURN jsonb_build_object('ok', true, 'action', 'ignored', 'reason', 'TEST_MODE');
    END IF;

    IF v_currency <> 'eur' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'UNSUPPORTED_CURRENCY');
    END IF;

    v_amount := (p_payout->>'amount')::bigint;
    IF v_amount IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_PAYOUT');
    END IF;

    -- Webhook e riallineamento possono arrivare insieme: uno alla volta per accredito
    PERFORM pg_advisory_xact_lock(hashtext('stripe_payout:' || v_id));

    SELECT * INTO v_existing FROM public.account_transfers WHERE stripe_payout_id = v_id FOR UPDATE;

    IF v_status = 'paid' AND v_amount <> 0 THEN
        -- Stripe dà il giorno di arrivo come istante (la mezzanotte UTC): il giorno italiano è lo stesso
        v_arrival := (to_timestamp((p_payout->>'arrival_date')::bigint) AT TIME ZONE 'Europe/Rome')::date;
        IF v_arrival IS NULL THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_PAYOUT');
        END IF;
        -- Un accredito negativo è Stripe che preleva dal conto per coprire un saldo sotto zero
        v_from := CASE WHEN v_amount > 0 THEN 'stripe' ELSE 'bank' END;
        v_to   := CASE WHEN v_amount > 0 THEN 'bank' ELSE 'stripe' END;

        IF v_existing.id IS NULL THEN
            INSERT INTO public.account_transfers (occurred_on, from_account, to_account, amount_cents, stripe_payout_id)
            VALUES (v_arrival, v_from, v_to, abs(v_amount)::integer, v_id)
            RETURNING id INTO v_transfer;
            RETURN jsonb_build_object('ok', true, 'action', 'recorded', 'transfer_id', v_transfer);
        END IF;

        IF v_existing.occurred_on = v_arrival AND v_existing.from_account = v_from
           AND v_existing.to_account = v_to AND v_existing.amount_cents = abs(v_amount) THEN
            RETURN jsonb_build_object('ok', true, 'action', 'unchanged', 'transfer_id', v_existing.id);
        END IF;

        UPDATE public.account_transfers
           SET occurred_on = v_arrival, from_account = v_from, to_account = v_to, amount_cents = abs(v_amount)::integer
         WHERE id = v_existing.id;
        RETURN jsonb_build_object('ok', true, 'action', 'updated', 'transfer_id', v_existing.id);
    END IF;

    -- Fallito o annullato dopo essere risultato arrivato: i soldi sono tornati su Stripe
    IF v_existing.id IS NOT NULL THEN
        DELETE FROM public.account_transfers WHERE id = v_existing.id;
        RETURN jsonb_build_object('ok', true, 'action', 'removed', 'transfer_id', v_existing.id);
    END IF;

    -- In attesa o in viaggio: i soldi sono ancora del conto Stripe finché non arrivano in banca
    RETURN jsonb_build_object('ok', true, 'action', 'waiting');
END;
$$;

ALTER FUNCTION "public"."stripe_apply_payout_state"("jsonb") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."stripe_apply_payout_state"("jsonb") IS
    'Riporta nel registro lo stato di un accredito di Stripe sul conto (riletto da Stripe): arrivato = giroconto Stripe → banca nel giorno di arrivo; fallito o annullato = nessun giroconto. Idempotente. Solo service_role (webhook e stripe-reconcile).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Saldi: cassa, banca e Stripe
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."finance_account_balances"("p_at" "date")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_settings  public.association_settings%ROWTYPE;
    v_cash      bigint;
    v_bank      bigint;
    -- Il conto Stripe è nato il 01/10/2026, dopo l'inizio della contabilità: parte da zero
    v_stripe    bigint := 0;
BEGIN
    IF NOT public.can_access_finance() THEN
        RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_settings FROM public.association_settings WHERE id = true;
    v_cash := v_settings.opening_cash_cents;
    v_bank := v_settings.opening_bank_cents;

    IF p_at >= v_settings.ledger_start_date THEN
        SELECT v_cash   + COALESCE(sum(t.amount_cents) FILTER (WHERE internal.cash_account_for(t.method) = 'cash'), 0),
               v_bank   + COALESCE(sum(t.amount_cents) FILTER (WHERE internal.cash_account_for(t.method) = 'bank'), 0),
               v_stripe + COALESCE(sum(t.amount_cents) FILTER (WHERE internal.cash_account_for(t.method) = 'stripe'), 0)
          INTO v_cash, v_bank, v_stripe
          FROM public.transactions t
          LEFT JOIN public.transactions o ON o.id = t.refund_of_id
         WHERE t.status IN ('paid', 'refunded', 'partially_refunded')
           AND (o.id IS NULL OR o.status IN ('paid', 'refunded', 'partially_refunded'))
           AND t.occurred_on BETWEEN v_settings.ledger_start_date AND p_at;

        SELECT v_cash   - COALESCE(sum(amount_cents) FILTER (WHERE internal.cash_account_for(payment_method) = 'cash'), 0),
               v_bank   - COALESCE(sum(amount_cents) FILTER (WHERE internal.cash_account_for(payment_method) = 'bank'), 0),
               v_stripe - COALESCE(sum(amount_cents) FILTER (WHERE internal.cash_account_for(payment_method) = 'stripe'), 0)
          INTO v_cash, v_bank, v_stripe
          FROM public.expenses
         WHERE confirmed_at IS NOT NULL
           AND expense_date BETWEEN v_settings.ledger_start_date AND p_at;

        SELECT v_cash   + COALESCE(sum(CASE WHEN to_account = 'cash' THEN amount_cents
                                            WHEN from_account = 'cash' THEN -amount_cents END), 0),
               v_bank   + COALESCE(sum(CASE WHEN to_account = 'bank' THEN amount_cents
                                            WHEN from_account = 'bank' THEN -amount_cents END), 0),
               v_stripe + COALESCE(sum(CASE WHEN to_account = 'stripe' THEN amount_cents
                                            WHEN from_account = 'stripe' THEN -amount_cents END), 0)
          INTO v_cash, v_bank, v_stripe
          FROM public.account_transfers
         WHERE occurred_on BETWEEN v_settings.ledger_start_date AND p_at;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'at', p_at,
        'ledger_start_date', v_settings.ledger_start_date,
        'before_ledger', p_at < v_settings.ledger_start_date,
        'cash_cents', v_cash,
        'bank_cents', v_bank,
        'stripe_cents', v_stripe,
        'total_cents', v_cash + v_bank + v_stripe
    );
END;
$$;

ALTER FUNCTION "public"."finance_account_balances"("date") OWNER TO "postgres";
COMMENT ON FUNCTION "public"."finance_account_balances"("date") IS
    'Saldi di cassa, banca (solo il conto corrente) e Stripe (pagamenti con carta non ancora accreditati) a fine giornata: saldi iniziali + entrate − uscite confermate ± giroconti, dal 19/08/2026. Solo Finanze.';
