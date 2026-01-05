-- Migration 0023: Fix subscriptions RLS policy to prevent users from seeing client-owned subscriptions
--
-- Problema: Gli utenti vedono subscriptions che non appartengono loro perché la policy
-- attuale permette di vedere subscriptions tramite client_id collegato al loro profile_id.
--
-- Soluzione: Correggere la policy SELECT per garantire che:
-- - Gli utenti autenticati vedano SOLO subscriptions con user_id = auth.uid() e client_id IS NULL
-- - Lo staff possa vedere tutte le subscriptions
-- - Gli utenti NON vedano subscriptions con client_id IS NOT NULL, anche se il client è collegato al loro profile_id
--
-- Contesto: Secondo DB_CONTEXT.md, l'app utente deve vedere SOLO subscriptions account-owned
-- (user_id = auth.uid() AND client_id IS NULL). Le subscriptions client-owned (client_id IS NOT NULL)
-- sono gestite solo dal gestionale e non devono essere visibili agli utenti dell'app.

-- ============================================================================
-- 1. RIMUOVI LA POLICY ESISTENTE
-- ============================================================================

DROP POLICY IF EXISTS "subscriptions_select_own_or_staff" ON "public"."subscriptions";

-- ============================================================================
-- 2. CREA LA NUOVA POLICY CORRETTA
-- ============================================================================

-- Policy SELECT per subscriptions:
-- - Utenti normali: vedono SOLO subscriptions con user_id = auth.uid() AND client_id IS NULL
-- - Staff: vedono tutte le subscriptions
CREATE POLICY "subscriptions_select_own_or_staff" 
ON "public"."subscriptions" 
FOR SELECT 
TO "authenticated" 
USING (
  -- Per utenti normali: solo subscriptions account-owned
  (
    auth.uid() IS NOT NULL 
    AND user_id = auth.uid() 
    AND user_id IS NOT NULL 
    AND client_id IS NULL
  )
  OR
  -- Per staff: tutte le subscriptions
  (public.is_staff() = true)
);

-- ============================================================================
-- 3. CORREZIONE POLICY PER subscription_usages
-- ============================================================================

-- Anche subscription_usages ha lo stesso problema: permette di vedere usages
-- tramite subscriptions client-owned. Secondo DB_CONTEXT.md, gli utenti devono
-- vedere solo subscription_usages collegati a subscriptions account-owned.

DROP POLICY IF EXISTS "subscription_usages_select_own_or_staff" ON "public"."subscription_usages";

-- Policy SELECT per subscription_usages:
-- - Utenti normali: vedono SOLO usages collegati a subscriptions con user_id = auth.uid() AND client_id IS NULL
-- - Staff: vedono tutti gli usages
CREATE POLICY "subscription_usages_select_own_or_staff" 
ON "public"."subscription_usages" 
FOR SELECT 
TO "authenticated" 
USING (
  -- Per staff: tutti gli usages
  (public.is_staff() = true)
  OR
  -- Per utenti normali: solo usages collegati a subscriptions account-owned
  (
    auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.subscriptions s
      WHERE s.id = subscription_usages.subscription_id
        AND s.user_id = auth.uid()
        AND s.user_id IS NOT NULL
        AND s.client_id IS NULL
    )
  )
);

-- ============================================================================
-- 4. COMMENTI ESPLICATIVI
-- ============================================================================

COMMENT ON POLICY "subscriptions_select_own_or_staff" ON "public"."subscriptions" IS 
'RLS policy per SELECT su subscriptions. Gli utenti autenticati vedono SOLO subscriptions con user_id = auth.uid() e client_id IS NULL (account-owned). Lo staff vede tutte le subscriptions. Gli utenti NON vedono subscriptions client-owned, anche se il client è collegato al loro profile_id.';

COMMENT ON POLICY "subscription_usages_select_own_or_staff" ON "public"."subscription_usages" IS 
'RLS policy per SELECT su subscription_usages. Gli utenti autenticati vedono SOLO usages collegati a subscriptions con user_id = auth.uid() e client_id IS NULL (account-owned). Lo staff vede tutti gli usages. Gli utenti NON vedono usages collegati a subscriptions client-owned.';

