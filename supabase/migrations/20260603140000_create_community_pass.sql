-- Kalòs Community Pass (tesseramento) + Bussola (consulenza 15') — Fase 6 della nuova app KMP, item B + F.
-- Modello membership distinto dai pacchetti a ingressi: un tesseramento ANNUALE (validità 365gg dalla
-- attivazione, rinnovo MANUALE, nessun auto-rinnovo) che dà accesso a vantaggi (sconti eventi/lab,
-- abbonamenti agevolati) e include la "Bussola" — una consulenza 1:1 di 15' richiedibile dall'app.
--
-- Decisioni di prodotto (AskUserQuestion 2026-06-03):
--   * Struttura: TIER UNICO al lancio (tabella pass_tiers già pronta per livelli futuri, additivo).
--   * Durata: ANNUALE a scadenza (validity_days DEFAULT 365), rinnovo manuale, no auto-rinnovo.
--   * Vantaggi al lancio: sconto eventi/lab + abbonamenti agevolati. Modello vantaggi STRUTTURATO/tipizzato.
--   * Pass assegnato a MANO dal gestionale (come gli abbonamenti); Stripe è la Fase 11.
--   * Bussola: RICHIESTA in-app (tabella bussola_requests) → lo staff la trasforma in una lezione
--     is_individual assegnata (auto-booking già esistente). INCLUSA per i tesserati (gating: solo Pass attivo).
--
-- VINCOLO IAP (NEW_APP_PLAN.md §10): il Pass NON gatela contenuti digitali (le pratiche restano gratis
-- per tutti gli utenti loggati). Qui i vantaggi sono agevolazioni/sconti/Bussola, mai accesso a contenuti.
--
-- Tutto ADDITIVO e retro-compatibile (NEW_APP_PLAN.md §3): nuovi enum + nuove tabelle + nuove RPC.
-- Nessuna tabella/colonna/RPC/constraint esistente viene toccata → website, gestionale e PWA restano identici.
-- Gatato dietro feature_flags.community_pass (già esistente, SPENTO): spedire ≠ attivare.
-- Vedi docs/NEW_APP_PLAN.md §5 (item B/F) e §9 (Fase 6).

-- ─────────────────────────────────────────────────────────────────────────────
-- Enum
-- ─────────────────────────────────────────────────────────────────────────────

-- Stato del tesseramento del singolo cliente.
CREATE TYPE "public"."membership_status" AS ENUM (
    'active',       -- attivo (e, di fatto, valido finché expires_at >= today)
    'expired',      -- scaduto (non rinnovato)
    'cancelled'     -- annullato dallo staff
);

-- Tipo di vantaggio del Pass. Definiamo ora l'intero spazio dei vantaggi: al lancio lo staff popola
-- i due sconti scelti (+ eventuale Bussola); gli altri restano a disposizione (additivo, già tipizzato).
CREATE TYPE "public"."pass_benefit_type" AS ENUM (
    'subscription_discount',  -- sconto % su abbonamenti (applicato a mano via subscriptions.discount_percent)
    'event_discount',         -- sconto % su eventi/lab
    'bussola',                -- consulenza Bussola 15' inclusa per i tesserati
    'community_access',       -- accesso agevolato ai servizi comunità (per lo più informativo)
    'priority_booking',       -- finestra di prenotazione anticipata (futuro)
    'other'                   -- vantaggio descrittivo generico
);

-- Stato di una richiesta di Bussola (consulenza 1:1).
CREATE TYPE "public"."bussola_request_status" AS ENUM (
    'pending',      -- inviata dal cliente, da gestire dallo staff
    'scheduled',    -- lo staff ha fissato la lezione is_individual (lesson_id valorizzato)
    'completed',    -- consulenza svolta
    'cancelled'     -- annullata (dal cliente o dallo staff)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabella: pass_tiers — definizione del tesseramento (catalogo, gestito dallo staff)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."pass_tiers" (
    "id"            "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "name"          "text"      NOT NULL,
    "description"   "text",
    "price_cents"   integer     DEFAULT 0 NOT NULL,
    "currency"      "text"      DEFAULT 'EUR'::"text" NOT NULL,
    "validity_days" integer     DEFAULT 365 NOT NULL,        -- tesseramento annuale
    "is_active"     boolean     DEFAULT true NOT NULL,
    "display_order" integer     DEFAULT 0 NOT NULL,
    "created_at"    timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"    timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at"    timestamp with time zone,

    CONSTRAINT "pass_tiers_pkey"            PRIMARY KEY ("id"),
    CONSTRAINT "pass_tiers_price_check"     CHECK ("price_cents" >= 0),
    CONSTRAINT "pass_tiers_validity_check"  CHECK ("validity_days" > 0)
);

ALTER TABLE "public"."pass_tiers" OWNER TO "postgres";

COMMENT ON TABLE  "public"."pass_tiers" IS 'Definizione del Kalòs Community Pass (tesseramento). Tier unico al lancio; struttura pronta per più livelli (additivo). Vedi NEW_APP_PLAN.md item B / §9 Fase 6.';
COMMENT ON COLUMN "public"."pass_tiers"."validity_days" IS 'Durata del tesseramento in giorni (default 365 = annuale). Rinnovo manuale, nessun auto-rinnovo.';
COMMENT ON COLUMN "public"."pass_tiers"."price_cents" IS 'Prezzo del tesseramento. Pagamento manuale dal gestionale fino al go-live Stripe (Fase 11).';
COMMENT ON COLUMN "public"."pass_tiers"."deleted_at" IS 'Soft delete: NULL = attivo. I tier archiviati non appaiono nel catalogo ma le memberships esistenti restano valide.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabella: pass_tier_benefits — vantaggi strutturati/tipizzati per tier
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."pass_tier_benefits" (
    "id"            "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "tier_id"       "uuid"      NOT NULL,
    "benefit_type"  "public"."pass_benefit_type" NOT NULL,
    "value_percent" numeric(5,2),                            -- per i vantaggi di tipo sconto (0–100)
    "value_int"     integer,                                 -- per conteggi (es. N inclusi); nullable
    "label"         "text",                                  -- etichetta di visualizzazione (override)
    "description"   "text",                                  -- descrizione di visualizzazione
    "display_order" integer     DEFAULT 0 NOT NULL,
    "is_active"     boolean     DEFAULT true NOT NULL,
    "created_at"    timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"    timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "pass_tier_benefits_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "pass_tier_benefits_value_percent_range" CHECK (
        "value_percent" IS NULL OR ("value_percent" >= 0 AND "value_percent" <= 100)
    ),
    CONSTRAINT "pass_tier_benefits_value_int_check" CHECK ("value_int" IS NULL OR "value_int" >= 0),
    CONSTRAINT "pass_tier_benefits_tier_id_fkey" FOREIGN KEY ("tier_id")
        REFERENCES "public"."pass_tiers"("id") ON DELETE CASCADE
);

ALTER TABLE "public"."pass_tier_benefits" OWNER TO "postgres";

COMMENT ON TABLE  "public"."pass_tier_benefits" IS 'Vantaggi tipizzati di un tier del Pass. value_percent per gli sconti, value_int per conteggi futuri. Mai accesso a contenuti digitali (vincolo IAP §10).';
COMMENT ON COLUMN "public"."pass_tier_benefits"."benefit_type" IS 'Tipo di vantaggio: subscription_discount, event_discount, bussola, community_access, priority_booking, other.';
COMMENT ON COLUMN "public"."pass_tier_benefits"."value_percent" IS 'Percentuale (0–100) per i vantaggi di tipo sconto. Lo sconto abbonamento reale è applicato dallo staff via subscriptions.discount_percent.';

CREATE INDEX "idx_pass_tier_benefits_tier" ON "public"."pass_tier_benefits" ("tier_id", "display_order");

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabella: memberships — tesseramento del singolo cliente (assegnato a mano dallo staff)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."memberships" (
    "id"               "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id"        "uuid"      NOT NULL,
    "tier_id"          "uuid"      NOT NULL,
    "status"           "public"."membership_status" DEFAULT 'active'::"public"."membership_status" NOT NULL,
    "started_at"       "date"      DEFAULT CURRENT_DATE NOT NULL,
    "expires_at"       "date"      NOT NULL,
    "price_cents_paid" integer,                              -- quanto effettivamente pagato (manuale); NULL se non tracciato
    "note"             "text",
    "created_by"       "uuid",                               -- auth.uid() dello staff che ha assegnato (nullable)
    "metadata"         "jsonb"     DEFAULT '{}'::"jsonb",
    "created_at"       timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"       timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at"       timestamp with time zone,

    CONSTRAINT "memberships_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "memberships_expires_after_start" CHECK ("expires_at" >= "started_at"),
    CONSTRAINT "memberships_price_check" CHECK ("price_cents_paid" IS NULL OR "price_cents_paid" >= 0),
    CONSTRAINT "memberships_client_id_fkey" FOREIGN KEY ("client_id")
        REFERENCES "public"."clients"("id") ON DELETE CASCADE,
    CONSTRAINT "memberships_tier_id_fkey" FOREIGN KEY ("tier_id")
        REFERENCES "public"."pass_tiers"("id") ON DELETE RESTRICT
);

ALTER TABLE "public"."memberships" OWNER TO "postgres";

COMMENT ON TABLE  "public"."memberships" IS 'Tesseramento Community Pass del singolo cliente. Assegnato a mano dal gestionale (come gli abbonamenti). Annuale, rinnovo manuale.';
COMMENT ON COLUMN "public"."memberships"."expires_at" IS 'Data di scadenza = started_at + tier.validity_days (calcolata dalla RPC assign_membership).';
COMMENT ON COLUMN "public"."memberships"."deleted_at" IS 'Soft delete: NULL = record attivo.';

-- Una sola membership ATTIVA per cliente (tier unico). Le storiche (expired/cancelled/soft-deleted) sono libere.
CREATE UNIQUE INDEX "memberships_one_active_per_client"
    ON "public"."memberships" ("client_id")
    WHERE ("status" = 'active' AND "deleted_at" IS NULL);

CREATE INDEX "idx_memberships_client"  ON "public"."memberships" ("client_id");
CREATE INDEX "idx_memberships_expires" ON "public"."memberships" ("status", "expires_at");

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabella: bussola_requests — richieste di consulenza Bussola (1:1, 15')
-- ─────────────────────────────────────────────────────────────────────────────
-- Il cliente (tesserato) richiede una Bussola dall'app; lo staff la trasforma in una lezione
-- is_individual assegnata (il trigger auto_create_booking_for_individual_lesson crea il booking).
-- La lezione vera vive in `lessons` (nessuna modifica ai suoi constraint): qui tracciamo solo la richiesta.

CREATE TABLE IF NOT EXISTS "public"."bussola_requests" (
    "id"           "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id"    "uuid"      NOT NULL,
    "status"       "public"."bussola_request_status" DEFAULT 'pending'::"public"."bussola_request_status" NOT NULL,
    "preferred_at" timestamp with time zone,                -- preferenza di data/ora (opzionale)
    "note"         "text",                                  -- cosa vorrebbe affrontare (opzionale)
    "lesson_id"    "uuid",                                  -- lezione is_individual creata dallo staff (quando scheduled)
    "handled_by"   "uuid",                                  -- staff che gestisce (nullable)
    "metadata"     "jsonb"     DEFAULT '{}'::"jsonb",
    "created_at"   timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"   timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "bussola_requests_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "bussola_requests_client_id_fkey" FOREIGN KEY ("client_id")
        REFERENCES "public"."clients"("id") ON DELETE CASCADE,
    CONSTRAINT "bussola_requests_lesson_id_fkey" FOREIGN KEY ("lesson_id")
        REFERENCES "public"."lessons"("id") ON DELETE SET NULL
);

ALTER TABLE "public"."bussola_requests" OWNER TO "postgres";

COMMENT ON TABLE "public"."bussola_requests" IS 'Richieste di consulenza Bussola 15'' (item F). Il cliente tesserato richiede; lo staff fissa una lezione is_individual assegnata. Inclusa per i tesserati (gating su Pass attivo).';

-- Una sola richiesta "aperta" (pending o scheduled) per cliente alla volta.
CREATE UNIQUE INDEX "bussola_requests_one_open_per_client"
    ON "public"."bussola_requests" ("client_id")
    WHERE ("status" IN ('pending', 'scheduled'));

CREATE INDEX "idx_bussola_requests_status" ON "public"."bussola_requests" ("status", "created_at" DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- Trigger updated_at (riusa l'helper esistente update_updated_at_column)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TRIGGER "pass_tiers_updated_at"
    BEFORE UPDATE ON "public"."pass_tiers"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

CREATE OR REPLACE TRIGGER "pass_tier_benefits_updated_at"
    BEFORE UPDATE ON "public"."pass_tier_benefits"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

CREATE OR REPLACE TRIGGER "memberships_updated_at"
    BEFORE UPDATE ON "public"."memberships"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

CREATE OR REPLACE TRIGGER "bussola_requests_updated_at"
    BEFORE UPDATE ON "public"."bussola_requests"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ─────────────────────────────────────────────────────────────────────────────

-- pass_tiers / pass_tier_benefits: catalogo leggibile da tutti (come i piani); scrittura solo staff.
ALTER TABLE "public"."pass_tiers"         ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."pass_tier_benefits" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pass_tiers_select_all" ON "public"."pass_tiers"
    FOR SELECT USING (true);
CREATE POLICY "pass_tiers_write_staff" ON "public"."pass_tiers"
    FOR ALL USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

CREATE POLICY "pass_tier_benefits_select_all" ON "public"."pass_tier_benefits"
    FOR SELECT USING (true);
CREATE POLICY "pass_tier_benefits_write_staff" ON "public"."pass_tier_benefits"
    FOR ALL USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- memberships: il cliente vede SOLO la propria; assegnazione/modifica solo staff (Pass assegnato a mano).
ALTER TABLE "public"."memberships" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "memberships_select_own" ON "public"."memberships"
    FOR SELECT USING ("client_id" = "public"."get_my_client_id"());
CREATE POLICY "memberships_all_staff" ON "public"."memberships"
    FOR ALL USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- bussola_requests: il cliente vede SOLO le proprie; le scritture del cliente passano dalle RPC
-- (SECURITY DEFINER) che validano il Pass attivo. Lo staff ha accesso completo (triage/scheduling).
ALTER TABLE "public"."bussola_requests" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bussola_requests_select_own" ON "public"."bussola_requests"
    FOR SELECT USING ("client_id" = "public"."get_my_client_id"());
CREATE POLICY "bussola_requests_all_staff" ON "public"."bussola_requests"
    FOR ALL USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- Grant coerenti con le altre tabelle: anon legge il catalogo; authenticated ha DML filtrato dalla RLS.
GRANT SELECT ON TABLE "public"."pass_tiers"         TO "anon";
GRANT SELECT ON TABLE "public"."pass_tier_benefits" TO "anon";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."pass_tiers"         TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."pass_tier_benefits" TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."memberships"        TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."bussola_requests"   TO "authenticated";
GRANT ALL ON TABLE "public"."pass_tiers"         TO "service_role";
GRANT ALL ON TABLE "public"."pass_tier_benefits" TO "service_role";
GRANT ALL ON TABLE "public"."memberships"        TO "service_role";
GRANT ALL ON TABLE "public"."bussola_requests"   TO "service_role";

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: get_my_membership — stato del Pass dell'utente autenticato (per l'app)
-- ─────────────────────────────────────────────────────────────────────────────
-- Ritorna jsonb { ok, has_pass, membership?, tier?, benefits[] }. has_pass = membership attiva e non scaduta.
-- I vantaggi sono quelli attivi del tier (ordinati). Pattern SECURITY DEFINER scoped sul proprio client.

CREATE OR REPLACE FUNCTION "public"."get_my_membership"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_my_client_id uuid;
  v_membership memberships%ROWTYPE;
  v_tier pass_tiers%ROWTYPE;
  v_has_pass boolean := false;
  v_benefits jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'has_pass', false);
  END IF;

  -- Membership più recente non soft-deleted (preferendo quella attiva).
  SELECT * INTO v_membership
  FROM public.memberships
  WHERE client_id = v_my_client_id AND deleted_at IS NULL
  ORDER BY (status = 'active') DESC, started_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'has_pass', false);
  END IF;

  v_has_pass := (v_membership.status = 'active' AND v_membership.expires_at >= CURRENT_DATE);

  SELECT * INTO v_tier FROM public.pass_tiers WHERE id = v_membership.tier_id;

  SELECT COALESCE(jsonb_agg(
           jsonb_build_object(
             'benefit_type', b.benefit_type,
             'value_percent', b.value_percent,
             'value_int', b.value_int,
             'label', b.label,
             'description', b.description
           ) ORDER BY b.display_order, b.created_at
         ), '[]'::jsonb)
  INTO v_benefits
  FROM public.pass_tier_benefits b
  WHERE b.tier_id = v_membership.tier_id AND b.is_active = true;

  RETURN jsonb_build_object(
    'ok', true,
    'has_pass', v_has_pass,
    'membership', jsonb_build_object(
      'id', v_membership.id,
      'status', v_membership.status,
      'started_at', v_membership.started_at,
      'expires_at', v_membership.expires_at
    ),
    'tier', jsonb_build_object(
      'id', v_tier.id,
      'name', v_tier.name,
      'description', v_tier.description,
      'price_cents', v_tier.price_cents,
      'currency', v_tier.currency,
      'validity_days', v_tier.validity_days
    ),
    'benefits', v_benefits
  );
END;
$$;

ALTER FUNCTION "public"."get_my_membership"() OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."get_my_membership"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_membership"() TO "service_role";
COMMENT ON FUNCTION "public"."get_my_membership"() IS 'Stato del Community Pass dell''utente autenticato: has_pass (attivo e non scaduto), membership, tier e vantaggi. Fase 6.';

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: assign_membership — assegnazione del Pass a un cliente (staff, dal gestionale)
-- ─────────────────────────────────────────────────────────────────────────────
-- Calcola expires_at = started_at + tier.validity_days e chiude l'eventuale membership attiva precedente
-- (tier unico: una sola attiva per cliente). Ritorna jsonb { ok, reason?, membership_id? }.

CREATE OR REPLACE FUNCTION "public"."assign_membership"(
    "p_client_id"   "uuid",
    "p_tier_id"     "uuid",
    "p_started_at"  "date"    DEFAULT CURRENT_DATE,
    "p_price_cents" integer   DEFAULT NULL,
    "p_note"        "text"    DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tier pass_tiers%ROWTYPE;
  v_started date := COALESCE(p_started_at, CURRENT_DATE);
  v_expires date;
  v_id uuid;
BEGIN
  IF NOT public.is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'FORBIDDEN');
  END IF;

  IF p_client_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.clients WHERE id = p_client_id AND deleted_at IS NULL
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  SELECT * INTO v_tier FROM public.pass_tiers WHERE id = p_tier_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'TIER_NOT_FOUND');
  END IF;

  v_expires := v_started + (v_tier.validity_days || ' days')::interval;

  -- Chiude l'eventuale Pass attivo precedente (rispetta l'indice "una attiva per cliente").
  UPDATE public.memberships
  SET status = 'cancelled', updated_at = now()
  WHERE client_id = p_client_id AND status = 'active' AND deleted_at IS NULL;

  INSERT INTO public.memberships (client_id, tier_id, status, started_at, expires_at, price_cents_paid, note, created_by)
  VALUES (p_client_id, p_tier_id, 'active', v_started, v_expires,
          COALESCE(p_price_cents, v_tier.price_cents), NULLIF(btrim(p_note), ''), auth.uid())
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'membership_id', v_id, 'expires_at', v_expires);
END;
$$;

ALTER FUNCTION "public"."assign_membership"("uuid", "uuid", "date", integer, "text") OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."assign_membership"("uuid", "uuid", "date", integer, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_membership"("uuid", "uuid", "date", integer, "text") TO "service_role";
COMMENT ON FUNCTION "public"."assign_membership"("uuid", "uuid", "date", integer, "text") IS 'Assegna il Community Pass a un cliente (staff). Calcola la scadenza dal tier e chiude il Pass attivo precedente. Fase 6.';

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: cancel_membership — annullamento del Pass (staff)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."cancel_membership"("p_membership_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_exists boolean;
BEGIN
  IF NOT public.is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'FORBIDDEN');
  END IF;

  SELECT EXISTS (SELECT 1 FROM public.memberships WHERE id = p_membership_id AND deleted_at IS NULL)
  INTO v_exists;
  IF NOT v_exists THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FOUND');
  END IF;

  UPDATE public.memberships
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_membership_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

ALTER FUNCTION "public"."cancel_membership"("uuid") OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."cancel_membership"("uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_membership"("uuid") TO "service_role";
COMMENT ON FUNCTION "public"."cancel_membership"("uuid") IS 'Annulla un Community Pass (staff). Fase 6.';

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: request_bussola — il cliente tesserato richiede una consulenza Bussola
-- ─────────────────────────────────────────────────────────────────────────────
-- Gating: richiede un Pass ATTIVO e non scaduto (Bussola inclusa per i tesserati). Una sola richiesta
-- aperta per volta. Ritorna jsonb { ok, reason?, request_id? }.

CREATE OR REPLACE FUNCTION "public"."request_bussola"(
    "p_preferred_at" timestamp with time zone DEFAULT NULL,
    "p_note"         "text"                   DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_my_client_id uuid;
  v_has_pass boolean;
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Bussola inclusa per i tesserati: serve un Pass attivo e non scaduto.
  SELECT EXISTS (
    SELECT 1 FROM public.memberships
    WHERE client_id = v_my_client_id AND status = 'active'
      AND deleted_at IS NULL AND expires_at >= CURRENT_DATE
  ) INTO v_has_pass;

  IF NOT v_has_pass THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NO_ACTIVE_PASS');
  END IF;

  -- Una sola richiesta aperta (pending/scheduled) alla volta.
  IF EXISTS (
    SELECT 1 FROM public.bussola_requests
    WHERE client_id = v_my_client_id AND status IN ('pending', 'scheduled')
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_OPEN');
  END IF;

  INSERT INTO public.bussola_requests (client_id, status, preferred_at, note)
  VALUES (v_my_client_id, 'pending', p_preferred_at, NULLIF(btrim(p_note), ''))
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'request_id', v_id);
END;
$$;

ALTER FUNCTION "public"."request_bussola"(timestamp with time zone, "text") OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."request_bussola"(timestamp with time zone, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_bussola"(timestamp with time zone, "text") TO "service_role";
COMMENT ON FUNCTION "public"."request_bussola"(timestamp with time zone, "text") IS 'Il cliente tesserato (Pass attivo) richiede una Bussola 15''. Una richiesta aperta per volta; lo staff la schedula. Fase 6 (item F).';

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: cancel_bussola_request — annullamento richiesta Bussola (cliente o staff)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."cancel_bussola_request"("p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_my_client_id uuid;
  v_req bussola_requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  SELECT * INTO v_req FROM public.bussola_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FOUND');
  END IF;

  -- Autorizzazione: lo staff può annullare qualsiasi richiesta; il cliente solo le proprie.
  IF NOT public.is_staff() THEN
    v_my_client_id := public.get_my_client_id();
    IF v_my_client_id IS NULL OR v_req.client_id <> v_my_client_id THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FORBIDDEN');
    END IF;
  END IF;

  IF v_req.status NOT IN ('pending', 'scheduled') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_CANCELLABLE');
  END IF;

  UPDATE public.bussola_requests
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

ALTER FUNCTION "public"."cancel_bussola_request"("uuid") OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."cancel_bussola_request"("uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_bussola_request"("uuid") TO "service_role";
COMMENT ON FUNCTION "public"."cancel_bussola_request"("uuid") IS 'Annulla una richiesta Bussola aperta (cliente proprietario o staff). Fase 6 (item F).';
