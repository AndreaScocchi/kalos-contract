-- Migration: Create newsletter storage bucket and policies
--
-- Obiettivo: Creare il bucket per le immagini delle newsletter con policy di sicurezza
-- che permettono allo staff di caricare e visualizzare le immagini.

-- ============================================================================
-- 1. CREATE STORAGE BUCKET
-- ============================================================================

-- Crea il bucket newsletter (privato)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'newsletter',
  'newsletter',
  false, -- bucket privato
  5242880, -- 5MB in bytes (limite dimensione file)
  ARRAY['image/jpeg', 'image/png', 'image/jpg', 'image/gif', 'image/webp'] -- solo immagini
)
ON CONFLICT (id) DO NOTHING; -- evita errore se il bucket esiste già

-- ============================================================================
-- 2. STORAGE POLICIES
-- ============================================================================
-- Nota: RLS è già abilitato di default su storage.objects in Supabase
-- Per le newsletter, solo lo staff può caricare/vedere le immagini

-- Policy INSERT: Lo staff può caricare immagini
CREATE POLICY "newsletter_staff_upload"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'newsletter'
  AND public.is_staff()
);

-- Policy SELECT: Lo staff può vedere le immagini
CREATE POLICY "newsletter_staff_view"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'newsletter'
  AND public.is_staff()
);

-- Policy UPDATE: Lo staff può aggiornare le immagini
CREATE POLICY "newsletter_staff_update"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'newsletter'
  AND public.is_staff()
)
WITH CHECK (
  bucket_id = 'newsletter'
  AND public.is_staff()
);

-- Policy DELETE: Lo staff può eliminare le immagini
CREATE POLICY "newsletter_staff_delete"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'newsletter'
  AND public.is_staff()
);

-- ============================================================================
-- 3. NOTES
-- ============================================================================
--
-- Nota: A differenza del bucket bug-reports, qui non c'è separazione per utente.
-- Tutte le immagini newsletter sono accessibili a tutto lo staff.
--
-- Path formato: {timestamp}-{random}.{ext}
-- Esempio: 1705151234567-abc123.jpg
