-- Migration 0007: Create Public Site Views (activities, operators, events)
--
-- Obiettivo: Creare views pubbliche per il sito pubblico (kalos-react)
-- che espongono solo i dati minimi necessari per attività, operatori e eventi.
--
-- Convenzione: tutte le views pubbliche iniziano con "public_site_"
-- e sono accessibili in sola lettura tramite anon key.

-- ============================================================================
-- 1. public_site_activities: Attività pubbliche/attive
-- ============================================================================

CREATE OR REPLACE VIEW public.public_site_activities AS
SELECT 
  a.id,
  a.name,
  -- NOTA: Se in futuro serve uno slug per matchare i file JSON activity.{slug}.json,
  -- aggiungere una colonna slug nella tabella activities e includerla qui
  a.description,
  a.discipline,
  a.color,
  -- NOTA: Se in futuro serve image_url, aggiungere la colonna nella tabella activities
  a.created_at
FROM public.activities a
WHERE 
  a.deleted_at IS NULL
  -- NOTA: Se in futuro viene aggiunto un campo is_public o is_active per filtrare
  -- le attività pubbliche, aggiungere il filtro qui (es: AND a.is_public = true)
ORDER BY a.name ASC;

COMMENT ON VIEW public.public_site_activities IS 
  'View pubblica per le attività. Espone solo dati minimi necessari: id, name, description, discipline, color. NOTA: slug e image_url non sono disponibili nella tabella activities attualmente.';

-- ============================================================================
-- 2. public_site_operators: Operatori attivi
-- ============================================================================

CREATE OR REPLACE VIEW public.public_site_operators AS
SELECT 
  o.id,
  o.name,
  o.role,
  o.bio,
  o.disciplines,
  -- NOTA: Se in futuro serve image_url, aggiungere la colonna nella tabella operators
  o.created_at
FROM public.operators o
WHERE 
  o.is_active = true
  AND o.deleted_at IS NULL
  -- Escludi operatori con status "Non attivo" (gestito da is_active = true)
ORDER BY o.name ASC;

COMMENT ON VIEW public.public_site_operators IS 
  'View pubblica per gli operatori attivi. Espone solo dati pubblici: id, name, role, bio, disciplines. NON include dati sensibili (email, note interne, profile_id, is_admin). NOTA: image_url non è disponibile nella tabella operators attualmente.';

-- ============================================================================
-- 3. public_site_events: Eventi (futuri e passati)
-- ============================================================================

CREATE OR REPLACE VIEW public.public_site_events AS
SELECT 
  e.id,
  e.name AS title,
  -- NOTA: Normalizzato come "title" per coerenza con l'uso nel sito
  e.description,
  e.starts_at,
  e.ends_at,
  e.location,
  e.image_url,
  e.link AS registration_url,
  -- NOTA: Normalizzato come "registration_url" per coerenza con l'uso nel sito
  e.capacity,
  e.price_cents,
  e.currency,
  e.is_active,
  e.created_at
FROM public.events e
WHERE 
  e.deleted_at IS NULL
  -- Nessun filtro su futuro/passato: il sito filtra client-side
ORDER BY e.starts_at DESC;

COMMENT ON VIEW public.public_site_events IS 
  'View pubblica per gli eventi. Espone tutti gli eventi non soft-deleted (futuri e passati). Il sito pubblico filtra client-side per mostrare solo eventi futuri o passati. Include: id, title (name), description, dates, location, image_url, registration_url (link), capacity, price, currency, is_active.';

-- ============================================================================
-- 4. GRANTS per accesso pubblico (anon)
-- ============================================================================

-- Le views sono accessibili tramite anon key
GRANT SELECT ON public.public_site_activities TO anon;
GRANT SELECT ON public.public_site_operators TO anon;
GRANT SELECT ON public.public_site_events TO anon;

-- Anche authenticated può accedere (utile per app)
GRANT SELECT ON public.public_site_activities TO authenticated;
GRANT SELECT ON public.public_site_operators TO authenticated;
GRANT SELECT ON public.public_site_events TO authenticated;

-- ============================================================================
-- 5. NOTA GDPR: Dati NON esposti
-- ============================================================================

-- Queste views NON espongono:
-- - Dati personali (email, telefono, note interne)
-- - Informazioni finanziarie sensibili
-- - ID di record interni non necessari per il sito
-- - Timestamps di creazione/modifica non necessari (manteniamo created_at per ordering)
-- - Campi amministrativi (is_admin, profile_id, ecc.)
--
-- Se in futuro servono altri dati pubblici, creare nuove views con prefisso "public_site_"
-- e seguire lo stesso principio di minimizzazione.

