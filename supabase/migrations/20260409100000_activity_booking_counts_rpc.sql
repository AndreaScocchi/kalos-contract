-- RPC to get total booking counts per activity (bypasses RLS)
CREATE OR REPLACE FUNCTION get_activity_booking_counts()
RETURNS TABLE(activity_id uuid, booking_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT l.activity_id, COUNT(b.id) AS booking_count
  FROM lessons l
  JOIN bookings b ON b.lesson_id = l.id
  WHERE l.deleted_at IS NULL
  GROUP BY l.activity_id;
$$;

-- Allow authenticated users to call this function
GRANT EXECUTE ON FUNCTION get_activity_booking_counts() TO authenticated;
