-- Fix RLS policies for newsletter_extra_emails to use is_staff() function

-- Drop existing policies
DROP POLICY IF EXISTS "Staff can view extra emails" ON "public"."newsletter_extra_emails";
DROP POLICY IF EXISTS "Staff can insert extra emails" ON "public"."newsletter_extra_emails";
DROP POLICY IF EXISTS "Staff can update extra emails" ON "public"."newsletter_extra_emails";
DROP POLICY IF EXISTS "Staff can delete extra emails" ON "public"."newsletter_extra_emails";

-- Recreate policies using is_staff() function
CREATE POLICY "Staff can view extra emails"
  ON "public"."newsletter_extra_emails"
  FOR SELECT
  TO authenticated
  USING ("public"."is_staff"());

CREATE POLICY "Staff can insert extra emails"
  ON "public"."newsletter_extra_emails"
  FOR INSERT
  TO authenticated
  WITH CHECK ("public"."is_staff"());

CREATE POLICY "Staff can update extra emails"
  ON "public"."newsletter_extra_emails"
  FOR UPDATE
  TO authenticated
  USING ("public"."is_staff"())
  WITH CHECK ("public"."is_staff"());

CREATE POLICY "Staff can delete extra emails"
  ON "public"."newsletter_extra_emails"
  FOR DELETE
  TO authenticated
  USING ("public"."is_staff"());
