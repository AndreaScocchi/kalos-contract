-- Migration: Add image_url column to newsletter_campaigns
--
-- Obiettivo: Permettere l'aggiunta di un'immagine alle newsletter

-- Aggiungere colonna image_url alla tabella newsletter_campaigns
ALTER TABLE "public"."newsletter_campaigns"
  ADD COLUMN IF NOT EXISTS "image_url" TEXT;

-- Comment
COMMENT ON COLUMN "public"."newsletter_campaigns"."image_url" IS
'Path relativo dell''immagine nel bucket storage newsletter, o URL completo';
