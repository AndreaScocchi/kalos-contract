-- Migration 0008: Update Public Site Views (operators and events)
--
-- Obiettivo: Aggiornare le views pubbliche per il sito pubblico Kalòs
-- secondo le specifiche richieste, adattando i campi a quelli disponibili
-- nello schema del database.
--
-- Note:
-- - Alcuni campi richiesti non esistono nelle tabelle (image_url, image_alt, 
--   display_order per operators; link_url per events)
-- - Questi campi vengono esposti come NULL con commenti per future implementazioni

-- ============================================================================
-- 1. public_site_operators: Operatori attivi per il sito pubblico
-- ============================================================================

-- NOTA: DROP necessario perché PostgreSQL non permette di cambiare i nomi delle colonne
-- con CREATE OR REPLACE VIEW. La vista esistente ha "disciplines" che viene sostituita.
DROP VIEW IF EXISTS public.public_site_operators;

CREATE VIEW public.public_site_operators AS
SELECT 
  o.id,
  o.name,
  o.role,
  o.bio,
  -- NOTA: image_url, image_alt, display_order non esistono nella tabella operators
  -- Se necessario in futuro, aggiungere queste colonne alla tabella operators
  NULL::text AS image_url,
  NULL::text AS image_alt,
  NULL::integer AS display_order,
  o.is_active
FROM public.operators o
WHERE 
  o.is_active = true
  AND o.deleted_at IS NULL
  -- Escludi operatori con status "Non attivo" (gestito da is_active = true)
  -- NOTA: La tabella operators non ha un campo "status", usa solo is_active
ORDER BY 
  -- Usa name come fallback per ordering se display_order non esiste
  o.name ASC;

COMMENT ON VIEW public.public_site_operators IS 
  'View pubblica per gli operatori attivi. Espone solo dati pubblici: id, name, role, bio, is_active. 
   NOTA: image_url, image_alt, display_order non sono disponibili nella tabella operators attualmente 
   e vengono esposti come NULL. Per abilitarli, aggiungere queste colonne alla tabella operators.';

-- ============================================================================
-- 2. public_site_events: Eventi (futuri e passati) per il sito pubblico
-- ============================================================================

-- NOTA: DROP necessario perché PostgreSQL non permette di cambiare i nomi delle colonne
-- con CREATE OR REPLACE VIEW. La vista esistente ha colonne diverse (location, capacity, ecc.)
DROP VIEW IF EXISTS public.public_site_events;

CREATE VIEW public.public_site_events AS
SELECT 
  e.id,
  e.name AS title,
  -- NOTA: Normalizzato come "title" per coerenza con l'uso nel sito
  e.description,
  e.image_url,
  e.starts_at AS start_date,
  -- NOTA: Normalizzato come "start_date" per coerenza con l'uso nel sito
  e.ends_at AS end_date,
  -- NOTA: Normalizzato come "end_date" per coerenza con l'uso nel sito
  e.link AS registration_url,
  -- NOTA: Normalizzato come "registration_url" per coerenza con l'uso nel sito
  -- NOTA: link_url non esiste nella tabella events, usiamo link come fallback
  -- Se in futuro serve un link_url separato, aggiungere la colonna alla tabella events
  e.link AS link_url,
  e.created_at,
  e.updated_at
FROM public.events e
WHERE 
  e.deleted_at IS NULL
  -- Nessun filtro su futuro/passato: il sito filtra client-side
ORDER BY e.starts_at DESC;

COMMENT ON VIEW public.public_site_events IS 
  'View pubblica per gli eventi. Espone tutti gli eventi non soft-deleted (futuri e passati). 
   Il sito pubblico filtra client-side per mostrare solo eventi futuri o passati. 
   Include: id, title (name), description, image_url, start_date (starts_at), end_date (ends_at), 
   registration_url (link), link_url (link), created_at, updated_at.';

-- ============================================================================
-- 3. GRANTS per accesso pubblico (anon)
-- ============================================================================

-- Le views sono accessibili tramite anon key (già grantati nella migration 0007, 
-- ma li rinnoviamo per sicurezza)
GRANT SELECT ON public.public_site_operators TO anon;
GRANT SELECT ON public.public_site_events TO anon;

-- Anche authenticated può accedere (utile per app)
GRANT SELECT ON public.public_site_operators TO authenticated;
GRANT SELECT ON public.public_site_events TO authenticated;

-- ============================================================================
-- 4. RLS: Policy aggiuntive per garantire accesso pubblico alle viste
-- ============================================================================

-- NOTA: Le views pubbliche devono essere accessibili in sola lettura con chiave anonima.
-- Le tabelle sottostanti (operators, events) hanno RLS abilitato con policy che filtrano
-- per is_active. Per la vista public_site_events, vogliamo mostrare TUTTI gli eventi
-- (futuri e passati), non solo quelli attivi, quindi creiamo una policy aggiuntiva.

-- Policy per permettere accesso anonimo a tutti gli eventi non soft-deleted per la vista
-- (la policy esistente "events_select_public_active" filtra solo is_active = true)
DROP POLICY IF EXISTS "events_select_public_for_site_view" ON "public"."events";
CREATE POLICY "events_select_public_for_site_view" ON "public"."events" 
  FOR SELECT 
  TO "anon"
  USING (deleted_at IS NULL);

-- NOTA: La policy "operators_select_public_active" già permette l'accesso anonimo
-- agli operatori con is_active = true, che è esattamente quello che vogliamo per la vista.

-- ============================================================================
-- 5. NOTA GDPR: Dati NON esposti
-- ============================================================================

-- Queste views NON espongono:
-- - Dati personali (email, telefono, note interne)
-- - Informazioni finanziarie sensibili (price_cents, currency per events)
-- - ID di record interni non necessari per il sito (profile_id, is_admin)
-- - Campi amministrativi (deleted_at, is_admin, ecc.)

