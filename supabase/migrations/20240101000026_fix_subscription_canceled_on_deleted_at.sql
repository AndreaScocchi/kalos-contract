-- Migration 0026: Fix subscription status when deleted_at is set
--
-- Obiettivo: Assicurare che quando un abbonamento viene cancellato (deleted_at popolato),
-- lo stato passi automaticamente a "canceled".
--
-- Problema: Attualmente ci sono abbonamenti con deleted_at popolato ma status != "canceled".
-- Questo non deve succedere: quando deleted_at viene impostato, lo status deve essere "canceled".
--
-- Soluzione:
-- 1. Correggere gli abbonamenti esistenti con deleted_at IS NOT NULL ma status != "canceled"
-- 2. Creare un trigger che automaticamente imposta status = "canceled" quando deleted_at viene impostato

-- ============================================================================
-- 1. CORREZIONE ABBONAMENTI ESISTENTI
-- ============================================================================

-- Aggiorna tutti gli abbonamenti che hanno deleted_at popolato ma status != "canceled"
UPDATE public.subscriptions
SET status = 'canceled'::subscription_status
WHERE deleted_at IS NOT NULL
  AND status != 'canceled'::subscription_status;

-- ============================================================================
-- 2. TRIGGER PER GARANTIRE CONSISTENZA FUTURA
-- ============================================================================

-- Funzione trigger che imposta status = "canceled" quando deleted_at viene impostato
CREATE OR REPLACE FUNCTION public.ensure_subscription_canceled_on_deleted_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Se deleted_at viene impostato (passa da NULL a NOT NULL), imposta status = "canceled"
  -- Gestisce sia INSERT (OLD è NULL) che UPDATE (OLD esiste)
  IF NEW.deleted_at IS NOT NULL THEN
    -- Per INSERT: OLD è NULL, quindi se NEW.deleted_at IS NOT NULL, imposta canceled
    -- Per UPDATE: se OLD.deleted_at era NULL e NEW.deleted_at è NOT NULL, imposta canceled
    IF OLD IS NULL OR OLD.deleted_at IS NULL THEN
      NEW.status := 'canceled'::subscription_status;
    END IF;
  END IF;
  
  -- Se deleted_at viene resettato a NULL (non dovrebbe succedere, ma per sicurezza)
  -- non modifichiamo lo status (potrebbe essere stato impostato manualmente)
  
  RETURN NEW;
END;
$$;

-- Crea il trigger BEFORE UPDATE per intercettare le modifiche a deleted_at
DROP TRIGGER IF EXISTS trigger_ensure_subscription_canceled_on_deleted_at ON public.subscriptions;
CREATE TRIGGER trigger_ensure_subscription_canceled_on_deleted_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW
  WHEN (NEW.deleted_at IS DISTINCT FROM OLD.deleted_at)
  EXECUTE FUNCTION public.ensure_subscription_canceled_on_deleted_at();

-- Crea anche un trigger BEFORE INSERT per sicurezza (anche se normalmente deleted_at dovrebbe essere NULL all'inserimento)
CREATE TRIGGER trigger_ensure_subscription_canceled_on_deleted_at_insert
  BEFORE INSERT ON public.subscriptions
  FOR EACH ROW
  WHEN (NEW.deleted_at IS NOT NULL)
  EXECUTE FUNCTION public.ensure_subscription_canceled_on_deleted_at();

-- ============================================================================
-- 3. COMMENTI ESPLICATIVI
-- ============================================================================

COMMENT ON FUNCTION public.ensure_subscription_canceled_on_deleted_at() IS 
  'Trigger function che garantisce che quando deleted_at viene impostato su subscriptions, lo status venga automaticamente impostato a "canceled". Questo mantiene la consistenza dei dati: un abbonamento cancellato (deleted_at IS NOT NULL) deve sempre avere status = "canceled".';

-- ============================================================================
-- 4. VERIFICA CONSISTENZA
-- ============================================================================

-- Query di verifica (non eseguita, solo per documentazione):
-- SELECT COUNT(*) FROM public.subscriptions 
-- WHERE deleted_at IS NOT NULL AND status != 'canceled';
-- Dovrebbe restituire 0 dopo questa migration

