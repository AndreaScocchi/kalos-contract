-- Migration: Add discount fields to subscriptions table
-- Allows staff to apply discounts directly on individual subscriptions

-- Add discount_percent column (0-100, nullable)
ALTER TABLE subscriptions
ADD COLUMN discount_percent numeric(5,2) DEFAULT NULL;

-- Add discount_reason column for tracking why the discount was applied
ALTER TABLE subscriptions
ADD COLUMN discount_reason text DEFAULT NULL;

-- Add constraint to ensure discount_percent is between 0 and 100
ALTER TABLE subscriptions
ADD CONSTRAINT subscriptions_discount_percent_range
CHECK (discount_percent IS NULL OR (discount_percent >= 0 AND discount_percent <= 100));

-- Add comment for documentation
COMMENT ON COLUMN subscriptions.discount_percent IS 'Discount percentage (0-100) applied to this subscription. Takes priority over plan discount.';
COMMENT ON COLUMN subscriptions.discount_reason IS 'Reason for the discount (e.g., "Referral - Porta un Amico", "Promo Natale")';
