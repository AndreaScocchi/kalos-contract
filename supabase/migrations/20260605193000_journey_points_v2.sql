-- Percorso & Punti Kalòs · v2 (affina la meccanica punti, Fase 7 app KMP).
-- Additivo e retro-compatibile: CREATE OR REPLACE delle due sole funzioni di lettura
--   `get_journey_summary()` e `get_journey_timeline(int, int)`. Firme, GRANT e tipi invariati;
--   nessuna tabella/colonna/enum toccati. I consumer non vanno rigenerati.
--
-- COSA CAMBIA rispetto a 20260603160000_journey_points_rpc.sql:
--   1) Casa · pratiche → i Punti Kalòs di una pratica COMPLETATA valgono i suoi MINUTI DICHIARATI
--      (`practices.duration_minutes`), non più il tempo reale passato nel player. Motivo: una pratica
--      può svolgersi con l'audio in background o offline, e una sessione tappata via veloce (tempo
--      reale ~pochi secondi) arrotondava a 0 punti → "ho completato ma non mi dà punti". Ora una
--      pratica completata dà sempre i suoi minuti.
--   2) Casa · diario → la PRIMA nota di ciascun giorno (fuso Europe/Rome) vale 10 Punti Kalòs; le
--      note successive dello stesso giorno non aggiungono punti. I punti del diario confluiscono
--      nella fetta "casa" del mix (pratiche + diario = benessere a casa): nessun cambto al modello
--      dell'app, totale sempre coerente col mix.
--   3) Fuso · pratiche → la data locale di completamento usa la conversione singola
--      `completed_at AT TIME ZONE 'Europe/Rome'` (come lezioni/eventi). La precedente doppia
--      conversione `AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Rome'` era pensata per timestamp naïve,
--      ma `practice_user_state.completed_at` è timestamptz → sfasava l'istante e poteva sbagliare il
--      giorno a cavallo della mezzanotte.
--   4) Timeline · pratiche → `occurred_at` emette il timestamptz grezzo (con offset), così l'app lo
--      parsa come per lezioni/eventi (prima emetteva un timestamp senza offset, non parsabile).
--
-- Sicurezza invariata: SECURITY DEFINER + scoping rigido sul proprio client via get_my_client_id().
-- Unità: 1 Punto Kalòs = 1 minuto. Pratica = minuti dichiarati · Diario = 10/giorno · Lezione
-- `attended` = durata · Evento partecipato = durata ×2 (fallback 90'). I nomi/soglie dei livelli
-- restano in commonMain (it.kalos.app.feature.journey.JourneyLevels).

-- =====================================================================================
-- Sintesi: punti totali, mix per sorgente, "membro dal", grafici settimana/4-settimane.
-- =====================================================================================
CREATE OR REPLACE FUNCTION "public"."get_journey_summary"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client uuid;
  v_uid uuid;
  v_today date;
  v_week_start date;  -- lunedì della settimana ISO corrente (Europe/Rome)
  v_result jsonb;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_client := public.get_my_client_id();
  IF v_client IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  v_today := (now() AT TIME ZONE 'Europe/Rome')::date;
  v_week_start := v_today - (EXTRACT(ISODOW FROM v_today)::int - 1);

  -- Base unificata: (data locale, punti, sorgente) per ogni "momento di benessere".
  WITH pts AS (
    -- Casa · pratiche: pratica completata → minuti dichiarati della pratica ×1.
    SELECT
      (pus.completed_at AT TIME ZONE 'Europe/Rome')::date AS d,
      GREATEST(COALESCE(pr.duration_minutes, 0), 0)::int AS pts,
      'home'::text AS source
    FROM public.practice_user_state pus
    JOIN public.practices pr ON pr.id = pus.practice_id
    WHERE pus.client_id = v_client
      AND pus.status = 'completed'
      AND pus.completed_at IS NOT NULL

    UNION ALL

    -- Casa · diario: la PRIMA nota di ciascun giorno locale → 10 punti (gesto riconosciuto 1×/dì).
    SELECT jd.d, 10, 'home'
    FROM (
      SELECT DISTINCT (je.created_at AT TIME ZONE 'Europe/Rome')::date AS d
      FROM public.journal_entries je
      WHERE je.client_id = v_client
    ) jd

    UNION ALL

    -- Studio: lezioni partecipate (attended) → durata ×1.
    SELECT
      (l.starts_at AT TIME ZONE 'Europe/Rome')::date,
      GREATEST(ROUND(EXTRACT(EPOCH FROM (l.ends_at - l.starts_at)) / 60.0), 0)::int,
      'studio'
    FROM public.bookings b
    JOIN public.lessons l ON l.id = b.lesson_id
    WHERE b.client_id = v_client
      AND b.status = 'attended'
      AND l.deleted_at IS NULL

    UNION ALL

    -- Esperienze: eventi passati a cui sei iscritto (non disdetti) → durata ×2 (fallback 90').
    SELECT
      (e.starts_at AT TIME ZONE 'Europe/Rome')::date,
      (GREATEST(ROUND(COALESCE(EXTRACT(EPOCH FROM (e.ends_at - e.starts_at)) / 60.0, 90)), 0)::int) * 2,
      'events'
    FROM public.event_bookings eb
    JOIN public.events e ON e.id = eb.event_id
    WHERE (eb.client_id = v_client OR eb.user_id = v_uid)
      AND eb.status <> 'canceled'
      AND e.deleted_at IS NULL
      AND e.starts_at < now()
  )
  SELECT jsonb_build_object(
    'ok', true,
    'total_points', (SELECT COALESCE(SUM(pts), 0)::int FROM pts),
    'mix', jsonb_build_object(
      'home',   (SELECT COALESCE(SUM(pts), 0)::int FROM pts WHERE source = 'home'),
      'studio', (SELECT COALESCE(SUM(pts), 0)::int FROM pts WHERE source = 'studio'),
      'events', (SELECT COALESCE(SUM(pts), 0)::int FROM pts WHERE source = 'events')
    ),
    'member_since', (SELECT MIN(d) FROM pts),
    -- Settimana corrente: punti per giorno (lun→dom), tutte le sorgenti.
    'weekly', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('label', lbl, 'value', val) ORDER BY idx), '[]'::jsonb)
      FROM (
        SELECT g.idx,
               (ARRAY['Lun','Mar','Mer','Gio','Ven','Sab','Dom'])[g.idx] AS lbl,
               (SELECT COALESCE(SUM(pts), 0)::int FROM pts WHERE d = v_week_start + (g.idx - 1)) AS val
        FROM generate_series(1, 7) AS g(idx)
      ) w
    ),
    -- Ultime 4 settimane ISO (dalla più vecchia): punti per settimana, tutte le sorgenti.
    'monthly', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('label', lbl, 'value', val) ORDER BY ws), '[]'::jsonb)
      FROM (
        SELECT (v_week_start - (s.off * 7)) AS ws,
               to_char(v_week_start - (s.off * 7), 'FMDD/FMMM') AS lbl,
               (SELECT COALESCE(SUM(pts), 0)::int FROM pts
                WHERE d >= (v_week_start - (s.off * 7)) AND d < (v_week_start - (s.off * 7) + 7)) AS val
        FROM generate_series(3, 0, -1) AS s(off)
      ) m
    )
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

ALTER FUNCTION "public"."get_journey_summary"() OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."get_journey_summary"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_journey_summary"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_journey_summary"() TO "service_role";
COMMENT ON FUNCTION "public"."get_journey_summary"() IS 'Sintesi "Il tuo percorso": Punti Kalòs totali, mix casa/studio/eventi, membro dal, grafici settimana e 4 settimane. Casa = pratiche (minuti dichiarati) + diario (10 per la prima nota del giorno). Studio = lezioni attended (durata). Eventi = durata ×2. Calcolo lato DB, fuso Europe/Rome.';

-- =====================================================================================
-- Timeline narrativa: feed cronologico unificato (pratiche + lezioni + eventi + diario),
-- paginato. `p_limit` clampato a [1,100]; ritorna `has_more` per il caricamento progressivo.
-- =====================================================================================
CREATE OR REPLACE FUNCTION "public"."get_journey_timeline"("p_limit" integer DEFAULT 30, "p_offset" integer DEFAULT 0)
    RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client uuid;
  v_uid uuid;
  v_limit int;
  v_offset int;
  v_items jsonb;
  v_has_more boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_client := public.get_my_client_id();
  IF v_client IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  WITH feed AS (
    -- Casa · pratiche: pratiche completate → minuti dichiarati.
    SELECT
      'practice'::text AS kind,
      pus.completed_at AS occurred_at,
      pr.title AS title,
      NULL::text AS subtitle,
      GREATEST(COALESCE(pr.duration_minutes, 0), 0)::int AS points,
      NULL::text AS discipline
    FROM public.practice_user_state pus
    JOIN public.practices pr ON pr.id = pus.practice_id
    WHERE pus.client_id = v_client
      AND pus.status = 'completed'
      AND pus.completed_at IS NOT NULL

    UNION ALL

    -- Studio: lezioni partecipate.
    SELECT
      'lesson',
      l.starts_at,
      a.name,
      NULL,
      GREATEST(ROUND(EXTRACT(EPOCH FROM (l.ends_at - l.starts_at)) / 60.0), 0)::int,
      a.discipline
    FROM public.bookings b
    JOIN public.lessons l ON l.id = b.lesson_id
    JOIN public.activities a ON a.id = l.activity_id
    WHERE b.client_id = v_client
      AND b.status = 'attended'
      AND l.deleted_at IS NULL

    UNION ALL

    -- Esperienze: eventi passati prenotati (non disdetti).
    SELECT
      'event',
      e.starts_at,
      e.name,
      NULL,
      (GREATEST(ROUND(COALESCE(EXTRACT(EPOCH FROM (e.ends_at - e.starts_at)) / 60.0, 90)), 0)::int) * 2,
      NULL
    FROM public.event_bookings eb
    JOIN public.events e ON e.id = eb.event_id
    WHERE (eb.client_id = v_client OR eb.user_id = v_uid)
      AND eb.status <> 'canceled'
      AND e.deleted_at IS NULL
      AND e.starts_at < now()

    UNION ALL

    -- Casa · diario: note personali; la PRIMA del giorno vale 10 punti, le altre nessuno.
    SELECT
      'journal',
      je.created_at,
      COALESCE(NULLIF(btrim(je.title), ''), 'Nota dal diario'),
      left(je.body, 120),
      CASE
        WHEN row_number() OVER (
               PARTITION BY (je.created_at AT TIME ZONE 'Europe/Rome')::date
               ORDER BY je.created_at ASC
             ) = 1 THEN 10
        ELSE NULL
      END,
      NULL
    FROM public.journal_entries je
    WHERE je.client_id = v_client
  ),
  lim AS (
    SELECT * FROM feed ORDER BY occurred_at DESC OFFSET v_offset LIMIT v_limit + 1
  ),
  ranked AS (
    SELECT *, row_number() OVER (ORDER BY occurred_at DESC) AS rn FROM lim
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'kind', kind,
          'occurred_at', occurred_at,
          'title', title,
          'subtitle', subtitle,
          'points', points,
          'discipline', discipline
        ) ORDER BY occurred_at DESC
      ) FILTER (WHERE rn <= v_limit),
      '[]'::jsonb
    ),
    (SELECT COUNT(*) FROM lim) > v_limit
  INTO v_items, v_has_more
  FROM ranked;

  RETURN jsonb_build_object('ok', true, 'items', COALESCE(v_items, '[]'::jsonb), 'has_more', COALESCE(v_has_more, false));
END;
$$;

ALTER FUNCTION "public"."get_journey_timeline"("p_limit" integer, "p_offset" integer) OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."get_journey_timeline"("p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_journey_timeline"("p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_journey_timeline"("p_limit" integer, "p_offset" integer) TO "service_role";
COMMENT ON FUNCTION "public"."get_journey_timeline"("p_limit" integer, "p_offset" integer) IS 'Timeline cronologica del percorso: pratiche completate (minuti dichiarati), lezioni partecipate, eventi passati e note di diario (prima del giorno = 10 punti), paginate (has_more). Calcolo lato DB.';
