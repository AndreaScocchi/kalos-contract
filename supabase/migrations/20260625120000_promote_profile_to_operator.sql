-- Promozione profilo a operatore dal gestionale (kalos-management → scheda cliente).
-- Additivo e retro-compatibile: aggiunge SOLO la funzione `promote_profile_to_operator(uuid)`.
-- Permette a un ADMIN di promuovere un account app con ruolo 'user' a 'operator'.
--
-- Sicurezza: SECURITY DEFINER ma gate rigido su public.is_admin() (solo admin).
-- Promuove SOLO se il ruolo attuale è 'user': non declassa mai operator/admin/finance
-- (evita che un admin venga abbassato per errore). Stesso stile di assign_membership.
-- Ritorna jsonb { ok, reason?, role? }.

CREATE OR REPLACE FUNCTION "public"."promote_profile_to_operator"(
    "p_profile_id" "uuid"
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_current_role user_role;
BEGIN
  -- Solo admin può cambiare i ruoli
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'FORBIDDEN');
  END IF;

  IF p_profile_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'PROFILE_NOT_FOUND');
  END IF;

  SELECT role INTO v_current_role
  FROM public.profiles
  WHERE id = p_profile_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'PROFILE_NOT_FOUND');
  END IF;

  -- Già staff: non toccare nulla (non declassare admin/finance, non ri-promuovere operator)
  IF v_current_role <> 'user' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_STAFF', 'role', v_current_role);
  END IF;

  UPDATE public.profiles
  SET role = 'operator'
  WHERE id = p_profile_id;

  RETURN jsonb_build_object('ok', true, 'role', 'operator');
END;
$$;

ALTER FUNCTION "public"."promote_profile_to_operator"("uuid") OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."promote_profile_to_operator"("uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."promote_profile_to_operator"("uuid") TO "service_role";
COMMENT ON FUNCTION "public"."promote_profile_to_operator"("uuid") IS 'Promuove un profilo con ruolo user a operator. Solo admin (is_admin). Non declassa lo staff esistente. Usata dal gestionale → scheda cliente.';
