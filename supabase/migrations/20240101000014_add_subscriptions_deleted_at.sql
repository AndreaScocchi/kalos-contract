-- Migration 0014: Add deleted_at field to subscriptions table
-- 
-- Obiettivo: Aggiungere il campo deleted_at alla tabella subscriptions per supportare
-- la cancellazione definitiva (soft delete) degli abbonamenti.
--
-- Comportamento:
-- - Quando un abbonamento viene cancellato, viene impostato deleted_at = NOW()
-- - Gli abbonamenti con deleted_at IS NOT NULL non sono più visibili nelle query
-- - La cancellazione è definitiva: deleted_at non viene mai resettato a NULL
-- - Gli abbonamenti esistenti avranno deleted_at = NULL dopo la migrazione
--
-- Implicazioni:
-- - Tutte le query che recuperano abbonamenti devono filtrare per deleted_at IS NULL
-- - La view subscriptions_with_remaining viene aggiornata per escludere abbonamenti cancellati
-- - Le RLS policies continuano a funzionare (il filtro deleted_at viene applicato lato applicazione)

-- ============================================================================
-- 1. AGGIUNTA CAMPO deleted_at
-- ============================================================================

ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL;

-- ============================================================================
-- 2. COMMENTO ESPLICATIVO
-- ============================================================================

COMMENT ON COLUMN public.subscriptions.deleted_at IS 
  'Timestamp di cancellazione definitiva (soft delete). Se NULL, l''abbonamento è attivo. Se NOT NULL, l''abbonamento è stato cancellato definitivamente e non è più visibile.';

-- ============================================================================
-- 3. INDICE PER PERFORMANCE
-- ============================================================================

-- Indice parziale per migliorare le performance delle query che filtrano per deleted_at IS NULL
CREATE INDEX IF NOT EXISTS idx_subscriptions_deleted_at_null 
  ON public.subscriptions(deleted_at) 
  WHERE deleted_at IS NULL;

-- ============================================================================
-- 4. AGGIORNAMENTO VIEW subscriptions_with_remaining
-- ============================================================================

-- Aggiorna la view per escludere automaticamente gli abbonamenti cancellati
CREATE OR REPLACE VIEW public.subscriptions_with_remaining 
  WITH (security_invoker = true) 
AS
WITH usage_totals AS (
  SELECT 
    subscription_usages.subscription_id,
    COALESCE(SUM(subscription_usages.delta), 0)::bigint AS delta_sum
  FROM public.subscription_usages
  GROUP BY subscription_usages.subscription_id
)
SELECT 
  s.id,
  s.user_id,
  s.client_id,
  s.plan_id,
  s.status,
  s.started_at,
  s.expires_at,
  s.custom_name,
  s.custom_price_cents,
  s.custom_entries,
  s.custom_validity_days,
  s.metadata,
  s.created_at,
  COALESCE(s.custom_entries, p.entries) AS effective_entries,
  CASE
    WHEN COALESCE(s.custom_entries, p.entries) IS NOT NULL 
    THEN COALESCE(s.custom_entries, p.entries) + COALESCE(u.delta_sum, 0)::bigint
    ELSE NULL::bigint
  END AS remaining_entries
FROM public.subscriptions s
LEFT JOIN public.plans p ON p.id = s.plan_id
LEFT JOIN usage_totals u ON u.subscription_id = s.id
WHERE s.deleted_at IS NULL; -- Escludi abbonamenti cancellati

ALTER VIEW public.subscriptions_with_remaining OWNER TO postgres;

-- ============================================================================
-- 5. NOTA SULLE RLS POLICIES
-- ============================================================================

-- Le RLS policies esistenti continuano a funzionare correttamente:
-- - subscriptions_select_own_or_staff: continua a permettere SELECT per utenti autorizzati
-- - subscriptions_write_staff: continua a permettere INSERT/UPDATE/DELETE solo allo staff
--
-- Il filtro deleted_at IS NULL viene applicato lato applicazione nelle query.
-- Le RLS policies non richiedono modifiche perché:
-- 1. Le policies di SELECT continuano a funzionare (il filtro deleted_at viene applicato lato applicazione)
-- 2. Le policies di UPDATE permettono già di aggiornare qualsiasi campo (incluso deleted_at) allo staff
-- 3. Le policies di INSERT non richiedono deleted_at (deve essere NULL di default)

