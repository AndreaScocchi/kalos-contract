-- Migration: allow_read_plans_from_own_subscriptions
-- Description: Allow users to read plans linked to their subscriptions, even if inactive
--
-- Problem: The RLS policy "plans_select_public_active" only allows reading active plans.
-- When a plan is deactivated (is_active = false), users with subscriptions linked to that
-- plan cannot read the plan data, causing the app to show "Piano" and "Ingressi illimitati"
-- instead of the actual plan name and entries.
--
-- Solution: Add a new policy that allows authenticated users to read plans that are
-- linked to their own subscriptions.

-- Add policy for users to read plans linked to their own subscriptions
CREATE POLICY "plans_select_own_subscription"
ON "public"."plans"
FOR SELECT
TO "authenticated"
USING (
  EXISTS (
    SELECT 1 FROM "public"."subscriptions" s
    INNER JOIN "public"."clients" c ON s.client_id = c.id
    WHERE s.plan_id = plans.id
      AND c.profile_id = auth.uid()
  )
);

-- Comment explaining the policy
COMMENT ON POLICY "plans_select_own_subscription" ON "public"."plans" IS
'Allows authenticated users to read plans linked to their own subscriptions, even if the plan is inactive';
