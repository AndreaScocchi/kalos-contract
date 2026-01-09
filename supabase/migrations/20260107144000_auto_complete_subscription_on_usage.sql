-- Migration: Auto-complete subscription when entries are exhausted
--
-- Problema: Il trigger auto_complete_expired_subscriptions viene eseguito solo su
-- INSERT/UPDATE della tabella subscriptions, ma NON quando cambia subscription_usages.
-- Quindi quando viene scalato un ingresso (INSERT in subscription_usages con delta = -1),
-- lo stato dell'abbonamento non viene aggiornato automaticamente a "completed".
--
-- Soluzione: Aggiungere un trigger su subscription_usages che, dopo ogni INSERT,
-- verifica se l'abbonamento ha esaurito gli ingressi e in tal caso aggiorna lo stato.

-- ============================================================================
-- 1. FUNZIONE TRIGGER: Aggiorna stato abbonamento quando cambiano gli usages
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."update_subscription_status_on_usage"() 
RETURNS "trigger"
LANGUAGE "plpgsql"
SECURITY DEFINER
SET "search_path" TO 'public'
AS $$
DECLARE
  v_subscription subscriptions%ROWTYPE;
  v_plan plans%ROWTYPE;
  v_effective_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_new_status subscription_status;
BEGIN
  -- Recupera l'abbonamento
  SELECT * INTO v_subscription
  FROM subscriptions
  WHERE id = NEW.subscription_id;
  
  -- Se non trovato o già in stato finale, esci
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;
  
  -- Preserva stati finali (canceled non deve essere modificato)
  IF v_subscription.status = 'canceled' THEN
    RETURN NEW;
  END IF;
  
  -- Recupera il piano
  SELECT * INTO v_plan
  FROM plans
  WHERE id = v_subscription.plan_id;
  
  -- Calcola effective_entries
  v_effective_entries := COALESCE(v_subscription.custom_entries, v_plan.entries);
  
  -- Se l'abbonamento è illimitato, non fare nulla (rimane active o expired in base alla scadenza)
  IF v_effective_entries IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- Calcola posti usati (somma di tutti i delta)
  SELECT COALESCE(SUM(delta), 0) INTO v_used_entries
  FROM subscription_usages
  WHERE subscription_id = NEW.subscription_id;
  
  -- Calcola posti rimanenti
  v_remaining_entries := v_effective_entries + v_used_entries;
  
  -- Determina il nuovo stato
  IF v_remaining_entries <= 0 THEN
    -- Ingressi esauriti -> completed (indipendentemente dalla scadenza)
    v_new_status := 'completed';
  ELSIF v_subscription.expires_at < CURRENT_DATE THEN
    -- Ha ancora ingressi ma è scaduto -> expired
    v_new_status := 'expired';
  ELSE
    -- Ha ancora ingressi e non è scaduto -> active
    v_new_status := 'active';
  END IF;
  
  -- Aggiorna solo se lo stato è cambiato
  IF v_subscription.status != v_new_status THEN
    UPDATE subscriptions
    SET status = v_new_status
    WHERE id = NEW.subscription_id;
  END IF;
  
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."update_subscription_status_on_usage"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."update_subscription_status_on_usage"() IS 
'Trigger function che aggiorna automaticamente lo stato dell''abbonamento quando vengono
modificati i subscription_usages. Se gli ingressi sono esauriti (remaining_entries <= 0),
imposta lo stato a "completed". Preserva lo stato "canceled".';

-- ============================================================================
-- 2. TRIGGER SU subscription_usages
-- ============================================================================

-- Rimuovi trigger esistente se presente
DROP TRIGGER IF EXISTS "trigger_update_subscription_status_on_usage" ON "public"."subscription_usages";

-- Crea trigger che si attiva dopo INSERT su subscription_usages
-- (gli usages vengono solo inseriti, non modificati o cancellati in condizioni normali)
CREATE TRIGGER "trigger_update_subscription_status_on_usage"
  AFTER INSERT ON "public"."subscription_usages"
  FOR EACH ROW
  EXECUTE FUNCTION "public"."update_subscription_status_on_usage"();

-- ============================================================================
-- 2b. FUNZIONE TRIGGER PER DELETE (usa OLD invece di NEW)
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."update_subscription_status_on_usage_after_delete"() 
RETURNS "trigger"
LANGUAGE "plpgsql"
SECURITY DEFINER
SET "search_path" TO 'public'
AS $$
DECLARE
  v_subscription subscriptions%ROWTYPE;
  v_plan plans%ROWTYPE;
  v_effective_entries integer;
  v_used_entries integer;
  v_remaining_entries integer;
  v_new_status subscription_status;
BEGIN
  -- Recupera l'abbonamento
  SELECT * INTO v_subscription
  FROM subscriptions
  WHERE id = OLD.subscription_id;
  
  -- Se non trovato o già in stato finale, esci
  IF NOT FOUND THEN
    RETURN OLD;
  END IF;
  
  -- Preserva stati finali (canceled non deve essere modificato)
  IF v_subscription.status = 'canceled' THEN
    RETURN OLD;
  END IF;
  
  -- Recupera il piano
  SELECT * INTO v_plan
  FROM plans
  WHERE id = v_subscription.plan_id;
  
  -- Calcola effective_entries
  v_effective_entries := COALESCE(v_subscription.custom_entries, v_plan.entries);
  
  -- Se l'abbonamento è illimitato, non fare nulla
  IF v_effective_entries IS NULL THEN
    RETURN OLD;
  END IF;
  
  -- Calcola posti usati (somma di tutti i delta)
  SELECT COALESCE(SUM(delta), 0) INTO v_used_entries
  FROM subscription_usages
  WHERE subscription_id = OLD.subscription_id;
  
  -- Calcola posti rimanenti
  v_remaining_entries := v_effective_entries + v_used_entries;
  
  -- Determina il nuovo stato
  IF v_remaining_entries <= 0 THEN
    v_new_status := 'completed';
  ELSIF v_subscription.expires_at < CURRENT_DATE THEN
    v_new_status := 'expired';
  ELSE
    v_new_status := 'active';
  END IF;
  
  -- Aggiorna solo se lo stato è cambiato
  IF v_subscription.status != v_new_status THEN
    UPDATE subscriptions
    SET status = v_new_status
    WHERE id = OLD.subscription_id;
  END IF;
  
  RETURN OLD;
END;
$$;

ALTER FUNCTION "public"."update_subscription_status_on_usage_after_delete"() OWNER TO "postgres";

-- ============================================================================
-- 3. TRIGGER PER DELETE SU subscription_usages
-- ============================================================================

-- Aggiungiamo un trigger per DELETE (in caso di ripristino ingressi o eliminazione record)
DROP TRIGGER IF EXISTS "trigger_update_subscription_status_on_usage_delete" ON "public"."subscription_usages";

CREATE TRIGGER "trigger_update_subscription_status_on_usage_delete"
  AFTER DELETE ON "public"."subscription_usages"
  FOR EACH ROW
  EXECUTE FUNCTION "public"."update_subscription_status_on_usage_after_delete"();

-- ============================================================================
-- 4. CORREZIONE ABBONAMENTI ESISTENTI CON INGRESSI ESAURITI
-- ============================================================================

-- Aggiorna tutti gli abbonamenti che hanno esaurito gli ingressi ma sono ancora "active"
WITH usage_totals AS (
  SELECT 
    subscription_id,
    COALESCE(SUM(delta), 0) AS delta_sum
  FROM public.subscription_usages
  GROUP BY subscription_id
),
subscription_data AS (
  SELECT 
    s.id,
    s.status,
    s.expires_at,
    s.custom_entries,
    p.entries AS plan_entries,
    COALESCE(u.delta_sum, 0) AS used_entries
  FROM public.subscriptions s
  LEFT JOIN public.plans p ON p.id = s.plan_id
  LEFT JOIN usage_totals u ON u.subscription_id = s.id
  WHERE s.deleted_at IS NULL
    AND s.status = 'active'  -- Solo quelli ancora attivi
),
to_complete AS (
  SELECT id
  FROM subscription_data
  WHERE COALESCE(custom_entries, plan_entries) IS NOT NULL  -- Solo quelli con ingressi limitati
    AND (COALESCE(custom_entries, plan_entries) + used_entries) <= 0  -- Ingressi esauriti
)
UPDATE public.subscriptions s
SET status = 'completed'
FROM to_complete tc
WHERE s.id = tc.id;

-- ============================================================================
-- 5. NOTE
-- ============================================================================

-- Il trigger viene eseguito automaticamente su:
-- - INSERT in subscription_usages: quando viene scalato un ingresso (delta = -1) o ripristinato (delta = +1)
-- - DELETE in subscription_usages: quando viene eliminato un record di utilizzo
--
-- Logica:
-- - Se remaining_entries <= 0 -> 'completed' (indipendentemente dalla scadenza)
-- - Se remaining_entries > 0 e scaduto -> 'expired'
-- - Se remaining_entries > 0 e non scaduto -> 'active'
-- - Se status = 'canceled' -> non modificare (preservato)

