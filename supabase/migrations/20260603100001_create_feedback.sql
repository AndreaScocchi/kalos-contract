-- Sistema Feedback (Fase 5 della nuova app KMP, item D).
-- Raccolta interna (solo staff) di valutazioni dei clienti su pratiche, lezioni, eventi e sul primo mese.
-- Decisioni di prodotto: feedback INTERNI (mai pubblici), rating a STELLE 1–5 + commento opzionale,
-- raccolta automatica su 4 momenti (practice / lesson / onboarding / event).
--
-- Tutto ADDITIVO e retro-compatibile (NEW_APP_PLAN.md §3): nuovi enum + nuova tabella + nuove RPC.
-- Nessuna tabella/colonna/RPC esistente viene toccata → website, gestionale e PWA continuano identici.
-- Vedi docs/NEW_APP_PLAN.md §5 (item D) e §9 (Fase 5).

-- ─────────────────────────────────────────────────────────────────────────────
-- Enum
-- ─────────────────────────────────────────────────────────────────────────────

-- Tipo di feedback = momento/oggetto a cui si riferisce.
CREATE TYPE "public"."feedback_kind" AS ENUM (
    'practice',     -- dopo una pratica a casa completata (target: practices.id)
    'lesson',       -- dopo una lezione/lab a cui il cliente ha partecipato (target: lessons.id)
    'onboarding',   -- esperienza complessiva dopo ~1 mese dall'iscrizione (nessun target)
    'event'         -- dopo la partecipazione a un evento (target: events.id)
);

-- Stato di triage lato staff.
CREATE TYPE "public"."feedback_status" AS ENUM (
    'new',          -- appena ricevuto, da leggere
    'reviewed',     -- letto/gestito dallo staff
    'archived'      -- archiviato
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabella
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."feedback" (
    "id"          "uuid"      DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id"   "uuid"      NOT NULL,
    "kind"        "public"."feedback_kind"   NOT NULL,
    -- Target tipizzato: esattamente una colonna valorizzata secondo `kind` (onboarding non ne ha).
    "lesson_id"   "uuid",
    "practice_id" "uuid",
    "event_id"    "uuid",
    "rating"      smallint,                                  -- 1–5 stelle, NULL se feedback solo-testo
    "comment"     "text",
    "status"      "public"."feedback_status" DEFAULT 'new'::"public"."feedback_status" NOT NULL,
    "metadata"    "jsonb"     DEFAULT '{}'::"jsonb",         -- estensibilità futura (es. sorgente, prompt)
    "created_at"  timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"  timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "feedback_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "feedback_rating_range" CHECK ("rating" IS NULL OR ("rating" BETWEEN 1 AND 5)),
    -- Almeno un contenuto: o un voto o un commento (niente feedback vuoti).
    CONSTRAINT "feedback_has_content" CHECK ("rating" IS NOT NULL OR ("comment" IS NOT NULL AND length(btrim("comment")) > 0)),
    -- Coerenza target ↔ kind: il target giusto è valorizzato, gli altri sono NULL.
    CONSTRAINT "feedback_target_matches_kind" CHECK (
        CASE "kind"
            WHEN 'practice'   THEN "practice_id" IS NOT NULL AND "lesson_id" IS NULL AND "event_id" IS NULL
            WHEN 'lesson'     THEN "lesson_id"   IS NOT NULL AND "practice_id" IS NULL AND "event_id" IS NULL
            WHEN 'event'      THEN "event_id"    IS NOT NULL AND "lesson_id" IS NULL AND "practice_id" IS NULL
            WHEN 'onboarding' THEN "lesson_id" IS NULL AND "practice_id" IS NULL AND "event_id" IS NULL
        END
    ),
    CONSTRAINT "feedback_client_id_fkey"   FOREIGN KEY ("client_id")   REFERENCES "public"."clients"("id")    ON DELETE CASCADE,
    CONSTRAINT "feedback_lesson_id_fkey"   FOREIGN KEY ("lesson_id")   REFERENCES "public"."lessons"("id")    ON DELETE SET NULL,
    CONSTRAINT "feedback_practice_id_fkey" FOREIGN KEY ("practice_id") REFERENCES "public"."practices"("id")  ON DELETE SET NULL,
    CONSTRAINT "feedback_event_id_fkey"    FOREIGN KEY ("event_id")    REFERENCES "public"."events"("id")     ON DELETE SET NULL
);

ALTER TABLE "public"."feedback" OWNER TO "postgres";

COMMENT ON TABLE  "public"."feedback" IS 'Feedback interni dei clienti (Fase 5 app). Rating 1–5 + commento, su pratiche/lezioni/eventi/onboarding. Mai pubblici: solo staff.';
COMMENT ON COLUMN "public"."feedback"."kind"     IS 'Momento/oggetto del feedback: practice, lesson, onboarding (primo mese), event.';
COMMENT ON COLUMN "public"."feedback"."rating"   IS 'Voto a stelle 1–5; NULL se feedback solo testuale.';
COMMENT ON COLUMN "public"."feedback"."status"   IS 'Triage staff: new → reviewed → archived.';
COMMENT ON COLUMN "public"."feedback"."metadata" IS 'Dati opzionali di estensione (sorgente, prompt mostrato, ecc.).';

-- Un solo feedback per cliente e per target (editabile via upsert nella RPC).
CREATE UNIQUE INDEX "feedback_unique_practice"   ON "public"."feedback" ("client_id", "practice_id") WHERE "practice_id" IS NOT NULL;
CREATE UNIQUE INDEX "feedback_unique_lesson"     ON "public"."feedback" ("client_id", "lesson_id")   WHERE "lesson_id"   IS NOT NULL;
CREATE UNIQUE INDEX "feedback_unique_event"      ON "public"."feedback" ("client_id", "event_id")    WHERE "event_id"    IS NOT NULL;
CREATE UNIQUE INDEX "feedback_unique_onboarding" ON "public"."feedback" ("client_id")                WHERE "kind" = 'onboarding';

-- Indici di servizio per il gestionale (filtri per stato e ordinamento cronologico).
CREATE INDEX "idx_feedback_status_created" ON "public"."feedback" ("status", "created_at" DESC);
CREATE INDEX "idx_feedback_client"         ON "public"."feedback" ("client_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."feedback" ENABLE ROW LEVEL SECURITY;

-- Il cliente vede solo i propri feedback (via get_my_client_id()).
CREATE POLICY "feedback_select_own"
    ON "public"."feedback"
    FOR SELECT
    USING ("client_id" = "public"."get_my_client_id"());

-- Il cliente inserisce solo per sé (la validazione di ownership del target è nella RPC submit_feedback).
CREATE POLICY "feedback_insert_own"
    ON "public"."feedback"
    FOR INSERT
    WITH CHECK ("client_id" = "public"."get_my_client_id"());

-- Il cliente può aggiornare i propri (editare voto/commento).
CREATE POLICY "feedback_update_own"
    ON "public"."feedback"
    FOR UPDATE
    USING ("client_id" = "public"."get_my_client_id"())
    WITH CHECK ("client_id" = "public"."get_my_client_id"());

-- Lo staff (operator/admin/finance) ha accesso completo: legge, triage, archivia.
CREATE POLICY "feedback_all_staff"
    ON "public"."feedback"
    FOR ALL
    USING ("public"."is_staff"())
    WITH CHECK ("public"."is_staff"());

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."feedback" TO "authenticated";
GRANT ALL ON TABLE "public"."feedback" TO "service_role";

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: submit_feedback — invio/aggiornamento di un feedback dall'app
-- ─────────────────────────────────────────────────────────────────────────────
-- Valida ownership del target (l'azione è davvero avvenuta) e fa upsert (un feedback per target,
-- editabile). SECURITY DEFINER con scoping rigido sul proprio client (pattern di book_lesson).
-- Ritorna jsonb { ok, reason?, feedback_id? }.

CREATE OR REPLACE FUNCTION "public"."submit_feedback"(
    "p_kind"      "public"."feedback_kind",
    "p_target_id" "uuid"     DEFAULT NULL,
    "p_rating"    smallint   DEFAULT NULL,
    "p_comment"   "text"     DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_my_client_id uuid;
  v_comment text;
  v_owns boolean;
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  IF v_my_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
  END IF;

  -- Normalizza il commento (stringa vuota → NULL).
  v_comment := NULLIF(btrim(p_comment), '');

  IF p_rating IS NOT NULL AND p_rating NOT BETWEEN 1 AND 5 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_RATING');
  END IF;

  IF p_rating IS NULL AND v_comment IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EMPTY_FEEDBACK');
  END IF;

  -- Target obbligatorio per tutti i kind tranne onboarding.
  IF p_kind <> 'onboarding' AND p_target_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'TARGET_REQUIRED');
  END IF;

  -- Ownership: l'azione su cui si dà feedback deve essere avvenuta per questo cliente.
  CASE p_kind
    WHEN 'practice' THEN
      SELECT EXISTS (
        SELECT 1 FROM public.practice_user_state
        WHERE client_id = v_my_client_id AND practice_id = p_target_id AND status = 'completed'
      ) INTO v_owns;
    WHEN 'lesson' THEN
      SELECT EXISTS (
        SELECT 1 FROM public.bookings
        WHERE client_id = v_my_client_id AND lesson_id = p_target_id AND status = 'attended'
      ) INTO v_owns;
    WHEN 'event' THEN
      SELECT EXISTS (
        SELECT 1 FROM public.event_bookings
        WHERE client_id = v_my_client_id AND event_id = p_target_id AND status <> 'canceled'
      ) INTO v_owns;
    WHEN 'onboarding' THEN
      v_owns := true;  -- nessun target: basta che il client esista (già verificato sopra)
  END CASE;

  IF NOT v_owns THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_ELIGIBLE');
  END IF;

  -- Upsert: un solo feedback per (client, target). Reinviare aggiorna voto/commento e riapre il triage.
  CASE p_kind
    WHEN 'practice' THEN
      INSERT INTO public.feedback (client_id, kind, practice_id, rating, comment)
      VALUES (v_my_client_id, p_kind, p_target_id, p_rating, v_comment)
      ON CONFLICT (client_id, practice_id) WHERE practice_id IS NOT NULL
      DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment, status = 'new', updated_at = now()
      RETURNING id INTO v_id;
    WHEN 'lesson' THEN
      INSERT INTO public.feedback (client_id, kind, lesson_id, rating, comment)
      VALUES (v_my_client_id, p_kind, p_target_id, p_rating, v_comment)
      ON CONFLICT (client_id, lesson_id) WHERE lesson_id IS NOT NULL
      DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment, status = 'new', updated_at = now()
      RETURNING id INTO v_id;
    WHEN 'event' THEN
      INSERT INTO public.feedback (client_id, kind, event_id, rating, comment)
      VALUES (v_my_client_id, p_kind, p_target_id, p_rating, v_comment)
      ON CONFLICT (client_id, event_id) WHERE event_id IS NOT NULL
      DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment, status = 'new', updated_at = now()
      RETURNING id INTO v_id;
    WHEN 'onboarding' THEN
      INSERT INTO public.feedback (client_id, kind, rating, comment)
      VALUES (v_my_client_id, p_kind, p_rating, v_comment)
      ON CONFLICT (client_id) WHERE kind = 'onboarding'
      DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment, status = 'new', updated_at = now()
      RETURNING id INTO v_id;
  END CASE;

  RETURN jsonb_build_object('ok', true, 'feedback_id', v_id);
END;
$$;

ALTER FUNCTION "public"."submit_feedback"("public"."feedback_kind", "uuid", smallint, "text") OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."submit_feedback"("public"."feedback_kind", "uuid", smallint, "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_feedback"("public"."feedback_kind", "uuid", smallint, "text") TO "service_role";

COMMENT ON FUNCTION "public"."submit_feedback"("public"."feedback_kind", "uuid", smallint, "text") IS 'Invia/aggiorna un feedback (1–5 stelle + commento) dell''utente autenticato, validando che l''azione (pratica completata / lezione attended / evento prenotato) sia avvenuta. Upsert: un feedback per target.';

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: queue_feedback_request — raccolta automatica (accoda la richiesta di feedback)
-- ─────────────────────────────────────────────────────────────────────────────
-- Accoda una notifica `feedback_request` per un cliente. Pensata per automazioni (trigger/edge/cron)
-- e per lo staff. Il delivery push vero arriva in Fase 7: qui basta la coda + il centro notifiche.
-- Rispetta le preferenze di canale (get_notification_channel): se entrambe spente, salta.

CREATE OR REPLACE FUNCTION "public"."queue_feedback_request"(
    "p_client_id"     "uuid",
    "p_kind"          "public"."feedback_kind",
    "p_target_id"     "uuid"        DEFAULT NULL,
    "p_scheduled_for" timestamp with time zone DEFAULT "now"()
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_channel public.notification_channel;
  v_title text := 'Com''è andata?';
  v_body text;
  v_id uuid;
BEGIN
  -- Autorizzazione: service_role/automazioni (auth.uid() NULL), staff, oppure il cliente stesso.
  IF auth.uid() IS NOT NULL
     AND NOT public.is_staff()
     AND p_client_id <> public.get_my_client_id() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'FORBIDDEN');
  END IF;

  v_channel := public.get_notification_channel(p_client_id, 'feedback_request');
  IF v_channel IS NULL THEN
    -- Entrambi i canali disattivati dalle preferenze: non accodiamo nulla.
    RETURN jsonb_build_object('ok', false, 'reason', 'CHANNEL_DISABLED');
  END IF;

  v_body := CASE p_kind
    WHEN 'practice'   THEN 'Raccontaci com''è andata la tua pratica: il tuo parere ci aiuta a crescere.'
    WHEN 'lesson'     THEN 'Com''è andata la lezione? Lascia un breve feedback.'
    WHEN 'event'      THEN 'Com''è andato l''evento? Ci piacerebbe sapere la tua.'
    WHEN 'onboarding' THEN 'Sei con noi da un mese: com''è la tua esperienza in Studio Kalòs?'
  END;

  INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
  VALUES (
    p_client_id,
    'feedback_request',
    v_channel,
    v_title,
    v_body,
    jsonb_build_object('kind', p_kind, 'target_id', p_target_id),
    p_scheduled_for
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'notification_id', v_id);
END;
$$;

ALTER FUNCTION "public"."queue_feedback_request"("uuid", "public"."feedback_kind", "uuid", timestamp with time zone) OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."queue_feedback_request"("uuid", "public"."feedback_kind", "uuid", timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."queue_feedback_request"("uuid", "public"."feedback_kind", "uuid", timestamp with time zone) TO "service_role";

COMMENT ON FUNCTION "public"."queue_feedback_request"("uuid", "public"."feedback_kind", "uuid", timestamp with time zone) IS 'Accoda una notifica feedback_request per un cliente (raccolta automatica Fase 5). Rispetta le preferenze di canale; delivery push in Fase 7.';
