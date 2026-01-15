-- Migration: Fix announcements table permissions
-- The staff needs INSERT, UPDATE, DELETE permissions on announcements table
-- Currently only SELECT is granted, which prevents staff from managing announcements

-- Grant full CRUD permissions to authenticated users
-- RLS policies will restrict actual access to staff only
GRANT INSERT, UPDATE, DELETE ON "public"."announcements" TO "authenticated";
