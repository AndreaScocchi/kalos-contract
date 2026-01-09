-- ============================================================================
-- FIX: CORREZIONE INCONSISTENZE PRENOTAZIONI E SUBSCRIPTION_USAGES
-- ============================================================================
--
-- ATTENZIONE: Eseguire PRIMA le query SELECT per verificare i dati che
-- verranno modificati. Poi eseguire le INSERT solo se i risultati sono corretti.
--
-- ============================================================================

-- ============================================================================
-- 1. PREVIEW: CANCELLAZIONI SENZA RESTORE
-- ============================================================================
-- Mostra le prenotazioni cancellate che hanno delta=-1 ma mancano del delta=+1

SELECT
  'PREVIEW: Cancellazioni senza restore' AS check_type,
  su.id AS usage_id,
  su.subscription_id,
  su.booking_id,
  su.delta,
  su.reason,
  su.created_at AS usage_created_at,
  b.status AS booking_status,
  b.created_at AS booking_created_at,
  c.full_name AS client_name,
  s.status AS subscription_status,
  COALESCE(s.custom_name, p.name) AS plan_name
FROM public.subscription_usages su
INNER JOIN public.bookings b ON b.id = su.booking_id
INNER JOIN public.subscriptions s ON s.id = su.subscription_id
LEFT JOIN public.plans p ON p.id = s.plan_id
LEFT JOIN public.clients c ON c.id = b.client_id
WHERE b.status = 'canceled'
  AND su.delta = -1
  AND NOT EXISTS (
    SELECT 1 FROM public.subscription_usages su2
    WHERE su2.booking_id = su.booking_id
      AND su2.delta = +1
  )
ORDER BY su.created_at DESC;

-- ============================================================================
-- 1. FIX: INSERISCI RESTORE PER CANCELLAZIONI SENZA RESTORE
-- ============================================================================
-- DECOMMENTARE PER ESEGUIRE

/*
INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
SELECT su.subscription_id, su.booking_id, +1, 'CANCEL_RESTORE_FIX'
FROM public.subscription_usages su
INNER JOIN public.bookings b ON b.id = su.booking_id
WHERE b.status = 'canceled'
  AND su.delta = -1
  AND NOT EXISTS (
    SELECT 1 FROM public.subscription_usages su2
    WHERE su2.booking_id = su.booking_id
      AND su2.delta = +1
  );
*/

-- ============================================================================
-- 2. PREVIEW: BOOKINGS ATTIVE CON SUBSCRIPTION LIMITATA SENZA USAGE
-- ============================================================================
-- Mostra prenotazioni attive che hanno subscription_id ma mancano di subscription_usages

SELECT
  'PREVIEW: Bookings senza subscription_usages' AS check_type,
  b.id AS booking_id,
  b.status AS booking_status,
  b.subscription_id,
  b.created_at AS booking_created_at,
  c.full_name AS client_name,
  l.starts_at AS lesson_starts_at,
  a.name AS activity_name,
  COALESCE(s.custom_entries, p.entries) AS plan_entries,
  s.status AS subscription_status,
  COALESCE(s.custom_name, p.name) AS plan_name
FROM public.bookings b
INNER JOIN public.subscriptions s ON s.id = b.subscription_id
LEFT JOIN public.plans p ON p.id = s.plan_id
LEFT JOIN public.clients c ON c.id = b.client_id
LEFT JOIN public.lessons l ON l.id = b.lesson_id
LEFT JOIN public.activities a ON a.id = l.activity_id
WHERE b.subscription_id IS NOT NULL
  AND b.status IN ('booked', 'attended', 'no_show')
  AND COALESCE(s.custom_entries, p.entries) IS NOT NULL  -- Solo subscription limitate
  AND NOT EXISTS (
    SELECT 1 FROM public.subscription_usages su
    WHERE su.booking_id = b.id
  )
ORDER BY b.created_at DESC;

-- ============================================================================
-- 2. FIX: CREA SUBSCRIPTION_USAGES MANCANTI PER BOOKINGS ATTIVE
-- ============================================================================
-- DECOMMENTARE PER ESEGUIRE

/*
INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
SELECT b.subscription_id, b.id, -1, 'BOOK_FIX'
FROM public.bookings b
INNER JOIN public.subscriptions s ON s.id = b.subscription_id
LEFT JOIN public.plans p ON p.id = s.plan_id
WHERE b.subscription_id IS NOT NULL
  AND b.status IN ('booked', 'attended', 'no_show')
  AND COALESCE(s.custom_entries, p.entries) IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.subscription_usages su
    WHERE su.booking_id = b.id
  );
*/

-- ============================================================================
-- 3. PREVIEW: BOOKINGS ATTIVE CON SUBSCRIPTION ILLIMITATA SENZA USAGE
-- ============================================================================
-- Per il nuovo requisito: tracciare anche gli abbonamenti illimitati

SELECT
  'PREVIEW: Bookings illimitate senza subscription_usages' AS check_type,
  b.id AS booking_id,
  b.status AS booking_status,
  b.subscription_id,
  b.created_at AS booking_created_at,
  c.full_name AS client_name,
  l.starts_at AS lesson_starts_at,
  a.name AS activity_name,
  s.status AS subscription_status,
  COALESCE(s.custom_name, p.name) AS plan_name,
  'ILLIMITATO' AS entries_type
FROM public.bookings b
INNER JOIN public.subscriptions s ON s.id = b.subscription_id
LEFT JOIN public.plans p ON p.id = s.plan_id
LEFT JOIN public.clients c ON c.id = b.client_id
LEFT JOIN public.lessons l ON l.id = b.lesson_id
LEFT JOIN public.activities a ON a.id = l.activity_id
WHERE b.subscription_id IS NOT NULL
  AND b.status IN ('booked', 'attended', 'no_show')
  AND COALESCE(s.custom_entries, p.entries) IS NULL  -- Solo subscription illimitate
  AND NOT EXISTS (
    SELECT 1 FROM public.subscription_usages su
    WHERE su.booking_id = b.id
  )
ORDER BY b.created_at DESC;

-- ============================================================================
-- 3. FIX: CREA SUBSCRIPTION_USAGES PER BOOKINGS ILLIMITATE (STORICO)
-- ============================================================================
-- DECOMMENTARE PER ESEGUIRE

/*
INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
SELECT b.subscription_id, b.id, -1, 'BOOK_FIX_UNLIMITED'
FROM public.bookings b
INNER JOIN public.subscriptions s ON s.id = b.subscription_id
LEFT JOIN public.plans p ON p.id = s.plan_id
WHERE b.subscription_id IS NOT NULL
  AND b.status IN ('booked', 'attended', 'no_show')
  AND COALESCE(s.custom_entries, p.entries) IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.subscription_usages su
    WHERE su.booking_id = b.id
  );
*/

-- ============================================================================
-- 4. PREVIEW: SUBSCRIPTION_USAGES DUPLICATI (delta=-1)
-- ============================================================================

SELECT
  'PREVIEW: Subscription_usages duplicati (delta=-1)' AS check_type,
  booking_id,
  COUNT(*) AS duplicate_count,
  array_agg(id ORDER BY created_at) AS usage_ids,
  array_agg(reason ORDER BY created_at) AS reasons,
  array_agg(created_at ORDER BY created_at) AS created_dates
FROM public.subscription_usages
WHERE delta = -1
GROUP BY booking_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- ============================================================================
-- 4. FIX: RIMUOVI SUBSCRIPTION_USAGES DUPLICATI (mantieni il primo)
-- ============================================================================
-- DECOMMENTARE PER ESEGUIRE

/*
WITH duplicates AS (
  SELECT id,
    ROW_NUMBER() OVER (PARTITION BY booking_id ORDER BY created_at) AS rn
  FROM public.subscription_usages
  WHERE delta = -1
)
DELETE FROM public.subscription_usages
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);
*/

-- ============================================================================
-- 5. PREVIEW: SUBSCRIPTION_USAGES DUPLICATI (delta=+1)
-- ============================================================================

SELECT
  'PREVIEW: Subscription_usages duplicati (delta=+1)' AS check_type,
  booking_id,
  COUNT(*) AS duplicate_count,
  array_agg(id ORDER BY created_at) AS usage_ids,
  array_agg(reason ORDER BY created_at) AS reasons
FROM public.subscription_usages
WHERE delta = +1
GROUP BY booking_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- ============================================================================
-- 5. FIX: RIMUOVI SUBSCRIPTION_USAGES DUPLICATI (delta=+1, mantieni il primo)
-- ============================================================================
-- DECOMMENTARE PER ESEGUIRE

/*
WITH duplicates AS (
  SELECT id,
    ROW_NUMBER() OVER (PARTITION BY booking_id ORDER BY created_at) AS rn
  FROM public.subscription_usages
  WHERE delta = +1
)
DELETE FROM public.subscription_usages
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);
*/

-- ============================================================================
-- 6. VERIFICA FINALE: CONTEGGIO DOPO I FIX
-- ============================================================================

SELECT
  'VERIFICA POST-FIX' AS check_type,
  (SELECT COUNT(*) FROM public.bookings WHERE subscription_id IS NOT NULL AND status IN ('booked', 'attended', 'no_show')) AS total_active_bookings_with_sub,
  (SELECT COUNT(*) FROM public.subscription_usages WHERE delta = -1) AS total_book_usages,
  (SELECT COUNT(*) FROM public.subscription_usages WHERE delta = +1) AS total_restore_usages,
  (SELECT COUNT(*) FROM public.bookings WHERE status = 'canceled' AND subscription_id IS NOT NULL) AS total_canceled_with_sub;

-- ============================================================================
-- FINE SCRIPT
-- ============================================================================
