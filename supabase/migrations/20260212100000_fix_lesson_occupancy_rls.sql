-- Migration: Fix lesson_occupancy view to show real booking counts
--
-- Problem: The lesson_occupancy view was created with security_invoker='true',
-- which means it respects RLS policies. Since clients can only see their own
-- bookings (via RLS policy "Clients can view own bookings"), they see incorrect
-- occupancy counts (only their own booking instead of all bookings).
--
-- Solution: Recreate the view WITHOUT security_invoker, so it uses the
-- view owner's permissions (postgres) and can count all bookings.
-- This is safe because the view only exposes aggregate counts, not personal data.

-- First drop dependent view (public_site_schedule depends on lesson_occupancy)
DROP VIEW IF EXISTS public.public_site_schedule;

-- Drop and recreate lesson_occupancy without security_invoker
DROP VIEW IF EXISTS public.lesson_occupancy;

CREATE VIEW public.lesson_occupancy AS
SELECT
  l.id AS lesson_id,
  COUNT(b.*) FILTER (WHERE b.status = 'booked'::public.booking_status) AS booked_count,
  l.capacity,
  GREATEST(
    l.capacity - COUNT(b.*) FILTER (WHERE b.status = 'booked'::public.booking_status),
    0::bigint
  ) AS free_spots
FROM public.lessons l
LEFT JOIN public.bookings b ON b.lesson_id = l.id AND b.status = 'booked'::public.booking_status
GROUP BY l.id, l.capacity;

COMMENT ON VIEW public.lesson_occupancy IS
  'Aggregated lesson occupancy data. Does NOT use security_invoker so all users see real counts.';

GRANT SELECT ON public.lesson_occupancy TO anon;
GRANT SELECT ON public.lesson_occupancy TO authenticated;

-- Recreate public_site_schedule (this view CAN use security_invoker since it's for public data)
CREATE VIEW public.public_site_schedule
WITH (security_invoker = true)
AS
SELECT
  l.id,
  l.starts_at,
  l.ends_at,
  l.capacity,
  a.id AS activity_id,
  a.name AS activity_name,
  a.discipline,
  a.color AS activity_color,
  lo.booked_count,
  lo.free_spots,
  o.id AS operator_id,
  o.name AS operator_name,
  l.booking_deadline_minutes,
  l.cancel_deadline_minutes
FROM public.lessons l
INNER JOIN public.activities a ON a.id = l.activity_id
LEFT JOIN public.lesson_occupancy lo ON lo.lesson_id = l.id
LEFT JOIN public.operators o ON o.id = l.operator_id AND o.is_active = true AND o.deleted_at IS NULL
WHERE
  l.deleted_at IS NULL
  AND a.deleted_at IS NULL
  AND l.is_individual = false
  AND l.starts_at >= CURRENT_DATE
ORDER BY l.starts_at ASC;

COMMENT ON VIEW public.public_site_schedule IS
  'View pubblica per lo schedule delle lezioni. Usa SECURITY INVOKER per rispettare le policy RLS.';

GRANT SELECT ON public.public_site_schedule TO anon;
GRANT SELECT ON public.public_site_schedule TO authenticated;
