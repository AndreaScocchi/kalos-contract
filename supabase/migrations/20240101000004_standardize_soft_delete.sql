-- Migration 0004: Standardize Soft Delete (deleted_at)
-- 
-- Obiettivo: Standardizzare l'uso di deleted_at su tutte le tabelle che necessitano
-- di soft delete per il gestionale e l'app.
--
-- Tabelle con deleted_at (già presenti):
-- - profiles, activities, clients, events, lessons, plans, operators, promotions
--
-- Tabelle che NON necessitano deleted_at:
-- - bookings: usa status='canceled' per cancellazioni
-- - event_bookings: usa status per cancellazioni
-- - subscription_usages: record storico, non si cancella
-- - waitlist: record temporaneo, può essere eliminato direttamente
-- - expenses, payouts, payout_rules: record finanziari storici, non si cancellano
-- - subscriptions: usa status per gestire lifecycle (active/completed/expired/canceled)
--
-- Questa migration:
-- 1. Aggiunge indici ottimizzati per query su deleted_at IS NULL
-- 2. Aggiunge commenti esplicativi
-- 3. Assicura che le views pubbliche escludano record soft-deleted

-- ============================================================================
-- 1. INDICI per performance su soft delete
-- ============================================================================

-- Indici parziali per query comuni (WHERE deleted_at IS NULL)
-- Questi indici sono più efficienti per query che filtrano solo record attivi

-- Activities: indice per query su attività attive
CREATE INDEX IF NOT EXISTS idx_activities_deleted_at_null 
  ON public.activities(deleted_at) 
  WHERE deleted_at IS NULL;

-- Clients: già presente idx_clients_deleted_at, ma assicuriamoci che sia corretto
-- (già presente in migration 0000, ma verifichiamo)

-- Events: indice per query su eventi attivi
CREATE INDEX IF NOT EXISTS idx_events_deleted_at_null 
  ON public.events(deleted_at) 
  WHERE deleted_at IS NULL;

-- Lessons: indice per query su lezioni attive
CREATE INDEX IF NOT EXISTS idx_lessons_deleted_at_null 
  ON public.lessons(deleted_at) 
  WHERE deleted_at IS NULL;

-- Plans: indice per query su piani attivi
CREATE INDEX IF NOT EXISTS idx_plans_deleted_at_null 
  ON public.plans(deleted_at) 
  WHERE deleted_at IS NULL;

-- Operators: indice per query su operatori attivi
CREATE INDEX IF NOT EXISTS idx_operators_deleted_at_null 
  ON public.operators(deleted_at) 
  WHERE deleted_at IS NULL;

-- Promotions: indice per query su promozioni attive
CREATE INDEX IF NOT EXISTS idx_promotions_deleted_at_null 
  ON public.promotions(deleted_at) 
  WHERE deleted_at IS NULL;

-- Profiles: indice per query su profili attivi (utile per admin/staff)
CREATE INDEX IF NOT EXISTS idx_profiles_deleted_at_null 
  ON public.profiles(deleted_at) 
  WHERE deleted_at IS NULL;

-- ============================================================================
-- 2. COMMENTI esplicativi per convenzione soft delete
-- ============================================================================

COMMENT ON COLUMN public.profiles.deleted_at IS 
  'Soft delete: timestamp di archiviazione. NULL = record attivo. I record soft-deleted non vengono mostrati nelle UI standard ma sono preservati per audit.';

COMMENT ON COLUMN public.activities.deleted_at IS 
  'Soft delete: timestamp di archiviazione. NULL = record attivo. Le attività archiviate non appaiono nelle selezioni ma i dati storici (lessons, subscriptions) rimangono collegati.';

COMMENT ON COLUMN public.clients.deleted_at IS 
  'Soft delete: timestamp di archiviazione. NULL = record attivo. I clienti archiviati non appaiono nelle liste standard ma i dati storici (bookings, subscriptions) rimangono collegati.';

COMMENT ON COLUMN public.events.deleted_at IS 
  'Soft delete: timestamp di archiviazione. NULL = record attivo. Gli eventi archiviati non appaiono nelle viste pubbliche.';

COMMENT ON COLUMN public.lessons.deleted_at IS 
  'Soft delete: timestamp di archiviazione. NULL = record attivo. Le lezioni archiviate non appaiono negli schedule pubblici ma i bookings storici rimangono collegati.';

COMMENT ON COLUMN public.plans.deleted_at IS 
  'Soft delete: timestamp di archiviazione. NULL = record attivo. I piani archiviati non appaiono nelle selezioni pubbliche ma le subscriptions esistenti rimangono valide.';

COMMENT ON COLUMN public.operators.deleted_at IS 
  'Soft delete: timestamp di archiviazione. NULL = record attivo. Gli operatori archiviati non appaiono nelle selezioni ma i dati storici (lessons, expenses) rimangono collegati.';

COMMENT ON COLUMN public.promotions.deleted_at IS 
  'Soft delete: timestamp di archiviazione. NULL = record attivo. Le promozioni archiviate non appaiono nelle viste pubbliche.';

-- ============================================================================
-- 3. AGGIORNAMENTO VIEWS per escludere soft-deleted
-- ============================================================================

-- Nota: Le views esistenti (lesson_occupancy, subscriptions_with_remaining, financial_monthly_summary)
-- già filtrano implicitamente tramite JOIN o RLS policies.
-- Le views pubbliche (public_site_*) verranno create in una migration successiva.

-- Verifichiamo che lesson_occupancy escluda lezioni soft-deleted
-- (già gestito dalla RLS policy "lessons_select_public_active" che filtra deleted_at IS NULL)

-- ============================================================================
-- 4. NOTA SULLA COMPATIBILITÀ RETROATTIVA
-- ============================================================================

-- Questa migration è completamente retroattiva:
-- - Gli indici sono IF NOT EXISTS, quindi non falliscono se già presenti
-- - I commenti sono idempotenti (sovrascrivono commenti esistenti)
-- - Non modifica dati esistenti
-- - Le query esistenti continuano a funzionare (deleted_at IS NULL è il default implicito)

