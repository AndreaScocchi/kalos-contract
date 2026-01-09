-- Migration: Create bug_reports table for bug tracking
-- 
-- Obiettivo: Permettere a clienti e operatori di segnalare bug.
-- Gli admin possono visualizzare tutti i bug, gli utenti solo i propri.

-- ============================================================================
-- 1. CREATE ENUM FOR BUG STATUS
-- ============================================================================

CREATE TYPE "public"."bug_status" AS ENUM (
    'open',
    'in_progress',
    'resolved',
    'closed'
);
ALTER TYPE "public"."bug_status" OWNER TO "postgres";

-- ============================================================================
-- 2. CREATE bug_reports TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."bug_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "image_url" "text",
    "created_by_user_id" "uuid",
    "created_by_client_id" "uuid",
    "status" "public"."bug_status" DEFAULT 'open'::"public"."bug_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "bug_reports_user_client_xor" CHECK (
        (("created_by_user_id" IS NOT NULL) AND ("created_by_client_id" IS NULL)) 
        OR 
        (("created_by_user_id" IS NULL) AND ("created_by_client_id" IS NOT NULL))
    )
);
ALTER TABLE "public"."bug_reports" OWNER TO "postgres";

-- ============================================================================
-- 3. PRIMARY KEY AND INDEXES
-- ============================================================================

ALTER TABLE "public"."bug_reports" ADD CONSTRAINT "bug_reports_pkey" PRIMARY KEY ("id");

CREATE INDEX "bug_reports_created_by_user_id_idx" ON "public"."bug_reports" ("created_by_user_id");
CREATE INDEX "bug_reports_created_by_client_id_idx" ON "public"."bug_reports" ("created_by_client_id");
CREATE INDEX "bug_reports_status_idx" ON "public"."bug_reports" ("status");
CREATE INDEX "bug_reports_created_at_idx" ON "public"."bug_reports" ("created_at" DESC);
CREATE INDEX "bug_reports_deleted_at_idx" ON "public"."bug_reports" ("deleted_at") WHERE "deleted_at" IS NULL;

-- ============================================================================
-- 4. FOREIGN KEYS
-- ============================================================================

ALTER TABLE "public"."bug_reports" 
    ADD CONSTRAINT "bug_reports_created_by_user_id_fkey" 
    FOREIGN KEY ("created_by_user_id") 
    REFERENCES "public"."profiles"("id") 
    ON DELETE SET NULL;

ALTER TABLE "public"."bug_reports" 
    ADD CONSTRAINT "bug_reports_created_by_client_id_fkey" 
    FOREIGN KEY ("created_by_client_id") 
    REFERENCES "public"."clients"("id") 
    ON DELETE SET NULL;

-- ============================================================================
-- 5. TRIGGER FOR updated_at
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."update_bug_reports_updated_at"()
RETURNS "trigger"
LANGUAGE "plpgsql"
AS $$
BEGIN
    NEW."updated_at" = now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER "bug_reports_updated_at"
    BEFORE UPDATE ON "public"."bug_reports"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."update_bug_reports_updated_at"();

-- ============================================================================
-- 6. ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE "public"."bug_reports" ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 7. RLS POLICIES
-- ============================================================================

-- Policy INSERT: Tutti gli utenti autenticati possono creare bug
-- - Clienti: usano created_by_user_id (via auth.uid())
-- - Operator/Staff: possono usare created_by_client_id per segnalare bug per conto di clienti
CREATE POLICY "bug_reports_insert_authenticated" 
ON "public"."bug_reports" 
FOR INSERT 
TO "authenticated" 
WITH CHECK (
    -- Utente normale: può creare solo bug con il proprio user_id
    (
        "created_by_user_id" = "auth"."uid"() 
        AND "created_by_client_id" IS NULL
    )
    OR
    -- Staff: può creare bug con client_id (per conto di clienti senza account)
    (
        "public"."is_staff"() 
        AND "created_by_user_id" IS NULL 
        AND "created_by_client_id" IS NOT NULL
    )
    OR
    -- Staff: può creare bug con il proprio user_id
    (
        "public"."is_staff"() 
        AND "created_by_user_id" = "auth"."uid"() 
        AND "created_by_client_id" IS NULL
    )
);

-- Policy SELECT: 
-- - Admin: può vedere tutti i bug (esclusi quelli soft-deleted)
-- - Utenti normali: possono vedere solo i propri bug (via user_id)
-- - Staff: possono vedere i bug creati con il proprio user_id
CREATE POLICY "bug_reports_select_own_or_admin" 
ON "public"."bug_reports" 
FOR SELECT 
TO "authenticated" 
USING (
    "deleted_at" IS NULL
    AND (
        -- Admin può vedere tutti i bug
        "public"."is_admin"()
        OR
        -- Utente può vedere i propri bug (via user_id)
        (
            "created_by_user_id" = "auth"."uid"() 
            AND "created_by_client_id" IS NULL
        )
    )
);

-- Policy UPDATE: Solo admin può aggiornare i bug (per cambiare status, ecc.)
CREATE POLICY "bug_reports_update_admin" 
ON "public"."bug_reports" 
FOR UPDATE 
TO "authenticated" 
USING ("public"."is_admin"())
WITH CHECK ("public"."is_admin"());

-- Policy DELETE: Solo admin può fare soft delete
CREATE POLICY "bug_reports_delete_admin" 
ON "public"."bug_reports" 
FOR DELETE 
TO "authenticated" 
USING ("public"."is_admin"());

-- ============================================================================
-- 8. COMMENTS
-- ============================================================================

COMMENT ON TABLE "public"."bug_reports" IS 
'Tabella per segnalazioni bug da parte di clienti e operatori. Gli admin possono visualizzare tutti i bug.';

COMMENT ON COLUMN "public"."bug_reports"."title" IS 
'Titolo del bug (obbligatorio)';

COMMENT ON COLUMN "public"."bug_reports"."description" IS 
'Descrizione dettagliata del bug (obbligatorio)';

COMMENT ON COLUMN "public"."bug_reports"."image_url" IS 
'URL dell immagine/screenshot del bug (opzionale ma consigliato)';

COMMENT ON COLUMN "public"."bug_reports"."created_by_user_id" IS 
'ID del profilo utente che ha creato il bug (per clienti con account)';

COMMENT ON COLUMN "public"."bug_reports"."created_by_client_id" IS 
'ID del cliente che ha creato il bug (per clienti senza account, creato da staff)';

COMMENT ON COLUMN "public"."bug_reports"."status" IS 
'Stato del bug: open, in_progress, resolved, closed';

COMMENT ON POLICY "bug_reports_insert_authenticated" ON "public"."bug_reports" IS 
'RLS: Permette INSERT a tutti gli utenti autenticati. Clienti usano user_id, staff può usare client_id.';

COMMENT ON POLICY "bug_reports_select_own_or_admin" ON "public"."bug_reports" IS 
'RLS: Admin può vedere tutti i bug. Utenti normali solo i propri (via user_id).';

COMMENT ON POLICY "bug_reports_update_admin" ON "public"."bug_reports" IS 
'RLS: Solo admin può aggiornare i bug (per cambiare status, ecc.).';

COMMENT ON POLICY "bug_reports_delete_admin" ON "public"."bug_reports" IS 
'RLS: Solo admin può fare soft delete dei bug.';

