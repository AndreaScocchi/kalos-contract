-- Migration: Make newsletter bucket public for permanent image URLs in emails
--
-- Problema: Le immagini nelle email newsletter usano signed URLs che scadono dopo 1 ora.
-- Dopo la scadenza, le immagini non sono più visibili nelle email.
--
-- Soluzione: Rendere il bucket pubblico. Le immagini newsletter sono contenuti marketing,
-- non dati sensibili, quindi possono essere accessibili pubblicamente.

-- ============================================================================
-- 1. UPDATE BUCKET TO PUBLIC
-- ============================================================================

UPDATE storage.buckets
SET public = true
WHERE id = 'newsletter';

-- ============================================================================
-- 2. ADD PUBLIC READ POLICY
-- ============================================================================
-- Aggiungiamo una policy che permette a chiunque (anche anonimi) di leggere le immagini

CREATE POLICY "newsletter_public_read"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'newsletter');

-- ============================================================================
-- 3. NOTES
-- ============================================================================
--
-- Con il bucket pubblico, le immagini sono accessibili tramite URL pubblici permanenti:
-- https://{project-id}.supabase.co/storage/v1/object/public/newsletter/{filename}
--
-- Le policy di upload/update/delete rimangono invariate (solo staff autenticato).
