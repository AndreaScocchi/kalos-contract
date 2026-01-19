-- =============================================================================
-- Fix marketing storage bucket policies
-- =============================================================================
-- Drop existing policies if they exist and recreate them

-- Drop policies if they exist (ignore errors if they don't)
DROP POLICY IF EXISTS "marketing_staff_insert" ON storage.objects;
DROP POLICY IF EXISTS "marketing_staff_update" ON storage.objects;
DROP POLICY IF EXISTS "marketing_staff_delete" ON storage.objects;
DROP POLICY IF EXISTS "marketing_public_read" ON storage.objects;

-- Recreate policies
-- Allow authenticated users (staff) to upload
CREATE POLICY "marketing_staff_insert" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'marketing' AND
  "public"."is_staff"()
);

-- Allow authenticated users (staff) to update their uploads
CREATE POLICY "marketing_staff_update" ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'marketing' AND
  "public"."is_staff"()
)
WITH CHECK (
  bucket_id = 'marketing' AND
  "public"."is_staff"()
);

-- Allow authenticated users (staff) to delete
CREATE POLICY "marketing_staff_delete" ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'marketing' AND
  "public"."is_staff"()
);

-- Allow public read access (images need to be publicly accessible for Meta API)
CREATE POLICY "marketing_public_read" ON storage.objects
FOR SELECT TO public
USING (bucket_id = 'marketing');
