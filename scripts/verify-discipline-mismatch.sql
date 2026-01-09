-- ============================================================================
-- VERIFICA: BOOKINGS CON SUBSCRIPTION CHE NON COPRE LA DISCIPLINA
-- ============================================================================
--
-- Questo script identifica prenotazioni dove l'abbonamento usato non copre
-- la disciplina della lezione prenotata.
--
-- I piani "Open" (senza plan_activities) sono considerati universali e
-- coprono tutte le discipline.
--
-- ============================================================================

-- ============================================================================
-- 1. RIEPILOGO: CONTEGGIO BOOKINGS CON DISCIPLINA MISMATCH
-- ============================================================================

SELECT
  'Bookings con subscription non valida per disciplina' AS check_type,
  COUNT(*) AS count
FROM public.bookings b
INNER JOIN public.lessons l ON l.id = b.lesson_id
INNER JOIN public.subscriptions s ON s.id = b.subscription_id
WHERE b.subscription_id IS NOT NULL
  AND b.status IN ('booked', 'attended', 'no_show')  -- Solo prenotazioni attive
  -- Il piano ha almeno una activity configurata (non è "Open")
  AND EXISTS (
    SELECT 1 FROM public.plan_activities pa2
    WHERE pa2.plan_id = s.plan_id
  )
  -- Ma non include l'activity della lezione
  AND NOT EXISTS (
    SELECT 1 FROM public.plan_activities pa
    WHERE pa.plan_id = s.plan_id
      AND pa.activity_id = l.activity_id
  );

-- ============================================================================
-- 2. DETTAGLIO: BOOKINGS CON DISCIPLINA MISMATCH
-- ============================================================================

SELECT
  b.id AS booking_id,
  b.status AS booking_status,
  b.created_at AS booking_created_at,

  -- Cliente
  c.id AS client_id,
  c.full_name AS client_name,
  c.email AS client_email,

  -- Lezione
  l.id AS lesson_id,
  l.starts_at AS lesson_starts_at,
  a.name AS activity_name,
  a.discipline AS activity_discipline,

  -- Subscription
  s.id AS subscription_id,
  s.status AS subscription_status,
  COALESCE(s.custom_name, p.name) AS plan_name,
  p.discipline AS plan_discipline,

  -- Activities coperte dal piano
  (
    SELECT array_agg(act.name)
    FROM public.plan_activities pa
    INNER JOIN public.activities act ON act.id = pa.activity_id
    WHERE pa.plan_id = s.plan_id
  ) AS plan_covers_activities

FROM public.bookings b
INNER JOIN public.lessons l ON l.id = b.lesson_id
INNER JOIN public.activities a ON a.id = l.activity_id
INNER JOIN public.subscriptions s ON s.id = b.subscription_id
INNER JOIN public.plans p ON p.id = s.plan_id
LEFT JOIN public.clients c ON c.id = b.client_id AND c.deleted_at IS NULL
WHERE b.subscription_id IS NOT NULL
  AND b.status IN ('booked', 'attended', 'no_show')
  -- Il piano ha almeno una activity configurata (non è "Open")
  AND EXISTS (
    SELECT 1 FROM public.plan_activities pa2
    WHERE pa2.plan_id = s.plan_id
  )
  -- Ma non include l'activity della lezione
  AND NOT EXISTS (
    SELECT 1 FROM public.plan_activities pa
    WHERE pa.plan_id = s.plan_id
      AND pa.activity_id = l.activity_id
  )
ORDER BY b.created_at DESC;

-- ============================================================================
-- 3. ANALISI: MISMATCH PER CLIENTE
-- ============================================================================

SELECT
  c.id AS client_id,
  c.full_name AS client_name,
  c.email AS client_email,
  COUNT(*) AS total_mismatch_bookings,
  COUNT(*) FILTER (WHERE b.status = 'booked') AS future_bookings,
  COUNT(*) FILTER (WHERE b.status = 'attended') AS attended_bookings,
  array_agg(DISTINCT a.name) AS wrong_activities,
  array_agg(DISTINCT COALESCE(s.custom_name, p.name)) AS used_plans

FROM public.bookings b
INNER JOIN public.lessons l ON l.id = b.lesson_id
INNER JOIN public.activities a ON a.id = l.activity_id
INNER JOIN public.subscriptions s ON s.id = b.subscription_id
INNER JOIN public.plans p ON p.id = s.plan_id
INNER JOIN public.clients c ON c.id = b.client_id AND c.deleted_at IS NULL
WHERE b.subscription_id IS NOT NULL
  AND b.status IN ('booked', 'attended', 'no_show')
  AND EXISTS (
    SELECT 1 FROM public.plan_activities pa2
    WHERE pa2.plan_id = s.plan_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.plan_activities pa
    WHERE pa.plan_id = s.plan_id
      AND pa.activity_id = l.activity_id
  )
GROUP BY c.id, c.full_name, c.email
ORDER BY total_mismatch_bookings DESC;

-- ============================================================================
-- 4. ANALISI: MISMATCH PER PIANO
-- ============================================================================

SELECT
  p.id AS plan_id,
  p.name AS plan_name,
  p.discipline AS plan_discipline,

  -- Activities coperte dal piano
  (
    SELECT array_agg(act.name)
    FROM public.plan_activities pa
    INNER JOIN public.activities act ON act.id = pa.activity_id
    WHERE pa.plan_id = p.id
  ) AS covers_activities,

  -- Activities usate erroneamente
  array_agg(DISTINCT a.name) AS wrongly_used_for,

  COUNT(*) AS total_mismatch_bookings

FROM public.bookings b
INNER JOIN public.lessons l ON l.id = b.lesson_id
INNER JOIN public.activities a ON a.id = l.activity_id
INNER JOIN public.subscriptions s ON s.id = b.subscription_id
INNER JOIN public.plans p ON p.id = s.plan_id
WHERE b.subscription_id IS NOT NULL
  AND b.status IN ('booked', 'attended', 'no_show')
  AND EXISTS (
    SELECT 1 FROM public.plan_activities pa2
    WHERE pa2.plan_id = s.plan_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.plan_activities pa
    WHERE pa.plan_id = s.plan_id
      AND pa.activity_id = l.activity_id
  )
GROUP BY p.id, p.name, p.discipline
ORDER BY total_mismatch_bookings DESC;

-- ============================================================================
-- 5. VERIFICA: PIANI "OPEN" (senza plan_activities)
-- ============================================================================
-- Questi piani sono considerati universali e coprono tutte le discipline

SELECT
  'Piani "Open" (universali)' AS check_type,
  p.id AS plan_id,
  p.name AS plan_name,
  p.discipline AS plan_discipline,
  p.is_active,
  (
    SELECT COUNT(*)
    FROM public.subscriptions s
    WHERE s.plan_id = p.id AND s.deleted_at IS NULL
  ) AS active_subscriptions
FROM public.plans p
WHERE p.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.plan_activities pa
    WHERE pa.plan_id = p.id
  )
ORDER BY p.name;

-- ============================================================================
-- FINE SCRIPT
-- ============================================================================
