-- ============================================================================
-- PULIZIA PRENOTAZIONI DOPPIE PER LEZIONI INDIVIDUALI
-- ============================================================================
-- 
-- Questo script identifica e rimuove le prenotazioni duplicate per lezioni
-- individuali, preferendo di mantenere quelle con reason 'BOOK' e rimuovere
-- quelle con reason 'individual_lesson_auto_booking'.
--
-- STRATEGIA:
-- 1. Identifica booking duplicati (stessa lezione, stesso cliente, status attivi)
-- 2. Per ogni gruppo di duplicati, mantiene il booking con reason 'BOOK'
-- 3. Rimuove i booking con reason 'individual_lesson_auto_booking'
-- 4. Restituisce le entry all'abbonamento per i booking rimossi
--
-- ============================================================================

-- ============================================================================
-- ANALISI: IDENTIFICAZIONE DUPLICATI
-- ============================================================================
-- Esegui questa query per vedere cosa verrà cancellato (solo lettura)

WITH duplicate_bookings AS (
  -- Trova lezioni individuali con booking duplicati
  SELECT 
    l.id AS lesson_id,
    l.is_individual,
    l.assigned_client_id,
    b.client_id,
    COUNT(*) AS booking_count,
    array_agg(b.id ORDER BY b.created_at) AS booking_ids,
    array_agg(b.subscription_id) AS subscription_ids,
    array_agg(b.status) AS booking_statuses,
    array_agg(b.created_at) AS created_ats
  FROM public.lessons l
  INNER JOIN public.bookings b ON b.lesson_id = l.id
  WHERE l.is_individual = true
    AND b.status IN ('booked', 'attended', 'no_show')
    AND b.client_id = l.assigned_client_id
  GROUP BY l.id, l.is_individual, l.assigned_client_id, b.client_id
  HAVING COUNT(*) > 1
)
SELECT 
  'ANALISI DUPLICATI' AS check_type,
  COUNT(*) AS lessons_with_duplicates,
  SUM(booking_count) AS total_duplicate_bookings
FROM duplicate_bookings;

-- ============================================================================
-- DETTAGLIO: DUPLICATI CON REASON
-- ============================================================================

WITH duplicate_groups AS (
  -- Identifica lezioni con booking duplicati
  SELECT 
    l.id AS lesson_id,
    b.client_id,
    COUNT(*) AS booking_count
  FROM public.lessons l
  INNER JOIN public.bookings b ON b.lesson_id = l.id
  WHERE l.is_individual = true
    AND b.status IN ('booked', 'attended', 'no_show')
    AND b.client_id = l.assigned_client_id
  GROUP BY l.id, b.client_id
  HAVING COUNT(*) > 1
),
duplicate_bookings AS (
  SELECT 
    l.id AS lesson_id,
    l.assigned_client_id,
    b.id AS booking_id,
    b.subscription_id,
    b.status AS booking_status,
    b.created_at,
    su.reason AS usage_reason,
    su.id AS usage_id,
    CASE 
      WHEN su.reason = 'BOOK' THEN 1
      WHEN su.reason = 'individual_lesson_auto_booking' THEN 3
      ELSE 2
    END AS priority_order,
    ROW_NUMBER() OVER (
      PARTITION BY l.id, b.client_id 
      ORDER BY 
        CASE 
          WHEN su.reason = 'BOOK' THEN 1
          WHEN su.reason = 'individual_lesson_auto_booking' THEN 3
          ELSE 2
        END,
        b.created_at DESC
    ) AS row_num
  FROM public.lessons l
  INNER JOIN public.bookings b ON b.lesson_id = l.id
  LEFT JOIN public.subscription_usages su ON su.booking_id = b.id AND su.delta = -1
  WHERE l.is_individual = true
    AND b.status IN ('booked', 'attended', 'no_show')
    AND b.client_id = l.assigned_client_id
    AND EXISTS (
      SELECT 1 FROM duplicate_groups dg
      WHERE dg.lesson_id = l.id AND dg.client_id = b.client_id
    )
)
SELECT 
  'DETTAGLIO DUPLICATI' AS check_type,
  lesson_id,
  booking_id,
  subscription_id,
  booking_status,
  created_at,
  usage_reason,
  priority_order,
  CASE WHEN row_num = 1 THEN 'MANTIENI' ELSE 'RIMUOVI' END AS azione
FROM duplicate_bookings
ORDER BY lesson_id, row_num;

-- ============================================================================
-- ESECUZIONE: RIMOZIONE DUPLICATI
-- ============================================================================
-- ATTENZIONE: Questa sezione modifica il database!
-- Rimuove commento per eseguire

BEGIN;

-- Tabella temporanea con i booking da rimuovere (quelli con individual_lesson_auto_booking)
WITH duplicate_groups AS (
  -- Identifica lezioni con booking duplicati
  SELECT 
    l.id AS lesson_id,
    b.client_id,
    COUNT(*) AS booking_count
  FROM public.lessons l
  INNER JOIN public.bookings b ON b.lesson_id = l.id
  WHERE l.is_individual = true
    AND b.status IN ('booked', 'attended', 'no_show')
    AND b.client_id = l.assigned_client_id
  GROUP BY l.id, b.client_id
  HAVING COUNT(*) > 1
),
duplicate_bookings AS (
  -- Per ogni gruppo di duplicati, classifica i booking
  SELECT 
    l.id AS lesson_id,
    b.id AS booking_id,
    b.subscription_id,
    b.created_at,
    su.id AS usage_id,
    su.reason AS usage_reason,
    -- Priorità: 1 = BOOK, 2 = altri, 3 = individual_lesson_auto_booking
    CASE 
      WHEN su.reason = 'BOOK' THEN 1
      WHEN su.reason = 'individual_lesson_auto_booking' THEN 3
      ELSE 2
    END AS priority_order,
    ROW_NUMBER() OVER (
      PARTITION BY l.id, b.client_id 
      ORDER BY 
        CASE 
          WHEN su.reason = 'BOOK' THEN 1
          WHEN su.reason = 'individual_lesson_auto_booking' THEN 3
          ELSE 2
        END,
        b.created_at DESC
    ) AS row_num
  FROM public.lessons l
  INNER JOIN public.bookings b ON b.lesson_id = l.id
  LEFT JOIN public.subscription_usages su ON su.booking_id = b.id AND su.delta = -1
  WHERE l.is_individual = true
    AND b.status IN ('booked', 'attended', 'no_show')
    AND b.client_id = l.assigned_client_id
    AND EXISTS (
      SELECT 1 FROM duplicate_groups dg
      WHERE dg.lesson_id = l.id AND dg.client_id = b.client_id
    )
),
bookings_to_remove AS (
  -- Mantiene solo il primo (priority_order più basso), rimuove gli altri
  SELECT 
    booking_id,
    subscription_id,
    usage_id,
    usage_reason
  FROM duplicate_bookings
  WHERE row_num > 1  -- Rimuove tutti tranne il primo (quello da mantenere)
)
SELECT 
  booking_id,
  subscription_id,
  usage_id
INTO TEMP temp_bookings_to_remove
FROM bookings_to_remove;

-- Mostra quanti booking verranno rimossi
SELECT 
  'RIEPILOGO RIMOZIONE' AS check_type,
  COUNT(*) AS bookings_to_remove,
  COUNT(DISTINCT subscription_id) AS subscriptions_affected
FROM temp_bookings_to_remove;

-- Restituisce le entry all'abbonamento per i booking rimossi
-- (solo se avevano una subscription e un usage_id con delta = -1)
-- Questo deve essere fatto PRIMA di cancellare gli usage originali
-- Usa subscription_id dal subscription_usages originale per sicurezza
INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
SELECT DISTINCT
  su.subscription_id,
  btr.booking_id,
  +1,  -- Restituisce l'entry
  'duplicate_booking_cleanup'
FROM temp_bookings_to_remove btr
INNER JOIN public.subscription_usages su ON su.id = btr.usage_id
WHERE btr.usage_id IS NOT NULL
  AND su.delta = -1
  AND su.subscription_id IS NOT NULL;

-- Ora cancella i subscription_usages originali dei booking rimossi
DELETE FROM public.subscription_usages
WHERE id IN (
  SELECT usage_id 
  FROM temp_bookings_to_remove 
  WHERE usage_id IS NOT NULL
);

-- Cancella i booking duplicati (imposta status a 'canceled' per sicurezza)
UPDATE public.bookings
SET status = 'canceled'
WHERE id IN (
  SELECT booking_id 
  FROM temp_bookings_to_remove
);

-- Mostra risultato finale
SELECT 
  'RISULTATO FINALE' AS check_type,
  COUNT(*) AS bookings_removed,
  COUNT(DISTINCT subscription_id) AS subscriptions_restored
FROM temp_bookings_to_remove;

-- Pulisci tabella temporanea
DROP TABLE temp_bookings_to_remove;

-- COMMIT;  -- Rimuovi commento per confermare le modifiche
-- ROLLBACK;  -- Oppure usa ROLLBACK per annullare

-- ============================================================================
-- VERIFICA POST-PULIZIA: Verifica che non ci siano più duplicati
-- ============================================================================

SELECT 
  'VERIFICA POST-PULIZIA' AS check_type,
  COUNT(*) AS remaining_duplicates
FROM (
  SELECT 
    l.id AS lesson_id,
    b.client_id,
    COUNT(*) AS booking_count
  FROM public.lessons l
  INNER JOIN public.bookings b ON b.lesson_id = l.id
  WHERE l.is_individual = true
    AND b.status IN ('booked', 'attended', 'no_show')
    AND b.client_id = l.assigned_client_id
  GROUP BY l.id, b.client_id
  HAVING COUNT(*) > 1
) duplicates;

-- ============================================================================
-- FINE SCRIPT
-- ============================================================================

