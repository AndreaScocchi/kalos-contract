-- Rendere amministratore un account dal gestionale (25/11/2026, richiesta dell'utente).
--
-- Fino a oggi dal gestionale si arrivava solo a «operatore» (`promote_profile_to_operator`); il
-- ruolo admin si dava a mano dal SQL Editor di Supabase. Ora un admin lo dà dalla scheda cliente,
-- con il pulsante «Rendi amministratore».
--
-- Additiva: aggiunge solo `promote_profile_to_admin(uuid)`, nessuna tabella né policy cambiata.
--
-- Regole:
-- - solo un admin (`is_admin()`), altrimenti FORBIDDEN;
-- - parte da qualsiasi ruolo non admin (user, operator, finance): non toglie mai un ruolo, quindi
--   non serve a declassare nessuno (per tornare indietro resta l'intervento a mano);
-- - un account eliminato (`deleted_at`) non si promuove: PROFILE_NOT_FOUND;
-- - già admin: ALREADY_ADMIN, nessuna scrittura.
-- Risponde jsonb { ok, reason?, role?, previous_role? }, come `promote_profile_to_operator`.
--
-- Il trigger `guard_profile_privileged_columns` non entra in gioco: la funzione è SECURITY DEFINER e
-- gira come postgres; il controllo sul ruolo di chi chiama è qui dentro.
--
-- migration-lint:allow revoke — reason: la REVOKE riguarda solo la funzione nuova di questa migrazione, che nasce chiusa ad anon e a PUBLIC.

CREATE OR REPLACE FUNCTION "public"."promote_profile_to_admin"(
    "p_profile_id" "uuid"
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_current_role user_role;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'FORBIDDEN');
  END IF;

  IF p_profile_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'PROFILE_NOT_FOUND');
  END IF;

  SELECT role INTO v_current_role
  FROM public.profiles
  WHERE id = p_profile_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'PROFILE_NOT_FOUND');
  END IF;

  IF v_current_role = 'admin' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_ADMIN', 'role', v_current_role);
  END IF;

  UPDATE public.profiles
  SET role = 'admin'
  WHERE id = p_profile_id;

  RETURN jsonb_build_object('ok', true, 'role', 'admin', 'previous_role', v_current_role);
END;
$$;

ALTER FUNCTION "public"."promote_profile_to_admin"("uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."promote_profile_to_admin"("uuid") FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."promote_profile_to_admin"("uuid") TO "authenticated", "service_role";
COMMENT ON FUNCTION "public"."promote_profile_to_admin"("uuid") IS
  'Rende admin un profilo (da user, operator o finance). Solo admin (is_admin). Non declassa mai. Usata dal gestionale → scheda cliente, «Rendi amministratore». 25/11/2026.';
