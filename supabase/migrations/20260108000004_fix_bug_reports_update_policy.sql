-- Migration: Fix bug_reports UPDATE policy for soft delete
-- 
-- Obiettivo: Correggere la policy UPDATE per permettere agli admin di fare 
-- soft delete (impostare deleted_at) senza errori RLS.
-- 
-- Problema: Quando si fa PATCH per impostare deleted_at, Supabase verifica
-- se la riga risultante può essere letta. La policy SELECT filtra deleted_at IS NULL,
-- quindi potrebbe interferire. La policy UPDATE deve permettere agli admin di
-- aggiornare qualsiasi riga, indipendentemente dal valore di deleted_at.

-- ============================================================================
-- 1. RIMUOVI E RICREA LA POLICY UPDATE
-- ============================================================================

-- Rimuovi la policy esistente
DROP POLICY IF EXISTS "bug_reports_update_admin" ON "public"."bug_reports";

-- Ricrea la policy UPDATE
-- IMPORTANTE: Non verifichiamo deleted_at perché gli admin devono poter
-- aggiornare anche righe con deleted_at già impostato (per ripristinarle)
CREATE POLICY "bug_reports_update_admin" 
ON "public"."bug_reports" 
FOR UPDATE 
TO "authenticated" 
USING (
  -- L'utente deve essere admin per aggiornare
  -- Non verifichiamo deleted_at perché gli admin devono poter aggiornare
  -- anche righe soft-deleted (per ripristinarle)
  "public"."is_admin"()
)
WITH CHECK (
  -- Dopo l'update, l'utente deve ancora essere admin
  -- Non verifichiamo deleted_at perché gli admin devono poter fare soft delete
  -- e aggiornare righe soft-deleted
  "public"."is_admin"()
);

-- ============================================================================
-- 2. AGGIORNA LA POLICY SELECT PER PERMETTERE AGLI ADMIN DI VEDERE 
--    ANCHE I BUG SOFT-DELETED (OPZIONALE, MA UTILE PER IL GESTIONALE)
-- ============================================================================

-- Rimuovi la policy SELECT esistente
DROP POLICY IF EXISTS "bug_reports_select_own_or_admin" ON "public"."bug_reports";

-- Ricrea la policy SELECT
-- Gli admin possono vedere tutti i bug (inclusi quelli soft-deleted)
-- Gli utenti normali possono vedere solo i propri bug non soft-deleted
CREATE POLICY "bug_reports_select_own_or_admin" 
ON "public"."bug_reports" 
FOR SELECT 
TO "authenticated" 
USING (
  (
    -- Admin può vedere tutti i bug (inclusi quelli soft-deleted)
    "public"."is_admin"()
  )
  OR
  (
    -- Utente può vedere solo i propri bug non soft-deleted
    "deleted_at" IS NULL
    AND "created_by_user_id" = "auth"."uid"() 
    AND "created_by_client_id" IS NULL
  )
);

-- ============================================================================
-- 2. NOTES
-- ============================================================================
-- La policy UPDATE permette agli admin di:
-- - Aggiornare qualsiasi campo del bug report (incluso status, deleted_at, ecc.)
-- - Fare soft delete impostando deleted_at
-- - Aggiornare bug anche se hanno già deleted_at impostato (per ripristinarli)
-- 
-- La policy SELECT continua a filtrare i bug con deleted_at IS NULL per gli utenti normali,
-- ma gli admin possono vedere tutti i bug (inclusi quelli soft-deleted) se necessario.

