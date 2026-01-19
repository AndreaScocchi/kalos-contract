-- =============================================================================
-- Create marketing storage bucket for campaign images
-- =============================================================================

-- Create the bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'marketing',
  'marketing',
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

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
