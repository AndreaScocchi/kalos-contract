-- Centro notifiche, preferenze (fascia oraria) e plumbing push — Fase 8 della nuova app KMP.
--
-- Additivo e retro-compatibile (NEW_APP_PLAN.md §3): NESSUNA tabella/colonna/RPC/enum/policy
-- esistente viene toccata. Website, gestionale e PWA restano identici. Aggiunge solo:
--   1) RPC get_my_notifications(p_limit, p_offset) — il FEED unificato del centro notifiche
--      (notification_logs personali + announcements broadcast), letto/non-letto calcolato lato DB,
--      e la rotta deep-link `kalos://` risolta server-side. Sostituisce le 3 query client della PWA
--      con un solo round-trip, coerente con la regola "calcolo server-side" (come get_journey_*).
--   2) tabella notification_settings — fascia oraria "non disturbare" (quiet hours) per cliente,
--      + RPC get_my_notification_settings / set_notification_quiet_hours. Lo SCHEDULING reale la userà
--      quando la consegna push sarà attiva (gating push_delivery): per ora la raccoglie soltanto.
--   3) RPC register_device_token / deactivate_device_token — PLUMBING push (riusa la tabella
--      device_tokens). La registrazione APNs/FCM nativa è cablata in app ma dietro
--      feature_flags.push_delivery (SPENTO): spedire ≠ attivare. Nessun invio finché mancano gli
--      account Apple/Firebase.
--
-- Sicurezza: tutte le funzioni SECURITY DEFINER con scoping rigido sul proprio client via
-- get_my_client_id() (stesso pattern di book_lesson / get_practice_metrics / get_journey_*).
-- Vedi docs/NEW_APP_PLAN.md §8 (Push) e §9 (Fase 8).

-- =====================================================================================
-- 1) Feed unificato del centro notifiche (calcolo lato DB)
-- =====================================================================================
-- Unisce le notifiche personali (notification_logs, ultimi 30 giorni, escluse quelle di tipo
-- 'announcement' che sono mostrate dalla tabella announcements) e gli annunci broadcast attivi e
-- visibili a questo cliente. Per ogni voce calcola `is_read` e la `route` deep-link:
--   * notifiche: data->>'route' se è una rotta kalos:// esplicita, altrimenti fallback derivato da
--     categoria + id presenti in `data` (lesson_id / event_id / practice_id / promotion_id);
--   * annunci: il CTA è `link_url` (può essere kalos:// o http); in mancanza si apre il dettaglio
--     dell'annuncio via kalos://announcement/<id>.
CREATE OR REPLACE FUNCTION "public"."get_my_notifications"("p_limit" integer DEFAULT 30, "p_offset" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client uuid;
  v_items jsonb;
  v_has_more boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_client := public.get_my_client_id();
  IF v_client IS NULL THEN
    -- Utente loggato ma non ancora collegato a un client: feed vuoto (non è un errore).
    RETURN jsonb_build_object('ok', true, 'items', '[]'::jsonb, 'has_more', false);
  END IF;

  WITH feed AS (
    -- Notifiche personali (log ultimi 30 giorni; le 'announcement' sono mostrate dagli annunci).
    SELECT
      nl.id AS id,
      'push'::text AS type,
      nl.category::text AS category,
      nl.title AS title,
      nl.body AS body,
      NULL::text AS image_url,
      nl.sent_at AS sent_at,
      EXISTS (
        SELECT 1 FROM public.notification_reads nr
        WHERE nr.notification_log_id = nl.id AND nr.client_id = v_client
      ) AS is_read,
      COALESCE(
        -- 1) rotta esplicita kalos:// nel payload
        CASE WHEN nl.data->>'route' LIKE 'kalos://%' THEN nl.data->>'route' END,
        -- 2) fallback: deriva dalla categoria + id presenti in `data`
        CASE
          WHEN NULLIF(nl.data->>'lesson_id', '') IS NOT NULL THEN 'kalos://lesson/' || (nl.data->>'lesson_id')
          WHEN NULLIF(nl.data->>'event_id', '') IS NOT NULL THEN 'kalos://event/' || (nl.data->>'event_id')
          WHEN NULLIF(nl.data->>'practice_id', '') IS NOT NULL THEN 'kalos://practice/' || (nl.data->>'practice_id')
          WHEN NULLIF(nl.data->>'promotion_id', '') IS NOT NULL THEN 'kalos://promotion/' || (nl.data->>'promotion_id')
          WHEN nl.category = 'journal_reminder' THEN 'kalos://journal'
          WHEN nl.category IN ('practice_reminder', 'practice_resume') THEN 'kalos://practices'
          WHEN nl.category = 'new_event' THEN 'kalos://explore'
          WHEN nl.category IN ('subscription_expiry', 'entries_low') THEN 'kalos://profile'
          ELSE NULL
        END
      ) AS route
    FROM public.notification_logs nl
    WHERE nl.client_id = v_client
      AND nl.sent_at > now() - interval '30 days'
      AND nl.category <> 'announcement'

    UNION ALL

    -- Annunci broadcast attivi e visibili a questo cliente (test mode incluso solo se mirato).
    SELECT
      a.id,
      'announcement'::text,
      a.category::text,
      a.title,
      a.body,
      a.image_url,
      a.starts_at,
      EXISTS (
        SELECT 1 FROM public.notification_reads nr
        WHERE nr.announcement_id = a.id AND nr.client_id = v_client
      ),
      -- L'annuncio ha il proprio dettaglio in-app (titolo/immagine/corpo): la `route` è SOLO
      -- l'eventuale CTA (link_url), kalos:// o http; nullo se l'annuncio non ha un'azione.
      NULLIF(a.link_url, '')
    FROM public.announcements a
    WHERE a.is_active = true
      AND a.starts_at <= now()
      AND (a.ends_at IS NULL OR a.ends_at > now())
      AND (a.is_test = false OR a.test_client_id = v_client)
  ),
  lim AS (
    SELECT * FROM feed ORDER BY sent_at DESC OFFSET p_offset LIMIT p_limit + 1
  ),
  ranked AS (
    SELECT *, row_number() OVER (ORDER BY sent_at DESC) AS rn FROM lim
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'type', type,
          'category', category,
          'title', title,
          'body', body,
          'image_url', image_url,
          'sent_at', sent_at,
          'is_read', is_read,
          'route', route
        ) ORDER BY sent_at DESC
      ) FILTER (WHERE rn <= p_limit),
      '[]'::jsonb
    ),
    (SELECT COUNT(*) FROM lim) > p_limit
  INTO v_items, v_has_more
  FROM ranked;

  RETURN jsonb_build_object('ok', true, 'items', COALESCE(v_items, '[]'::jsonb), 'has_more', COALESCE(v_has_more, false));
END;
$$;

ALTER FUNCTION "public"."get_my_notifications"("p_limit" integer, "p_offset" integer) OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."get_my_notifications"("p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_notifications"("p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_notifications"("p_limit" integer, "p_offset" integer) TO "service_role";
COMMENT ON FUNCTION "public"."get_my_notifications"("p_limit" integer, "p_offset" integer) IS 'Centro notifiche (Fase 8): feed unificato notifiche personali + annunci, letto/non-letto e rotta deep-link kalos:// calcolati lato DB, paginato (has_more).';

-- =====================================================================================
-- 2) Impostazioni notifiche per cliente — fascia oraria "non disturbare" (quiet hours)
-- =====================================================================================
CREATE TABLE IF NOT EXISTS "public"."notification_settings" (
    "client_id" "uuid" NOT NULL,
    "quiet_hours_enabled" boolean DEFAULT false NOT NULL,
    "quiet_hours_start" time without time zone,
    "quiet_hours_end" time without time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_settings_pkey" PRIMARY KEY ("client_id"),
    CONSTRAINT "notification_settings_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE CASCADE
);

ALTER TABLE "public"."notification_settings" OWNER TO "postgres";
COMMENT ON TABLE "public"."notification_settings" IS 'Impostazioni notifiche per cliente: fascia oraria "non disturbare" (quiet hours). Lo scheduling reale la userà quando la consegna push sarà attiva (Fase 8, dietro feature_flags.push_delivery).';

ALTER TABLE "public"."notification_settings" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notification_settings_select_own" ON "public"."notification_settings" FOR SELECT TO "authenticated" USING (("client_id" = "public"."get_my_client_id"()));
CREATE POLICY "notification_settings_insert_own" ON "public"."notification_settings" FOR INSERT TO "authenticated" WITH CHECK (("client_id" = "public"."get_my_client_id"()));
CREATE POLICY "notification_settings_update_own" ON "public"."notification_settings" FOR UPDATE TO "authenticated" USING (("client_id" = "public"."get_my_client_id"())) WITH CHECK (("client_id" = "public"."get_my_client_id"()));
CREATE POLICY "notification_settings_select_staff" ON "public"."notification_settings" FOR SELECT TO "authenticated" USING ("public"."is_staff"());
CREATE POLICY "notification_settings_service_all" ON "public"."notification_settings" TO "service_role" USING (true) WITH CHECK (true);

CREATE OR REPLACE TRIGGER "update_notification_settings_updated_at" BEFORE UPDATE ON "public"."notification_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

GRANT ALL ON TABLE "public"."notification_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_settings" TO "service_role";

-- Lettura impostazioni del cliente corrente (default sicuri se la riga non esiste ancora).
CREATE OR REPLACE FUNCTION "public"."get_my_notification_settings"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client uuid;
  v_row public.notification_settings%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_client := public.get_my_client_id();
  IF v_client IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'quiet_hours_enabled', false, 'quiet_hours_start', NULL, 'quiet_hours_end', NULL);
  END IF;

  SELECT * INTO v_row FROM public.notification_settings WHERE client_id = v_client;

  RETURN jsonb_build_object(
    'ok', true,
    'quiet_hours_enabled', COALESCE(v_row.quiet_hours_enabled, false),
    'quiet_hours_start', to_char(v_row.quiet_hours_start, 'HH24:MI'),
    'quiet_hours_end', to_char(v_row.quiet_hours_end, 'HH24:MI')
  );
END;
$$;

ALTER FUNCTION "public"."get_my_notification_settings"() OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."get_my_notification_settings"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_notification_settings"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_notification_settings"() TO "service_role";
COMMENT ON FUNCTION "public"."get_my_notification_settings"() IS 'Centro notifiche (Fase 8): fascia oraria non-disturbare del cliente corrente (HH:MM). Default spenta se assente.';

-- Imposta/aggiorna la fascia oraria "non disturbare" (upsert sul proprio client).
CREATE OR REPLACE FUNCTION "public"."set_notification_quiet_hours"("p_enabled" boolean, "p_start" time without time zone DEFAULT NULL, "p_end" time without time zone DEFAULT NULL) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_client := public.get_my_client_id();
  IF v_client IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  INSERT INTO public.notification_settings (client_id, quiet_hours_enabled, quiet_hours_start, quiet_hours_end)
  VALUES (v_client, COALESCE(p_enabled, false), p_start, p_end)
  ON CONFLICT (client_id) DO UPDATE
    SET quiet_hours_enabled = EXCLUDED.quiet_hours_enabled,
        quiet_hours_start = EXCLUDED.quiet_hours_start,
        quiet_hours_end = EXCLUDED.quiet_hours_end,
        updated_at = now();

  RETURN jsonb_build_object('ok', true, 'quiet_hours_enabled', COALESCE(p_enabled, false),
    'quiet_hours_start', to_char(p_start, 'HH24:MI'), 'quiet_hours_end', to_char(p_end, 'HH24:MI'));
END;
$$;

ALTER FUNCTION "public"."set_notification_quiet_hours"("p_enabled" boolean, "p_start" time without time zone, "p_end" time without time zone) OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."set_notification_quiet_hours"("p_enabled" boolean, "p_start" time without time zone, "p_end" time without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."set_notification_quiet_hours"("p_enabled" boolean, "p_start" time without time zone, "p_end" time without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_notification_quiet_hours"("p_enabled" boolean, "p_start" time without time zone, "p_end" time without time zone) TO "service_role";
COMMENT ON FUNCTION "public"."set_notification_quiet_hours"("p_enabled" boolean, "p_start" time without time zone, "p_end" time without time zone) IS 'Centro notifiche (Fase 8): imposta la fascia oraria non-disturbare del cliente corrente.';

-- =====================================================================================
-- 3) Plumbing push — registrazione/deregistrazione token device (gating in app: push_delivery)
-- =====================================================================================
-- Riusa la tabella device_tokens (la colonna expo_push_token contiene QUALSIASI token: per la nuova
-- app nativa è il token APNs/FCM). Upsert manuale per (client_id, token) senza richiedere un nuovo
-- indice univoco sulla tabella esistente (zero rischio su dati prod già presenti).
CREATE OR REPLACE FUNCTION "public"."register_device_token"("p_token" "text", "p_platform" "text" DEFAULT NULL, "p_device_id" "text" DEFAULT NULL, "p_app_version" "text" DEFAULT NULL) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client uuid;
  v_updated integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;
  IF p_token IS NULL OR btrim(p_token) = '' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'MISSING_TOKEN');
  END IF;

  v_client := public.get_my_client_id();
  IF v_client IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  UPDATE public.device_tokens
     SET is_active = true,
         platform = COALESCE(p_platform, platform),
         device_id = COALESCE(p_device_id, device_id),
         app_version = COALESCE(p_app_version, app_version),
         last_used_at = now(),
         updated_at = now()
   WHERE client_id = v_client AND expo_push_token = p_token;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    INSERT INTO public.device_tokens (client_id, expo_push_token, platform, device_id, app_version, is_active)
    VALUES (v_client, p_token, p_platform, p_device_id, p_app_version, true);
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$$;

ALTER FUNCTION "public"."register_device_token"("p_token" "text", "p_platform" "text", "p_device_id" "text", "p_app_version" "text") OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."register_device_token"("p_token" "text", "p_platform" "text", "p_device_id" "text", "p_app_version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_device_token"("p_token" "text", "p_platform" "text", "p_device_id" "text", "p_app_version" "text") TO "service_role";
COMMENT ON FUNCTION "public"."register_device_token"("p_token" "text", "p_platform" "text", "p_device_id" "text", "p_app_version" "text") IS 'Plumbing push (Fase 8, dietro flag push_delivery): registra il token APNs/FCM del device per il cliente corrente (upsert su device_tokens).';

-- Disattiva un token (es. al logout o quando il device revoca i permessi push).
CREATE OR REPLACE FUNCTION "public"."deactivate_device_token"("p_token" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_client := public.get_my_client_id();
  IF v_client IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  UPDATE public.device_tokens
     SET is_active = false, updated_at = now()
   WHERE client_id = v_client AND expo_push_token = p_token;

  RETURN jsonb_build_object('ok', true);
END;
$$;

ALTER FUNCTION "public"."deactivate_device_token"("p_token" "text") OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."deactivate_device_token"("p_token" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."deactivate_device_token"("p_token" "text") TO "service_role";
COMMENT ON FUNCTION "public"."deactivate_device_token"("p_token" "text") IS 'Plumbing push (Fase 8): disattiva un token device del cliente corrente (logout / revoca permessi).';

-- Feature flag della consegna push nativa (SPENTO): l'app cabla la registrazione token + l'invio
-- (Edge Function send-push) ma non parte finché lo staff non accende il flag, e comunque servono prima
-- gli account Apple Developer (APNs) e Firebase (FCM). Spedire ≠ attivare (NEW_APP_PLAN.md §3/§8).
-- Additivo (ON CONFLICT DO NOTHING): non tocca la riga se già presente in un ambiente.
INSERT INTO "public"."feature_flags" ("key", "enabled", "description") VALUES
    ('push_delivery', false, 'Consegna push nativa APNs/FCM (Fase 8) — richiede account Apple/Firebase')
ON CONFLICT ("key") DO NOTHING;
