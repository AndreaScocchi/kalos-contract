-- ============================================================================
-- PRENOTAZIONI SENZA SUBSCRIPTION COLLEGATA
-- ============================================================================
-- 
-- Questo script mostra tutte le prenotazioni che non hanno una subscription
-- collegata (subscription_id IS NULL)
--
-- ============================================================================

-- ============================================================================
-- RIEPILOGO: CONTEggio PRENOTAZIONI SENZA SUBSCRIPTION
-- ============================================================================

SELECT 
  'RIEPILOGO' AS check_type,
  COUNT(*) AS total_bookings_without_subscription,
  COUNT(*) FILTER (WHERE b.status = 'booked') AS status_booked,
  COUNT(*) FILTER (WHERE b.status = 'attended') AS status_attended,
  COUNT(*) FILTER (WHERE b.status = 'no_show') AS status_no_show,
  COUNT(*) FILTER (WHERE b.status = 'canceled') AS status_canceled,
  COUNT(*) FILTER (WHERE b.client_id IS NOT NULL) AS with_client_id,
  COUNT(*) FILTER (WHERE b.client_id IS NULL) AS without_client_id
FROM public.bookings b
WHERE b.subscription_id IS NULL;

-- ============================================================================
-- DETTAGLIO: TUTTE LE PRENOTAZIONI SENZA SUBSCRIPTION
-- ============================================================================

SELECT 
  b.id AS booking_id,
  b.status AS booking_status,
  b.created_at AS booking_created_at,
  
  -- Informazioni cliente
  b.client_id,
  c.full_name AS client_name,
  c.email AS client_email,
  c.phone AS client_phone,
  
  -- Informazioni lezione
  b.lesson_id,
  l.starts_at AS lesson_starts_at,
  l.ends_at AS lesson_ends_at,
  l.capacity AS lesson_capacity,
  l.is_individual AS lesson_is_individual,
  
  -- Informazioni attività
  a.id AS activity_id,
  a.name AS activity_name,
  a.discipline AS activity_discipline,
  
  -- Informazioni operatore
  o.id AS operator_id,
  o.name AS operator_name
  
FROM public.bookings b
LEFT JOIN public.clients c ON c.id = b.client_id AND c.deleted_at IS NULL
LEFT JOIN public.lessons l ON l.id = b.lesson_id
LEFT JOIN public.activities a ON a.id = l.activity_id
LEFT JOIN public.operators o ON o.id = l.operator_id
WHERE b.subscription_id IS NULL
ORDER BY b.created_at DESC;

-- ============================================================================
-- ANALISI: PRENOTAZIONI SENZA SUBSCRIPTION PER STATUS
-- ============================================================================

SELECT 
  b.status AS booking_status,
  COUNT(*) AS count,
  MIN(b.created_at) AS oldest_booking,
  MAX(b.created_at) AS newest_booking,
  COUNT(*) FILTER (WHERE b.client_id IS NOT NULL) AS with_client,
  COUNT(*) FILTER (WHERE b.client_id IS NULL) AS without_client
FROM public.bookings b
WHERE b.subscription_id IS NULL
GROUP BY b.status
ORDER BY count DESC;

-- ============================================================================
-- ANALISI: PRENOTAZIONI SENZA SUBSCRIPTION PER ATTIVITÀ
-- ============================================================================

SELECT 
  a.name AS activity_name,
  a.discipline AS activity_discipline,
  COUNT(*) AS bookings_without_subscription,
  COUNT(*) FILTER (WHERE b.status = 'booked') AS active_bookings,
  COUNT(*) FILTER (WHERE b.status = 'canceled') AS canceled_bookings
FROM public.bookings b
INNER JOIN public.lessons l ON l.id = b.lesson_id
INNER JOIN public.activities a ON a.id = l.activity_id
WHERE b.subscription_id IS NULL
GROUP BY a.id, a.name, a.discipline
ORDER BY bookings_without_subscription DESC;

-- ============================================================================
-- ANALISI: PRENOTAZIONI SENZA SUBSCRIPTION PER CLIENTE
-- ============================================================================

SELECT 
  c.id AS client_id,
  c.full_name AS client_name,
  c.email AS client_email,
  COUNT(*) AS bookings_without_subscription,
  COUNT(*) FILTER (WHERE b.status = 'booked') AS active_bookings,
  COUNT(*) FILTER (WHERE b.status = 'attended') AS attended_bookings,
  MIN(b.created_at) AS first_booking,
  MAX(b.created_at) AS last_booking
FROM public.bookings b
INNER JOIN public.clients c ON c.id = b.client_id AND c.deleted_at IS NULL
WHERE b.subscription_id IS NULL
GROUP BY c.id, c.full_name, c.email
ORDER BY bookings_without_subscription DESC
LIMIT 50; -- Limita ai top 50 clienti per evitare output troppo lungo

-- ============================================================================
-- VERIFICA: PRENOTAZIONI RECENTI SENZA SUBSCRIPTION (ULTIMI 30 GIORNI)
-- ============================================================================

SELECT 
  b.id AS booking_id,
  b.status AS booking_status,
  b.created_at AS booking_created_at,
  c.full_name AS client_name,
  a.name AS activity_name,
  l.starts_at AS lesson_starts_at
FROM public.bookings b
LEFT JOIN public.clients c ON c.id = b.client_id AND c.deleted_at IS NULL
INNER JOIN public.lessons l ON l.id = b.lesson_id
INNER JOIN public.activities a ON a.id = l.activity_id
WHERE b.subscription_id IS NULL
  AND b.created_at >= NOW() - INTERVAL '30 days'
ORDER BY b.created_at DESC;

-- ============================================================================
-- FINE SCRIPT
-- ============================================================================

