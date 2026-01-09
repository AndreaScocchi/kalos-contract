-- Migration: Grant permissions on bug_reports table
-- 
-- Obiettivo: Concedere i permessi necessari agli utenti autenticati sulla tabella bug_reports.
-- Le RLS policies controllano cosa possono fare, ma servono comunque i GRANT di base.

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Concedi permessi SELECT, INSERT, UPDATE, DELETE agli utenti autenticati
-- Le RLS policies controlleranno cosa possono effettivamente fare
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."bug_reports" TO "authenticated";

-- Concedi permessi anche al service_role (per operazioni amministrative)
GRANT ALL ON TABLE "public"."bug_reports" TO "service_role";

-- Concedi permessi di utilizzo sulla sequenza (se presente) e sul tipo enum
GRANT USAGE ON TYPE "public"."bug_status" TO "authenticated";

