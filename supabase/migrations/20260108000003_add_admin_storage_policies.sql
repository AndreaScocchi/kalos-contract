-- Migration: Add admin storage policies for bug-reports bucket
-- 
-- Obiettivo: Aggiungere le policy mancanti per permettere agli admin di 
-- caricare e aggiornare file nel bucket bug-reports.
-- 
-- Questa migration aggiunge le policy che mancavano nella migration iniziale
-- 20260108000001_create_bug_reports_storage.sql

-- ============================================================================
-- 1. POLICY INSERT: Admin possono caricare file ovunque nel bucket
-- ============================================================================

-- Rimuovi la policy se esiste già (per idempotenza)
DROP POLICY IF EXISTS "bug_reports_admins_upload_all" ON storage.objects;

-- Policy INSERT: Gli admin possono caricare file ovunque nel bucket
-- Permette agli admin di caricare immagini per conto di altri utenti o per gestire bug reports
CREATE POLICY "bug_reports_admins_upload_all"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'bug-reports' 
  AND public.is_admin()
);

-- ============================================================================
-- 2. POLICY UPDATE: Admin possono aggiornare tutti i file
-- ============================================================================

-- Rimuovi la policy se esiste già (per idempotenza)
DROP POLICY IF EXISTS "bug_reports_admins_update_all_files" ON storage.objects;

-- Policy UPDATE: Gli admin possono aggiornare tutti i file
CREATE POLICY "bug_reports_admins_update_all_files"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'bug-reports' 
  AND public.is_admin()
)
WITH CHECK (
  bucket_id = 'bug-reports' 
  AND public.is_admin()
);

-- ============================================================================
-- 3. NOTES
-- ============================================================================
-- Queste policy permettono agli admin di:
-- - Caricare file nel bucket bug-reports senza restrizioni sul path
-- - Aggiornare qualsiasi file nel bucket bug-reports
-- 
-- Le policy per gli utenti normali rimangono invariate:
-- - Possono caricare solo nella propria cartella ({user_id}/*)
-- - Possono leggere/aggiornare/eliminare solo i propri file
-- 
-- Le policy per gli admin includono ora:
-- - INSERT: bug_reports_admins_upload_all
-- - SELECT: bug_reports_admins_view_all_files (già esistente)
-- - UPDATE: bug_reports_admins_update_all_files
-- - DELETE: bug_reports_admins_delete_all_files (già esistente)

