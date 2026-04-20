-- =============================================================================
-- Create events storage bucket for event images
-- =============================================================================

-- Create the bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'events',
  'events',
  true,  -- Public bucket so images can be displayed without signed URLs
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated staff to upload
CREATE POLICY "events_staff_insert" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'events' AND
  "public"."is_staff"()
);

-- Allow authenticated staff to update their uploads
CREATE POLICY "events_staff_update" ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'events' AND
  "public"."is_staff"()
)
WITH CHECK (
  bucket_id = 'events' AND
  "public"."is_staff"()
);

-- Allow authenticated staff to delete
CREATE POLICY "events_staff_delete" ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'events' AND
  "public"."is_staff"()
);

-- Allow public read access (images need to be publicly accessible)
CREATE POLICY "events_public_read" ON storage.objects
FOR SELECT TO public
USING (bucket_id = 'events');
