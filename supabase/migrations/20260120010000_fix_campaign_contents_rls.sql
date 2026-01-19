-- =============================================================================
-- Fix campaign_contents RLS policies
-- =============================================================================
-- The "FOR ALL" policy may not work correctly for SELECT in some PostgREST
-- configurations. Adding explicit SELECT policy.
-- =============================================================================

-- Drop the existing "ALL" policy and create separate policies
DROP POLICY IF EXISTS "campaign_contents_staff_all" ON "public"."campaign_contents";

-- Separate SELECT policy
CREATE POLICY "campaign_contents_staff_select" ON "public"."campaign_contents"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"());

-- Separate INSERT policy
CREATE POLICY "campaign_contents_staff_insert" ON "public"."campaign_contents"
    FOR INSERT TO "authenticated"
    WITH CHECK ("public"."is_staff"());

-- Separate UPDATE policy
CREATE POLICY "campaign_contents_staff_update" ON "public"."campaign_contents"
    FOR UPDATE TO "authenticated"
    USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- Separate DELETE policy
CREATE POLICY "campaign_contents_staff_delete" ON "public"."campaign_contents"
    FOR DELETE TO "authenticated"
    USING ("public"."is_staff"());
