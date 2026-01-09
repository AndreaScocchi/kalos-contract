-- Migration: Create bug-reports storage bucket and policies
-- 
-- Obiettivo: Creare il bucket per le immagini dei bug reports con policy di sicurezza
-- che permettono agli utenti di caricare solo nella propria cartella e agli admin
-- di vedere tutti i file.

-- ============================================================================
-- 1. CREATE STORAGE BUCKET
-- ============================================================================

-- Crea il bucket bug-reports (privato)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'bug-reports',
  'bug-reports',
  false, -- bucket privato
  5242880, -- 5MB in bytes (limite dimensione file)
  ARRAY['image/jpeg', 'image/png', 'image/jpg'] -- solo immagini
)
ON CONFLICT (id) DO NOTHING; -- evita errore se il bucket esiste già

-- ============================================================================
-- 2. STORAGE POLICIES
-- ============================================================================
-- Nota: RLS è già abilitato di default su storage.objects in Supabase

-- Policy INSERT: Gli utenti autenticati possono caricare solo nella propria cartella
-- Path formato: {user_id}/{timestamp}.{ext}
CREATE POLICY "bug_reports_users_upload_own_folder"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'bug-reports' 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

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

-- Policy SELECT: Gli utenti possono leggere solo i propri file
CREATE POLICY "bug_reports_users_view_own_files"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'bug-reports' 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy SELECT: Gli admin possono vedere tutti i file
CREATE POLICY "bug_reports_admins_view_all_files"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'bug-reports' 
  AND public.is_admin()
);

-- Policy UPDATE: Gli utenti possono aggiornare solo i propri file
CREATE POLICY "bug_reports_users_update_own_files"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'bug-reports' 
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'bug-reports' 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

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

-- Policy DELETE: Gli utenti possono eliminare solo i propri file
CREATE POLICY "bug_reports_users_delete_own_files"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'bug-reports' 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy DELETE: Gli admin possono eliminare tutti i file
CREATE POLICY "bug_reports_admins_delete_all_files"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'bug-reports' 
  AND public.is_admin()
);

-- ============================================================================
-- 4. NOTES
-- ============================================================================
-- Nota: I COMMENT ON POLICY non possono essere aggiunti su storage.objects
-- perché non siamo proprietari della tabella. Le policy sono documentate qui:
-- 
-- - bug_reports_users_upload_own_folder: Gli utenti autenticati possono caricare 
--   file solo nella propria cartella (bug-reports/{user_id}/...)
-- - bug_reports_admins_upload_all: Gli admin possono caricare file ovunque nel 
--   bucket bug-reports (per gestire bug reports per conto di altri utenti)
-- - bug_reports_users_view_own_files: Gli utenti possono leggere solo i propri 
--   file nel bucket bug-reports
-- - bug_reports_admins_view_all_files: Gli admin possono vedere tutti i file 
--   nel bucket bug-reports
-- - bug_reports_users_update_own_files: Gli utenti possono aggiornare solo i 
--   propri file nel bucket bug-reports
-- - bug_reports_admins_update_all_files: Gli admin possono aggiornare tutti i 
--   file nel bucket bug-reports
-- - bug_reports_users_delete_own_files: Gli utenti possono eliminare solo i 
--   propri file nel bucket bug-reports
-- - bug_reports_admins_delete_all_files: Gli admin possono eliminare tutti i 
--   file nel bucket bug-reports

