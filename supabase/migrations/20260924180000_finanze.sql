-- Migration 20260924180000: Finanze (sessione 7)
--
-- La sessione 3 ha messo nel database il registro degli incassi, le uscite con categorie e
-- ricorrenze, i compensi a mattoni. Qui si completa quello che serve perché le Finanze del
-- gestionale diano numeri CORRETTI per un'associazione che deve presentare un rendiconto per cassa
-- (art. 18 dello statuto, art. 13 del Codice del Terzo Settore):
--
--   1. RENDICONTO. Le voci del rendiconto per cassa degli ETS (Modello D del DM 5 marzo 2020) sono
--      una tabella, `rendiconto_voci`. Ogni categoria di uscita punta a una voce (modificabile dal
--      gestionale); le entrate hanno una voce calcolata dal tipo di incasso e da CHI paga: per
--      un'APS la differenza fra associatə e terzi è quella che conta (art. 85 del Codice). Si può
--      sempre indicare a mano una voce diversa, riga per riga.
--   2. CASSA E BANCA. Il Modello D chiude con i saldi di cassa e banca. Per questo anche le uscite
--      hanno un metodo di pagamento, esistono i giroconti (versare i contanti in banca) e i saldi
--      iniziali del 19/08/2026. I pagamenti con carta (Stripe) contano in banca dal giorno del
--      pagamento: Stripe li versa sul conto qualche giorno dopo.
--   3. USCITE. Il gestionale scrive `category_id` e il database tiene allineata da solo la vecchia
--      colonna testuale. Le uscite nate da sole (compensi, commissioni Stripe, rimborsi ai
--      volontari) non si cambiano né si cancellano dall'API: si correggono dalla loro origine. Le
--      spese ricorrenti recuperano i mesi saltati invece di perderli, e la conferma permette di
--      correggere anche data e metodo (per cassa conta il giorno in cui il denaro esce).
--   4. COMPENSI. Un pagamento per persona e per mese, datato il giorno del pagamento, invece di
--      un'uscita per ogni lezione a fine mese. Con la RITENUTA D'ACCONTO impostabile per persona
--      (20% per le prestazioni occasionali, 0 per chi fattura in regime forfettario): il netto è
--      un'uscita subito, la ritenuta un'uscita "da confermare" con scadenza il 16 del mese dopo,
--      quando si paga l'F24. Si congelano solo le lezioni già fatte, e un mese congelato si riapre
--      finché non è pagato. Il calcolo usa i confini del mese in ora italiana e la durata vera
--      della lezione. I modelli si salvano in un colpo solo (modello, mattoni, scaglioni).
--   5. ENTRATE PER ATTIVITÀ: un abbonamento si divide fra le attività in proporzione alle lezioni
--      prenotate con quell'abbonamento (deciso il 24/09). Finché non ne ha, resta "non ancora
--      usato".
--
-- Cosa NON si decide qui: gli importi, i modelli dei compensi (E6: nessuno preimpostato), le
-- ritenute delle singole persone. Sono dati, modificabili dal gestionale.
--
-- Compatibilità: tabelle, colonne con DEFAULT, funzioni e trigger nuovi. Cambiano firma tre funzioni
-- delle Finanze che nessun'app chiama ancora (`confirm_expense`, `calculate_compensation_v2`, che
-- aggiunge `activity_id` all'uscita) o che il gestionale chiama con i soli parametri già esistenti
-- (`staff_pay_volunteer_reimbursement`). Sparisce `staff_mark_compensation_paid`, mai usata: la
-- sostituisce `staff_pay_compensation`.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 E5–E8 e §0-septies.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enum
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
    CREATE TYPE "public"."cash_account" AS ENUM (
        'cash',     -- contanti in cassa
        'bank'      -- conto corrente, compresi i pagamenti con carta incassati da Stripe
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. rendiconto_voci — lo schema del rendiconto per cassa (Modello D)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."rendiconto_voci" (
    "code"          "text"      NOT NULL,
    "kind"          "text"      NOT NULL,
    "section"       "text"      NOT NULL,
    "section_label" "text"      NOT NULL,
    "number"        integer,
    "label"         "text"      NOT NULL,
    "position"      integer     NOT NULL,

    CONSTRAINT "rendiconto_voci_pkey" PRIMARY KEY ("code"),
    CONSTRAINT "rendiconto_voci_kind_check" CHECK ("kind" IN ('entrata', 'uscita'))
);

ALTER TABLE "public"."rendiconto_voci" OWNER TO "postgres";

COMMENT ON TABLE "public"."rendiconto_voci" IS
    'Voci del rendiconto per cassa degli enti del Terzo Settore (Modello D, DM 5 marzo 2020). Le categorie di uscita e le entrate puntano qui; l''export del gestionale segue quest''ordine. Proposta in attesa della conferma del commercialista (domanda 4.1).';
COMMENT ON COLUMN "public"."rendiconto_voci"."section" IS
    'A–E come nel modello; IMP = imposte; INV e DIS = investimenti e disinvestimenti, che stanno sotto il risultato della gestione.';

INSERT INTO "public"."rendiconto_voci" ("code", "kind", "section", "section_label", "number", "label", "position") VALUES
    -- Uscite
    ('U-A1', 'uscita', 'A', 'A) Uscite da attività di interesse generale', 1, 'Materie prime, sussidiarie, di consumo e di merci', 101),
    ('U-A2', 'uscita', 'A', 'A) Uscite da attività di interesse generale', 2, 'Servizi', 102),
    ('U-A3', 'uscita', 'A', 'A) Uscite da attività di interesse generale', 3, 'Godimento beni di terzi', 103),
    ('U-A4', 'uscita', 'A', 'A) Uscite da attività di interesse generale', 4, 'Personale', 104),
    ('U-A5', 'uscita', 'A', 'A) Uscite da attività di interesse generale', 5, 'Uscite diverse di gestione', 105),
    ('U-B1', 'uscita', 'B', 'B) Uscite da attività diverse', 1, 'Materie prime, sussidiarie, di consumo e di merci', 111),
    ('U-B2', 'uscita', 'B', 'B) Uscite da attività diverse', 2, 'Servizi', 112),
    ('U-B3', 'uscita', 'B', 'B) Uscite da attività diverse', 3, 'Godimento beni di terzi', 113),
    ('U-B4', 'uscita', 'B', 'B) Uscite da attività diverse', 4, 'Personale', 114),
    ('U-B5', 'uscita', 'B', 'B) Uscite da attività diverse', 5, 'Uscite diverse di gestione', 115),
    ('U-C1', 'uscita', 'C', 'C) Uscite da attività di raccolta fondi', 1, 'Uscite per raccolte fondi abituali', 121),
    ('U-C2', 'uscita', 'C', 'C) Uscite da attività di raccolta fondi', 2, 'Uscite per raccolte fondi occasionali', 122),
    ('U-C3', 'uscita', 'C', 'C) Uscite da attività di raccolta fondi', 3, 'Altre uscite', 123),
    ('U-D1', 'uscita', 'D', 'D) Uscite da attività finanziarie e patrimoniali', 1, 'Su rapporti bancari', 131),
    ('U-D2', 'uscita', 'D', 'D) Uscite da attività finanziarie e patrimoniali', 2, 'Su investimenti finanziari', 132),
    ('U-D3', 'uscita', 'D', 'D) Uscite da attività finanziarie e patrimoniali', 3, 'Su patrimonio edilizio', 133),
    ('U-D4', 'uscita', 'D', 'D) Uscite da attività finanziarie e patrimoniali', 4, 'Su altri beni patrimoniali', 134),
    ('U-D5', 'uscita', 'D', 'D) Uscite da attività finanziarie e patrimoniali', 5, 'Altre uscite', 135),
    ('U-E1', 'uscita', 'E', 'E) Uscite di supporto generale', 1, 'Materie prime, sussidiarie, di consumo e di merci', 141),
    ('U-E2', 'uscita', 'E', 'E) Uscite di supporto generale', 2, 'Servizi', 142),
    ('U-E3', 'uscita', 'E', 'E) Uscite di supporto generale', 3, 'Godimento beni di terzi', 143),
    ('U-E4', 'uscita', 'E', 'E) Uscite di supporto generale', 4, 'Personale', 144),
    ('U-E5', 'uscita', 'E', 'E) Uscite di supporto generale', 5, 'Altre uscite', 145),
    ('U-IMP', 'uscita', 'IMP', 'Imposte', NULL, 'Imposte', 151),
    ('U-INV1', 'uscita', 'INV', 'Uscite da investimenti in immobilizzazioni o da deflussi di capitale di terzi', 1, 'Investimenti in immobilizzazioni inerenti alle attività di interesse generale', 161),
    ('U-INV2', 'uscita', 'INV', 'Uscite da investimenti in immobilizzazioni o da deflussi di capitale di terzi', 2, 'Investimenti in immobilizzazioni inerenti alle attività diverse', 162),
    ('U-INV3', 'uscita', 'INV', 'Uscite da investimenti in immobilizzazioni o da deflussi di capitale di terzi', 3, 'Investimenti in attività finanziarie e patrimoniali', 163),
    ('U-INV4', 'uscita', 'INV', 'Uscite da investimenti in immobilizzazioni o da deflussi di capitale di terzi', 4, 'Rimborso di finanziamenti per quota capitale e di prestiti', 164),
    -- Entrate
    ('E-A1',  'entrata', 'A', 'A) Entrate da attività di interesse generale', 1, 'Entrate da quote associative e apporti dei fondatori', 201),
    ('E-A2',  'entrata', 'A', 'A) Entrate da attività di interesse generale', 2, 'Entrate dagli associati per attività mutuali', 202),
    ('E-A3',  'entrata', 'A', 'A) Entrate da attività di interesse generale', 3, 'Entrate per prestazioni e cessioni ad associati e fondatori', 203),
    ('E-A4',  'entrata', 'A', 'A) Entrate da attività di interesse generale', 4, 'Erogazioni liberali', 204),
    ('E-A5',  'entrata', 'A', 'A) Entrate da attività di interesse generale', 5, 'Entrate del 5 per mille', 205),
    ('E-A6',  'entrata', 'A', 'A) Entrate da attività di interesse generale', 6, 'Contributi da soggetti privati', 206),
    ('E-A7',  'entrata', 'A', 'A) Entrate da attività di interesse generale', 7, 'Entrate per prestazioni e cessioni a terzi', 207),
    ('E-A8',  'entrata', 'A', 'A) Entrate da attività di interesse generale', 8, 'Contributi da enti pubblici', 208),
    ('E-A9',  'entrata', 'A', 'A) Entrate da attività di interesse generale', 9, 'Entrate da contratti con enti pubblici', 209),
    ('E-A10', 'entrata', 'A', 'A) Entrate da attività di interesse generale', 10, 'Altre entrate', 210),
    ('E-B1',  'entrata', 'B', 'B) Entrate da attività diverse', 1, 'Entrate per prestazioni e cessioni ad associati e fondatori', 211),
    ('E-B2',  'entrata', 'B', 'B) Entrate da attività diverse', 2, 'Contributi da soggetti privati', 212),
    ('E-B3',  'entrata', 'B', 'B) Entrate da attività diverse', 3, 'Entrate per prestazioni e cessioni a terzi', 213),
    ('E-B4',  'entrata', 'B', 'B) Entrate da attività diverse', 4, 'Contributi da enti pubblici', 214),
    ('E-B5',  'entrata', 'B', 'B) Entrate da attività diverse', 5, 'Entrate da contratti con enti pubblici', 215),
    ('E-B6',  'entrata', 'B', 'B) Entrate da attività diverse', 6, 'Altre entrate', 216),
    ('E-C1',  'entrata', 'C', 'C) Entrate da attività di raccolta fondi', 1, 'Entrate da raccolte fondi abituali', 221),
    ('E-C2',  'entrata', 'C', 'C) Entrate da attività di raccolta fondi', 2, 'Entrate da raccolte fondi occasionali', 222),
    ('E-C3',  'entrata', 'C', 'C) Entrate da attività di raccolta fondi', 3, 'Altre entrate', 223),
    ('E-D1',  'entrata', 'D', 'D) Entrate da attività finanziarie e patrimoniali', 1, 'Da rapporti bancari', 231),
    ('E-D2',  'entrata', 'D', 'D) Entrate da attività finanziarie e patrimoniali', 2, 'Da altri investimenti finanziari', 232),
    ('E-D3',  'entrata', 'D', 'D) Entrate da attività finanziarie e patrimoniali', 3, 'Da patrimonio edilizio', 233),
    ('E-D4',  'entrata', 'D', 'D) Entrate da attività finanziarie e patrimoniali', 4, 'Da altri beni patrimoniali', 234),
    ('E-D5',  'entrata', 'D', 'D) Entrate da attività finanziarie e patrimoniali', 5, 'Altre entrate', 235),
    ('E-E1',  'entrata', 'E', 'E) Entrate di supporto generale', 1, 'Entrate da distacco del personale', 241),
    ('E-E2',  'entrata', 'E', 'E) Entrate di supporto generale', 2, 'Altre entrate di supporto generale', 242),
    ('E-DIS1', 'entrata', 'DIS', 'Entrate da disinvestimenti in immobilizzazioni o da flussi di capitale di terzi', 1, 'Disinvestimenti di immobilizzazioni inerenti alle attività di interesse generale', 261),
    ('E-DIS2', 'entrata', 'DIS', 'Entrate da disinvestimenti in immobilizzazioni o da flussi di capitale di terzi', 2, 'Disinvestimenti di immobilizzazioni inerenti alle attività diverse', 262),
    ('E-DIS3', 'entrata', 'DIS', 'Entrate da disinvestimenti in immobilizzazioni o da flussi di capitale di terzi', 3, 'Disinvestimenti di attività finanziarie e patrimoniali', 263),
    ('E-DIS4', 'entrata', 'DIS', 'Entrate da disinvestimenti in immobilizzazioni o da flussi di capitale di terzi', 4, 'Ricevimento di finanziamenti e di prestiti', 264)
ON CONFLICT ("code") DO NOTHING;

ALTER TABLE "public"."rendiconto_voci" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rendiconto_voci_select_finance" ON "public"."rendiconto_voci";
CREATE POLICY "rendiconto_voci_select_finance" ON "public"."rendiconto_voci"
    FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());

-- Sola lettura: lo schema del rendiconto cambia con una migrazione, non dall'interfaccia.
GRANT SELECT ON TABLE "public"."rendiconto_voci" TO "authenticated";

-- Una voce di entrata non può finire su un'uscita e viceversa. Il nome della colonna e il tipo
-- atteso arrivano dagli argomenti del trigger, così lo stesso controllo vale per tre tabelle.
CREATE OR REPLACE FUNCTION "internal"."check_rendiconto_voce"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_code text := to_jsonb(NEW) ->> TG_ARGV[0];
    v_kind text;
BEGIN
    IF v_code IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT kind INTO v_kind FROM public.rendiconto_voci WHERE code = v_code;
    IF v_kind IS DISTINCT FROM TG_ARGV[1] THEN
        RAISE EXCEPTION 'RENDICONTO_VOCE_KIND_MISMATCH'
            USING ERRCODE = 'P0001',
                  DETAIL = format('La voce %s non è una voce di %s.', v_code, TG_ARGV[1]);
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION "internal"."check_rendiconto_voce"() OWNER TO "postgres";

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Categorie di uscita: voci del rendiconto e categorie che mancavano
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO "public"."expense_categories" ("slug", "name", "legacy_category", "display_order", "description") VALUES
    ('consulenze',     'Consulenze e amministrazione', 'other', 65,  'Commercialista, consulente del lavoro, notaio, spese di segreteria.'),
    ('spese-bancarie', 'Spese bancarie',               'other', 85,  'Canone e commissioni del conto corrente.'),
    ('imposte',        'Imposte e tasse',              'other', 110, 'Imposte dell''associazione (non le ritenute sui compensi, che stanno nei compensi).'),
    ('investimenti',   'Attrezzature durevoli',        'other', 120, 'Beni che durano più anni (arredi, impianti, attrezzature): nel rendiconto sono investimenti, non uscite della gestione.')
ON CONFLICT ("slug") DO NOTHING;

-- Proposta di partenza, modificabile da Finanze → Uscite → Categorie. Solo dove la voce manca: se
-- qualcuno l'ha già scelta, resta la sua.
UPDATE "public"."expense_categories" c
   SET "rendiconto_bucket" = m.code
  FROM (VALUES
      ('compensi',           'U-A4'),
      ('materiali',          'U-A1'),
      ('affitto-sale',       'U-A3'),
      ('affitto',            'U-A3'),
      ('utenze',             'U-A2'),
      ('software',           'U-E2'),
      ('consulenze',         'U-E2'),
      ('marketing',          'U-A2'),
      ('commissioni',        'U-D1'),
      ('spese-bancarie',     'U-D1'),
      ('rimborsi-volontari', 'U-A5'),
      ('assicurazioni',      'U-A2'),
      ('imposte',            'U-IMP'),
      ('investimenti',       'U-INV1'),
      ('altro',              'U-A5')
  ) AS m(slug, code)
 WHERE c.slug = m.slug
   AND c.rendiconto_bucket IS NULL;

DO $$ BEGIN
    ALTER TABLE "public"."expense_categories"
        ADD CONSTRAINT "expense_categories_rendiconto_bucket_fkey"
        FOREIGN KEY ("rendiconto_bucket") REFERENCES "public"."rendiconto_voci"("code") ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DROP TRIGGER IF EXISTS "expense_categories_check_voce" ON "public"."expense_categories";
CREATE TRIGGER "expense_categories_check_voce"
    BEFORE INSERT OR UPDATE OF "rendiconto_bucket" ON "public"."expense_categories"
    FOR EACH ROW EXECUTE FUNCTION "internal"."check_rendiconto_voce"('rendiconto_bucket', 'uscita');

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Cassa e banca: saldi iniziali, metodo sulle uscite, giroconti
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."association_settings"
    ADD COLUMN IF NOT EXISTS "opening_cash_cents" integer DEFAULT 0 NOT NULL,
    ADD COLUMN IF NOT EXISTS "opening_bank_cents" integer DEFAULT 0 NOT NULL;

COMMENT ON COLUMN "public"."association_settings"."opening_cash_cents" IS
    'Contanti in cassa all''inizio della contabilità (`ledger_start_date`). Da lì in poi il saldo si calcola dai movimenti.';
COMMENT ON COLUMN "public"."association_settings"."opening_bank_cents" IS
    'Saldo del conto all''inizio della contabilità (`ledger_start_date`).';

ALTER TABLE "public"."expenses"
    ADD COLUMN IF NOT EXISTS "payment_method" "public"."payment_method"
        DEFAULT 'bank_transfer'::"public"."payment_method" NOT NULL,
    ADD COLUMN IF NOT EXISTS "rendiconto_voce" "text";

COMMENT ON COLUMN "public"."expenses"."payment_method" IS
    'Come è uscito il denaro: contanti (cassa) o dal conto (bonifico, addebito, carta). Stripe = commissione trattenuta da Stripe sugli incassi con carta.';
COMMENT ON COLUMN "public"."expenses"."rendiconto_voce" IS
    'Voce del rendiconto scelta a mano per questa uscita. NULL = quella della categoria.';

DO $$ BEGIN
    ALTER TABLE "public"."expenses"
        ADD CONSTRAINT "expenses_rendiconto_voce_fkey"
        FOREIGN KEY ("rendiconto_voce") REFERENCES "public"."rendiconto_voci"("code") ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Un'uscita è sempre un importo positivo: i soldi che tornano indietro sono un'entrata.
DO $$ BEGIN
    ALTER TABLE "public"."expenses"
        ADD CONSTRAINT "expenses_amount_positive" CHECK ("amount_cents" > 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE "public"."recurring_expenses"
    ADD COLUMN IF NOT EXISTS "payment_method" "public"."payment_method"
        DEFAULT 'bank_transfer'::"public"."payment_method" NOT NULL;

COMMENT ON COLUMN "public"."recurring_expenses"."payment_method" IS
    'Metodo con cui si paga di solito: le uscite generate partono da qui e si può correggere alla conferma.';

ALTER TABLE "public"."transactions"
    ADD COLUMN IF NOT EXISTS "rendiconto_voce" "text";

COMMENT ON COLUMN "public"."transactions"."rendiconto_voce" IS
    'Voce del rendiconto scelta a mano (es. contributo di un ente pubblico, 5 per mille). NULL = calcolata da tipo di incasso e stato di sociə alla data (`internal.income_voce`).';

DO $$ BEGIN
    ALTER TABLE "public"."transactions"
        ADD CONSTRAINT "transactions_rendiconto_voce_fkey"
        FOREIGN KEY ("rendiconto_voce") REFERENCES "public"."rendiconto_voci"("code") ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DROP TRIGGER IF EXISTS "transactions_check_voce" ON "public"."transactions";
CREATE TRIGGER "transactions_check_voce"
    BEFORE INSERT OR UPDATE OF "rendiconto_voce" ON "public"."transactions"
    FOR EACH ROW EXECUTE FUNCTION "internal"."check_rendiconto_voce"('rendiconto_voce', 'entrata');

DROP TRIGGER IF EXISTS "expenses_check_voce" ON "public"."expenses";
CREATE TRIGGER "expenses_check_voce"
    BEFORE INSERT OR UPDATE OF "rendiconto_voce" ON "public"."expenses"
    FOR EACH ROW EXECUTE FUNCTION "internal"."check_rendiconto_voce"('rendiconto_voce', 'uscita');

CREATE TABLE IF NOT EXISTS "public"."account_transfers" (
    "id"            "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "occurred_on"   "date"      DEFAULT CURRENT_DATE NOT NULL,
    "from_account"  "public"."cash_account" NOT NULL,
    "to_account"    "public"."cash_account" NOT NULL,
    "amount_cents"  integer     NOT NULL,
    "note"          "text",
    "created_by"    "uuid",
    "created_at"    timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"    timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "account_transfers_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "account_transfers_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "account_transfers_amount_positive" CHECK ("amount_cents" > 0),
    CONSTRAINT "account_transfers_different_accounts" CHECK ("from_account" <> "to_account")
);

ALTER TABLE "public"."account_transfers" OWNER TO "postgres";

COMMENT ON TABLE "public"."account_transfers" IS
    'Giroconti fra cassa e banca (i contanti versati sul conto, un prelievo). Non sono né entrate né uscite: spostano denaro fra i due conti del rendiconto.';

CREATE INDEX IF NOT EXISTS "idx_account_transfers_occurred_on" ON "public"."account_transfers" ("occurred_on");

CREATE OR REPLACE TRIGGER "account_transfers_updated_at"
    BEFORE UPDATE ON "public"."account_transfers"
    FOR EACH ROW EXECUTE FUNCTION "internal"."update_updated_at_column"();

ALTER TABLE "public"."account_transfers" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "account_transfers_all_finance" ON "public"."account_transfers";
CREATE POLICY "account_transfers_all_finance" ON "public"."account_transfers"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."account_transfers" TO "authenticated";

-- Il conto su cui arriva o da cui esce il denaro, dal metodo di pagamento.
CREATE OR REPLACE FUNCTION "internal"."cash_account_for"("p_method" "public"."payment_method")
    RETURNS "public"."cash_account"
    LANGUAGE "sql"
    IMMUTABLE
    AS $$
    SELECT CASE WHEN p_method = 'cash' THEN 'cash' ELSE 'bank' END::public.cash_account;
$$;

ALTER FUNCTION "internal"."cash_account_for"("public"."payment_method") OWNER TO "postgres";

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Uscite: categoria allineata, uscite automatiche protette, delete per il Tesoriere
-- ─────────────────────────────────────────────────────────────────────────────

-- SECURITY INVOKER di proposito: `current_user` distingue chi scrive dall'API (authenticated) dalle
-- funzioni delle Finanze e dai trigger (postgres) e dalle edge function (service_role).
CREATE OR REPLACE FUNCTION "internal"."expenses_before_write"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_from_api boolean := current_user IN ('authenticated', 'anon');
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF v_from_api AND OLD.source IN ('payout', 'stripe_fee', 'volunteer') THEN
            RAISE EXCEPTION 'AUTOMATIC_EXPENSE'
                USING ERRCODE = 'P0001',
                      DETAIL = 'Questa uscita è nata da un compenso, da una commissione o da un rimborso: si annulla dalla sua origine.';
        END IF;
        RETURN OLD;
    END IF;

    IF v_from_api THEN
        IF TG_OP = 'INSERT' AND NEW.source <> 'manual' THEN
            RAISE EXCEPTION 'AUTOMATIC_EXPENSE'
                USING ERRCODE = 'P0001', DETAIL = 'Dall''interfaccia si inseriscono solo uscite a mano.';
        END IF;

        IF TG_OP = 'UPDATE' THEN
            IF NEW.source IS DISTINCT FROM OLD.source THEN
                RAISE EXCEPTION 'AUTOMATIC_EXPENSE'
                    USING ERRCODE = 'P0001', DETAIL = 'L''origine di un''uscita non si cambia.';
            END IF;

            -- Di un'uscita automatica si possono cambiare solo metodo, note, fornitore, allegato e voce
            IF OLD.source IN ('payout', 'stripe_fee', 'volunteer') AND (
                   NEW.amount_cents IS DISTINCT FROM OLD.amount_cents
                OR NEW.expense_date IS DISTINCT FROM OLD.expense_date
                OR NEW.category_id IS DISTINCT FROM OLD.category_id
                OR NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at
                OR NEW.operator_id IS DISTINCT FROM OLD.operator_id
                OR NEW.lesson_id IS DISTINCT FROM OLD.lesson_id
                OR NEW.event_id IS DISTINCT FROM OLD.event_id
                OR NEW.payout_id IS DISTINCT FROM OLD.payout_id
                OR NEW.volunteer_reimbursement_id IS DISTINCT FROM OLD.volunteer_reimbursement_id
                OR NEW.recurring_expense_id IS DISTINCT FROM OLD.recurring_expense_id
            ) THEN
                RAISE EXCEPTION 'AUTOMATIC_EXPENSE'
                    USING ERRCODE = 'P0001',
                          DETAIL = 'Importo, data e categoria di un''uscita automatica si correggono dalla sua origine.';
            END IF;
        END IF;
    END IF;

    -- La vecchia colonna testuale segue la categoria vera: il gestionale scrive solo category_id
    IF NEW.category_id IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.category_id IS DISTINCT FROM OLD.category_id) THEN
        SELECT COALESCE(c.legacy_category, 'other') INTO NEW.category
          FROM public.expense_categories c WHERE c.id = NEW.category_id;
    END IF;

    -- Un'uscita scritta a mano è già vera: solo le ricorrenze e le ritenute nascono da confermare
    IF TG_OP = 'INSERT' AND NEW.source = 'manual' AND NEW.confirmed_at IS NULL THEN
        NEW.confirmed_at := now();
    END IF;

    -- La commissione la trattiene Stripe dall'incasso con carta
    IF NEW.source = 'stripe_fee' THEN
        NEW.payment_method := 'stripe';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        NEW.updated_at := now();
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION "internal"."expenses_before_write"() OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."expenses_before_write"() IS
    'Allinea `expenses.category` a `category_id`, conferma le uscite scritte a mano e impedisce di cambiare dall''API le uscite nate da compensi, commissioni Stripe e rimborsi ai volontari.';

DROP TRIGGER IF EXISTS "expenses_before_write" ON "public"."expenses";
CREATE TRIGGER "expenses_before_write"
    BEFORE INSERT OR UPDATE ON "public"."expenses"
    FOR EACH ROW EXECUTE FUNCTION "internal"."expenses_before_write"();

DROP TRIGGER IF EXISTS "expenses_before_delete" ON "public"."expenses";
CREATE TRIGGER "expenses_before_delete"
    BEFORE DELETE ON "public"."expenses"
    FOR EACH ROW EXECUTE FUNCTION "internal"."expenses_before_write"();

-- Il Tesoriere corregge i propri errori: cancella le uscite scritte a mano e le proposte delle
-- ricorrenze (il trigger qui sopra tiene fuori quelle automatiche). Prima poteva solo l'admin.
DROP POLICY IF EXISTS "expenses_delete_finance" ON "public"."expenses";
CREATE POLICY "expenses_delete_finance" ON "public"."expenses"
    FOR DELETE TO "authenticated" USING ("public"."can_access_finance"());

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Compensi: ritenuta per persona e pagamenti
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."operator_compensation_settings" (
    "operator_id"           "uuid"          NOT NULL,
    "withholding_percent"   numeric(5,2)    DEFAULT 0 NOT NULL,
    "note"                  "text",
    "updated_by"            "uuid",
    "updated_at"            timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "operator_compensation_settings_pkey" PRIMARY KEY ("operator_id"),
    CONSTRAINT "operator_compensation_settings_operator_id_fkey"
        FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE CASCADE,
    CONSTRAINT "operator_compensation_settings_updated_by_fkey"
        FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "operator_compensation_settings_withholding_range"
        CHECK ("withholding_percent" >= 0 AND "withholding_percent" <= 100)
);

ALTER TABLE "public"."operator_compensation_settings" OWNER TO "postgres";

COMMENT ON TABLE "public"."operator_compensation_settings" IS
    'Dati per pagare una persona retribuita. Tabella a parte e solo per le Finanze: `operators` è leggibile dal sito.';
COMMENT ON COLUMN "public"."operator_compensation_settings"."withholding_percent" IS
    'Ritenuta d''acconto trattenuta sul compenso e versata con l''F24 entro il 16 del mese dopo: 20 per le prestazioni occasionali, 0 per chi emette fattura in regime forfettario. Lo decide il commercialista persona per persona.';

CREATE OR REPLACE TRIGGER "operator_compensation_settings_updated_at"
    BEFORE UPDATE ON "public"."operator_compensation_settings"
    FOR EACH ROW EXECUTE FUNCTION "internal"."update_updated_at_column"();

CREATE TABLE IF NOT EXISTS "public"."compensation_payments" (
    "id"                        "uuid"          DEFAULT "gen_random_uuid"() NOT NULL,
    "operator_id"               "uuid"          NOT NULL,
    "period_month"              "date"          NOT NULL,
    "paid_on"                   "date"          NOT NULL,
    "method"                    "public"."payment_method" NOT NULL,
    "entries_cents"             bigint          NOT NULL,
    "gross_cents"               bigint          NOT NULL,
    "withholding_percent"       numeric(5,2)    DEFAULT 0 NOT NULL,
    "withholding_cents"         bigint          DEFAULT 0 NOT NULL,
    "net_cents"                 bigint          NOT NULL,
    "net_expense_id"            "uuid",
    "withholding_expense_id"    "uuid",
    "note"                      "text",
    "created_by"                "uuid",
    "created_at"                timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"                timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "compensation_payments_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "compensation_payments_operator_id_fkey"
        FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE RESTRICT,
    CONSTRAINT "compensation_payments_net_expense_id_fkey"
        FOREIGN KEY ("net_expense_id") REFERENCES "public"."expenses"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_payments_withholding_expense_id_fkey"
        FOREIGN KEY ("withholding_expense_id") REFERENCES "public"."expenses"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_payments_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL,
    CONSTRAINT "compensation_payments_gross_positive" CHECK ("gross_cents" > 0),
    CONSTRAINT "compensation_payments_withholding_range"
        CHECK ("withholding_percent" >= 0 AND "withholding_percent" <= 100),
    CONSTRAINT "compensation_payments_amounts_add_up"
        CHECK ("withholding_cents" >= 0 AND "net_cents" >= 0
               AND "net_cents" + "withholding_cents" = "gross_cents"),
    CONSTRAINT "compensation_payments_period_is_month"
        CHECK ("period_month" = date_trunc('month', "period_month")::date)
);

ALTER TABLE "public"."compensation_payments" OWNER TO "postgres";

COMMENT ON TABLE "public"."compensation_payments" IS
    'Un pagamento a una persona per i compensi congelati di un mese: lordo, ritenuta d''acconto e netto. Il netto è un''uscita del giorno del pagamento; la ritenuta un''uscita da confermare col pagamento dell''F24. Da qui escono anche i totali per la Certificazione Unica.';
COMMENT ON COLUMN "public"."compensation_payments"."entries_cents" IS
    'Somma dei compensi congelati pagati. `gross_cents` di norma coincide; se diverge (per esempio una correzione concordata) la nota è obbligatoria.';

CREATE INDEX IF NOT EXISTS "idx_compensation_payments_operator"
    ON "public"."compensation_payments" ("operator_id", "period_month");
CREATE INDEX IF NOT EXISTS "idx_compensation_payments_paid_on"
    ON "public"."compensation_payments" ("paid_on");

CREATE OR REPLACE TRIGGER "compensation_payments_updated_at"
    BEFORE UPDATE ON "public"."compensation_payments"
    FOR EACH ROW EXECUTE FUNCTION "internal"."update_updated_at_column"();

ALTER TABLE "public"."compensation_entries"
    ADD COLUMN IF NOT EXISTS "payment_id" "uuid";

DO $$ BEGIN
    ALTER TABLE "public"."compensation_entries"
        ADD CONSTRAINT "compensation_entries_payment_id_fkey"
        FOREIGN KEY ("payment_id") REFERENCES "public"."compensation_payments"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN "public"."compensation_entries"."payment_id" IS
    'Il pagamento che ha saldato questo compenso.';

CREATE INDEX IF NOT EXISTS "idx_compensation_entries_payment"
    ON "public"."compensation_entries" ("payment_id") WHERE "payment_id" IS NOT NULL;

ALTER TABLE "public"."operator_compensation_settings" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."compensation_payments"          ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "operator_compensation_settings_all_finance" ON "public"."operator_compensation_settings";
CREATE POLICY "operator_compensation_settings_all_finance" ON "public"."operator_compensation_settings"
    FOR ALL TO "authenticated"
    USING ("public"."can_access_finance"()) WITH CHECK ("public"."can_access_finance"());

-- I pagamenti si leggono dall'interfaccia ma si scrivono solo con le funzioni qui sotto, che tengono
-- insieme pagamento, uscite e compensi.
DROP POLICY IF EXISTS "compensation_payments_select_finance" ON "public"."compensation_payments";
CREATE POLICY "compensation_payments_select_finance" ON "public"."compensation_payments"
    FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."operator_compensation_settings" TO "authenticated";
GRANT SELECT ON TABLE "public"."compensation_payments" TO "authenticated";

-- Anche i compensi congelati si scrivono solo con le funzioni (congela, riapri, paga, annulla):
-- cancellarne uno pagato dall'interfaccia lascerebbe un pagamento che non torna. Nessun'app li
-- scriveva direttamente.
DROP POLICY IF EXISTS "compensation_entries_all_finance" ON "public"."compensation_entries";
DROP POLICY IF EXISTS "compensation_entries_select_finance" ON "public"."compensation_entries";
CREATE POLICY "compensation_entries_select_finance" ON "public"."compensation_entries"
    FOR SELECT TO "authenticated" USING ("public"."can_access_finance"());

-- Una spesa ricorrente riattivata riparte dal mese in corso: i mesi in cui era sospesa non sono
-- spese da recuperare.
CREATE OR REPLACE FUNCTION "internal"."recurring_expenses_on_reactivate"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_previous date := (date_trunc('month', (now() AT TIME ZONE 'Europe/Rome')) - INTERVAL '1 month')::date;
BEGIN
    IF NEW.is_active AND NOT OLD.is_active THEN
        NEW.last_generated_month := GREATEST(COALESCE(OLD.last_generated_month, v_previous), v_previous);
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION "internal"."recurring_expenses_on_reactivate"() OWNER TO "postgres";

DROP TRIGGER IF EXISTS "recurring_expenses_on_reactivate" ON "public"."recurring_expenses";
CREATE TRIGGER "recurring_expenses_on_reactivate"
    BEFORE UPDATE OF "is_active" ON "public"."recurring_expenses"
    FOR EACH ROW EXECUTE FUNCTION "internal"."recurring_expenses_on_reactivate"();

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Entrate: voce del rendiconto, righe e ripartizione per attività
-- ─────────────────────────────────────────────────────────────────────────────

-- Associatə alla data: ammessə entro quel giorno e non ancora cessatə. Chi ha solo la domanda in
-- attesa non è ancora associatə: la delibera del CD è la data che conta (art. 4 dello statuto).
CREATE OR REPLACE FUNCTION "internal"."client_is_member_on"("p_client_id" "uuid", "p_on" "date")
    RETURNS boolean
    LANGUAGE "sql"
    STABLE
    SET "search_path" TO 'public'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.members m
         WHERE m.client_id = p_client_id
           AND m.admitted_on <= p_on
           AND (m.ceased_on IS NULL OR m.ceased_on > p_on)
    );
$$;

ALTER FUNCTION "internal"."client_is_member_on"("uuid", "date") OWNER TO "postgres";

-- Voce del rendiconto di un incasso, se nessuno l'ha scelta a mano.
CREATE OR REPLACE FUNCTION "internal"."income_voce"(
    "p_kind" "public"."transaction_kind",
    "p_is_commercial" boolean,
    "p_is_member" boolean
) RETURNS "text"
    LANGUAGE "sql"
    IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_kind = 'membership_fee' THEN 'E-A1'
        WHEN p_kind = 'donation'       THEN 'E-A4'
        WHEN p_kind = 'commercial' OR (p_is_commercial AND p_kind <> 'other') THEN
            CASE WHEN p_is_member THEN 'E-B1' ELSE 'E-B3' END
        WHEN p_kind IN ('subscription', 'event', 'trial') THEN
            CASE WHEN p_is_member THEN 'E-A3' ELSE 'E-A7' END
        WHEN p_is_commercial THEN 'E-B6'
        ELSE 'E-A10'
    END;
$$;

ALTER FUNCTION "internal"."income_voce"("public"."transaction_kind", boolean, boolean) OWNER TO "postgres";
COMMENT ON FUNCTION "internal"."income_voce"("public"."transaction_kind", boolean, boolean) IS
    'Quote → A1; donazioni → A4; contributi per attività ed eventi → A3 da associatə, A7 da terzi; entrate commerciali → B1/B3; il resto → A10 (B6 se commerciale). Una voce scelta a mano sulla riga vince sempre.';

-- 7.1 — Le entrate del periodo, una riga per incasso (e per rimborso, in negativo).
CREATE OR REPLACE FUNCTION "public"."finance_income_lines"("p_from" "date", "p_to" "date")
    RETURNS TABLE (
        "transaction_id"        "uuid",
        "occurred_on"           "date",
        "kind"                  "public"."transaction_kind",
        "method"                "public"."payment_method",
        "account"               "public"."cash_account",
        "source"                "public"."transaction_source",
        "status"                "public"."transaction_status",
        "amount_cents"          integer,
        "refund_of_id"          "uuid",
        "client_id"             "uuid",
        "client_name"           "text",
        "is_member"             boolean,
        "is_commercial"         boolean,
        "description"           "text",
        "note"                  "text",
        "receipt_id"            "uuid",
        "receipt_number"        "text",
        "receipt_voided"        boolean,
        "subscription_id"       "uuid",
        "subscription_name"     "text",
        "event_id"              "uuid",
        "event_name"            "text",
        "voce"                  "text",
        "voce_override"         "text",
        "created_at"            timestamp with time zone
    )
    LANGUAGE "plpgsql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_start date;
BEGIN
    IF NOT public.can_access_finance() THEN
        RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
    END IF;

    SELECT ledger_start_date INTO v_start FROM public.association_settings WHERE id = true;

    RETURN QUERY
    SELECT
        t.id,
        t.occurred_on,
        base.kind,
        t.method,
        internal.cash_account_for(t.method),
        t.source,
        t.status,
        t.amount_cents,
        t.refund_of_id,
        COALESCE(t.client_id, o.client_id),
        c.full_name,
        base.is_member,
        base.is_commercial,
        COALESCE(t.description, o.description),
        t.note,
        r.id,
        r.full_number,
        (r.voided_at IS NOT NULL),
        base.subscription_id,
        COALESCE(NULLIF(s.custom_name, ''), p.name),
        e.id,
        e.name,
        COALESCE(t.rendiconto_voce, o.rendiconto_voce,
                 internal.income_voce(base.kind, base.is_commercial, base.is_member)),
        t.rendiconto_voce,
        t.created_at
    FROM public.transactions t
    -- Un rimborso segue l'incasso che restituisce: stesso tipo, stessa voce, stessa persona
    LEFT JOIN public.transactions o ON o.id = t.refund_of_id
    CROSS JOIN LATERAL (
        SELECT
            COALESCE(o.kind, t.kind)                                    AS kind,
            COALESCE(o.is_commercial, t.is_commercial)                  AS is_commercial,
            COALESCE(o.subscription_id, t.subscription_id)              AS subscription_id,
            COALESCE(o.event_booking_id, t.event_booking_id)            AS event_booking_id,
            COALESCE(internal.client_is_member_on(COALESCE(o.client_id, t.client_id),
                                                  COALESCE(o.occurred_on, t.occurred_on)), false) AS is_member
    ) base
    LEFT JOIN public.clients c ON c.id = COALESCE(t.client_id, o.client_id)
    LEFT JOIN public.receipts r ON r.transaction_id = t.id
    LEFT JOIN public.subscriptions s ON s.id = base.subscription_id
    LEFT JOIN public.plans p ON p.id = s.plan_id
    LEFT JOIN public.event_bookings eb ON eb.id = base.event_booking_id
    LEFT JOIN public.events e ON e.id = eb.event_id
    WHERE t.occurred_on BETWEEN GREATEST(p_from, v_start) AND p_to
      -- "Da saldare" non è ancora denaro; un annullato non lo è mai stato
      AND t.status IN ('paid', 'refunded', 'partially_refunded')
    ORDER BY t.occurred_on, t.created_at;
END;
$$;

ALTER FUNCTION "public"."finance_income_lines"("date", "date") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."finance_income_lines"("date", "date") TO "authenticated";
COMMENT ON FUNCTION "public"."finance_income_lines"("date", "date") IS
    'Entrate del periodo (dal 19/08/2026), una riga per incasso e per rimborso (negativo), con conto, voce del rendiconto e stato di sociə alla data. Esclusi i "da saldare" e gli annullati. Solo Finanze.';

-- 7.2 — Le entrate per attività. Un abbonamento si divide fra le attività in proporzione alle
-- lezioni prenotate con quell'abbonamento (prenotate, frequentate o assenze: le disdette non
-- contano). I centesimi avanzati dalla divisione vanno alle quote con il resto più alto, così la
-- somma torna sempre all'incasso. Un evento va all'evento (gruppo "laboratori", come sul sito).
CREATE OR REPLACE FUNCTION "public"."finance_income_allocations"("p_from" "date", "p_to" "date")
    RETURNS TABLE (
        "transaction_id"    "uuid",
        "occurred_on"       "date",
        "kind"              "public"."transaction_kind",
        "bucket"            "text",
        "activity_id"       "uuid",
        "activity_name"     "text",
        "group_id"          "uuid",
        "group_name"        "text",
        "event_id"          "uuid",
        "event_name"        "text",
        "bookings"          integer,
        "amount_cents"      bigint
    )
    LANGUAGE "plpgsql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_start date;
BEGIN
    IF NOT public.can_access_finance() THEN
        RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
    END IF;

    SELECT ledger_start_date INTO v_start FROM public.association_settings WHERE id = true;

    RETURN QUERY
    WITH tx AS (
        SELECT t.id,
               t.occurred_on,
               COALESCE(o.kind, t.kind)                         AS kind,
               t.amount_cents::bigint                           AS amount_cents,
               COALESCE(o.subscription_id, t.subscription_id)   AS subscription_id,
               COALESCE(o.event_booking_id, t.event_booking_id) AS event_booking_id,
               COALESCE(o.booking_id, t.booking_id)             AS booking_id
          FROM public.transactions t
          LEFT JOIN public.transactions o ON o.id = t.refund_of_id
         WHERE t.occurred_on BETWEEN GREATEST(p_from, v_start) AND p_to
           AND t.status IN ('paid', 'refunded', 'partially_refunded')
           AND COALESCE(o.kind, t.kind) IN ('subscription', 'event', 'trial')
    ),
    weights AS (
        -- Abbonamenti: lezioni prenotate con quell'abbonamento, per attività
        SELECT tx.id AS tx_id, l.activity_id, count(*)::bigint AS n
          FROM tx
          JOIN public.bookings b ON b.subscription_id = tx.subscription_id
                                AND b.status IN ('booked', 'attended', 'no_show')
          JOIN public.lessons l ON l.id = b.lesson_id
         WHERE tx.kind = 'subscription' AND tx.subscription_id IS NOT NULL
         GROUP BY tx.id, l.activity_id
        UNION ALL
        -- Una prova pagata va all'attività della sua lezione
        SELECT tx.id, l.activity_id, 1
          FROM tx
          JOIN public.bookings b ON b.id = tx.booking_id
          JOIN public.lessons l ON l.id = b.lesson_id
         WHERE tx.kind = 'trial'
    ),
    shares AS (
        -- Tutto in bigint: la divisione deve essere intera (sum() di bigint darebbe numeric)
        SELECT w.tx_id, w.activity_id, w.n,
               (sum(w.n) OVER (PARTITION BY w.tx_id))::bigint AS total,
               abs(tx.amount_cents)::bigint AS abs_amount,
               sign(tx.amount_cents)::bigint AS sgn
          FROM weights w JOIN tx ON tx.id = w.tx_id
    ),
    rounded AS (
        SELECT s.tx_id, s.activity_id, s.n, s.sgn,
               (s.abs_amount * s.n) / s.total AS base,
               (s.abs_amount - sum((s.abs_amount * s.n) / s.total) OVER (PARTITION BY s.tx_id))::bigint AS remainder,
               row_number() OVER (PARTITION BY s.tx_id
                                  ORDER BY (s.abs_amount * s.n) % s.total DESC, s.activity_id) AS rn
          FROM shares s
    ),
    allocated AS (
        SELECT r.tx_id, 'activity'::text AS bucket, r.activity_id, NULL::uuid AS event_id,
               r.n::integer AS bookings,
               r.sgn * (r.base + CASE WHEN r.rn <= r.remainder THEN 1 ELSE 0 END) AS amount_cents
          FROM rounded r
        UNION ALL
        SELECT tx.id, 'event', NULL, eb.event_id, 1, tx.amount_cents
          FROM tx JOIN public.event_bookings eb ON eb.id = tx.event_booking_id
         WHERE tx.kind = 'event'
        UNION ALL
        -- Nessuna lezione prenotata ancora, o nessun collegamento: restano da parte, dichiarati
        SELECT tx.id,
               CASE WHEN tx.kind = 'subscription' AND tx.subscription_id IS NOT NULL THEN 'unused'
                    ELSE 'unlinked' END,
               NULL, NULL, 0, tx.amount_cents
          FROM tx
         WHERE NOT EXISTS (SELECT 1 FROM weights w WHERE w.tx_id = tx.id)
           AND NOT (tx.kind = 'event' AND EXISTS (
                   SELECT 1 FROM public.event_bookings eb WHERE eb.id = tx.event_booking_id))
    )
    SELECT al.tx_id,
           tx.occurred_on,
           tx.kind,
           al.bucket,
           al.activity_id,
           a.name,
           COALESCE(g.id, ge.id),
           COALESCE(g.name, ge.name),
           al.event_id,
           e.name,
           al.bookings,
           al.amount_cents
      FROM allocated al
      JOIN tx ON tx.id = al.tx_id
      LEFT JOIN public.activities a ON a.id = al.activity_id
      LEFT JOIN public.activity_groups g ON g.id = a.group_id
      LEFT JOIN public.events e ON e.id = al.event_id
      LEFT JOIN public.activity_groups ge ON al.bucket = 'event' AND ge.slug = 'laboratori'
     ORDER BY tx.occurred_on, al.tx_id, al.bucket, a.name;
END;
$$;

ALTER FUNCTION "public"."finance_income_allocations"("date", "date") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."finance_income_allocations"("date", "date") TO "authenticated";
COMMENT ON FUNCTION "public"."finance_income_allocations"("date", "date") IS
    'Entrate per attività ed evento: gli abbonamenti divisi in proporzione alle lezioni prenotate con ciascuno (i rimborsi seguono l''incasso originale). bucket: activity, event, unused (abbonamento senza prenotazioni), unlinked (incasso non collegato). I numeri di un mese cambiano man mano che gli abbonamenti si usano. Solo Finanze.';

-- 7.3 — Saldi di cassa e banca alla fine di un giorno.
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
BEGIN
    IF NOT public.can_access_finance() THEN
        RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_settings FROM public.association_settings WHERE id = true;
    v_cash := v_settings.opening_cash_cents;
    v_bank := v_settings.opening_bank_cents;

    IF p_at >= v_settings.ledger_start_date THEN
        SELECT v_cash + COALESCE(sum(amount_cents) FILTER (WHERE internal.cash_account_for(method) = 'cash'), 0),
               v_bank + COALESCE(sum(amount_cents) FILTER (WHERE internal.cash_account_for(method) = 'bank'), 0)
          INTO v_cash, v_bank
          FROM public.transactions
         WHERE status IN ('paid', 'refunded', 'partially_refunded')
           AND occurred_on BETWEEN v_settings.ledger_start_date AND p_at;

        SELECT v_cash - COALESCE(sum(amount_cents) FILTER (WHERE internal.cash_account_for(payment_method) = 'cash'), 0),
               v_bank - COALESCE(sum(amount_cents) FILTER (WHERE internal.cash_account_for(payment_method) = 'bank'), 0)
          INTO v_cash, v_bank
          FROM public.expenses
         WHERE confirmed_at IS NOT NULL
           AND expense_date BETWEEN v_settings.ledger_start_date AND p_at;

        SELECT v_cash + COALESCE(sum(CASE WHEN to_account = 'cash' THEN amount_cents
                                          WHEN from_account = 'cash' THEN -amount_cents END), 0),
               v_bank + COALESCE(sum(CASE WHEN to_account = 'bank' THEN amount_cents
                                          WHEN from_account = 'bank' THEN -amount_cents END), 0)
          INTO v_cash, v_bank
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
        'total_cents', v_cash + v_bank
    );
END;
$$;

ALTER FUNCTION "public"."finance_account_balances"("date") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."finance_account_balances"("date") TO "authenticated";
COMMENT ON FUNCTION "public"."finance_account_balances"("date") IS
    'Saldi di cassa e banca a fine giornata: saldi iniziali + entrate − uscite confermate ± giroconti, dal 19/08/2026. Solo Finanze.';

-- 7.4 — Saldi iniziali: li imposta il Tesoriere, non solo l'admin come il resto delle impostazioni.
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

    IF p_cash_cents IS NULL OR p_bank_cents IS NULL OR p_cash_cents < 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT');
    END IF;

    UPDATE public.association_settings
       SET opening_cash_cents = p_cash_cents,
           opening_bank_cents = p_bank_cents,
           updated_by = auth.uid(),
           updated_at = now()
     WHERE id = true;

    RETURN jsonb_build_object('ok', true, 'reason', 'SAVED');
END;
$$;

ALTER FUNCTION "public"."finance_set_opening_balances"(integer, integer) OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."finance_set_opening_balances"(integer, integer) TO "authenticated";
COMMENT ON FUNCTION "public"."finance_set_opening_balances"(integer, integer) IS
    'Imposta i saldi di cassa e banca all''inizio della contabilità. Solo Finanze.';

-- 7.5 — La voce del rendiconto si sceglie anche registrando l'incasso (solo le Finanze: le
-- operatrici registrano gli incassi ma il rendiconto non è affar loro, E3). Stessa firma e stessa
-- risposta di prima; cambia solo la lettura di `rendiconto_voce`.
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
    v_voce          text := NULLIF(btrim(COALESCE(p_payload->>'rendiconto_voce', '')), '');
    v_receipt       jsonb := NULL;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF v_amount IS NULL OR v_amount <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT');
    END IF;

    IF v_voce IS NOT NULL THEN
        IF NOT public.can_access_finance() THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.rendiconto_voci WHERE code = v_voce AND kind = 'entrata') THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_VOCE');
        END IF;
    END IF;

    v_kind   := COALESCE(NULLIF(p_payload->>'kind', ''), 'other')::public.transaction_kind;
    v_status := COALESCE(NULLIF(p_payload->>'status', ''), 'paid')::public.transaction_status;

    INSERT INTO public.transactions (
        client_id, kind, amount_cents, method, source, status, occurred_on,
        subscription_id, event_booking_id, member_fee_id, booking_id,
        is_commercial, description, note, rendiconto_voce, created_by
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
        v_voce,
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Uscite: ricorrenze che recuperano i mesi, conferma con data e metodo, rimborsi per cassa
-- ─────────────────────────────────────────────────────────────────────────────

-- Genera le proposte "da confermare" di tutti i mesi mancanti fino a `p_month` compreso, mai oltre il
-- mese in corso. Prima generava solo il mese chiesto e, se un mese veniva saltato, lo perdeva per
-- sempre (l'ultimo mese generato era già più avanti).
CREATE OR REPLACE FUNCTION "public"."generate_recurring_expenses"("p_month" "date" DEFAULT NULL)
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_today     date := (now() AT TIME ZONE 'Europe/Rome')::date;
    v_until     date := LEAST(date_trunc('month', COALESCE(p_month, v_today))::date,
                              date_trunc('month', v_today)::date);
    v_rec       public.recurring_expenses%ROWTYPE;
    v_month     date;
    v_date      date;
    v_last      date;
    v_created   integer := 0;
BEGIN
    IF NOT public.can_access_finance() THEN
        RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
    END IF;

    FOR v_rec IN
        SELECT * FROM public.recurring_expenses
         WHERE is_active = true
           AND starts_on <= (v_until + INTERVAL '1 month - 1 day')::date
           AND (last_generated_month IS NULL OR last_generated_month < v_until)
         FOR UPDATE
    LOOP
        v_month := GREATEST(
            date_trunc('month', v_rec.starts_on)::date,
            COALESCE((v_rec.last_generated_month + INTERVAL '1 month')::date, '-infinity'::date)
        );
        v_last := v_rec.last_generated_month;

        WHILE v_month <= v_until LOOP
            v_date := v_month + (v_rec.day_of_month - 1);
            EXIT WHEN v_rec.ends_on IS NOT NULL AND v_date > v_rec.ends_on;

            IF v_date >= v_rec.starts_on THEN
                INSERT INTO public.expenses (
                    amount_cents, expense_date, category, category_id, vendor, notes,
                    is_fixed, source, recurring_expense_id, payment_method, created_by
                ) VALUES (
                    v_rec.amount_cents, v_date, 'other', v_rec.category_id, v_rec.vendor, v_rec.label,
                    true, 'recurring', v_rec.id, v_rec.payment_method, auth.uid()
                );
                v_created := v_created + 1;
            END IF;

            v_last := v_month;
            v_month := (v_month + INTERVAL '1 month')::date;
        END LOOP;

        IF v_last IS DISTINCT FROM v_rec.last_generated_month THEN
            UPDATE public.recurring_expenses SET last_generated_month = v_last WHERE id = v_rec.id;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'until', v_until, 'created', v_created);
END;
$$;

COMMENT ON FUNCTION "public"."generate_recurring_expenses"("date") IS
    'Crea le uscite "da confermare" delle spese ricorrenti per tutti i mesi mancanti fino a quello indicato (mai oltre il mese in corso). Si può chiamare quante volte si vuole: ogni mese nasce una volta sola. Solo Finanze.';

-- La conferma permette di correggere anche data e metodo: per cassa conta il giorno in cui il
-- denaro esce davvero (l'F24 delle ritenute, l'affitto pagato il 3 invece dell'1).
DROP FUNCTION IF EXISTS "public"."confirm_expense"("uuid", integer);

CREATE OR REPLACE FUNCTION "public"."confirm_expense"(
    "p_expense_id" "uuid",
    "p_amount_cents" integer DEFAULT NULL,
    "p_expense_date" "date" DEFAULT NULL,
    "p_payment_method" "public"."payment_method" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_expense public.expenses%ROWTYPE;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    IF p_amount_cents IS NOT NULL AND p_amount_cents <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT');
    END IF;

    SELECT * INTO v_expense FROM public.expenses WHERE id = p_expense_id FOR UPDATE;
    IF NOT FOUND OR v_expense.confirmed_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'EXPENSE_NOT_FOUND_OR_ALREADY_CONFIRMED');
    END IF;

    -- La ritenuta di un compenso è un obbligo di legge: l'importo non si cambia alla conferma
    IF v_expense.source = 'payout' AND p_amount_cents IS NOT NULL
       AND p_amount_cents <> v_expense.amount_cents THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'AMOUNT_LOCKED');
    END IF;

    UPDATE public.expenses
       SET confirmed_at   = now(),
           amount_cents   = COALESCE(p_amount_cents, amount_cents),
           expense_date   = COALESCE(p_expense_date, expense_date),
           payment_method = COALESCE(p_payment_method, payment_method)
     WHERE id = p_expense_id
    RETURNING * INTO v_expense;

    RETURN jsonb_build_object('ok', true, 'reason', 'CONFIRMED',
                              'amount_cents', v_expense.amount_cents,
                              'expense_date', v_expense.expense_date);
END;
$$;

ALTER FUNCTION "public"."confirm_expense"("uuid", integer, "date", "public"."payment_method") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."confirm_expense"("uuid", integer, "date", "public"."payment_method") TO "authenticated";
COMMENT ON FUNCTION "public"."confirm_expense"("uuid", integer, "date", "public"."payment_method") IS
    'Conferma un''uscita proposta (ricorrenza o ritenuta), correggendo se serve importo, data e metodo. L''importo della ritenuta di un compenso non si cambia. Solo Finanze.';

-- Il rimborso a unə volontariə esce di cassa quando lo si paga, non quando è stata fatta la spesa.
DROP FUNCTION IF EXISTS "public"."staff_pay_volunteer_reimbursement"("uuid");

CREATE OR REPLACE FUNCTION "public"."staff_pay_volunteer_reimbursement"(
    "p_reimbursement_id" "uuid",
    "p_paid_on" "date" DEFAULT NULL,
    "p_method" "public"."payment_method" DEFAULT 'bank_transfer'::"public"."payment_method"
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_r             public.volunteer_reimbursements%ROWTYPE;
    v_category_id   uuid;
    v_expense_id    uuid;
    v_paid_on       date := COALESCE(p_paid_on, (now() AT TIME ZONE 'Europe/Rome')::date);
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
        amount_cents, expense_date, category, category_id, notes, payment_method,
        attachment_path, source, volunteer_reimbursement_id, confirmed_at, created_by
    )
    SELECT v_r.amount_cents, v_paid_on, 'other', v_category_id,
           'Rimborso spese del ' || to_char(v_r.spent_on, 'DD/MM/YYYY') || ': ' || v_r.description
               || ' — ' || v.full_name,
           COALESCE(p_method, 'bank_transfer'),
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

ALTER FUNCTION "public"."staff_pay_volunteer_reimbursement"("uuid", "date", "public"."payment_method") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_pay_volunteer_reimbursement"("uuid", "date", "public"."payment_method") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_pay_volunteer_reimbursement"("uuid", "date", "public"."payment_method") IS
    'Segna pagato un rimborso spese a unə volontariə e crea l''uscita del giorno del pagamento, con lo stesso documento allegato. Solo Finanze.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Compensi: calcolo in ora italiana, congelamento, pagamento
-- ─────────────────────────────────────────────────────────────────────────────

-- 9.1 — Il calcolo del mese. Rispetto alla sessione 3: confini del mese e data del modello in ora
-- italiana (una lezione alle 00:30 del primo del mese era del mese prima), durata vera della lezione
-- prima di quella tipica dell'attività (conta per i compensi a ora e per il tetto orario), le
-- operatrici archiviate restano nei mesi in cui hanno lavorato, e l'uscita dice anche l'attività.
DROP FUNCTION IF EXISTS "public"."calculate_compensation_v2"("date", "date", "uuid");

CREATE OR REPLACE FUNCTION "public"."calculate_compensation_v2"(
    "p_month_start" "date",
    "p_month_end" "date",
    "p_operator_id" "uuid" DEFAULT NULL
) RETURNS TABLE (
    "operator_id" "uuid",
    "operator_name" "text",
    "lesson_id" "uuid",
    "event_id" "uuid",
    "activity_id" "uuid",
    "occurred_at" timestamp with time zone,
    "title" "text",
    "duration_minutes" integer,
    "participants" integer,
    "revenue_cents" bigint,
    "model_id" "uuid",
    "model_name" "text",
    "amount_cents" bigint,
    "breakdown" "jsonb"
)
    LANGUAGE "plpgsql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_from  timestamptz := (p_month_start::timestamp AT TIME ZONE 'Europe/Rome');
    v_to    timestamptz := ((p_month_end + 1)::timestamp AT TIME ZONE 'Europe/Rome');
BEGIN
    IF NOT public.can_access_finance() THEN
        RAISE EXCEPTION 'Access denied: finance role required' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH lesson_base AS (
        SELECT
            l.id                AS lesson_id,
            l.operator_id,
            l.starts_at,
            l.activity_id,
            a.name              AS activity_name,
            GREATEST(COALESCE(
                NULLIF((EXTRACT(EPOCH FROM (l.ends_at - l.starts_at)) / 60)::integer, 0),
                a.duration_minutes
            ), 1)               AS duration_minutes,
            COUNT(b.id) FILTER (WHERE b.status IN ('booked', 'attended', 'no_show'))::integer AS participants,
            COALESCE(SUM(
                CASE
                    WHEN s.custom_price_cents IS NOT NULL AND COALESCE(s.custom_entries, 0) > 0
                        THEN s.custom_price_cents::numeric / s.custom_entries
                    WHEN s.discount_percent IS NOT NULL AND s.discount_percent > 0
                         AND p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
                        THEN round(p.price_cents * (1 - s.discount_percent / 100.0)) / p.entries
                    WHEN p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
                        THEN round(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0)) / p.entries
                    ELSE 0
                END
            ) FILTER (WHERE b.status IN ('booked', 'attended', 'no_show')), 0)::bigint AS revenue_cents
        FROM public.lessons l
        JOIN public.activities a ON a.id = l.activity_id
        LEFT JOIN public.bookings b ON b.lesson_id = l.id
        LEFT JOIN public.subscriptions s ON s.id = b.subscription_id
        LEFT JOIN public.plans p ON p.id = s.plan_id
        WHERE l.starts_at >= v_from
          AND l.starts_at < v_to
          AND l.deleted_at IS NULL
          AND l.operator_id IS NOT NULL
          AND (p_operator_id IS NULL OR l.operator_id = p_operator_id)
        GROUP BY l.id, l.operator_id, l.starts_at, l.activity_id, a.name, a.duration_minutes, l.ends_at
    ),
    event_base AS (
        SELECT
            eo.operator_id,
            e.id                AS event_id,
            e.starts_at,
            e.name              AS event_name,
            eo.model_id         AS override_model_id,
            GREATEST(COALESCE(
                NULLIF((EXTRACT(EPOCH FROM (e.ends_at - e.starts_at)) / 60)::integer, 0), 90
            ), 1)               AS duration_minutes,
            COUNT(eb.id) FILTER (WHERE eb.status IN ('booked', 'attended', 'no_show'))::integer AS participants,
            (COALESCE(e.price_cents, 0)::bigint
                * COUNT(eb.id) FILTER (WHERE eb.status IN ('booked', 'attended', 'no_show'))) AS revenue_cents
        FROM public.event_operators eo
        JOIN public.events e ON e.id = eo.event_id
        LEFT JOIN public.event_bookings eb ON eb.event_id = e.id
        WHERE e.starts_at >= v_from
          AND e.starts_at < v_to
          AND e.deleted_at IS NULL
          AND (p_operator_id IS NULL OR eo.operator_id = p_operator_id)
        GROUP BY eo.operator_id, e.id, e.starts_at, e.name, eo.model_id, e.ends_at, e.price_cents
    ),
    resolved AS (
        SELECT lb.operator_id, lb.lesson_id, NULL::uuid AS event_id, lb.activity_id,
               lb.starts_at AS occurred_at, lb.activity_name AS title,
               lb.duration_minutes, lb.participants, lb.revenue_cents,
               internal.resolve_compensation_model(
                   lb.operator_id, lb.activity_id, (lb.starts_at AT TIME ZONE 'Europe/Rome')::date) AS model_id
          FROM lesson_base lb
        UNION ALL
        SELECT eb.operator_id, NULL::uuid, eb.event_id, NULL::uuid,
               eb.starts_at, eb.event_name,
               eb.duration_minutes, eb.participants, eb.revenue_cents,
               COALESCE(eb.override_model_id,
                        internal.resolve_compensation_model(
                            eb.operator_id, NULL, (eb.starts_at AT TIME ZONE 'Europe/Rome')::date))
          FROM event_base eb
    )
    SELECT
        r.operator_id,
        o.name,
        r.lesson_id,
        r.event_id,
        r.activity_id,
        r.occurred_at,
        r.title,
        r.duration_minutes,
        r.participants,
        r.revenue_cents,
        r.model_id,
        m.name,
        COALESCE((calc.result->>'amount_cents')::bigint, 0),
        COALESCE(calc.result, jsonb_build_object('ok', false, 'reason', 'NO_MODEL'))
    FROM resolved r
    JOIN public.operators o ON o.id = r.operator_id
    LEFT JOIN public.compensation_models m ON m.id = r.model_id
    LEFT JOIN LATERAL (
        SELECT internal.compute_compensation(r.model_id, r.duration_minutes, r.participants, r.revenue_cents) AS result
        WHERE r.model_id IS NOT NULL
    ) calc ON true
    -- I volontari non prendono compensi: solo rimborsi documentati (art. 23)
    WHERE o.engagement_type = 'paid'::public.staff_engagement_type
    ORDER BY r.occurred_at, o.name;
END;
$$;

ALTER FUNCTION "public"."calculate_compensation_v2"("date", "date", "uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."calculate_compensation_v2"("date", "date", "uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."calculate_compensation_v2"("date", "date", "uuid") IS
    'Compensi del periodo, lezione per lezione ed evento per evento, secondo i modelli assegnati (mese in ora italiana). Di sola lettura: non scrive nulla, si può rifare. Esclude chi è volontariə. Solo Finanze.';

-- 9.2 — Congela solo quello che è già successo: una lezione futura cambierebbe ancora (presenze,
-- prenotazioni). Si può congelare più volte lo stesso mese: le righe già congelate non cambiano.
CREATE OR REPLACE FUNCTION "public"."staff_freeze_compensation"(
    "p_month_start" "date",
    "p_month_end" "date",
    "p_operator_id" "uuid" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_month     date := date_trunc('month', p_month_start)::date;
    v_inserted  integer := 0;
    v_future    integer := 0;
    v_no_model  integer := 0;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    WITH calc AS (
        SELECT * FROM public.calculate_compensation_v2(p_month_start, p_month_end, p_operator_id)
    ),
    ins AS (
        INSERT INTO public.compensation_entries (
            operator_id, period_month, lesson_id, event_id, model_id, occurred_at,
            duration_minutes, participants, revenue_cents, amount_cents, breakdown, created_by
        )
        SELECT c.operator_id, v_month, c.lesson_id, c.event_id, c.model_id, c.occurred_at,
               c.duration_minutes, c.participants, c.revenue_cents, c.amount_cents, c.breakdown, auth.uid()
          FROM calc c
         WHERE c.model_id IS NOT NULL
           AND c.occurred_at < now()
        ON CONFLICT DO NOTHING
        RETURNING 1
    )
    SELECT (SELECT count(*) FROM ins),
           count(*) FILTER (WHERE c.occurred_at >= now()),
           count(*) FILTER (WHERE c.model_id IS NULL AND c.occurred_at < now())
      INTO v_inserted, v_future, v_no_model
      FROM calc c;

    RETURN jsonb_build_object('ok', true, 'reason', 'FROZEN', 'month', v_month,
                              'inserted', v_inserted, 'future', v_future, 'no_model', v_no_model);
END;
$$;

COMMENT ON FUNCTION "public"."staff_freeze_compensation"("date", "date", "uuid") IS
    'Congela i compensi calcolati del periodo, solo per lezioni ed eventi già avvenuti. Le righe già congelate restano come sono: chiudere due volte lo stesso mese non cambia gli importi. Risponde anche quante ne restano fuori (future, senza modello). Solo Finanze.';

-- 9.3 — Riapre un mese congelato e non ancora pagato: il compenso torna calcolato dal vivo (per
-- esempio dopo aver corretto una presenza o il modello).
CREATE OR REPLACE FUNCTION "public"."staff_unfreeze_compensation"(
    "p_month_start" "date",
    "p_operator_id" "uuid" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_deleted integer;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    DELETE FROM public.compensation_entries
     WHERE period_month = date_trunc('month', p_month_start)::date
       AND (p_operator_id IS NULL OR operator_id = p_operator_id)
       AND payment_id IS NULL
       AND status <> 'paid';

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RETURN jsonb_build_object('ok', true, 'reason', 'UNFROZEN', 'deleted', v_deleted);
END;
$$;

ALTER FUNCTION "public"."staff_unfreeze_compensation"("date", "uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_unfreeze_compensation"("date", "uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_unfreeze_compensation"("date", "uuid") IS
    'Riapre i compensi congelati e non ancora pagati di un mese (di una persona o di tuttə). Quelli pagati non si toccano. Solo Finanze.';

-- 9.4 — Paga i compensi congelati di una persona per un mese. Un pagamento solo, con la ritenuta
-- d'acconto: il netto esce il giorno del pagamento, la ritenuta resta da confermare fino all'F24.
DROP FUNCTION IF EXISTS "public"."staff_mark_compensation_paid"("uuid"[]);

CREATE OR REPLACE FUNCTION "public"."staff_pay_compensation"(
    "p_operator_id" "uuid",
    "p_month_start" "date",
    "p_paid_on" "date" DEFAULT NULL,
    "p_method" "public"."payment_method" DEFAULT 'bank_transfer'::"public"."payment_method",
    "p_withholding_percent" numeric DEFAULT NULL,
    "p_gross_cents" bigint DEFAULT NULL,
    "p_note" "text" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_month         date := date_trunc('month', p_month_start)::date;
    v_paid_on       date := COALESCE(p_paid_on, (now() AT TIME ZONE 'Europe/Rome')::date);
    v_operator      public.operators%ROWTYPE;
    v_entries_sum   bigint;
    v_entries_n     integer;
    v_gross         bigint;
    v_pct           numeric(5,2);
    v_withholding   bigint;
    v_net           bigint;
    v_note          text := NULLIF(btrim(COALESCE(p_note, '')), '');
    v_category_id   uuid;
    v_payment_id    uuid;
    v_net_exp       uuid;
    v_wh_exp        uuid;
    v_f24_date      date;
    v_label         text;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    SELECT * INTO v_operator FROM public.operators WHERE id = p_operator_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'OPERATOR_NOT_FOUND');
    END IF;

    IF p_method IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_METHOD');
    END IF;

    -- I compensi da pagare, bloccati: due pagamenti contemporanei non li prendono entrambi
    PERFORM 1 FROM public.compensation_entries
      WHERE operator_id = p_operator_id AND period_month = v_month
        AND payment_id IS NULL AND status <> 'paid'
      FOR UPDATE;

    SELECT COALESCE(sum(amount_cents), 0), count(*)
      INTO v_entries_sum, v_entries_n
      FROM public.compensation_entries
     WHERE operator_id = p_operator_id AND period_month = v_month
       AND payment_id IS NULL AND status <> 'paid';

    IF v_entries_n = 0 OR v_entries_sum <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOTHING_TO_PAY');
    END IF;

    v_gross := COALESCE(p_gross_cents, v_entries_sum);
    IF v_gross <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT');
    END IF;
    IF v_gross <> v_entries_sum AND v_note IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'REASON_REQUIRED');
    END IF;

    v_pct := COALESCE(
        p_withholding_percent,
        (SELECT withholding_percent FROM public.operator_compensation_settings WHERE operator_id = p_operator_id),
        0
    );
    IF v_pct < 0 OR v_pct > 100 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_WITHHOLDING');
    END IF;

    v_withholding := round(v_gross * v_pct / 100.0)::bigint;
    v_net := v_gross - v_withholding;
    v_label := v_operator.name || ' — ' || to_char(v_month, 'MM/YYYY');

    SELECT id INTO v_category_id FROM public.expense_categories WHERE slug = 'compensi';

    INSERT INTO public.compensation_payments (
        operator_id, period_month, paid_on, method, entries_cents, gross_cents,
        withholding_percent, withholding_cents, net_cents, note, created_by
    ) VALUES (
        p_operator_id, v_month, v_paid_on, p_method, v_entries_sum, v_gross,
        v_pct, v_withholding, v_net, v_note, auth.uid()
    )
    RETURNING id INTO v_payment_id;

    IF v_net > 0 THEN
        INSERT INTO public.expenses (
            amount_cents, expense_date, category, category_id, operator_id, notes,
            is_fixed, source, payment_method, confirmed_at, created_by
        ) VALUES (
            v_net, v_paid_on, 'staff_compensation', v_category_id, p_operator_id,
            CASE WHEN v_withholding > 0 THEN 'Compenso netto ' ELSE 'Compenso ' END || v_label,
            false, 'payout', p_method, now(), auth.uid()
        )
        RETURNING id INTO v_net_exp;
    END IF;

    IF v_withholding > 0 THEN
        -- L'F24 delle ritenute si paga entro il 16 del mese dopo quello del pagamento
        v_f24_date := (date_trunc('month', v_paid_on) + INTERVAL '1 month' + INTERVAL '15 days')::date;
        INSERT INTO public.expenses (
            amount_cents, expense_date, category, category_id, operator_id, notes,
            is_fixed, source, payment_method, confirmed_at, created_by
        ) VALUES (
            v_withholding, v_f24_date, 'staff_compensation', v_category_id, p_operator_id,
            'Ritenuta d''acconto ' || replace(rtrim(rtrim(v_pct::text, '0'), '.'), '.', ',')
                || '% su compenso ' || v_label
                || ' — F24 entro il ' || to_char(v_f24_date, 'DD/MM/YYYY'),
            false, 'payout', 'bank_transfer', NULL, auth.uid()
        )
        RETURNING id INTO v_wh_exp;
    END IF;

    UPDATE public.compensation_payments
       SET net_expense_id = v_net_exp, withholding_expense_id = v_wh_exp
     WHERE id = v_payment_id;

    UPDATE public.compensation_entries
       SET status      = 'paid',
           paid_at     = now(),
           payment_id  = v_payment_id,
           expense_id  = v_net_exp,
           approved_at = COALESCE(approved_at, now()),
           approved_by = COALESCE(approved_by, auth.uid())
     WHERE operator_id = p_operator_id AND period_month = v_month
       AND payment_id IS NULL AND status <> 'paid';

    RETURN jsonb_build_object(
        'ok', true, 'reason', 'PAID',
        'payment_id', v_payment_id,
        'entries', v_entries_n,
        'gross_cents', v_gross,
        'withholding_cents', v_withholding,
        'net_cents', v_net,
        'net_expense_id', v_net_exp,
        'withholding_expense_id', v_wh_exp,
        'f24_due_on', v_f24_date
    );
END;
$$;

ALTER FUNCTION "public"."staff_pay_compensation"("uuid", "date", "date", "public"."payment_method", numeric, bigint, "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_pay_compensation"("uuid", "date", "date", "public"."payment_method", numeric, bigint, "text") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_pay_compensation"("uuid", "date", "date", "public"."payment_method", numeric, bigint, "text") IS
    'Paga i compensi congelati di una persona per un mese: un pagamento, l''uscita del netto nel giorno del pagamento e, con la ritenuta d''acconto, un''uscita da confermare per l''F24 entro il 16 del mese dopo. Solo Finanze.';

-- 9.5 — Annulla un pagamento registrato per errore: via le uscite, i compensi tornano da pagare.
CREATE OR REPLACE FUNCTION "public"."staff_undo_compensation_payment"("p_payment_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_payment public.compensation_payments%ROWTYPE;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    SELECT * INTO v_payment FROM public.compensation_payments WHERE id = p_payment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PAYMENT_NOT_FOUND');
    END IF;

    UPDATE public.compensation_entries
       SET status = 'pending', paid_at = NULL, payment_id = NULL, expense_id = NULL
     WHERE payment_id = p_payment_id;

    DELETE FROM public.compensation_payments WHERE id = p_payment_id;

    DELETE FROM public.expenses
     WHERE id IN (v_payment.net_expense_id, v_payment.withholding_expense_id);

    RETURN jsonb_build_object('ok', true, 'reason', 'UNDONE');
END;
$$;

ALTER FUNCTION "public"."staff_undo_compensation_payment"("uuid") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_undo_compensation_payment"("uuid") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_undo_compensation_payment"("uuid") IS
    'Annulla un pagamento di compensi registrato per errore: cancella le sue uscite (netto e ritenuta) e riporta i compensi a da pagare. Solo Finanze.';

-- 9.6 — Salva un modello in un colpo solo: modello, mattoni e scaglioni. Scritti uno per uno
-- dall'interfaccia, un errore a metà lascerebbe un modello diverso da quello mostrato.
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
        INSERT INTO public.compensation_models (name, description, min_guaranteed_cents, max_hourly_cents, is_active, created_by)
        VALUES (
            v_name,
            NULLIF(btrim(COALESCE(p_payload->>'description', '')), ''),
            NULLIF(p_payload->>'min_guaranteed_cents', '')::integer,
            NULLIF(p_payload->>'max_hourly_cents', '')::integer,
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

ALTER FUNCTION "public"."staff_save_compensation_model"("jsonb") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_save_compensation_model"("jsonb") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_save_compensation_model"("jsonb") IS
    'Crea o modifica un modello di compenso con i suoi mattoni e scaglioni, tutto o niente. Le modifiche valgono per i mesi non ancora congelati. Solo Finanze.';

-- 9.7 — Prova un modello con numeri inventati, prima di assegnarlo.
CREATE OR REPLACE FUNCTION "public"."preview_compensation"(
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
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;
    RETURN internal.compute_compensation(p_model_id, p_duration_minutes, p_participants, p_revenue_cents);
END;
$$;

ALTER FUNCTION "public"."preview_compensation"("uuid", integer, integer, bigint) OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."preview_compensation"("uuid", integer, integer, bigint) TO "authenticated";
COMMENT ON FUNCTION "public"."preview_compensation"("uuid", integer, integer, bigint) IS
    'Calcola il compenso che un modello darebbe per una durata, un numero di presenti e un incasso di prova, con il dettaglio mattone per mattone. Solo Finanze.';
