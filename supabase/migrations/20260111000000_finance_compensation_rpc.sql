-- Migration: Finance Compensation RPC Functions
-- Creates functions for operator compensation calculation and revenue by client

-- Function to calculate operator compensation per lesson
-- Uses the formula:
-- 1. Room rental = 15% of generated (ALWAYS)
-- 2. If generated/hour > 40 EUR:
--    - Operator = 40 EUR/hour (prorated)
--    - Margin = generated - room_rental - operator
--    - Alice (manager) = 25% of margin
--    - Studio = 75% of margin
-- 3. If generated/hour <= 40 EUR:
--    - Operator = generated - room_rental
--    - Alice = 0
--    - Studio = 0

CREATE OR REPLACE FUNCTION calculate_operator_compensation(
  p_month_start DATE,
  p_month_end DATE,
  p_operator_id UUID DEFAULT NULL
)
RETURNS TABLE (
  operator_id UUID,
  operator_name TEXT,
  lesson_id UUID,
  lesson_date TIMESTAMPTZ,
  activity_name TEXT,
  lesson_duration_minutes INTEGER,
  generated_revenue_cents BIGINT,
  revenue_per_hour_cents BIGINT,
  room_rental_cents BIGINT,
  operator_payout_cents BIGINT,
  alice_share_cents BIGINT,
  studio_margin_cents BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH lesson_revenue AS (
    -- Calculate revenue generated per lesson from bookings
    -- Revenue = sum of (subscription price / entries) for each booking
    SELECT
      l.id AS lesson_id,
      l.operator_id,
      l.starts_at,
      l.ends_at,
      a.name AS activity_name,
      COALESCE(a.duration_minutes,
        EXTRACT(EPOCH FROM (l.ends_at - l.starts_at)) / 60
      )::INTEGER AS duration_minutes,
      COALESCE(SUM(
        CASE
          -- Custom subscription: use custom price / custom entries
          WHEN s.custom_price_cents IS NOT NULL AND COALESCE(s.custom_entries, 0) > 0
            THEN s.custom_price_cents / s.custom_entries
          -- Regular subscription: use plan price (with discount) / entries
          WHEN p.price_cents IS NOT NULL AND COALESCE(p.entries, 0) > 0
            THEN ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0)) / p.entries
          ELSE 0
        END
      ), 0)::BIGINT AS generated_revenue_cents
    FROM lessons l
    JOIN activities a ON l.activity_id = a.id
    LEFT JOIN bookings b ON b.lesson_id = l.id
      AND b.status IN ('booked', 'attended', 'no_show')
    LEFT JOIN subscriptions s ON b.subscription_id = s.id
    LEFT JOIN plans p ON s.plan_id = p.id
    WHERE l.starts_at >= p_month_start
      AND l.starts_at < (p_month_end + INTERVAL '1 day')
      AND l.deleted_at IS NULL
      AND l.operator_id IS NOT NULL
      AND (p_operator_id IS NULL OR l.operator_id = p_operator_id)
    GROUP BY l.id, l.operator_id, l.starts_at, l.ends_at, a.name, a.duration_minutes
  ),
  compensation_calc AS (
    SELECT
      lr.lesson_id,
      lr.operator_id,
      o.name AS operator_name,
      lr.starts_at AS lesson_date,
      lr.activity_name,
      GREATEST(lr.duration_minutes, 1) AS lesson_duration_minutes, -- Avoid division by zero
      lr.generated_revenue_cents,
      -- Revenue per hour calculation
      CASE
        WHEN lr.duration_minutes > 0
        THEN (lr.generated_revenue_cents * 60 / lr.duration_minutes)::BIGINT
        ELSE lr.generated_revenue_cents
      END AS revenue_per_hour_cents,
      -- Room rental: always 15%
      ROUND(lr.generated_revenue_cents * 0.15)::BIGINT AS room_rental_cents
    FROM lesson_revenue lr
    JOIN operators o ON lr.operator_id = o.id
    WHERE o.deleted_at IS NULL
  )
  SELECT
    cc.operator_id,
    cc.operator_name,
    cc.lesson_id,
    cc.lesson_date,
    cc.activity_name,
    cc.lesson_duration_minutes::INTEGER,
    cc.generated_revenue_cents,
    cc.revenue_per_hour_cents,
    cc.room_rental_cents,
    -- Operator payout calculation
    CASE
      WHEN cc.revenue_per_hour_cents > 4000 -- > 40 EUR/hour (4000 cents)
      THEN ROUND(4000.0 * cc.lesson_duration_minutes / 60.0)::BIGINT -- 40 EUR/hour prorated
      ELSE GREATEST(cc.generated_revenue_cents - cc.room_rental_cents, 0)::BIGINT -- Revenue minus room rental (floor at 0)
    END AS operator_payout_cents,
    -- Alice share calculation (25% of margin, only if > 40/hour)
    CASE
      WHEN cc.revenue_per_hour_cents > 4000 -- > 40 EUR/hour
      THEN ROUND(
        GREATEST(
          cc.generated_revenue_cents
          - cc.room_rental_cents
          - ROUND(4000.0 * cc.lesson_duration_minutes / 60.0),
          0
        ) * 0.25
      )::BIGINT
      ELSE 0::BIGINT
    END AS alice_share_cents,
    -- Studio margin calculation (75% of margin, only if > 40/hour)
    CASE
      WHEN cc.revenue_per_hour_cents > 4000 -- > 40 EUR/hour
      THEN ROUND(
        GREATEST(
          cc.generated_revenue_cents
          - cc.room_rental_cents
          - ROUND(4000.0 * cc.lesson_duration_minutes / 60.0),
          0
        ) * 0.75
      )::BIGINT
      ELSE 0::BIGINT
    END AS studio_margin_cents
  FROM compensation_calc cc
  ORDER BY cc.lesson_date, cc.operator_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users (RLS in the app guards access)
GRANT EXECUTE ON FUNCTION calculate_operator_compensation(DATE, DATE, UUID) TO authenticated;


-- Function to get monthly revenue breakdown by client
-- Returns revenue from subscriptions created in the period
CREATE OR REPLACE FUNCTION get_monthly_revenue_by_client(
  p_month_start DATE,
  p_month_end DATE
)
RETURNS TABLE (
  client_id UUID,
  client_name TEXT,
  client_email TEXT,
  total_revenue_cents BIGINT,
  subscription_count INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id AS client_id,
    c.full_name AS client_name,
    c.email AS client_email,
    COALESCE(SUM(
      CASE
        -- Custom subscription: use custom price
        WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
        -- Regular subscription: use plan price with discount
        ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
      END
    ), 0)::BIGINT AS total_revenue_cents,
    COUNT(DISTINCT s.id)::INTEGER AS subscription_count
  FROM clients c
  INNER JOIN subscriptions s ON s.client_id = c.id
    AND s.created_at >= p_month_start
    AND s.created_at < (p_month_end + INTERVAL '1 day')
    AND s.deleted_at IS NULL
  LEFT JOIN plans p ON s.plan_id = p.id
  WHERE c.deleted_at IS NULL
  GROUP BY c.id, c.full_name, c.email
  HAVING COALESCE(SUM(
    CASE
      WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
      ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
    END
  ), 0) > 0
  ORDER BY total_revenue_cents DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_monthly_revenue_by_client(DATE, DATE) TO authenticated;


-- Function to get monthly revenue breakdown by plan
-- Returns revenue grouped by subscription plan
CREATE OR REPLACE FUNCTION get_monthly_revenue_by_plan(
  p_month_start DATE,
  p_month_end DATE
)
RETURNS TABLE (
  plan_id UUID,
  plan_name TEXT,
  total_revenue_cents BIGINT,
  subscription_count INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS plan_id,
    COALESCE(s.custom_name, p.name) AS plan_name,
    COALESCE(SUM(
      CASE
        WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
        ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
      END
    ), 0)::BIGINT AS total_revenue_cents,
    COUNT(DISTINCT s.id)::INTEGER AS subscription_count
  FROM subscriptions s
  JOIN plans p ON s.plan_id = p.id
  WHERE s.created_at >= p_month_start
    AND s.created_at < (p_month_end + INTERVAL '1 day')
    AND s.deleted_at IS NULL
  GROUP BY p.id, COALESCE(s.custom_name, p.name)
  HAVING COALESCE(SUM(
    CASE
      WHEN s.custom_price_cents IS NOT NULL THEN s.custom_price_cents
      ELSE ROUND(p.price_cents * (1 - COALESCE(p.discount_percent, 0) / 100.0))
    END
  ), 0) > 0
  ORDER BY total_revenue_cents DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_monthly_revenue_by_plan(DATE, DATE) TO authenticated;
