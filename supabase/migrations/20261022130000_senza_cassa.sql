-- Migration 20261022130000: niente cassa, i contanti vanno in banca (contract v0.3.19)
--
-- Decisione dell'utente del 22/10/2026: l'associazione non ha una cassa fisica. I pochi contanti
-- che arrivano dai soci si versano subito sul conto corrente. Il conto «cassa» delle Finanze
-- (sessione 7) teneva quei contanti come se restassero in studio finché qualcunə non registrava un
-- giroconto: in produzione mostrava 245 € «in cassa» (sette quote del 07/10) che in realtà erano già
-- in banca, e «In banca» restava 245 € sotto l'estratto conto.
--
-- Ora i conti sono due più Stripe:
--   banca   conto corrente, compresi i contanti versati
--   stripe  pagamenti con carta non ancora accreditati (v0.3.15, invariato)
--
--   - `internal.cash_account_for`: il metodo `cash` va in banca. Le ricevute e il registro
--     continuano a dire «Contanti»: cambia solo il conto su cui arrivano. Lo usano
--     `finance_income_lines` (colonna `account`) e `finance_account_balances`.
--   - I due conti si uniscono: il saldo iniziale di cassa passa alla banca e i giroconti fra cassa
--     e banca spariscono, perché dopo l'unione sarebbero movimenti dalla banca alla banca. Il
--     totale non cambia. In produzione non c'è nessuna delle due cose (saldo iniziale di cassa 0,
--     un solo giroconto, l'accredito di Stripe del 16/10): i due comandi non toccano niente.
--   - Vincoli: il saldo iniziale di cassa resta 0 e nessun giroconto tocca la cassa. Dall'API il
--     trigger risponde `NO_CASH_ACCOUNT`; `finance_set_opening_balances` lo stesso con una cassa
--     diversa da 0.
--   - Colonne, tipi e firme restano: `cash_account` tiene il valore `cash` (un valore di un enum non
--     si toglie), `opening_cash_cents` resta a 0, `finance_account_balances` risponde ancora
--     `cash_cents`, sempre 0.
--
-- Il rendiconto (Modello D) tiene la riga «Cassa» del suo schema, a 0.
--
-- Compatibilità: il gestionale di prima mostra «In cassa» a 0 e i contanti in banca; il suo
-- «+ Giroconto» riceve NO_CASH_ACCOUNT. Il gestionale nuovo esce nello stesso rilascio.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. I contanti vanno in banca
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."cash_account_for"("p_method" "public"."payment_method")
    RETURNS "public"."cash_account"
    LANGUAGE "sql"
    IMMUTABLE
    AS $$
    SELECT CASE p_method
               WHEN 'stripe' THEN 'stripe'
               ELSE 'bank'
           END::public.cash_account;
$$;

ALTER FUNCTION "internal"."cash_account_for"("public"."payment_method") OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."cash_account_for"("public"."payment_method") IS
    'Il conto su cui arriva o da cui esce il denaro: Stripe → conto Stripe (fino all''accredito), tutto il resto → banca. Dal 22/10/2026 anche i contanti: non c''è una cassa, si versano subito sul conto.';

COMMENT ON COLUMN "public"."expenses"."payment_method" IS
    'Come è uscito il denaro: dal conto (bonifico, addebito, carta; anche «contanti», che dal 22/10/2026 contano in banca: non c''è una cassa). Stripe = commissione trattenuta da Stripe sugli incassi con carta.';

COMMENT ON TYPE "public"."cash_account" IS
    'I conti dell''associazione: banca (conto corrente) e stripe (i pagamenti con carta incassati e non ancora accreditati sul conto). Il valore cash (cassa) non si usa più dal 22/10/2026: i contanti vanno in banca.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. La cassa si unisce alla banca
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE "public"."association_settings"
   SET "opening_bank_cents" = "opening_bank_cents" + "opening_cash_cents",
       "opening_cash_cents" = 0
 WHERE "opening_cash_cents" <> 0;

-- Fra cassa e banca, dopo l'unione: dalla banca alla banca. Mai un accredito di Stripe (vincolo
-- `account_transfers_stripe_only_payouts`).
DELETE FROM "public"."account_transfers"
 WHERE 'cash' IN ("from_account", "to_account");

DO $$ BEGIN
    ALTER TABLE "public"."association_settings"
        ADD CONSTRAINT "association_settings_no_cash" CHECK ("opening_cash_cents" = 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE "public"."account_transfers"
        ADD CONSTRAINT "account_transfers_no_cash" CHECK ('cash' NOT IN ("from_account", "to_account"));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN "public"."association_settings"."opening_cash_cents" IS
    'Sempre 0 dal 22/10/2026: non c''è una cassa, il saldo iniziale è tutto in `opening_bank_cents`. Resta per compatibilità.';
COMMENT ON TABLE "public"."account_transfers" IS
    'Giroconti fra i conti. Dal 22/10/2026 sono solo gli accrediti di Stripe sul conto (e i rari prelievi di Stripe), scritti dal database: non c''è una cassa. Non sono né entrate né uscite.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Dall'API: niente cassa, Stripe solo dagli accrediti
-- ─────────────────────────────────────────────────────────────────────────────

-- SECURITY INVOKER di proposito (v0.3.15): `current_user` distingue chi scrive dall'API.
CREATE OR REPLACE FUNCTION "internal"."account_transfers_before_write"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF current_user NOT IN ('authenticated', 'anon') THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') AND 'cash' IN (NEW.from_account, NEW.to_account) THEN
        RAISE EXCEPTION 'NO_CASH_ACCOUNT'
            USING ERRCODE = 'P0001',
                  DETAIL = 'Non c''è una cassa: i contanti si versano subito e contano in banca.';
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
                  DETAIL = 'I movimenti del conto Stripe si registrano da soli.';
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

ALTER FUNCTION "internal"."account_transfers_before_write"() OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."account_transfers_before_write"() IS
    'Dall''API non si scrive un giroconto che tocca la cassa (non c''è, dal 22/10/2026) o il conto Stripe, e non si cambia né cancella un accredito di Stripe (si può solo cambiarne la nota).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Saldo iniziale: solo la banca
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Stessa firma (il gestionale di prima la chiama ancora con la cassa): una cassa diversa da 0
-- risponde NO_CASH_ACCOUNT.

CREATE OR REPLACE FUNCTION "public"."finance_set_opening_balances"(
    "p_cash_cents" integer,
    "p_bank_cents" integer
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    IF p_bank_cents IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT');
    END IF;

    IF COALESCE(p_cash_cents, 0) <> 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NO_CASH_ACCOUNT');
    END IF;

    UPDATE public.association_settings
       SET opening_bank_cents = p_bank_cents,
           updated_by = auth.uid(),
           updated_at = now()
     WHERE id = true;

    RETURN jsonb_build_object('ok', true, 'reason', 'SAVED');
END;
$$;

ALTER FUNCTION "public"."finance_set_opening_balances"(integer, integer) OWNER TO "postgres";
COMMENT ON FUNCTION "public"."finance_set_opening_balances"(integer, integer) IS
    'Imposta il saldo del conto all''inizio della contabilità. La cassa non c''è più (22/10/2026): p_cash_cents deve essere 0 o NULL. Solo Finanze.';

COMMENT ON FUNCTION "public"."finance_account_balances"("date") IS
    'Saldi di banca (conto corrente, compresi i contanti versati) e Stripe (pagamenti con carta non ancora accreditati) a fine giornata: saldo iniziale + entrate − uscite confermate ± accrediti di Stripe, dal 19/08/2026. cash_cents resta nella risposta ed è sempre 0. Solo Finanze.';
