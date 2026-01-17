-- Create RPC function for soft-deleting campaigns
-- This uses SECURITY DEFINER to bypass RLS issues while still checking is_staff()

CREATE OR REPLACE FUNCTION "public"."delete_campaign"(campaign_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verify user is staff
  IF NOT is_staff() THEN
    RAISE EXCEPTION 'Permission denied: user is not staff';
  END IF;

  -- Soft delete the campaign
  UPDATE campaigns
  SET deleted_at = now()
  WHERE id = campaign_id;
END;
$$;

GRANT EXECUTE ON FUNCTION "public"."delete_campaign"(uuid) TO "authenticated";
