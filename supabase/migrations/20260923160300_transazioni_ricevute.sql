-- Migration 20260923160300: registro delle transazioni, ricevute numerate e dati dell'associazione
-- (sessione 3, blocco 3)
--
-- Obiettivo: oggi gli incassi non sono registrati da nessuna parte. Le Finanze del gestionale mostrano
-- una STIMA ricavata dai prezzi degli abbonamenti — e per giunta conta due volte lo stesso denaro,
-- perché somma sia il prezzo dell'abbonamento quando nasce sia il valore di ogni ingresso consumato
-- (`get_financial_kpis`, `financial_monthly_summary`). Per un'associazione che deve produrre un
-- rendiconto (art. 18) non basta.
--
-- Qui nasce il registro vero:
--   1. `association_settings` — i dati dell'associazione in UN SOLO POSTO lato database, come
--      `associazione.json` lo è per il sito (BRAND.md §1-bis). Da qui escono le ricevute.
--   2. `transactions`         — ogni movimento in entrata, e i rimborsi come importi negativi, così la
--      somma del registro è il saldo. Il registro parte dal 19/08/2026, data di costituzione (E4).
--   3. `receipts`             — la ricevuta, numerata per anno SENZA BUCHI, con i dati del momento
--      dell'emissione congelati dentro. Il numero si prende con un lock di riga sulla sequenza, quindi
--      due emissioni contemporanee non possono ottenere lo stesso numero.
--
-- Cosa NON si decide qui: quale documento serve per quale entrata, la marca da bollo, il formato della
-- numerazione. Sono le domande 2.1–2.4 al commercialista, ancora senza risposta: vivono in
-- `association_settings` come dati modificabili, non nel codice.
--
-- Le Finanze passeranno a leggere questa tabella nella sessione 7. Qui non si tocca nulla di ciò che
-- esiste: `get_financial_kpis`, `financial_monthly_summary` e le altre restano come sono.
--
-- Compatibilità: solo nuovi enum, tabelle e funzioni, più una chiave esterna sulla colonna
-- `member_fees.transaction_id` creata (vuota) dalla migrazione dei soci.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 (A5, E1, E2, E4, D4) e docs/DOMANDE-COMMERCIALISTA.md §2.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enum
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
    CREATE TYPE "public"."transaction_kind" AS ENUM (
        'membership_fee',   -- quota associativa
        'subscription',     -- contributo per un abbonamento
        'event',            -- evento o laboratorio
        'trial',            -- lezione di prova, se mai diventasse a pagamento (F1)
        'donation',         -- erogazione liberale
        'commercial',       -- entrata commerciale: oggi nessuna, previste in futuro (A5)
        'other'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE "public"."payment_method" AS ENUM (
        'cash',             -- contanti in studio
        'bank_transfer',    -- bonifico
        'stripe',           -- carta, Apple Pay, Google Pay
        'other'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE "public"."transaction_source" AS ENUM (
        'studio',           -- registrato dallo staff
        'app',
        'site'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE "public"."transaction_status" AS ENUM (
        'pending',          -- "da saldare" (E2): l'abbonamento c'è, il denaro non ancora
        'paid',
        'refunded',
        'partially_refunded',
        'void'              -- annullata per errore di registrazione
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. association_settings — i dati dell'associazione, in un punto solo
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."association_settings" (
    "id"                            boolean DEFAULT true NOT NULL,
    "legal_name"                    "text"  NOT NULL,
    "short_legal_name"              "text"  NOT NULL,
    "fiscal_code"                   "text"  NOT NULL,
    "vat_number"                    "text",
    "address_street"                "text"  NOT NULL,
    "address_zip"                   "text"  NOT NULL,
    "address_city"                  "text"  NOT NULL,
    "address_province"              "text"  NOT NULL,
    "pec"                           "text",
    "email"                         "text",
    "phone"                         "text",
    "legal_representative"          "text",
    "runts_registered"              boolean DEFAULT false NOT NULL,
    "runts_number"                  "text",
    "ledger_start_date"             "date"  DEFAULT '2026-08-19'::"date" NOT NULL,
    "receipt_prefix"                "text"  DEFAULT ''::"text" NOT NULL,
    "receipt_footer"                "text",
    "stamp_duty_threshold_cents"    integer DEFAULT 0 NOT NULL,
    "stamp_duty_cents"              integer DEFAULT 0 NOT NULL,
    "updated_by"                    "uuid",
    "updated_at"                    timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "association_settings_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "association_settings_single_row" CHECK ("id" = true),
    CONSTRAINT "association_settings_updated_by_fkey"
        FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "association_settings_stamp_duty_non_negative"
        CHECK ("stamp_duty_threshold_cents" >= 0 AND "stamp_duty_cents" >= 0)
);

ALTER TABLE "public"."association_settings" OWNER TO "postgres";

COMMENT ON TABLE "public"."association_settings" IS
    'Dati e impostazioni dell''associazione, riga unica. È il corrispettivo lato database di kalos-website/kalos-react/src/config/associazione.json: quando l''iscrizione al RUNTS arriva, si cambia qui e cambia ovunque.';
COMMENT ON COLUMN "public"."association_settings"."ledger_start_date" IS
    'Data da cui parte la contabilità dell''associazione: il 19/08/2026, giorno della costituzione. Quello che è stato incassato prima appartiene alla gestione precedente (E4).';
COMMENT ON COLUMN "public"."association_settings"."stamp_duty_threshold_cents" IS
    'Soglia oltre la quale si applica la marca da bollo. 0 = nessun bollo, in attesa della risposta 2.2 del commercialista.';
COMMENT ON COLUMN "public"."association_settings"."runts_registered" IS
    'Con l''iscrizione al RUNTS la denominazione diventa "Studio Kalòs APS - ETS" (art. 1). Una riga, non una modifica al codice.';

INSERT INTO "public"."association_settings" (
    "id", "legal_name", "short_legal_name", "fiscal_code", "vat_number",
    "address_street", "address_zip", "address_city", "address_province",
    "pec", "email", "phone", "legal_representative", "receipt_footer"
) VALUES (
    true,
    'Studio Kalòs Associazione di Promozione Sociale',
    'Studio Kalòs APS',
    '01292700315',
    '01292700315',
    'Piazza Furlan 5', '34077', 'Ronchi dei Legionari', 'GO',
    'kalostudio@pec.it',
    'info.studiokalos@gmail.com',
    '+39 352 070 4434',
    'Andrea Scocchi',
    'Studio Kalòs APS · Piazza Furlan 5, 34077 Ronchi dei Legionari (GO) · C.F. e P.IVA 01292700315'
) ON CONFLICT ("id") DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. transactions — il registro
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."transactions" (
    "id"                    "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id"             "uuid",
    "kind"                  "public"."transaction_kind" NOT NULL,
    "amount_cents"          integer     NOT NULL,
    "currency"              "text"      DEFAULT 'EUR'::"text" NOT NULL,
    "method"                "public"."payment_method" NOT NULL,
    "source"                "public"."transaction_source" NOT NULL,
    "status"                "public"."transaction_status" DEFAULT 'paid'::"public"."transaction_status" NOT NULL,
    "occurred_on"           "date"      DEFAULT CURRENT_DATE NOT NULL,

    "subscription_id"       "uuid",
    "event_booking_id"      "uuid",
    "member_fee_id"         "uuid",
    "booking_id"            "uuid",
    "refund_of_id"          "uuid",
    "stripe_payment_id"     "uuid",

    "is_commercial"         boolean     DEFAULT false NOT NULL,
    "description"           "text",
    "note"                  "text",
    "metadata"              "jsonb"     DEFAULT '{}'::"jsonb",
    "created_by"            "uuid",
    "created_at"            timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"            timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "transactions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "transactions_client_id_fkey"
        FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL,
    CONSTRAINT "transactions_subscription_id_fkey"
        FOREIGN KEY ("subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE SET NULL,
    CONSTRAINT "transactions_event_booking_id_fkey"
        FOREIGN KEY ("event_booking_id") REFERENCES "public"."event_bookings"("id") ON DELETE SET NULL,
    CONSTRAINT "transactions_member_fee_id_fkey"
        FOREIGN KEY ("member_fee_id") REFERENCES "public"."member_fees"("id") ON DELETE SET NULL,
    CONSTRAINT "transactions_booking_id_fkey"
        FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL,
    CONSTRAINT "transactions_refund_of_id_fkey"
        FOREIGN KEY ("refund_of_id") REFERENCES "public"."transactions"("id") ON DELETE RESTRICT,
    CONSTRAINT "transactions_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "transactions_amount_not_zero" CHECK ("amount_cents" <> 0),
    -- Un rimborso è una riga a importo negativo collegata all'originale; un incasso è positivo.
    CONSTRAINT "transactions_refund_sign"
        CHECK (("refund_of_id" IS NULL AND "amount_cents" > 0)
               OR ("refund_of_id" IS NOT NULL AND "amount_cents" < 0))
);

ALTER TABLE "public"."transactions" OWNER TO "postgres";

COMMENT ON TABLE "public"."transactions" IS
    'Registro degli incassi dell''associazione, dal 19/08/2026. I rimborsi sono righe a importo NEGATIVO collegate all''originale, così sommare la colonna dà il saldo senza casi particolari. Sostituirà la stima delle Finanze nella sessione 7.';
COMMENT ON COLUMN "public"."transactions"."status" IS
    '`pending` è il "da saldare": l''abbonamento esiste, il denaro non è ancora arrivato. Niente rate (E2).';
COMMENT ON COLUMN "public"."transactions"."is_commercial" IS
    'Entrata commerciale: oggi nessuna. Serve a tenerle separate dalle attività istituzionali quando arriveranno (A5).';
COMMENT ON COLUMN "public"."transactions"."stripe_payment_id" IS
    'Pagamento Stripe collegato. Il vincolo di chiave esterna lo aggiunge la migrazione di Stripe.';

CREATE INDEX IF NOT EXISTS "idx_transactions_occurred_on" ON "public"."transactions" ("occurred_on");
CREATE INDEX IF NOT EXISTS "idx_transactions_client" ON "public"."transactions" ("client_id") WHERE "client_id" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "idx_transactions_kind_status" ON "public"."transactions" ("kind", "status");
CREATE INDEX IF NOT EXISTS "idx_transactions_pending" ON "public"."transactions" ("occurred_on")
    WHERE "status" = 'pending'::"public"."transaction_status";

CREATE OR REPLACE TRIGGER "transactions_updated_at"
    BEFORE UPDATE ON "public"."transactions"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- La quota può ora puntare al suo incasso.
ALTER TABLE "public"."member_fees"
    ADD CONSTRAINT "member_fees_transaction_id_fkey"
    FOREIGN KEY ("transaction_id") REFERENCES "public"."transactions"("id") ON DELETE SET NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. receipts — numerazione per anno, senza buchi
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."receipt_sequences" (
    "year"          integer NOT NULL,
    "last_number"   integer DEFAULT 0 NOT NULL,
    CONSTRAINT "receipt_sequences_pkey" PRIMARY KEY ("year"),
    CONSTRAINT "receipt_sequences_non_negative" CHECK ("last_number" >= 0)
);

ALTER TABLE "public"."receipt_sequences" OWNER TO "postgres";
COMMENT ON TABLE "public"."receipt_sequences" IS
    'Contatore delle ricevute per anno. Tabella interna: nessuna app la legge o la scrive. Il numero si prende con UPDATE … RETURNING, che tiene il lock di riga fino a fine transazione: due emissioni contemporanee si mettono in coda invece di collidere.';

CREATE TABLE IF NOT EXISTS "public"."receipts" (
    "id"                        "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "transaction_id"            "uuid"      NOT NULL,
    "year"                      integer     NOT NULL,
    "number"                    integer     NOT NULL,
    "full_number"               "text"      NOT NULL,
    "issued_at"                 timestamp with time zone DEFAULT "now"() NOT NULL,

    "recipient_name"            "text"      NOT NULL,
    "recipient_fiscal_code"     "text",
    "recipient_address"         "text",
    "issuer_snapshot"           "jsonb"     NOT NULL,

    "causale"                   "text"      NOT NULL,
    "amount_cents"              integer     NOT NULL,
    "stamp_duty_cents"          integer     DEFAULT 0 NOT NULL,
    "pdf_path"                  "text",
    "sent_at"                   timestamp with time zone,
    "voided_at"                 timestamp with time zone,
    "void_reason"               "text",
    "created_by"                "uuid",
    "created_at"                timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"                timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "receipts_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "receipts_transaction_id_key" UNIQUE ("transaction_id"),
    CONSTRAINT "receipts_year_number_key" UNIQUE ("year", "number"),
    CONSTRAINT "receipts_full_number_key" UNIQUE ("full_number"),
    CONSTRAINT "receipts_transaction_id_fkey"
        FOREIGN KEY ("transaction_id") REFERENCES "public"."transactions"("id") ON DELETE RESTRICT,
    CONSTRAINT "receipts_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "receipts_number_positive" CHECK ("number" > 0),
    CONSTRAINT "receipts_amount_positive" CHECK ("amount_cents" > 0),
    CONSTRAINT "receipts_stamp_duty_non_negative" CHECK ("stamp_duty_cents" >= 0),
    CONSTRAINT "receipts_voided_needs_reason"
        CHECK ("voided_at" IS NULL OR "length"("btrim"(COALESCE("void_reason", ''))) > 0)
);

ALTER TABLE "public"."receipts" OWNER TO "postgres";

COMMENT ON TABLE "public"."receipts" IS
    'Ricevuta emessa per una transazione, numerata per anno. I dati di chi emette e di chi riceve sono CONGELATI qui dentro: una ricevuta del 2026 deve restare leggibile com''era, anche se poi la denominazione cambia in "APS - ETS" o la persona cambia indirizzo.';
COMMENT ON COLUMN "public"."receipts"."issuer_snapshot" IS
    'Dati dell''associazione al momento dell''emissione, copiati da `association_settings`.';
COMMENT ON COLUMN "public"."receipts"."voided_at" IS
    'Annullamento: la ricevuta resta, con il suo numero, e si annota il motivo. Non si cancella e non si riusa il numero, altrimenti la numerazione avrebbe buchi.';

CREATE INDEX IF NOT EXISTS "idx_receipts_year" ON "public"."receipts" ("year", "number");
CREATE INDEX IF NOT EXISTS "idx_receipts_issued_at" ON "public"."receipts" ("issued_at");

CREATE OR REPLACE TRIGGER "receipts_updated_at"
    BEFORE UPDATE ON "public"."receipts"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RLS e grant
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."association_settings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."transactions"         ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."receipts"             ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."receipt_sequences"    ENABLE ROW LEVEL SECURITY;

-- I dati dell'associazione li legge tutto lo staff (servono a stampare), li cambia solo un admin.
DROP POLICY IF EXISTS "association_settings_select_staff" ON "public"."association_settings";
CREATE POLICY "association_settings_select_staff" ON "public"."association_settings"
    FOR SELECT TO "authenticated" USING ("public"."is_staff"());

DROP POLICY IF EXISTS "association_settings_write_admin" ON "public"."association_settings";
CREATE POLICY "association_settings_write_admin" ON "public"."association_settings"
    FOR ALL TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());

-- Le operatrici REGISTRANO gli incassi ma non vedono le Finanze (E3): possono scrivere e rileggere,
-- la lettura d'insieme resta ad admin e Tesoriere tramite le funzioni delle Finanze.
DROP POLICY IF EXISTS "transactions_select_staff" ON "public"."transactions";
CREATE POLICY "transactions_select_staff" ON "public"."transactions"
    FOR SELECT TO "authenticated" USING ("public"."is_staff"());

DROP POLICY IF EXISTS "transactions_insert_staff" ON "public"."transactions";
CREATE POLICY "transactions_insert_staff" ON "public"."transactions"
    FOR INSERT TO "authenticated" WITH CHECK ("public"."is_staff"());

-- Correggere o annullare un movimento già registrato è cosa da admin o Tesoriere.
DROP POLICY IF EXISTS "transactions_update_finance" ON "public"."transactions";
CREATE POLICY "transactions_update_finance" ON "public"."transactions"
    FOR UPDATE TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

DROP POLICY IF EXISTS "transactions_delete_finance" ON "public"."transactions";
CREATE POLICY "transactions_delete_finance" ON "public"."transactions"
    FOR DELETE TO "authenticated" USING ("public"."can_access_finance"());

DROP POLICY IF EXISTS "receipts_select_staff" ON "public"."receipts";
CREATE POLICY "receipts_select_staff" ON "public"."receipts"
    FOR SELECT TO "authenticated" USING ("public"."is_staff"());

DROP POLICY IF EXISTS "receipts_write_finance" ON "public"."receipts";
CREATE POLICY "receipts_write_finance" ON "public"."receipts"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

-- `receipt_sequences` resta senza policy e senza grant: ci arrivano solo le funzioni e service_role.

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."association_settings" TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."transactions"         TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."receipts"             TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Funzioni
-- ─────────────────────────────────────────────────────────────────────────────

-- 6.1 — Prossimo numero di ricevuta. Interna: la chiamano solo le funzioni qui sotto.
CREATE OR REPLACE FUNCTION "public"."next_receipt_number"("p_year" integer)
    RETURNS integer
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_next integer;
BEGIN
    INSERT INTO public.receipt_sequences (year, last_number)
    VALUES (p_year, 0)
    ON CONFLICT (year) DO NOTHING;

    -- UPDATE … RETURNING tiene il lock di riga fino al commit: due emissioni contemporanee si
    -- mettono in coda e ottengono numeri diversi.
    UPDATE public.receipt_sequences
       SET last_number = last_number + 1
     WHERE year = p_year
    RETURNING last_number INTO v_next;

    RETURN v_next;
END;
$$;

ALTER FUNCTION "public"."next_receipt_number"(integer) OWNER TO "postgres";
COMMENT ON FUNCTION "public"."next_receipt_number"(integer) IS
    'Prossimo numero di ricevuta dell''anno. Funzione interna: nessun GRANT alle app.';

-- 6.2 — Emette la ricevuta di una transazione.
CREATE OR REPLACE FUNCTION "public"."issue_receipt"(
    "p_transaction_id" "uuid",
    "p_causale" "text" DEFAULT NULL
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
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

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

    -- Dati di chi riceve: prima quelli della domanda di ammissione, che sono i più completi
    SELECT COALESCE(c.full_name, btrim(a.first_name || ' ' || a.last_name)),
           a.fiscal_code,
           NULLIF(btrim(COALESCE(a.address_street, '') || ' ' || COALESCE(a.address_zip, '') || ' '
                  || COALESCE(a.address_city, '') || ' ' || COALESCE(a.address_province, '')), '')
      INTO v_name, v_fiscal_code, v_address
      FROM public.clients c
      LEFT JOIN public.members m ON m.client_id = c.id
      LEFT JOIN public.member_applications a ON a.id = m.application_id
     WHERE c.id = v_tx.client_id;

    IF v_name IS NULL THEN
        v_name := COALESCE(v_tx.description, 'Non indicato');
    END IF;

    v_year := EXTRACT(YEAR FROM v_tx.occurred_on)::integer;
    v_number := public.next_receipt_number(v_year);
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
        v_causale, v_tx.amount_cents, v_stamp, auth.uid()
    )
    RETURNING id INTO v_receipt_id;

    RETURN jsonb_build_object(
        'ok', true, 'reason', 'ISSUED',
        'receipt_id', v_receipt_id, 'full_number', v_full_number,
        'number', v_number, 'year', v_year, 'stamp_duty_cents', v_stamp
    );
END;
$$;

ALTER FUNCTION "public"."issue_receipt"("uuid", "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."issue_receipt"("uuid", "text") TO "authenticated";
COMMENT ON FUNCTION "public"."issue_receipt"("uuid", "text") IS
    'Emette la ricevuta di una transazione incassata, con numero progressivo per anno e i dati del momento congelati dentro.';

-- 6.3 — Annulla una ricevuta senza toccarne il numero.
CREATE OR REPLACE FUNCTION "public"."void_receipt"("p_receipt_id" "uuid", "p_reason" "text")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    IF COALESCE(btrim(p_reason), '') = '' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'REASON_REQUIRED');
    END IF;

    UPDATE public.receipts
       SET voided_at = now(), void_reason = p_reason
     WHERE id = p_receipt_id AND voided_at IS NULL;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'RECEIPT_NOT_FOUND_OR_ALREADY_VOID');
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'VOIDED');
END;
$$;

ALTER FUNCTION "public"."void_receipt"("uuid", "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."void_receipt"("uuid", "text") TO "authenticated";
COMMENT ON FUNCTION "public"."void_receipt"("uuid", "text") IS
    'Annulla una ricevuta con motivazione. Il numero resta occupato: riusarlo creerebbe un buco nella numerazione.';

-- 6.4 — Registra un incasso e, se richiesto, emette subito la ricevuta.
CREATE OR REPLACE FUNCTION "public"."staff_register_payment"("p_payload" "jsonb")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_tx_id         uuid;
    v_kind          public.transaction_kind;
    v_status        public.transaction_status;
    v_client_id     uuid := NULLIF(p_payload->>'client_id', '')::uuid;
    v_member_fee_id uuid := NULLIF(p_payload->>'member_fee_id', '')::uuid;
    v_amount        integer := (p_payload->>'amount_cents')::integer;
    v_receipt       jsonb := NULL;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF v_amount IS NULL OR v_amount <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT');
    END IF;

    v_kind   := COALESCE(NULLIF(p_payload->>'kind', ''), 'other')::public.transaction_kind;
    v_status := COALESCE(NULLIF(p_payload->>'status', ''), 'paid')::public.transaction_status;

    INSERT INTO public.transactions (
        client_id, kind, amount_cents, method, source, status, occurred_on,
        subscription_id, event_booking_id, member_fee_id, booking_id,
        is_commercial, description, note, created_by
    ) VALUES (
        v_client_id, v_kind, v_amount,
        COALESCE(NULLIF(p_payload->>'method', ''), 'cash')::public.payment_method,
        COALESCE(NULLIF(p_payload->>'source', ''), 'studio')::public.transaction_source,
        v_status,
        COALESCE((p_payload->>'occurred_on')::date, CURRENT_DATE),
        NULLIF(p_payload->>'subscription_id', '')::uuid,
        NULLIF(p_payload->>'event_booking_id', '')::uuid,
        v_member_fee_id,
        NULLIF(p_payload->>'booking_id', '')::uuid,
        COALESCE((p_payload->>'is_commercial')::boolean, false),
        NULLIF(btrim(COALESCE(p_payload->>'description', '')), ''),
        NULLIF(btrim(COALESCE(p_payload->>'note', '')), ''),
        auth.uid()
    )
    RETURNING id INTO v_tx_id;

    -- Se l'incasso è una quota associativa, la quota risulta pagata
    IF v_member_fee_id IS NOT NULL AND v_status = 'paid' THEN
        UPDATE public.member_fees
           SET status = 'paid', paid_at = COALESCE(paid_at, now()), transaction_id = v_tx_id
         WHERE id = v_member_fee_id;
    END IF;

    IF COALESCE((p_payload->>'issue_receipt')::boolean, false) AND v_status = 'paid' THEN
        v_receipt := public.issue_receipt(v_tx_id, NULLIF(btrim(COALESCE(p_payload->>'causale', '')), ''));
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'REGISTERED',
                              'transaction_id', v_tx_id, 'receipt', v_receipt);
END;
$$;

ALTER FUNCTION "public"."staff_register_payment"("jsonb") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_register_payment"("jsonb") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_register_payment"("jsonb") IS
    'Registra un incasso in studio e, se richiesto, emette la ricevuta. È il modulo unico di cui parla E2: stesso gesto per abbonamenti, quote, eventi e donazioni.';

-- 6.5 — Rimborso, sempre deciso a mano (D4).
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
    v_tx            public.transactions%ROWTYPE;
    v_refunded      integer;
    v_refund_id     uuid;
    v_new_status    public.transaction_status;
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

    SELECT COALESCE(SUM(-amount_cents), 0) INTO v_refunded
      FROM public.transactions WHERE refund_of_id = p_transaction_id;

    IF p_amount_cents IS NULL OR p_amount_cents <= 0
       OR p_amount_cents > (v_tx.amount_cents - v_refunded) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT',
                                  'refundable_cents', v_tx.amount_cents - v_refunded);
    END IF;

    INSERT INTO public.transactions (
        client_id, kind, amount_cents, method, source, status, occurred_on,
        refund_of_id, description, note, created_by
    ) VALUES (
        v_tx.client_id, v_tx.kind, -p_amount_cents, v_tx.method, v_tx.source, 'paid', CURRENT_DATE,
        p_transaction_id, 'Rimborso', p_reason, auth.uid()
    )
    RETURNING id INTO v_refund_id;

    v_new_status := CASE
        WHEN (v_refunded + p_amount_cents) >= v_tx.amount_cents THEN 'refunded'
        ELSE 'partially_refunded'
    END::public.transaction_status;

    UPDATE public.transactions SET status = v_new_status WHERE id = p_transaction_id;

    IF v_tx.member_fee_id IS NOT NULL AND v_new_status = 'refunded' THEN
        UPDATE public.member_fees
           SET status = 'refunded', refunded_at = now(), refund_reason = p_reason
         WHERE id = v_tx.member_fee_id;
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'REFUNDED',
                              'refund_transaction_id', v_refund_id, 'status', v_new_status);
END;
$$;

ALTER FUNCTION "public"."staff_refund_transaction"("uuid", integer, "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_refund_transaction"("uuid", integer, "text") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_refund_transaction"("uuid", integer, "text") IS
    'Rimborso totale o parziale, deciso caso per caso dallo staff (D4). Crea una riga a importo negativo collegata all''originale e aggiorna lo stato.';
