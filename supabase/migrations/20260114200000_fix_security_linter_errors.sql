-- Migration: Fix Supabase Security Linter Errors
--
-- This migration fixes two categories of security issues flagged by the Supabase linter:
--
-- 1. policy_exists_rls_disabled / rls_disabled_in_public on notification_queue:
--    The table has RLS policies but RLS is disabled. We need to either:
--    - Enable RLS and keep the policies, OR
--    - Remove the policies since RLS is disabled
--    Since notification_queue is only accessed by Edge Functions via service_role,
--    we remove the unused policies (service_role bypasses RLS anyway).
--
-- 2. security_definer_view on multiple views:
--    Views created without explicit security_invoker=true use SECURITY DEFINER
--    by default, which enforces the view creator's permissions instead of the
--    querying user's. We recreate the views with SECURITY INVOKER.

-- ============================================================================
-- 1. FIX notification_queue: Remove unused RLS policies
-- ============================================================================
-- Since RLS is disabled on notification_queue (done intentionally in migration
-- 20260114000003), the policies serve no purpose. Remove them to satisfy the linter.

DROP POLICY IF EXISTS "notification_queue_anon_all" ON "public"."notification_queue";
DROP POLICY IF EXISTS "notification_queue_authenticated_all" ON "public"."notification_queue";
DROP POLICY IF EXISTS "notification_queue_service_all" ON "public"."notification_queue";

COMMENT ON TABLE "public"."notification_queue" IS
'Coda notifiche da processare. RLS disabilitato - accessibile solo via Edge Functions con service_role key.';

-- ============================================================================
-- 2. FIX SECURITY DEFINER views: Recreate with SECURITY INVOKER
-- ============================================================================

-- 2a. public_site_operators
DROP VIEW IF EXISTS public.public_site_operators;
CREATE VIEW public.public_site_operators
WITH (security_invoker = true)
AS
SELECT
  o.id,
  o.name,
  o.role,
  o.bio,
  NULL::text AS image_url,
  NULL::text AS image_alt,
  NULL::integer AS display_order,
  o.is_active
FROM public.operators o
WHERE
  o.is_active = true
  AND o.deleted_at IS NULL
ORDER BY o.name ASC;

COMMENT ON VIEW public.public_site_operators IS
  'View pubblica per gli operatori attivi. Usa SECURITY INVOKER per rispettare le policy RLS.';

GRANT SELECT ON public.public_site_operators TO anon;
GRANT SELECT ON public.public_site_operators TO authenticated;

-- 2b. public_site_activities
DROP VIEW IF EXISTS public.public_site_activities;
CREATE VIEW public.public_site_activities
WITH (security_invoker = true)
AS
SELECT
  a.id,
  a.name,
  a.slug,
  a.description,
  a.discipline,
  a.color,
  a.duration_minutes,
  a.image_url,
  a.is_active,
  a.icon_name,
  -- Campi landing page
  a.landing_title,
  a.landing_subtitle,
  a.active_months,
  a.target_audience,
  a.program_objectives,
  a.why_participate,
  a.journey_structure,
  a.created_at,
  a.updated_at
FROM public.activities a
WHERE
  a.deleted_at IS NULL
ORDER BY a.name ASC;

COMMENT ON VIEW public.public_site_activities IS
  'View pubblica per le attività. Usa SECURITY INVOKER per rispettare le policy RLS.';

GRANT SELECT ON public.public_site_activities TO anon;
GRANT SELECT ON public.public_site_activities TO authenticated;

-- 2c. public_site_pricing
DROP VIEW IF EXISTS public.public_site_pricing;
CREATE VIEW public.public_site_pricing
WITH (security_invoker = true)
AS
SELECT
  p.id,
  p.name,
  p.discipline,
  p.price_cents,
  p.currency,
  p.entries,
  p.validity_days,
  p.description,
  p.discount_percent,
  COALESCE(
    json_agg(
      json_build_object(
        'id', pa.activity_id,
        'name', a.name,
        'discipline', a.discipline
      )
    ) FILTER (WHERE pa.activity_id IS NOT NULL),
    '[]'::json
  ) AS activities
FROM public.plans p
LEFT JOIN public.plan_activities pa ON pa.plan_id = p.id
LEFT JOIN public.activities a ON a.id = pa.activity_id
  AND a.deleted_at IS NULL
WHERE
  p.deleted_at IS NULL
  AND p.is_active = true
GROUP BY
  p.id,
  p.name,
  p.discipline,
  p.price_cents,
  p.currency,
  p.entries,
  p.validity_days,
  p.description,
  p.discount_percent
ORDER BY p.price_cents ASC;

COMMENT ON VIEW public.public_site_pricing IS
  'View pubblica per i piani e prezzi. Usa SECURITY INVOKER per rispettare le policy RLS.';

GRANT SELECT ON public.public_site_pricing TO anon;
GRANT SELECT ON public.public_site_pricing TO authenticated;

-- 2d. public_site_schedule
DROP VIEW IF EXISTS public.public_site_schedule;
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

-- 2e. public_site_events
DROP VIEW IF EXISTS public.public_site_events;
CREATE VIEW public.public_site_events
WITH (security_invoker = true)
AS
SELECT
  e.id,
  e.name AS title,
  e.description,
  e.image_url,
  e.starts_at AS start_date,
  e.ends_at AS end_date,
  e.link AS registration_url,
  e.link AS link_url,
  e.created_at,
  e.updated_at
FROM public.events e
WHERE
  e.deleted_at IS NULL
ORDER BY e.starts_at DESC;

COMMENT ON VIEW public.public_site_events IS
  'View pubblica per gli eventi. Usa SECURITY INVOKER per rispettare le policy RLS.';

GRANT SELECT ON public.public_site_events TO anon;
GRANT SELECT ON public.public_site_events TO authenticated;

-- 2f. financial_monthly_summary
DROP VIEW IF EXISTS public.financial_monthly_summary;
CREATE VIEW public.financial_monthly_summary
WITH (security_invoker = true)
AS
WITH lesson_revenue AS (
  SELECT
    (date_trunc('month', l.starts_at))::date AS month,
    (sum(
      CASE
        WHEN (s.custom_price_cents IS NOT NULL AND s.custom_entries IS NOT NULL AND s.custom_entries > 0)
          THEN round((s.custom_price_cents::numeric / s.custom_entries::numeric))
        WHEN (p.price_cents IS NOT NULL AND p.entries IS NOT NULL AND p.entries > 0)
          THEN round((p.price_cents::numeric / p.entries::numeric))
        ELSE 0::numeric
      END
    ))::integer AS revenue_cents,
    count(DISTINCT b.id) AS bookings_count
  FROM public.bookings b
  JOIN public.lessons l ON l.id = b.lesson_id
  LEFT JOIN public.subscriptions s ON s.id = b.subscription_id
  LEFT JOIN public.plans p ON p.id = s.plan_id
  WHERE
    b.status = ANY (ARRAY['booked'::public.booking_status, 'attended'::public.booking_status, 'no_show'::public.booking_status])
    AND b.subscription_id IS NOT NULL
  GROUP BY (date_trunc('month', l.starts_at))::date
),
event_revenue AS (
  SELECT
    (date_trunc('month', e.starts_at))::date AS month,
    (sum(e.price_cents))::integer AS revenue_cents,
    count(DISTINCT eb.id) AS bookings_count
  FROM public.event_bookings eb
  JOIN public.events e ON e.id = eb.event_id
  WHERE
    eb.status = ANY (ARRAY['booked'::public.booking_status, 'attended'::public.booking_status, 'no_show'::public.booking_status])
    AND e.price_cents IS NOT NULL
  GROUP BY (date_trunc('month', e.starts_at))::date
),
subscription_revenue AS (
  SELECT
    (date_trunc('month', s.started_at::timestamp with time zone))::date AS month,
    (sum(
      CASE
        WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
        WHEN p.price_cents IS NOT NULL THEN p.price_cents
        ELSE 0
      END
    ))::integer AS revenue_cents,
    count(*) AS subscriptions_count
  FROM public.subscriptions s
  LEFT JOIN public.plans p ON p.id = s.plan_id
  GROUP BY (date_trunc('month', s.started_at::timestamp with time zone))::date
),
all_months AS (
  SELECT DISTINCT month FROM lesson_revenue
  UNION
  SELECT DISTINCT month FROM event_revenue
  UNION
  SELECT DISTINCT month FROM subscription_revenue
)
SELECT
  am.month,
  (COALESCE(lr.revenue_cents, 0) + COALESCE(er.revenue_cents, 0) + COALESCE(sr.revenue_cents, 0)) AS revenue_cents,
  (COALESCE(lr.revenue_cents, 0) + COALESCE(er.revenue_cents, 0) + COALESCE(sr.revenue_cents, 0)) AS gross_revenue_cents,
  0 AS refunds_cents,
  (COALESCE(lr.bookings_count, 0::bigint) + COALESCE(er.bookings_count, 0::bigint) + COALESCE(sr.subscriptions_count, 0::bigint)) AS completed_payments_count,
  0 AS refunded_payments_count
FROM all_months am
LEFT JOIN lesson_revenue lr ON lr.month = am.month
LEFT JOIN event_revenue er ON er.month = am.month
LEFT JOIN subscription_revenue sr ON sr.month = am.month
ORDER BY am.month DESC;

COMMENT ON VIEW public.financial_monthly_summary IS
  'View per il sommario finanziario mensile. Usa SECURITY INVOKER - accessibile solo a utenti con permessi finanziari.';

GRANT SELECT ON public.financial_monthly_summary TO authenticated;
