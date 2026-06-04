-- Preferenze utente & stato onboarding — Fase 9 della nuova app KMP.
-- Raccolte durante l'onboarding cinematico dei NUOVI utenti (obiettivi/interessi) per personalizzare i
-- suggerimenti dal day-one, e per marcare "onboarding completato" lato server (sopravvive a reinstall /
-- multi-device). Chi migra dalla PWA fa solo login e NON vede l'onboarding (vedi NEW_APP_PLAN.md §7.9).
--
-- Decisione di prodotto (AskUserQuestion 2026-06-03): persistenza server-side in tabella DEDICATA
-- (non colonne su profiles, che è una tabella condivisa hot, né solo locale). È dato di proprietà
-- dell'utente, scritto dall'app — NON staff-managed → nessuna UI gestionale obbligatoria.
--
-- Chiave su profile_id = auth.uid(): ogni utente autenticato ha sempre un profilo (1:1 con auth.users),
-- mentre clients.id può essere NULL per chi non è ancora un cliente CRM. Così l'onboarding funziona
-- per qualunque utente loggato.
--
-- Tutto ADDITIVO e retro-compatibile (NEW_APP_PLAN.md §3): nuova tabella, nessun oggetto esistente
-- toccato → website, gestionale e PWA restano identici. Tabella nuova ⇒ impatto zero.

CREATE TABLE IF NOT EXISTS "public"."user_preferences" (
    "profile_id"              "uuid"      NOT NULL,
    "goals"                   "jsonb"     DEFAULT '[]'::"jsonb" NOT NULL,   -- obiettivi scelti (es. ["relax","movimento"])
    "interests"               "jsonb"     DEFAULT '[]'::"jsonb" NOT NULL,   -- interessi/discipline (estensione futura)
    "onboarding_completed_at" timestamp with time zone,                      -- NULL = onboarding non ancora completato
    "created_at"              timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"              timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "user_preferences_pkey" PRIMARY KEY ("profile_id"),
    CONSTRAINT "user_preferences_profile_id_fkey"
        FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE,
    CONSTRAINT "user_preferences_goals_is_array"     CHECK ("jsonb_typeof"("goals") = 'array'),
    CONSTRAINT "user_preferences_interests_is_array" CHECK ("jsonb_typeof"("interests") = 'array')
);

ALTER TABLE "public"."user_preferences" OWNER TO "postgres";

COMMENT ON TABLE  "public"."user_preferences" IS 'Preferenze (obiettivi/interessi) e stato onboarding del singolo utente, raccolte dall''app KMP. Chiave = profile_id (auth.uid()).';
COMMENT ON COLUMN "public"."user_preferences"."goals"                   IS 'Array JSON di chiavi-obiettivo scelte nell''onboarding (es. ["relax","movimento","creativita"]).';
COMMENT ON COLUMN "public"."user_preferences"."interests"               IS 'Array JSON di interessi/discipline (estensione futura della personalizzazione).';
COMMENT ON COLUMN "public"."user_preferences"."onboarding_completed_at" IS 'Timestamp di completamento (o skip) dell''onboarding. NULL finché non completato.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Trigger updated_at (riusa l'helper esistente update_updated_at_column)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE TRIGGER "trg_user_preferences_updated_at"
    BEFORE UPDATE ON "public"."user_preferences"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS: l'utente vede e scrive SOLO la propria riga (profile_id = auth.uid()); lo staff può leggere
-- (per future analisi/personalizzazione); service_role accesso pieno per i job.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "public"."user_preferences" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_preferences_select_own" ON "public"."user_preferences"
    FOR SELECT TO "authenticated"
    USING (("profile_id" = "auth"."uid"()));

CREATE POLICY "user_preferences_insert_own" ON "public"."user_preferences"
    FOR INSERT TO "authenticated"
    WITH CHECK (("profile_id" = "auth"."uid"()));

CREATE POLICY "user_preferences_update_own" ON "public"."user_preferences"
    FOR UPDATE TO "authenticated"
    USING (("profile_id" = "auth"."uid"()))
    WITH CHECK (("profile_id" = "auth"."uid"()));

CREATE POLICY "user_preferences_staff_select" ON "public"."user_preferences"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"());

CREATE POLICY "user_preferences_service_all" ON "public"."user_preferences"
    TO "service_role"
    USING (true) WITH CHECK (true);

-- Grant coerenti con le altre tabelle owner-scoped (es. practice_user_state): la RLS fa il filtro reale.
GRANT SELECT, INSERT, UPDATE ON TABLE "public"."user_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."user_preferences" TO "service_role";
