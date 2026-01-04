-- Migration 0017: Hide Individual Lessons from Public Access
-- 
-- Obiettivo: Le lezioni individuali devono essere visibili solo:
-- 1. Dal gestionale (staff)
-- 2. A chi è stata assegnata
-- 
-- Problema: La policy "lessons_select_public_active" permette a tutti (anon e authenticated)
-- di vedere tutte le lezioni non soft-deleted, incluse quelle individuali.
--
-- Soluzione: Modificare "lessons_select_public_active" per escludere le lezioni individuali.
-- Le lezioni individuali saranno accessibili solo tramite la policy "Clients can view their lessons"
-- che già filtra correttamente per staff o assegnatari.

-- ============================================================================
-- 1. DROP e RECREATE policy "lessons_select_public_active"
-- ============================================================================

DROP POLICY IF EXISTS "lessons_select_public_active" ON "public"."lessons";

CREATE POLICY "lessons_select_public_active" ON "public"."lessons" 
FOR SELECT 
USING (
  ("deleted_at" IS NULL) 
  AND ("is_individual" = false)
);

COMMENT ON POLICY "lessons_select_public_active" ON public.lessons IS 
  'RLS: Accesso pubblico (anon) solo a lezioni pubbliche (non individuali) non soft-deleted. Le lezioni individuali sono accessibili solo tramite "Clients can view their lessons" (staff o assegnatari).';

