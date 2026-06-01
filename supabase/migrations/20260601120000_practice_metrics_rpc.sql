-- Pratica a casa — metriche di percorso (Fase 3 nuova app KMP).
-- Additivo e retro-compatibile: aggiunge SOLO la funzione `get_practice_metrics()`.
-- Sposta il calcolo delle metriche dal client al DB (decisione NEW_APP_PLAN.md §5/§9),
-- per coerenza d'ecosistema. Nessuna tabella/colonna/enum toccati.
--
-- Ritorna un jsonb { ok, reason?, total_completed, total_minutes, active_days, weekly[], monthly[] }.
-- Sicurezza: SECURITY DEFINER ma scoping rigido sul proprio client via get_my_client_id()
-- (stesso pattern di book_lesson/cancel_booking). I timestamp di practice_user_state sono
-- naïve-UTC: vengono proiettati su Europe/Rome per i confini di giorno/settimana.

CREATE OR REPLACE FUNCTION "public"."get_practice_metrics"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_my_client_id uuid;
  v_total_completed integer;
  v_total_minutes integer;
  v_active_days integer;
  v_weekly jsonb;
  v_monthly jsonb;
  v_today date;
  v_week_start date;  -- lunedì della settimana ISO corrente (Europe/Rome)
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Totali: pratiche completate e minuti totali.
  SELECT
    COALESCE(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END), 0)::int,
    COALESCE(ROUND(SUM(time_spent_seconds) / 60.0), 0)::int
  INTO v_total_completed, v_total_minutes
  FROM public.practice_user_state
  WHERE client_id = v_my_client_id;

  -- Giorni attivi: date locali distinte tra started/completed/last_accessed.
  SELECT COUNT(DISTINCT d)::int
  INTO v_active_days
  FROM (
    SELECT (ts AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Rome')::date AS d
    FROM (
      SELECT started_at AS ts FROM public.practice_user_state WHERE client_id = v_my_client_id
      UNION ALL
      SELECT completed_at FROM public.practice_user_state WHERE client_id = v_my_client_id AND completed_at IS NOT NULL
      UNION ALL
      SELECT last_accessed_at FROM public.practice_user_state WHERE client_id = v_my_client_id
    ) src
    WHERE ts IS NOT NULL
  ) days;

  v_today := (now() AT TIME ZONE 'Europe/Rome')::date;
  v_week_start := v_today - (EXTRACT(ISODOW FROM v_today)::int - 1);

  -- Settimana corrente: minuti per giorno (lun→dom), riferimento completed_at o last_accessed_at.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('label', lbl, 'value', val) ORDER BY idx), '[]'::jsonb)
  INTO v_weekly
  FROM (
    SELECT g.idx,
           (ARRAY['Lun','Mar','Mer','Gio','Ven','Sab','Dom'])[g.idx] AS lbl,
           COALESCE((
             SELECT ROUND(SUM(pus.time_spent_seconds) / 60.0)::int
             FROM public.practice_user_state pus
             WHERE pus.client_id = v_my_client_id
               AND (COALESCE(pus.completed_at, pus.last_accessed_at) AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Rome')::date
                   = v_week_start + (g.idx - 1)
           ), 0) AS val
    FROM generate_series(1, 7) AS g(idx)
  ) w;

  -- Ultime 4 settimane ISO (dalla più vecchia): pratiche completate per settimana.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('label', lbl, 'value', val) ORDER BY ws), '[]'::jsonb)
  INTO v_monthly
  FROM (
    SELECT (v_week_start - (s.off * 7)) AS ws,
           to_char(v_week_start - (s.off * 7), 'FMDD/FMMM') AS lbl,
           (
             SELECT COUNT(*)::int
             FROM public.practice_user_state pus
             WHERE pus.client_id = v_my_client_id
               AND pus.status = 'completed'
               AND pus.completed_at IS NOT NULL
               AND (pus.completed_at AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Rome')::date >= (v_week_start - (s.off * 7))
               AND (pus.completed_at AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Rome')::date <  (v_week_start - (s.off * 7) + 7)
           ) AS val
    FROM generate_series(3, 0, -1) AS s(off)
  ) m;

  RETURN jsonb_build_object(
    'ok', true,
    'total_completed', v_total_completed,
    'total_minutes', v_total_minutes,
    'active_days', v_active_days,
    'weekly', v_weekly,
    'monthly', v_monthly
  );
END;
$$;

ALTER FUNCTION "public"."get_practice_metrics"() OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."get_practice_metrics"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_practice_metrics"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_practice_metrics"() TO "service_role";

COMMENT ON FUNCTION "public"."get_practice_metrics"() IS 'Metriche di percorso "Pratica a casa" per l''utente autenticato (completate, minuti, giorni attivi, breakdown settimanale e mensile). Calcolo lato DB, fuso Europe/Rome.';
