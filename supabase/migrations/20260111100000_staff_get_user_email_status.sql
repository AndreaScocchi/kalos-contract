-- Migration: Add staff_get_user_email_status RPC function
-- Allows staff to check email confirmation status for a user

CREATE OR REPLACE FUNCTION public.staff_get_user_email_status(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_email text;
  v_email_confirmed_at timestamptz;
BEGIN
  -- Verify caller is staff
  IF NOT is_staff() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'UNAUTHORIZED');
  END IF;

  -- Get email and confirmation status from auth.users
  SELECT email, email_confirmed_at
  INTO v_email, v_email_confirmed_at
  FROM auth.users
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'USER_NOT_FOUND');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'email', v_email,
    'email_confirmed_at', v_email_confirmed_at,
    'is_confirmed', v_email_confirmed_at IS NOT NULL
  );
END;
$$;

ALTER FUNCTION public.staff_get_user_email_status(uuid) OWNER TO postgres;

-- Grant execute to authenticated users (staff check is done inside the function)
GRANT EXECUTE ON FUNCTION public.staff_get_user_email_status(uuid) TO authenticated;

COMMENT ON FUNCTION public.staff_get_user_email_status(uuid) IS
  'Returns email confirmation status for a user. Staff only.';
