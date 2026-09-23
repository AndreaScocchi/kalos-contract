-- Migration 20260923160200: volontari e rimborsi spese (sessione 3, blocco 2)
--
-- Obiettivo: lo statuto (art. 2, 22 e 23) impone due cose che il database oggi non sa rappresentare:
--   1. un REGISTRO DEI VOLONTARI non occasionali, consultabile ed esportabile;
--   2. che ai volontari si rimborsino SOLO spese effettive e documentate. I rimborsi forfettari sono
--      vietati, ed essere volontariə è incompatibile con qualsiasi rapporto retribuito con
--      l'associazione.
--
-- Da qui due conseguenze tecniche:
--   * ogni persona dello staff dichiara se è retribuita o volontaria (`operators.engagement_type`).
--     Il motore dei compensi (blocco 5) calcola solo per chi è retribuitə;
--   * ogni rimborso ha un ALLEGATO OBBLIGATORIO: senza documento non si salva. Non esiste nessun
--     calcolo automatico, perché un importo calcolato sarebbe un forfait.
--
-- Oggi le operatrici sono tutte retribuite (A9): il default della colonna è `paid`, quindi nulla cambia.
--
-- Compatibilità: una colonna nuova con DEFAULT su `operators` (nessuna riga cambia significato) e due
-- tabelle nuove. Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 A9 e §1-bis.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enum
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
    CREATE TYPE "public"."staff_engagement_type" AS ENUM (
        'paid',         -- retribuitə: dipendente o lavoratrice autonoma (art. 21)
        'volunteer'     -- volontariə: mai retribuitə, solo rimborsi documentati (art. 23)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE "public"."reimbursement_status" AS ENUM (
        'pending',      -- inserito, da approvare
        'approved',     -- approvato, da pagare
        'paid',         -- pagato: diventa un'uscita nelle Finanze
        'rejected'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. operators: retribuitə o volontariə
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."operators"
    ADD COLUMN IF NOT EXISTS "engagement_type" "public"."staff_engagement_type"
    DEFAULT 'paid'::"public"."staff_engagement_type" NOT NULL;

COMMENT ON COLUMN "public"."operators"."engagement_type" IS
    'Retribuitə o volontariə. I compensi si calcolano solo per chi è retribuitə; ai volontari spettano solo rimborsi spese documentati (art. 23 dello statuto).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. volunteers — il registro
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."volunteers" (
    "id"                "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "full_name"         "text"  NOT NULL,
    "fiscal_code"       "text",
    "client_id"         "uuid",
    "operator_id"       "uuid",
    "started_on"        "date"  NOT NULL,
    "ended_on"          "date",
    "is_occasional"     boolean DEFAULT false NOT NULL,
    "activity_note"     "text",
    "insurance_note"    "text",
    "created_by"        "uuid",
    "created_at"        timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"        timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "volunteers_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "volunteers_client_id_fkey"
        FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL,
    CONSTRAINT "volunteers_operator_id_fkey"
        FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE SET NULL,
    CONSTRAINT "volunteers_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "volunteers_name_not_empty" CHECK ("length"("btrim"("full_name")) > 0),
    CONSTRAINT "volunteers_ended_after_started" CHECK ("ended_on" IS NULL OR "ended_on" >= "started_on")
);

ALTER TABLE "public"."volunteers" OWNER TO "postgres";

COMMENT ON TABLE "public"."volunteers" IS
    'Registro dei volontari (art. 22 dello statuto). Il registro obbligatorio riguarda i volontari NON occasionali: `is_occasional` distingue gli altri, che restano annotati ma fuori dall''obbligo.';
COMMENT ON COLUMN "public"."volunteers"."full_name" IS
    'Nome e cognome, conservati qui anche quando la persona è collegata a una scheda cliente o a un''operatrice: il registro deve restare leggibile per sé.';
COMMENT ON COLUMN "public"."volunteers"."insurance_note" IS
    'Estremi della copertura assicurativa, quando ci sarà (domanda 3.5 al commercialista).';

CREATE INDEX IF NOT EXISTS "idx_volunteers_active"
    ON "public"."volunteers" ("started_on") WHERE "ended_on" IS NULL;

CREATE OR REPLACE TRIGGER "volunteers_updated_at"
    BEFORE UPDATE ON "public"."volunteers"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. volunteer_reimbursements — solo spese documentate
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."volunteer_reimbursements" (
    "id"                "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "volunteer_id"      "uuid"      NOT NULL,
    "spent_on"          "date"      NOT NULL,
    "amount_cents"      integer     NOT NULL,
    "description"       "text"      NOT NULL,
    "attachment_path"   "text"      NOT NULL,
    "status"            "public"."reimbursement_status" DEFAULT 'pending'::"public"."reimbursement_status" NOT NULL,
    "approved_by"       "uuid",
    "approved_at"       timestamp with time zone,
    "paid_at"           timestamp with time zone,
    "rejection_reason"  "text",
    "expense_id"        "uuid",
    "note"              "text",
    "created_by"        "uuid",
    "created_at"        timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"        timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "volunteer_reimbursements_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "volunteer_reimbursements_volunteer_id_fkey"
        FOREIGN KEY ("volunteer_id") REFERENCES "public"."volunteers"("id") ON DELETE RESTRICT,
    CONSTRAINT "volunteer_reimbursements_approved_by_fkey"
        FOREIGN KEY ("approved_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "volunteer_reimbursements_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "volunteer_reimbursements_amount_positive" CHECK ("amount_cents" > 0),
    -- Statuto art. 23: spese effettive e documentate. Senza documento non è un rimborso ammissibile.
    CONSTRAINT "volunteer_reimbursements_attachment_required"
        CHECK ("length"("btrim"("attachment_path")) > 0),
    CONSTRAINT "volunteer_reimbursements_description_not_empty"
        CHECK ("length"("btrim"("description")) > 0),
    CONSTRAINT "volunteer_reimbursements_approved_needs_date"
        CHECK ("status" NOT IN ('approved'::"public"."reimbursement_status",
                                'paid'::"public"."reimbursement_status")
               OR "approved_at" IS NOT NULL),
    CONSTRAINT "volunteer_reimbursements_paid_needs_date"
        CHECK ("status" <> 'paid'::"public"."reimbursement_status" OR "paid_at" IS NOT NULL),
    CONSTRAINT "volunteer_reimbursements_rejected_needs_reason"
        CHECK ("status" <> 'rejected'::"public"."reimbursement_status"
               OR "length"("btrim"(COALESCE("rejection_reason", ''))) > 0)
);

ALTER TABLE "public"."volunteer_reimbursements" OWNER TO "postgres";

COMMENT ON TABLE "public"."volunteer_reimbursements" IS
    'Rimborsi spese ai volontari: solo spese effettive e documentate (art. 23). Nessun importo viene mai calcolato in automatico, perché sarebbe un forfait, che lo statuto vieta. Una volta pagato, il rimborso diventa un''uscita nelle Finanze.';
COMMENT ON COLUMN "public"."volunteer_reimbursements"."attachment_path" IS
    'Percorso del documento di spesa nello Storage. Obbligatorio per vincolo, non solo per convenzione.';
COMMENT ON COLUMN "public"."volunteer_reimbursements"."expense_id" IS
    'Uscita generata al pagamento. Il vincolo di chiave esterna lo aggiunge la migrazione delle uscite.';

CREATE INDEX IF NOT EXISTS "idx_volunteer_reimbursements_status"
    ON "public"."volunteer_reimbursements" ("status", "spent_on");

CREATE OR REPLACE TRIGGER "volunteer_reimbursements_updated_at"
    BEFORE UPDATE ON "public"."volunteer_reimbursements"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RLS e grant
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."volunteers"               ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."volunteer_reimbursements" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "volunteers_all_staff" ON "public"."volunteers";
CREATE POLICY "volunteers_all_staff" ON "public"."volunteers"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- I rimborsi contengono importi: li vedono solo admin e Tesoriere, come le Finanze (E3).
DROP POLICY IF EXISTS "volunteer_reimbursements_all_finance" ON "public"."volunteer_reimbursements";
CREATE POLICY "volunteer_reimbursements_all_finance" ON "public"."volunteer_reimbursements"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."volunteers"               TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."volunteer_reimbursements" TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. View: registro dei volontari da esportare
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW "public"."volunteer_registry"
    WITH ("security_invoker" = true) AS
SELECT
    v.id                AS volunteer_id,
    v.full_name,
    v.fiscal_code,
    v.started_on,
    v.ended_on,
    v.is_occasional,
    v.activity_note,
    v.insurance_note,
    (v.ended_on IS NULL) AS is_active
FROM public.volunteers v
WHERE v.is_occasional = false;

ALTER VIEW "public"."volunteer_registry" OWNER TO "postgres";
COMMENT ON VIEW "public"."volunteer_registry" IS
    'Registro dei volontari non occasionali (art. 22), pronto da esportare. `security_invoker`: lo vede solo chi ha già il permesso sulla tabella sotto.';

GRANT SELECT ON TABLE "public"."volunteer_registry" TO "authenticated";
