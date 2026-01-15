-- Migration: Add RLS policy for staff to read all device_tokens
-- This allows operators and admins in the management portal to see
-- which clients have push notifications enabled

-- Add policy for staff to read all device tokens
CREATE POLICY "device_tokens_select_staff"
ON "public"."device_tokens" FOR SELECT TO "authenticated"
USING ("public"."is_staff"());

COMMENT ON POLICY "device_tokens_select_staff" ON "public"."device_tokens" IS
  'Permette allo staff (operator, admin, finance) di vedere tutti i device tokens per il gestionale';
