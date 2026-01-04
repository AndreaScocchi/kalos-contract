-- Migration 0020: Auto-update subscription status based on expiration and entries
--
-- Obiettivo: Aggiornare automaticamente lo status degli abbonamenti in base a:
-- - Scadenza (expires_at)
-- - Posti rimanenti (remaining_entries dalla view subscriptions_with_remaining)
--
-- Logica:
-- 1. Se scaduto (expires_at < CURRENT_DATE) E ha esaurito i posti (remaining_entries <= 0) -> 'completed'
-- 2. Se scaduto (expires_at < CURRENT_DATE) ma ha ancora posti (remaining_entries > 0 o NULL) -> 'expired'
-- 3. Se non scaduto -> 'active' (mantiene o imposta a 'active')
--
-- Modifiche:
-- - Funzione trigger che verifica scadenza e posti rimanenti prima di INSERT/UPDATE
-- - Non modifica stati 'canceled' (vengono preservati)
--
-- Comportamento:
-- - Il trigger viene eseguito prima di INSERT o UPDATE sulla tabella subscriptions
-- - Calcola remaining_entries usando la stessa logica della view subscriptions_with_remaining
-- - Aggiorna solo gli abbonamenti con status = 'active' per evitare di sovrascrivere altri stati

-- ============================================================================
-- 1. FUNZIONE TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."auto_complete_expired_subscriptions"() 
RETURNS "trigger"
LANGUAGE "plpgsql"
SECURITY DEFINER
SET "search_path" TO 'public'
AS $$
DECLARE
  v_effective_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_plan_entries integer;
BEGIN
  -- Solo per abbonamenti con status 'active' (preserva 'canceled', 'expired', 'completed')
  IF NEW.status != 'active' THEN
    RETURN NEW;
  END IF;
  
  -- Se non è scaduto, mantieni 'active'
  IF NEW.expires_at >= CURRENT_DATE THEN
    RETURN NEW;
  END IF;
  
  -- Se è scaduto, calcola i posti rimanenti
  -- Calcola effective_entries (custom_entries o entries dal plan)
  SELECT entries INTO v_plan_entries
  FROM plans
  WHERE id = NEW.plan_id;
  
  v_effective_entries := COALESCE(NEW.custom_entries, v_plan_entries);
  
  -- Se l'abbonamento è illimitato (effective_entries è NULL), imposta 'expired'
  IF v_effective_entries IS NULL THEN
    NEW.status := 'expired';
    RETURN NEW;
  END IF;
  
  -- Calcola posti usati
  SELECT COALESCE(SUM(delta), 0) INTO v_used_entries
  FROM subscription_usages
  WHERE subscription_id = NEW.id;
  
  -- Calcola posti rimanenti
  v_remaining_entries := v_effective_entries + v_used_entries;
  
  -- Se ha esaurito i posti -> 'completed', altrimenti -> 'expired'
  IF v_remaining_entries <= 0 THEN
    NEW.status := 'completed';
  ELSE
    NEW.status := 'expired';
  END IF;
  
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."auto_complete_expired_subscriptions"() OWNER TO "postgres";

-- ============================================================================
-- 2. TRIGGER
-- ============================================================================

CREATE TRIGGER "trigger_auto_complete_expired_subscriptions"
  BEFORE INSERT OR UPDATE OF expires_at, status
  ON "public"."subscriptions"
  FOR EACH ROW
  EXECUTE FUNCTION "public"."auto_complete_expired_subscriptions"();

-- ============================================================================
-- 3. AGGIORNAMENTO ABBONAMENTI ESISTENTI SCADUTI
-- ============================================================================
-- Nota: La correzione dei dati esistenti viene fatta nella migration 0021
-- per applicare la logica completa che considera anche i posti rimanenti

-- ============================================================================
-- 4. NOTE
-- ============================================================================

-- Il trigger viene eseguito automaticamente su:
-- - INSERT: quando viene creato un nuovo abbonamento
-- - UPDATE: quando viene modificato expires_at o status di un abbonamento esistente
--
-- Il trigger aggiorna solo gli abbonamenti con status = 'active' per evitare di
-- sovrascrivere altri stati (es. 'canceled', 'expired', 'completed').
--
-- L'UPDATE iniziale:
-- 1. Aggiorna tutti gli abbonamenti esistenti che sono scaduti ma hanno ancora status = 'active'
-- 2. Corregge gli abbonamenti che sono erroneamente in stato 'completed' ma non sono scaduti

