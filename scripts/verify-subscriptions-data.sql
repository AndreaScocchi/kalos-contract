-- Script per verificare subscriptions con dati inconsistenti
-- 
-- Questo script verifica:
-- 1. Subscriptions con user_id IS NULL e client_id IS NULL (dovrebbero essere rimosse o corrette)
-- 2. Subscriptions con user_id IS NOT NULL e client_id IS NOT NULL (violano il constraint XOR)
-- 3. Subscriptions con user_id che non corrisponde a nessun profilo esistente
-- 4. Subscriptions con client_id che non corrisponde a nessun client esistente

-- ============================================================================
-- 1. SUBSCRIPTIONS CON user_id IS NULL E client_id IS NULL
-- ============================================================================

SELECT 
  'Subscriptions con user_id IS NULL e client_id IS NULL (dovrebbero essere rimosse o corrette)' AS check_type,
  COUNT(*) AS count,
  array_agg(id ORDER BY created_at DESC) AS subscription_ids
FROM public.subscriptions
WHERE user_id IS NULL 
  AND client_id IS NULL
  AND deleted_at IS NULL;

-- ============================================================================
-- 2. SUBSCRIPTIONS CON user_id IS NOT NULL E client_id IS NOT NULL
-- (violano il constraint XOR - non dovrebbero esistere)
-- ============================================================================

SELECT 
  'Subscriptions con user_id IS NOT NULL e client_id IS NOT NULL (violano constraint XOR)' AS check_type,
  COUNT(*) AS count,
  array_agg(id ORDER BY created_at DESC) AS subscription_ids
FROM public.subscriptions
WHERE user_id IS NOT NULL 
  AND client_id IS NOT NULL
  AND deleted_at IS NULL;

-- ============================================================================
-- 3. SUBSCRIPTIONS CON user_id CHE NON CORRISPONDE A NESSUN PROFILO ESISTENTE
-- ============================================================================

SELECT 
  'Subscriptions con user_id che non corrisponde a nessun profilo esistente' AS check_type,
  COUNT(*) AS count,
  array_agg(s.id ORDER BY s.created_at DESC) AS subscription_ids,
  array_agg(DISTINCT s.user_id) AS invalid_user_ids
FROM public.subscriptions s
LEFT JOIN public.profiles p ON p.id = s.user_id
WHERE s.user_id IS NOT NULL
  AND p.id IS NULL
  AND s.deleted_at IS NULL;

-- ============================================================================
-- 4. SUBSCRIPTIONS CON client_id CHE NON CORRISPONDE A NESSUN CLIENT ESISTENTE
-- ============================================================================

SELECT 
  'Subscriptions con client_id che non corrisponde a nessun client esistente' AS check_type,
  COUNT(*) AS count,
  array_agg(s.id ORDER BY s.created_at DESC) AS subscription_ids,
  array_agg(DISTINCT s.client_id) AS invalid_client_ids
FROM public.subscriptions s
LEFT JOIN public.clients c ON c.id = s.client_id
WHERE s.client_id IS NOT NULL
  AND c.id IS NULL
  AND s.deleted_at IS NULL;

-- ============================================================================
-- 5. RIEPILOGO GENERALE
-- ============================================================================

SELECT 
  'Riepilogo generale subscriptions' AS check_type,
  COUNT(*) FILTER (WHERE user_id IS NOT NULL AND client_id IS NULL) AS account_owned,
  COUNT(*) FILTER (WHERE user_id IS NULL AND client_id IS NOT NULL) AS client_owned,
  COUNT(*) FILTER (WHERE user_id IS NULL AND client_id IS NULL) AS orphaned,
  COUNT(*) FILTER (WHERE user_id IS NOT NULL AND client_id IS NOT NULL) AS invalid_xor,
  COUNT(*) FILTER (WHERE deleted_at IS NOT NULL) AS deleted,
  COUNT(*) AS total
FROM public.subscriptions;

