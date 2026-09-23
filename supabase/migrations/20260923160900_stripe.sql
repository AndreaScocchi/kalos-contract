-- Migration 20260923160900: schema dei pagamenti Stripe (sessione 3, blocco 9)
--
-- Obiettivo: preparare il terreno per i pagamenti in app e sul sito, che si costruiscono nella
-- sessione 5. Qui ci sono solo le tabelle e il collegamento con il registro delle transazioni; il
-- checkout e il webhook arriveranno con l'account Stripe vero.
--
-- Due cose che il rischio noto di NEW_APP_PLAN.md chiede esplicitamente:
--   * IDEMPOTENZA del webhook. Stripe rispedisce lo stesso evento più volte, e senza un vincolo di
--     unicità sull'id dell'evento si finisce per registrare due volte lo stesso incasso. Per questo
--     `stripe_events` ha l'id di Stripe come CHIAVE PRIMARIA: la seconda consegna sbatte contro il
--     vincolo invece di creare un doppione.
--   * NESSUN DOPPIO CONTEGGIO: un pagamento online deve produrre gli stessi record di uno registrato
--     in studio. Per questo `stripe_payments` non è un registro parallelo ma punta alla riga in
--     `transactions`, che resta l'unica fonte per le Finanze.
--
-- Le COMMISSIONI diventano un'uscita da sole (H5): è denaro che esce, e a fine anno deve comparire nel
-- rendiconto senza che nessuno se lo ricordi a mano.
--
-- Modello dei pagamenti: una tantum, mai rinnovo automatico (§2 del piano). Niente Stripe
-- Subscriptions: qui non c'è nulla che assomigli a un abbonamento ricorrente, ed è voluto.
--
-- Gli interruttori `payments` e `stripe_live` esistono già, spenti.
--
-- Compatibilità: solo enum, tabelle e funzioni nuove, più la chiave esterna sulla colonna
-- `transactions.stripe_payment_id` creata (vuota) dalla migrazione delle transazioni.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §2, §3 D1–D4, H5.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enum
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
    CREATE TYPE "public"."stripe_payment_status" AS ENUM (
        'created',      -- intento creato, la persona non ha ancora pagato
        'processing',
        'succeeded',
        'failed',
        'canceled',
        'refunded',
        'partially_refunded'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE "public"."stripe_purpose" AS ENUM (
        'membership_fee',   -- quota associativa
        'subscription',     -- abbonamento
        'event',            -- evento o laboratorio
        'donation',         -- donazione dal sito (in app no: regole di Apple e Google)
        'other'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. stripe_events — la memoria del webhook
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."stripe_events" (
    "id"            "text"      NOT NULL,
    "type"          "text"      NOT NULL,
    "payload"       "jsonb"     NOT NULL,
    "livemode"      boolean     DEFAULT false NOT NULL,
    "received_at"   timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at"  timestamp with time zone,
    "error_message" "text",
    "attempts"      integer     DEFAULT 0 NOT NULL,

    CONSTRAINT "stripe_events_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "stripe_events_attempts_non_negative" CHECK ("attempts" >= 0)
);

ALTER TABLE "public"."stripe_events" OWNER TO "postgres";

COMMENT ON TABLE "public"."stripe_events" IS
    'Eventi ricevuti dal webhook di Stripe. L''id è quello di Stripe ed è la chiave primaria: è così che la seconda consegna dello stesso evento non registra due volte lo stesso incasso.';
COMMENT ON COLUMN "public"."stripe_events"."livemode" IS
    'false in modalità test. Tenerlo permette di distinguere le prove dagli incassi veri anche a distanza di tempo.';

CREATE INDEX IF NOT EXISTS "idx_stripe_events_unprocessed"
    ON "public"."stripe_events" ("received_at") WHERE "processed_at" IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. stripe_payments
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."stripe_payments" (
    "id"                    "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "payment_intent_id"     "text"  NOT NULL,
    "checkout_session_id"   "text",
    "client_id"             "uuid",
    "purpose"               "public"."stripe_purpose" NOT NULL,
    "target_id"             "uuid",
    "amount_cents"          integer NOT NULL,
    "currency"              "text"  DEFAULT 'EUR'::"text" NOT NULL,
    "fee_cents"             integer,
    "net_cents"             integer,
    "status"                "public"."stripe_payment_status"
                            DEFAULT 'created'::"public"."stripe_payment_status" NOT NULL,
    "livemode"              boolean DEFAULT false NOT NULL,
    "transaction_id"        "uuid",
    "fee_expense_id"        "uuid",
    "payment_method_type"   "text",
    "receipt_email"         "text",
    "failure_message"       "text",
    "created_at"            timestamp with time zone DEFAULT "now"() NOT NULL,
    "succeeded_at"          timestamp with time zone,
    "updated_at"            timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "stripe_payments_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "stripe_payments_payment_intent_id_key" UNIQUE ("payment_intent_id"),
    CONSTRAINT "stripe_payments_client_id_fkey"
        FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL,
    CONSTRAINT "stripe_payments_transaction_id_fkey"
        FOREIGN KEY ("transaction_id") REFERENCES "public"."transactions"("id") ON DELETE SET NULL,
    CONSTRAINT "stripe_payments_fee_expense_id_fkey"
        FOREIGN KEY ("fee_expense_id") REFERENCES "public"."expenses"("id") ON DELETE SET NULL,
    CONSTRAINT "stripe_payments_amount_positive" CHECK ("amount_cents" > 0),
    CONSTRAINT "stripe_payments_fee_non_negative" CHECK ("fee_cents" IS NULL OR "fee_cents" >= 0),
    CONSTRAINT "stripe_payments_succeeded_needs_date"
        CHECK ("status" <> 'succeeded'::"public"."stripe_payment_status" OR "succeeded_at" IS NOT NULL)
);

ALTER TABLE "public"."stripe_payments" OWNER TO "postgres";

COMMENT ON TABLE "public"."stripe_payments" IS
    'Pagamenti online. Non è un registro parallelo: `transaction_id` punta alla riga di `transactions`, che resta l''unica fonte delle Finanze. Un pagamento in app e uno in studio finiscono nello stesso posto, ciascuno una volta sola.';
COMMENT ON COLUMN "public"."stripe_payments"."target_id" IS
    'A cosa si riferisce il pagamento: l''abbonamento, l''evento o la quota, secondo `purpose`.';
COMMENT ON COLUMN "public"."stripe_payments"."fee_cents" IS
    'Commissione trattenuta da Stripe. Diventa un''uscita nella categoria commissioni (H5).';

CREATE INDEX IF NOT EXISTS "idx_stripe_payments_client" ON "public"."stripe_payments" ("client_id");
CREATE INDEX IF NOT EXISTS "idx_stripe_payments_status" ON "public"."stripe_payments" ("status", "created_at");

CREATE OR REPLACE TRIGGER "stripe_payments_updated_at"
    BEFORE UPDATE ON "public"."stripe_payments"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- Il registro può ora puntare al pagamento online.
ALTER TABLE "public"."transactions"
    ADD CONSTRAINT "transactions_stripe_payment_id_fkey"
    FOREIGN KEY ("stripe_payment_id") REFERENCES "public"."stripe_payments"("id") ON DELETE SET NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. stripe_refunds
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."stripe_refunds" (
    "id"                    "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "refund_id"             "text"  NOT NULL,
    "stripe_payment_id"     "uuid"  NOT NULL,
    "amount_cents"          integer NOT NULL,
    "reason"                "text",
    "status"                "text",
    "transaction_id"        "uuid",
    "created_by"            "uuid",
    "created_at"            timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "stripe_refunds_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "stripe_refunds_refund_id_key" UNIQUE ("refund_id"),
    CONSTRAINT "stripe_refunds_stripe_payment_id_fkey"
        FOREIGN KEY ("stripe_payment_id") REFERENCES "public"."stripe_payments"("id") ON DELETE CASCADE,
    CONSTRAINT "stripe_refunds_transaction_id_fkey"
        FOREIGN KEY ("transaction_id") REFERENCES "public"."transactions"("id") ON DELETE SET NULL,
    CONSTRAINT "stripe_refunds_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "stripe_refunds_amount_positive" CHECK ("amount_cents" > 0)
);

ALTER TABLE "public"."stripe_refunds" OWNER TO "postgres";

COMMENT ON TABLE "public"."stripe_refunds" IS
    'Rimborsi effettuati via Stripe. Nessuno è automatico: li decide lo staff caso per caso (D4). La riga negativa nel registro la crea `staff_refund_transaction`.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RLS e grant — nessuna app scrive qui, scrive solo il webhook (service_role)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."stripe_events"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."stripe_payments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."stripe_refunds"  ENABLE ROW LEVEL SECURITY;

-- `stripe_events` resta senza policy e senza grant: è roba del webhook, che usa service_role.
-- Pagamenti e rimborsi li legge chi vede le Finanze; le scritture arrivano dalle edge function.
DROP POLICY IF EXISTS "stripe_payments_select_finance" ON "public"."stripe_payments";
CREATE POLICY "stripe_payments_select_finance" ON "public"."stripe_payments"
    FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());

DROP POLICY IF EXISTS "stripe_refunds_select_finance" ON "public"."stripe_refunds";
CREATE POLICY "stripe_refunds_select_finance" ON "public"."stripe_refunds"
    FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());

GRANT SELECT ON TABLE "public"."stripe_payments" TO "authenticated";
GRANT SELECT ON TABLE "public"."stripe_refunds"  TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. La commissione diventa un'uscita
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."record_stripe_fee_expense"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_category_id uuid;
    v_expense_id  uuid;
BEGIN
    -- Solo quando il pagamento riesce, c'è una commissione e non è già stata registrata
    IF NEW.status <> 'succeeded'
       OR COALESCE(NEW.fee_cents, 0) <= 0
       OR NEW.fee_expense_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT id INTO v_category_id FROM public.expense_categories WHERE slug = 'commissioni';

    INSERT INTO public.expenses (
        amount_cents, expense_date, category, category_id, notes,
        is_fixed, source, confirmed_at
    ) VALUES (
        NEW.fee_cents,
        COALESCE(NEW.succeeded_at, now())::date,
        'other', v_category_id,
        'Commissione Stripe — ' || NEW.payment_intent_id,
        false, 'stripe_fee', now()
    )
    RETURNING id INTO v_expense_id;

    UPDATE public.stripe_payments SET fee_expense_id = v_expense_id WHERE id = NEW.id;

    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."record_stripe_fee_expense"() OWNER TO "postgres";
COMMENT ON FUNCTION "public"."record_stripe_fee_expense"() IS
    'Quando un pagamento online va a buon fine, registra la commissione di Stripe come uscita (H5). Si protegge dai doppioni con `fee_expense_id`.';

CREATE OR REPLACE TRIGGER "stripe_payments_fee_expense"
    AFTER INSERT OR UPDATE OF "status", "fee_cents" ON "public"."stripe_payments"
    FOR EACH ROW EXECUTE FUNCTION "public"."record_stripe_fee_expense"();
