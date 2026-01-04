-- Migration 0015: Add assigned_subscription_id field to lessons table
-- 
-- Obiettivo: Aggiungere il campo assigned_subscription_id alla tabella lessons per
-- associare un abbonamento alle lezioni individuali con cliente assegnato.
--
-- Comportamento:
-- - Il campo è NULL per le lezioni normali
-- - Per le lezioni individuali con cliente assegnato, contiene l'ID dell'abbonamento utilizzato
-- - Foreign key verso subscriptions(id)
-- - Campo opzionale (NULL ammesso)
--
-- Implicazioni:
-- - Le RLS policies continuano a funzionare (non viene aggiunta nuova logica di sicurezza)
-- - L'indice migliora le performance delle query che filtrano per assigned_subscription_id

-- ============================================================================
-- 1. AGGIUNTA CAMPO assigned_subscription_id
-- ============================================================================

ALTER TABLE public.lessons
ADD COLUMN IF NOT EXISTS assigned_subscription_id UUID NULL REFERENCES subscriptions(id);

-- ============================================================================
-- 2. COMMENTO ESPLICATIVO
-- ============================================================================

COMMENT ON COLUMN public.lessons.assigned_subscription_id IS 
  'Abbonamento utilizzato per questa lezione individuale. Impostato solo per lezioni individuali (is_individual = true) con cliente assegnato (assigned_client_id IS NOT NULL).';

-- ============================================================================
-- 3. INDICE PER PERFORMANCE
-- ============================================================================

-- Indice parziale per migliorare le performance delle query che filtrano per assigned_subscription_id
CREATE INDEX IF NOT EXISTS idx_lessons_assigned_subscription_id 
  ON public.lessons(assigned_subscription_id) 
  WHERE assigned_subscription_id IS NOT NULL;

-- ============================================================================
-- 4. NOTA SULLE RLS POLICIES
-- ============================================================================

-- Le RLS policies esistenti continuano a funzionare correttamente:
-- - lessons_select_public_active: continua a permettere SELECT anon per lezioni non soft-deleted
-- - Clients can view their lessons: continua a permettere SELECT per utenti autorizzati
-- - Only staff can manage lessons: continua a permettere INSERT/UPDATE/DELETE solo allo staff
--
-- Il nuovo campo assigned_subscription_id non richiede modifiche alle RLS policies perché:
-- 1. È un campo informativo che non cambia i criteri di accesso
-- 2. Le policies di SELECT continuano a funzionare (il campo viene semplicemente incluso nei risultati)
-- 3. Le policies di INSERT/UPDATE permettono già di inserire/aggiornare qualsiasi campo allo staff

