-- Feature flags server-side (Fase 0, punto 7 della nuova app).
-- Infrastruttura per accendere/spegnere feature (Pass, Shop, pagamenti, Stripe live) da remoto,
-- senza ripassare dalla review degli store. Modifica ADDITIVA: tabella nuova, impatto zero sui
-- consumer esistenti (website, gestionale, PWA). Vedi docs/NEW_APP_PLAN.md §3 e CONTRACT_DISCIPLINE.md.

CREATE TABLE IF NOT EXISTS "public"."feature_flags" (
    "key"         text        PRIMARY KEY,
    "enabled"     boolean     NOT NULL DEFAULT false,
    "description" text,
    "payload"     jsonb       NOT NULL DEFAULT '{}'::jsonb,   -- config opzionale (rollout graduale, soglie…)
    "updated_at"  timestamptz NOT NULL DEFAULT now(),
    "updated_by"  uuid                                          -- auth.uid() di chi ha modificato (nullable)
);

COMMENT ON TABLE  "public"."feature_flags" IS 'Flag server-side per accendere/spegnere feature dell''app da remoto (Pass, Shop, pagamenti).';
COMMENT ON COLUMN "public"."feature_flags"."payload" IS 'Config opzionale del flag (es. percentuale di rollout, parametri).';

ALTER TABLE "public"."feature_flags" ENABLE ROW LEVEL SECURITY;

-- Lettura: tutti (anon + authenticated). I flag non sono dati sensibili e servono a website/gestionale/app.
CREATE POLICY "feature_flags_select_all"
    ON "public"."feature_flags"
    FOR SELECT
    USING (true);

-- Scrittura: solo admin (riusa l'helper esistente is_admin()).
CREATE POLICY "feature_flags_write_admin"
    ON "public"."feature_flags"
    FOR ALL
    USING ("public"."is_admin"())
    WITH CHECK ("public"."is_admin"());

-- Grant coerenti con le altre tabelle: anon legge; authenticated ha DML ma è filtrato dalla RLS (solo admin scrive).
GRANT SELECT ON TABLE "public"."feature_flags" TO "anon";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."feature_flags" TO "authenticated";
GRANT SELECT ON TABLE "public"."feature_flags" TO "service_role";

-- Flag iniziali, tutti SPENTI (gestionale-first: lo staff li accenderà quando le feature saranno pronte).
INSERT INTO "public"."feature_flags" ("key", "enabled", "description") VALUES
    ('community_pass', false, 'Kalòs Community Pass (tesseramento)'),
    ('shop',           false, 'Shop / Merch (Fragranza Kalòs)'),
    ('payments',       false, 'Pagamenti in-app (Stripe)'),
    ('stripe_live',    false, 'Stripe in modalità LIVE (altrimenti test mode)')
ON CONFLICT ("key") DO NOTHING;
