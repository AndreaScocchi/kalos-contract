-- Migration 20260923160400: uscite — categorie modificabili, spese ricorrenti, allegati
-- (sessione 3, blocco 4)
--
-- Obiettivo: oggi `expenses` ha una categoria TESTUALE vincolata da un CHECK a otto valori scritti nel
-- database, nessun allegato, nessuna ricorrenza, e dall'interfaccia è in sola lettura. Il rendiconto
-- dell'art. 18 vorrà categorie decise dal commercialista (domanda 4.1), che devono potersi cambiare
-- senza una migrazione.
--
-- Come si fa senza rompere niente:
--   * il CHECK sulla colonna `category` NON si tocca — toglierlo sarebbe distruttivo e il gestionale
--     legge ancora quella colonna. Resta, popolata con uno degli otto valori storici;
--   * la verità nuova è `category_id`, che punta a `expense_categories`, una tabella di righe
--     modificabili. Le uscite generate in automatico (commissioni Stripe, rimborsi ai volontari,
--     compensi pagati) scrivono `category = 'other'` o `'staff_compensation'` e la categoria vera in
--     `category_id`;
--   * `source` dice CHI ha creato l'uscita, così le Finanze possono distinguere quello che è stato
--     inserito a mano da quello che è arrivato da solo.
--
-- Le spese ricorrenti non si registrano da sole: ogni mese compaiono "da confermare" con l'importo
-- modificabile (E5). `confirmed_at` è quello che le rende vere.
--
-- Compatibilità: colonne nuove sempre NULL o con DEFAULT, tabelle nuove, nessun vincolo esistente
-- toccato. Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 E5, E7 e docs/DOMANDE-COMMERCIALISTA.md 4.1.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enum
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
    CREATE TYPE "public"."expense_source" AS ENUM (
        'manual',       -- inserita a mano dal gestionale
        'recurring',    -- generata da una spesa ricorrente, da confermare
        'payout',       -- compenso segnato come pagato (E7)
        'stripe_fee',   -- commissione di un pagamento online (H5)
        'volunteer'     -- rimborso spese a unə volontariə (art. 23)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. expense_categories
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."expense_categories" (
    "id"                    "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "slug"                  "text"  NOT NULL,
    "name"                  "text"  NOT NULL,
    "description"           "text",
    "legacy_category"       "text",
    "rendiconto_bucket"     "text",
    "is_active"             boolean DEFAULT true NOT NULL,
    "display_order"         integer DEFAULT 0 NOT NULL,
    "created_at"            timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"            timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "expense_categories_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "expense_categories_slug_key" UNIQUE ("slug"),
    CONSTRAINT "expense_categories_slug_format" CHECK ("slug" ~ '^[a-z0-9-]+$'),
    CONSTRAINT "expense_categories_name_not_empty" CHECK ("length"("btrim"("name")) > 0)
);

ALTER TABLE "public"."expense_categories" OWNER TO "postgres";

COMMENT ON TABLE "public"."expense_categories" IS
    'Categorie di uscita, modificabili dal gestionale. Si parte da quelle storiche e si allineeranno a quelle del rendiconto indicate dal commercialista (domanda 4.1).';
COMMENT ON COLUMN "public"."expense_categories"."legacy_category" IS
    'Valore corrispondente nella vecchia colonna testuale `expenses.category`, che resta vincolata a otto valori. Serve a tenere le due cose allineate finché il gestionale non passa a `category_id`.';
COMMENT ON COLUMN "public"."expense_categories"."rendiconto_bucket" IS
    'Voce del rendiconto in cui confluisce questa categoria. Da compilare quando il commercialista indica lo schema (4.1).';

CREATE OR REPLACE TRIGGER "expense_categories_updated_at"
    BEFORE UPDATE ON "public"."expense_categories"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

INSERT INTO "public"."expense_categories" ("slug", "name", "legacy_category", "display_order") VALUES
    ('compensi',            'Compensi',                     'staff_compensation', 10),
    ('materiali',           'Materiali',                    'materials',          20),
    ('affitto-sale',        'Affitto sale',                 'location_fee',       30),
    ('affitto',             'Affitto',                      'rent',               40),
    ('utenze',              'Utenze',                       'utilities',          50),
    ('software',            'Software e servizi',           'software',           60),
    ('marketing',           'Marketing e comunicazione',    'marketing',          70),
    ('commissioni',         'Commissioni sui pagamenti',    'other',              80),
    ('rimborsi-volontari',  'Rimborsi spese ai volontari',  'other',              90),
    ('assicurazioni',       'Assicurazioni',                'other',             100),
    ('altro',               'Altro',                        'other',             999)
ON CONFLICT ("slug") DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. recurring_expenses
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."recurring_expenses" (
    "id"                    "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "category_id"           "uuid"      NOT NULL,
    "label"                 "text"      NOT NULL,
    "amount_cents"          integer     NOT NULL,
    "vendor"                "text",
    "day_of_month"          integer     DEFAULT 1 NOT NULL,
    "is_active"             boolean     DEFAULT true NOT NULL,
    "starts_on"             "date"      DEFAULT CURRENT_DATE NOT NULL,
    "ends_on"               "date",
    "last_generated_month"  "date",
    "notes"                 "text",
    "created_by"            "uuid",
    "created_at"            timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"            timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "recurring_expenses_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "recurring_expenses_category_id_fkey"
        FOREIGN KEY ("category_id") REFERENCES "public"."expense_categories"("id") ON DELETE RESTRICT,
    CONSTRAINT "recurring_expenses_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "recurring_expenses_amount_positive" CHECK ("amount_cents" > 0),
    CONSTRAINT "recurring_expenses_day_range" CHECK ("day_of_month" BETWEEN 1 AND 28),
    CONSTRAINT "recurring_expenses_label_not_empty" CHECK ("length"("btrim"("label")) > 0),
    CONSTRAINT "recurring_expenses_ends_after_starts" CHECK ("ends_on" IS NULL OR "ends_on" >= "starts_on")
);

ALTER TABLE "public"."recurring_expenses" OWNER TO "postgres";

COMMENT ON TABLE "public"."recurring_expenses" IS
    'Spese che tornano ogni mese (affitto, utenze, software). Non si registrano da sole: generano un''uscita "da confermare" con importo modificabile (E5).';
COMMENT ON COLUMN "public"."recurring_expenses"."day_of_month" IS
    'Giorno del mese, al massimo il 28 così esiste in febbraio senza casi particolari.';
COMMENT ON COLUMN "public"."recurring_expenses"."last_generated_month" IS
    'Primo giorno dell''ultimo mese già generato: evita di creare due volte la stessa spesa.';

CREATE OR REPLACE TRIGGER "recurring_expenses_updated_at"
    BEFORE UPDATE ON "public"."recurring_expenses"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. expenses: colonne nuove
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."expenses"
    ADD COLUMN IF NOT EXISTS "category_id" "uuid",
    ADD COLUMN IF NOT EXISTS "attachment_path" "text",
    ADD COLUMN IF NOT EXISTS "recurring_expense_id" "uuid",
    ADD COLUMN IF NOT EXISTS "confirmed_at" timestamp with time zone,
    ADD COLUMN IF NOT EXISTS "payout_id" "uuid",
    ADD COLUMN IF NOT EXISTS "volunteer_reimbursement_id" "uuid",
    ADD COLUMN IF NOT EXISTS "source" "public"."expense_source"
        DEFAULT 'manual'::"public"."expense_source" NOT NULL;

DO $$ BEGIN
    ALTER TABLE "public"."expenses"
        ADD CONSTRAINT "expenses_category_id_fkey"
        FOREIGN KEY ("category_id") REFERENCES "public"."expense_categories"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE "public"."expenses"
        ADD CONSTRAINT "expenses_recurring_expense_id_fkey"
        FOREIGN KEY ("recurring_expense_id") REFERENCES "public"."recurring_expenses"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE "public"."expenses"
        ADD CONSTRAINT "expenses_payout_id_fkey"
        FOREIGN KEY ("payout_id") REFERENCES "public"."payouts"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE "public"."expenses"
        ADD CONSTRAINT "expenses_volunteer_reimbursement_id_fkey"
        FOREIGN KEY ("volunteer_reimbursement_id")
        REFERENCES "public"."volunteer_reimbursements"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN "public"."expenses"."category_id" IS
    'Categoria vera dell''uscita. La colonna testuale `category` resta, vincolata agli otto valori storici, finché tutti i consumer non passano di qui.';
COMMENT ON COLUMN "public"."expenses"."confirmed_at" IS
    'Una spesa ricorrente nasce non confermata: finché `confirmed_at` è NULL è una proposta, non un''uscita.';
COMMENT ON COLUMN "public"."expenses"."attachment_path" IS
    'Percorso della foto o del PDF nello Storage. Facoltativo in generale, obbligatorio per i rimborsi ai volontari, dove il vincolo sta su `volunteer_reimbursements`.';
COMMENT ON COLUMN "public"."expenses"."source" IS
    'Chi ha creato l''uscita: a mano, una ricorrenza, un compenso pagato, una commissione Stripe o un rimborso.';

CREATE INDEX IF NOT EXISTS "idx_expenses_category_id" ON "public"."expenses" ("category_id");
CREATE INDEX IF NOT EXISTS "idx_expenses_unconfirmed" ON "public"."expenses" ("expense_date")
    WHERE "confirmed_at" IS NULL;

-- Le uscite già presenti sono tutte inserite a mano e confermate: si allineano alle nuove colonne
-- senza cambiare significato.
UPDATE "public"."expenses" e
   SET "category_id" = c.id
  FROM "public"."expense_categories" c
 WHERE c."legacy_category" = e."category"
   AND c."slug" <> 'altro'
   AND e."category_id" IS NULL;

UPDATE "public"."expenses"
   SET "category_id" = (SELECT id FROM "public"."expense_categories" WHERE "slug" = 'altro')
 WHERE "category_id" IS NULL;

UPDATE "public"."expenses" SET "confirmed_at" = "created_at" WHERE "confirmed_at" IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RLS e grant
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."expense_categories" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."recurring_expenses" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "expense_categories_select_staff" ON "public"."expense_categories";
CREATE POLICY "expense_categories_select_staff" ON "public"."expense_categories"
    FOR SELECT TO "authenticated" USING ("public"."is_staff"());

DROP POLICY IF EXISTS "expense_categories_write_finance" ON "public"."expense_categories";
CREATE POLICY "expense_categories_write_finance" ON "public"."expense_categories"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

DROP POLICY IF EXISTS "recurring_expenses_all_finance" ON "public"."recurring_expenses";
CREATE POLICY "recurring_expenses_all_finance" ON "public"."recurring_expenses"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."expense_categories" TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."recurring_expenses" TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Funzioni
-- ─────────────────────────────────────────────────────────────────────────────

-- 6.1 — Genera le uscite "da confermare" di un mese. La chiamerà un cron o il gestionale all'apertura.
CREATE OR REPLACE FUNCTION "public"."generate_recurring_expenses"("p_month" "date" DEFAULT NULL)
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_month     date := date_trunc('month', COALESCE(p_month, CURRENT_DATE))::date;
    v_rec       public.recurring_expenses%ROWTYPE;
    v_created   integer := 0;
BEGIN
    IF NOT public.can_access_finance() THEN
        RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
    END IF;

    FOR v_rec IN
        SELECT * FROM public.recurring_expenses
         WHERE is_active = true
           AND starts_on <= (v_month + INTERVAL '1 month - 1 day')::date
           AND (ends_on IS NULL OR ends_on >= v_month)
           AND (last_generated_month IS NULL OR last_generated_month < v_month)
    LOOP
        INSERT INTO public.expenses (
            amount_cents, expense_date, category, category_id, vendor, notes,
            is_fixed, source, recurring_expense_id, created_by
        )
        SELECT v_rec.amount_cents,
               v_month + (v_rec.day_of_month - 1),
               COALESCE(c.legacy_category, 'other'),
               v_rec.category_id,
               v_rec.vendor,
               v_rec.label,
               true,
               'recurring',
               v_rec.id,
               auth.uid()
          FROM public.expense_categories c WHERE c.id = v_rec.category_id;

        UPDATE public.recurring_expenses SET last_generated_month = v_month WHERE id = v_rec.id;
        v_created := v_created + 1;
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'month', v_month, 'created', v_created);
END;
$$;

ALTER FUNCTION "public"."generate_recurring_expenses"("date") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."generate_recurring_expenses"("date") TO "authenticated";
COMMENT ON FUNCTION "public"."generate_recurring_expenses"("date") IS
    'Crea le uscite del mese a partire dalle spese ricorrenti, lasciandole DA CONFERMARE. Non registra nulla di definitivo: l''importo si può ancora cambiare (E5).';

-- 6.2 — Conferma un'uscita, eventualmente correggendone l'importo.
CREATE OR REPLACE FUNCTION "public"."confirm_expense"(
    "p_expense_id" "uuid",
    "p_amount_cents" integer DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_amount integer;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    IF p_amount_cents IS NOT NULL AND p_amount_cents <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT');
    END IF;

    UPDATE public.expenses
       SET confirmed_at = now(),
           amount_cents = COALESCE(p_amount_cents, amount_cents)
     WHERE id = p_expense_id AND confirmed_at IS NULL
    RETURNING amount_cents INTO v_amount;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'EXPENSE_NOT_FOUND_OR_ALREADY_CONFIRMED');
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'CONFIRMED', 'amount_cents', v_amount);
END;
$$;

ALTER FUNCTION "public"."confirm_expense"("uuid", integer) OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."confirm_expense"("uuid", integer) TO "authenticated";
COMMENT ON FUNCTION "public"."confirm_expense"("uuid", integer) IS
    'Conferma un''uscita proposta da una spesa ricorrente, con la possibilità di correggere l''importo.';

-- 6.3 — Un rimborso pagato diventa un'uscita (art. 23 + E7).
CREATE OR REPLACE FUNCTION "public"."staff_pay_volunteer_reimbursement"("p_reimbursement_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_r             public.volunteer_reimbursements%ROWTYPE;
    v_category_id   uuid;
    v_expense_id    uuid;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    SELECT * INTO v_r FROM public.volunteer_reimbursements WHERE id = p_reimbursement_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'REIMBURSEMENT_NOT_FOUND');
    END IF;

    IF v_r.status = 'paid' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_PAID');
    END IF;

    IF v_r.status = 'rejected' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'REIMBURSEMENT_REJECTED');
    END IF;

    SELECT id INTO v_category_id FROM public.expense_categories WHERE slug = 'rimborsi-volontari';

    INSERT INTO public.expenses (
        amount_cents, expense_date, category, category_id, notes,
        attachment_path, source, volunteer_reimbursement_id, confirmed_at, created_by
    )
    SELECT v_r.amount_cents, v_r.spent_on, 'other', v_category_id,
           'Rimborso spese: ' || v_r.description || ' — ' || v.full_name,
           v_r.attachment_path, 'volunteer', v_r.id, now(), auth.uid()
      FROM public.volunteers v WHERE v.id = v_r.volunteer_id
    RETURNING id INTO v_expense_id;

    UPDATE public.volunteer_reimbursements
       SET status = 'paid',
           approved_at = COALESCE(approved_at, now()),
           approved_by = COALESCE(approved_by, auth.uid()),
           paid_at = now(),
           expense_id = v_expense_id
     WHERE id = p_reimbursement_id;

    RETURN jsonb_build_object('ok', true, 'reason', 'PAID', 'expense_id', v_expense_id);
END;
$$;

ALTER FUNCTION "public"."staff_pay_volunteer_reimbursement"("uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_pay_volunteer_reimbursement"("uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_pay_volunteer_reimbursement"("uuid") IS
    'Segna pagato un rimborso spese a unə volontariə e crea l''uscita corrispondente, con lo stesso documento allegato.';
