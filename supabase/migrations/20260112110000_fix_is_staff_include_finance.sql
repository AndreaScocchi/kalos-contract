-- Fix is_staff() function to include 'finance' role
-- The finance role should also be considered staff for accessing management features

CREATE OR REPLACE FUNCTION "public"."is_staff"() RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_role user_role;
begin
  -- Se non c'è un utente autenticato, ritorna false
  if auth.uid() is null then
    return false;
  end if;

  -- Recupera il ruolo dell'utente
  select role into v_role
  from profiles
  where id = auth.uid();

  -- Ritorna true se è operator, admin o finance
  return v_role in ('operator', 'admin', 'finance');
end;
$$;

COMMENT ON FUNCTION "public"."is_staff"() IS 'Verifica se l''utente corrente è staff (operator, admin o finance)';
