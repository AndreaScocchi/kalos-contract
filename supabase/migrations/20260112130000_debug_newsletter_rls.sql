-- Temporarily disable RLS on newsletter tables to debug permission issues
-- This should allow all authenticated users to access the tables

-- First, let's check if the issue is RLS by temporarily disabling it
ALTER TABLE "public"."newsletter_campaigns" DISABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."newsletter_templates" DISABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."newsletter_emails" DISABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."newsletter_tracking_events" DISABLE ROW LEVEL SECURITY;
