-- Migration 20260109000001: Add Unique Constraints to subscription_usages
--
-- Prevents duplicate entries in subscription_usages table:
-- - Only one delta=-1 (BOOK) per booking_id
-- - Only one delta=+1 (CANCEL_RESTORE) per booking_id
--
-- This prevents bugs from creating multiple usage records for the same booking.

-- First, clean up any existing duplicates

-- Remove duplicate delta=-1 entries (keep the oldest one)
WITH duplicates AS (
  SELECT id,
    ROW_NUMBER() OVER (PARTITION BY booking_id ORDER BY created_at) AS rn
  FROM public.subscription_usages
  WHERE delta = -1 AND booking_id IS NOT NULL
)
DELETE FROM public.subscription_usages
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);

-- Remove duplicate delta=+1 entries (keep the oldest one)
WITH duplicates AS (
  SELECT id,
    ROW_NUMBER() OVER (PARTITION BY booking_id ORDER BY created_at) AS rn
  FROM public.subscription_usages
  WHERE delta = +1 AND booking_id IS NOT NULL
)
DELETE FROM public.subscription_usages
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);

-- Create unique partial indexes to prevent future duplicates
-- These indexes only apply when booking_id is not null (manual adjustments may have null booking_id)

CREATE UNIQUE INDEX IF NOT EXISTS idx_subscription_usages_booking_minus
ON public.subscription_usages(booking_id)
WHERE delta = -1 AND booking_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_subscription_usages_booking_plus
ON public.subscription_usages(booking_id)
WHERE delta = +1 AND booking_id IS NOT NULL;

COMMENT ON INDEX public.idx_subscription_usages_booking_minus IS
'Ensures only one delta=-1 (booking usage) per booking_id';

COMMENT ON INDEX public.idx_subscription_usages_booking_plus IS
'Ensures only one delta=+1 (cancel restore) per booking_id';
