-- ============================================================================
-- SCRIPT DI VERIFICA COMPLETA: ABBONAMENTI, INGRESSI E PRENOTAZIONI
-- ============================================================================
-- 
-- Questo script verifica la coerenza tra:
-- - subscriptions (abbonamenti)
-- - subscription_usages (tracciamento ingressi utilizzati/ripristinati)
-- - bookings (prenotazioni)
-- - subscriptions_with_remaining (view calcolo ingressi rimanenti)
--
-- ============================================================================

-- ============================================================================
-- 1. VERIFICA: BOOKINGS CON subscription_id MA SENZA subscription_usages
-- ============================================================================
-- Le prenotazioni con subscription_id dovrebbero avere almeno un record
-- in subscription_usages con delta = -1

SELECT 
  'Bookings con subscription_id ma senza subscription_usages' AS check_type,
  COUNT(*) AS count,
  array_agg(b.id ORDER BY b.created_at DESC) AS booking_ids,
  array_agg(DISTINCT b.subscription_id) AS subscription_ids
FROM public.bookings b
WHERE b.subscription_id IS NOT NULL
  AND b.status IN ('booked', 'attended', 'no_show')  -- Solo prenotazioni attive
  AND NOT EXISTS (
    SELECT 1
    FROM public.subscription_usages su
    WHERE su.booking_id = b.id
      AND su.subscription_id = b.subscription_id
  );

-- ============================================================================
-- 2. VERIFICA: BOOKINGS CANCELLATE CON subscription_usages delta=-1 MA SENZA RESTORE
-- ============================================================================
-- Le prenotazioni cancellate dovrebbero avere un record con delta = +1
-- per ripristinare gli ingressi

SELECT 
  'Bookings cancellate senza restore (delta=+1 mancante)' AS check_type,
  COUNT(*) AS count,
  array_agg(b.id ORDER BY b.created_at DESC) AS booking_ids,
  array_agg(DISTINCT su.subscription_id) AS subscription_ids
FROM public.bookings b
INNER JOIN public.subscription_usages su ON su.booking_id = b.id
WHERE b.status = 'canceled'
  AND su.delta = -1
  AND NOT EXISTS (
    SELECT 1
    FROM public.subscription_usages su2
    WHERE su2.booking_id = b.id
      AND su2.delta = +1
  );

-- ============================================================================
-- 3. VERIFICA: SUBSCRIPTION_USAGES SENZA BOOKING CORRISPONDENTE
-- ============================================================================
-- Ogni subscription_usages con booking_id dovrebbe avere una booking valida

SELECT 
  'Subscription_usages con booking_id inesistente o cancellata' AS check_type,
  COUNT(*) AS count,
  array_agg(su.id ORDER BY su.created_at DESC) AS usage_ids,
  array_agg(DISTINCT su.booking_id) AS invalid_booking_ids
FROM public.subscription_usages su
WHERE su.booking_id IS NOT NULL
  AND (
    NOT EXISTS (
      SELECT 1
      FROM public.bookings b
      WHERE b.id = su.booking_id
    )
    OR EXISTS (
      SELECT 1
      FROM public.bookings b
      WHERE b.id = su.booking_id
        AND b.status = 'canceled'
        AND su.delta = -1
        AND NOT EXISTS (
          SELECT 1
          FROM public.subscription_usages su2
          WHERE su2.booking_id = b.id
            AND su2.delta = +1
        )
    )
  );

-- ============================================================================
-- 4. VERIFICA: SUBSCRIPTION_USAGES CON DELTA INCONSISTENTI
-- ============================================================================
-- I delta dovrebbero essere solo -1 (prenotazione) o +1 (ripristino)

SELECT 
  'Subscription_usages con delta diverso da -1 o +1' AS check_type,
  COUNT(*) AS count,
  array_agg(su.id ORDER BY su.created_at DESC) AS usage_ids,
  array_agg(DISTINCT su.delta) AS invalid_deltas
FROM public.subscription_usages su
WHERE su.delta NOT IN (-1, +1);

-- ============================================================================
-- 5. VERIFICA: COERENZA subscription_id TRA bookings E subscription_usages
-- ============================================================================
-- Il subscription_id nella booking dovrebbe corrispondere a quello in subscription_usages

SELECT 
  'Bookings con subscription_id diverso da subscription_usages' AS check_type,
  COUNT(*) AS count,
  array_agg(b.id ORDER BY b.created_at DESC) AS booking_ids,
  array_agg(DISTINCT b.subscription_id) AS booking_subscription_ids
FROM public.bookings b
INNER JOIN public.subscription_usages su ON su.booking_id = b.id
WHERE b.subscription_id IS NOT NULL
  AND b.subscription_id != su.subscription_id;

-- ============================================================================
-- 6. VERIFICA: CALCOLO INGRESSI RIMANENTI (MANUALE vs VIEW)
-- ============================================================================
-- Confronta il calcolo manuale degli ingressi rimanenti con la view
-- subscriptions_with_remaining

WITH subscription_info AS (
  SELECT 
    s.id,
    s.client_id,
    COALESCE(s.custom_entries, p.entries) as effective_entries,
    s.status,
    s.deleted_at
  FROM public.subscriptions s
  LEFT JOIN public.plans p ON p.id = s.plan_id
  WHERE s.deleted_at IS NULL
),
usage_totals AS (
  SELECT 
    subscription_id,
    COALESCE(SUM(delta), 0) as delta_sum,
    COUNT(*) FILTER (WHERE delta = -1) as minus_count,
    COUNT(*) FILTER (WHERE delta = +1) as plus_count
  FROM public.subscription_usages
  GROUP BY subscription_id
),
calculated_remaining AS (
  SELECT 
    si.id,
    si.effective_entries,
    COALESCE(ut.delta_sum, 0) as used_entries_sum,
    CASE
      WHEN si.effective_entries IS NOT NULL 
      THEN si.effective_entries + COALESCE(ut.delta_sum, 0)
      ELSE NULL
    END as calculated_remaining,
    ut.minus_count,
    ut.plus_count
  FROM subscription_info si
  LEFT JOIN usage_totals ut ON ut.subscription_id = si.id
)
SELECT 
  'Abbonamenti con calcolo ingressi rimanenti inconsistente' AS check_type,
  COUNT(*) AS count,
  array_agg(cr.id ORDER BY cr.id) AS subscription_ids,
  array_agg(cr.calculated_remaining) AS calculated_values,
  array_agg(swr.remaining_entries) AS view_values
FROM calculated_remaining cr
LEFT JOIN public.subscriptions_with_remaining swr ON swr.id = cr.id
WHERE cr.effective_entries IS NOT NULL
  AND (
    cr.calculated_remaining != swr.remaining_entries
    OR (cr.calculated_remaining IS NULL AND swr.remaining_entries IS NOT NULL)
    OR (cr.calculated_remaining IS NOT NULL AND swr.remaining_entries IS NULL)
  );

-- ============================================================================
-- 7. VERIFICA: ABBONAMENTI CON INGRESSI RIMANENTI NEGATIVI
-- ============================================================================
-- Gli ingressi rimanenti non dovrebbero essere negativi (a meno di errori)

SELECT 
  'Abbonamenti con ingressi rimanenti negativi' AS check_type,
  COUNT(*) AS count,
  array_agg(swr.id ORDER BY swr.remaining_entries) AS subscription_ids,
  array_agg(swr.remaining_entries) AS remaining_entries_values
FROM public.subscriptions_with_remaining swr
WHERE swr.remaining_entries IS NOT NULL
  AND swr.remaining_entries < 0;

-- ============================================================================
-- 8. VERIFICA: BOOKINGS CON STATUS 'booked' MA CON subscription_usages delta=+1
-- ============================================================================
-- Le prenotazioni attive non dovrebbero avere restore (delta=+1) senza cancellazione

SELECT 
  'Bookings attive (booked/attended/no_show) con restore (delta=+1) senza cancellazione' AS check_type,
  COUNT(*) AS count,
  array_agg(b.id ORDER BY b.created_at DESC) AS booking_ids,
  array_agg(DISTINCT su.subscription_id) AS subscription_ids
FROM public.bookings b
INNER JOIN public.subscription_usages su ON su.booking_id = b.id
WHERE b.status IN ('booked', 'attended', 'no_show')
  AND su.delta = +1
  AND NOT EXISTS (
    SELECT 1
    FROM public.subscription_usages su2
    WHERE su2.booking_id = b.id
      AND su2.delta = -1
  );

-- ============================================================================
-- 9. VERIFICA: SUBSCRIPTION_USAGES CON subscription_id INESISTENTE
-- ============================================================================
-- Ogni subscription_usages dovrebbe riferirsi a una subscription esistente

SELECT 
  'Subscription_usages con subscription_id inesistente' AS check_type,
  COUNT(*) AS count,
  array_agg(su.id ORDER BY su.created_at DESC) AS usage_ids,
  array_agg(DISTINCT su.subscription_id) AS invalid_subscription_ids
FROM public.subscription_usages su
LEFT JOIN public.subscriptions s ON s.id = su.subscription_id
WHERE s.id IS NULL;

-- ============================================================================
-- 10. VERIFICA: SUBSCRIPTION_USAGES CON booking_id INESISTENTE
-- ============================================================================

SELECT 
  'Subscription_usages con booking_id inesistente' AS check_type,
  COUNT(*) AS count,
  array_agg(su.id ORDER BY su.created_at DESC) AS usage_ids,
  array_agg(DISTINCT su.booking_id) AS invalid_booking_ids
FROM public.subscription_usages su
WHERE su.booking_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.bookings b
    WHERE b.id = su.booking_id
  );

-- ============================================================================
-- 11. RIEPILOGO GENERALE: STATISTICHE
-- ============================================================================

SELECT 
  'RIEPILOGO GENERALE' AS check_type,
  (SELECT COUNT(*) FROM public.subscriptions WHERE deleted_at IS NULL) AS total_subscriptions,
  (SELECT COUNT(*) FROM public.bookings) AS total_bookings,
  (SELECT COUNT(*) FROM public.subscription_usages) AS total_subscription_usages,
  (SELECT COUNT(*) FROM public.subscription_usages WHERE delta = -1) AS total_minus_delta,
  (SELECT COUNT(*) FROM public.subscription_usages WHERE delta = +1) AS total_plus_delta,
  (SELECT COUNT(*) FROM public.bookings WHERE subscription_id IS NOT NULL) AS bookings_with_subscription,
  (SELECT COUNT(*) FROM public.bookings WHERE status = 'canceled') AS canceled_bookings,
  (SELECT COUNT(*) FROM public.subscriptions_with_remaining WHERE remaining_entries < 0) AS subscriptions_negative_entries,
  (SELECT COUNT(*) FROM public.subscriptions_with_remaining WHERE remaining_entries IS NULL) AS subscriptions_unlimited;

-- ============================================================================
-- 12. VERIFICA: BILANCIO DELTA PER OGNI SUBSCRIPTION
-- ============================================================================
-- Per ogni subscription, la somma dei delta dovrebbe essere <= 0
-- (non può essere positiva perché non si possono avere più ingressi del totale)

WITH subscription_deltas AS (
  SELECT 
    su.subscription_id,
    SUM(su.delta) as total_delta,
    COUNT(*) FILTER (WHERE su.delta = -1) as bookings_count,
    COUNT(*) FILTER (WHERE su.delta = +1) as restores_count,
    s.custom_entries,
    p.entries as plan_entries,
    COALESCE(s.custom_entries, p.entries) as effective_entries
  FROM public.subscription_usages su
  INNER JOIN public.subscriptions s ON s.id = su.subscription_id
  LEFT JOIN public.plans p ON p.id = s.plan_id
  WHERE s.deleted_at IS NULL
  GROUP BY su.subscription_id, s.custom_entries, p.entries
)
SELECT 
  'Subscriptions con bilancio delta positivo (più restore che prenotazioni)' AS check_type,
  COUNT(*) AS count,
  array_agg(subscription_id ORDER BY total_delta DESC) AS subscription_ids,
  array_agg(total_delta) AS total_deltas
FROM subscription_deltas
WHERE effective_entries IS NOT NULL
  AND total_delta > 0;

-- ============================================================================
-- 13. VERIFICA: BOOKINGS CON PIÙ subscription_usages CON LO STESSO DELTA
-- ============================================================================
-- Ogni booking dovrebbe avere al massimo un delta=-1 e un delta=+1

WITH booking_deltas AS (
  SELECT 
    b.id as booking_id,
    COUNT(*) FILTER (WHERE su.delta = -1) as minus_count,
    COUNT(*) FILTER (WHERE su.delta = +1) as plus_count
  FROM public.bookings b
  INNER JOIN public.subscription_usages su ON su.booking_id = b.id
  GROUP BY b.id
)
SELECT 
  'Bookings con più subscription_usages con lo stesso delta' AS check_type,
  COUNT(*) AS count,
  array_agg(booking_id ORDER BY booking_id) AS booking_ids
FROM booking_deltas
WHERE minus_count > 1 OR plus_count > 1;

-- ============================================================================
-- FINE SCRIPT
-- ============================================================================

