-- Migration 20260923160600: gruppi di attività, luoghi e tipo degli eventi (sessione 3, blocco 6)
--
-- Obiettivo: tre concetti che oggi mancano e che servono al sito e all'app.
--
--   1. GRUPPI (B3). Le attività sono una lista piatta. I quattro gruppi decisi — Kalòs x Benessere,
--      Kalòs x Mamme, Kalòs x Terza Età, Laboratori e Eventi — avranno ciascuno una pagina sul sito.
--      Le "quattro fasce" dell'enum `activity_category` restano dove sono, ma non le usa più nessuno:
--      toglierle sarebbe distruttivo e non porterebbe niente.
--
--   2. LUOGHI (B10). Oggi l'unico indirizzo è `events.location`, testo libero. Ma Piazza Furlan 5 è
--      solo sede legale e non è aperta al pubblico: le attività si svolgono in più posti tra Ronchi dei
--      Legionari, Monfalcone e Staranzano. Il luogo appartiene alla singola lezione o al singolo
--      evento, mai "allo studio" (BRAND.md). Da qui usciranno anche le pagine per comune e la SEO.
--
--   3. TIPO DEGLI EVENTI (B3): evento, laboratorio o incontro, per etichettarli e filtrarli.
--
-- Le view pubbliche si ALLARGANO: il sito fa `select('*')` e mappa campi fissi, quindi aggiungere
-- colonne è innocuo, toglierne una romperebbe tutto. Due view nuove per gruppi e luoghi, leggibili
-- senza login come le altre del sito.
--
-- Fuori da qui: la ricostruzione automatica del sito quando si cambia un luogo (build hook Netlify) è
-- la sessione 6, e gli indirizzi veri li inserirete voi dal gestionale.
--
-- Compatibilità: colonne nuove sempre NULL o con DEFAULT, tabelle e view nuove, view esistenti solo
-- allargate. Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 B3, B10, B11, B12.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enum: tipo dell'evento
-- ─────────────────────────────────────────────────────────────────────────────

DO $$ BEGIN
    CREATE TYPE "public"."event_type" AS ENUM (
        'evento',
        'laboratorio',
        'incontro'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. activity_groups
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."activity_groups" (
    "id"                "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "slug"              "text"  NOT NULL,
    "name"              "text"  NOT NULL,
    "description"       "text",
    "image_url"         "text",
    "color"             "text",
    "seo_title"         "text",
    "seo_description"   "text",
    "display_order"     integer DEFAULT 0 NOT NULL,
    "is_active"         boolean DEFAULT true NOT NULL,
    "created_at"        timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"        timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "activity_groups_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "activity_groups_slug_key" UNIQUE ("slug"),
    CONSTRAINT "activity_groups_slug_format" CHECK ("slug" ~ '^[a-z0-9-]+$'),
    CONSTRAINT "activity_groups_name_not_empty" CHECK ("length"("btrim"("name")) > 0)
);

ALTER TABLE "public"."activity_groups" OWNER TO "postgres";

COMMENT ON TABLE "public"."activity_groups" IS
    'Gruppi di attività (B3). Ogni gruppo ha una pagina sul sito, per esempio /attivita/benessere. Sostituiscono nell''uso le quattro fasce di `activity_category`, che restano nel database ma non le legge più nessuno.';

CREATE OR REPLACE TRIGGER "activity_groups_updated_at"
    BEFORE UPDATE ON "public"."activity_groups"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- I quattro gruppi decisi. Le attività ci si collegano dal gestionale (sessione 6): qui nessuna
-- attività viene toccata, così niente cambia da solo su sito e app.
INSERT INTO "public"."activity_groups" ("slug", "name", "description", "display_order") VALUES
    ('benessere',   'Kalòs x Benessere',   'Meditazione, yoga e pratiche per prenderti cura di te.', 10),
    ('mamme',       'Kalòs x Mamme',       'Movimento e incontri per la maternità e il post parto.', 20),
    ('terza-eta',   'Kalòs x Terza Età',   'Attività pensate per la terza età.',                     30),
    ('laboratori',  'Laboratori e Eventi', 'Laboratori, eventi e incontri una tantum.',              40)
ON CONFLICT ("slug") DO NOTHING;

ALTER TABLE "public"."activities"
    ADD COLUMN IF NOT EXISTS "group_id" "uuid";

DO $$ BEGIN
    ALTER TABLE "public"."activities"
        ADD CONSTRAINT "activities_group_id_fkey"
        FOREIGN KEY ("group_id") REFERENCES "public"."activity_groups"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN "public"."activities"."group_id" IS
    'Gruppo di appartenenza. NULL finché non lo si assegna dal gestionale: nessuna attività cambia comportamento per questa migrazione.';

CREATE INDEX IF NOT EXISTS "idx_activities_group_id" ON "public"."activities" ("group_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. locations
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."locations" (
    "id"                "uuid"  DEFAULT "gen_random_uuid"() NOT NULL,
    "slug"              "text"  NOT NULL,
    "name"              "text"  NOT NULL,
    "address_street"    "text",
    "address_zip"       "text",
    "city"              "text"  NOT NULL,
    "province"          "text",
    "map_url"           "text",
    "latitude"          numeric(9,6),
    "longitude"         numeric(9,6),
    "notes"             "text",
    "access_notes"      "text",
    "show_on_site"      boolean DEFAULT true NOT NULL,
    "is_active"         boolean DEFAULT true NOT NULL,
    "display_order"     integer DEFAULT 0 NOT NULL,
    "created_at"        timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at"        timestamp with time zone DEFAULT "now"() NOT NULL,

    CONSTRAINT "locations_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "locations_slug_key" UNIQUE ("slug"),
    CONSTRAINT "locations_slug_format" CHECK ("slug" ~ '^[a-z0-9-]+$'),
    CONSTRAINT "locations_name_not_empty" CHECK ("length"("btrim"("name")) > 0),
    CONSTRAINT "locations_city_not_empty" CHECK ("length"("btrim"("city")) > 0),
    CONSTRAINT "locations_latitude_range"
        CHECK ("latitude" IS NULL OR ("latitude" BETWEEN -90 AND 90)),
    CONSTRAINT "locations_longitude_range"
        CHECK ("longitude" IS NULL OR ("longitude" BETWEEN -180 AND 180))
);

ALTER TABLE "public"."locations" OWNER TO "postgres";

COMMENT ON TABLE "public"."locations" IS
    'Luoghi in cui si svolgono lezioni ed eventi (B10). Il comune è obbligatorio perché da lì nascono le pagine per comune e la SEO locale; l''indirizzo può mancare finché non è definito.';
COMMENT ON COLUMN "public"."locations"."show_on_site" IS
    'false tiene il luogo fuori da "Dove siamo" e dalla sitemap: serve per i posti non aperti al pubblico, a partire dalla sede legale di Piazza Furlan.';
COMMENT ON COLUMN "public"."locations"."access_notes" IS
    'Come si entra, dove si parcheggia, a quale campanello suonare: quello che serve sapere prima di arrivare.';

CREATE OR REPLACE TRIGGER "locations_updated_at"
    BEFORE UPDATE ON "public"."locations"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

ALTER TABLE "public"."lessons"
    ADD COLUMN IF NOT EXISTS "location_id" "uuid";
ALTER TABLE "public"."events"
    ADD COLUMN IF NOT EXISTS "location_id" "uuid",
    ADD COLUMN IF NOT EXISTS "event_type" "public"."event_type"
        DEFAULT 'evento'::"public"."event_type" NOT NULL;
ALTER TABLE "public"."activities"
    ADD COLUMN IF NOT EXISTS "default_location_id" "uuid";

DO $$ BEGIN
    ALTER TABLE "public"."lessons" ADD CONSTRAINT "lessons_location_id_fkey"
        FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE "public"."events" ADD CONSTRAINT "events_location_id_fkey"
        FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE "public"."activities" ADD CONSTRAINT "activities_default_location_id_fkey"
        FOREIGN KEY ("default_location_id") REFERENCES "public"."locations"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN "public"."lessons"."location_id" IS
    'Dove si tiene la lezione. NULL = non ancora indicato; l''attività può suggerire un valore predefinito.';
COMMENT ON COLUMN "public"."events"."location_id" IS
    'Dove si tiene l''evento. La vecchia colonna `location`, testo libero, resta finché il gestionale non passa a questa.';
COMMENT ON COLUMN "public"."events"."event_type" IS
    'Evento, laboratorio o incontro (B3). Sito e app mostrano l''etichetta e permettono di filtrare.';
COMMENT ON COLUMN "public"."activities"."default_location_id" IS
    'Luogo predefinito per le lezioni di questa attività, da usare come suggerimento quando se ne crea una.';

CREATE INDEX IF NOT EXISTS "idx_lessons_location_id" ON "public"."lessons" ("location_id");
CREATE INDEX IF NOT EXISTS "idx_events_location_id" ON "public"."events" ("location_id");
CREATE INDEX IF NOT EXISTS "idx_events_event_type" ON "public"."events" ("event_type");

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RLS e grant
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE "public"."activity_groups" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."locations"       ENABLE ROW LEVEL SECURITY;

-- Gruppi e luoghi sono dati pubblici del sito, come attività e piani: anon li legge, li scrive lo staff.
DROP POLICY IF EXISTS "activity_groups_select_anon" ON "public"."activity_groups";
CREATE POLICY "activity_groups_select_anon" ON "public"."activity_groups"
    FOR SELECT TO "anon" USING ("is_active" = true);

DROP POLICY IF EXISTS "activity_groups_select_authenticated" ON "public"."activity_groups";
CREATE POLICY "activity_groups_select_authenticated" ON "public"."activity_groups"
    FOR SELECT TO "authenticated" USING (true);

DROP POLICY IF EXISTS "activity_groups_write_staff" ON "public"."activity_groups";
CREATE POLICY "activity_groups_write_staff" ON "public"."activity_groups"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

DROP POLICY IF EXISTS "locations_select_anon" ON "public"."locations";
CREATE POLICY "locations_select_anon" ON "public"."locations"
    FOR SELECT TO "anon" USING ("is_active" = true AND "show_on_site" = true);

DROP POLICY IF EXISTS "locations_select_authenticated" ON "public"."locations";
CREATE POLICY "locations_select_authenticated" ON "public"."locations"
    FOR SELECT TO "authenticated" USING (true);

DROP POLICY IF EXISTS "locations_write_staff" ON "public"."locations";
CREATE POLICY "locations_write_staff" ON "public"."locations"
    FOR ALL TO "authenticated" USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

GRANT SELECT ON TABLE "public"."activity_groups" TO "anon";
GRANT SELECT ON TABLE "public"."locations"       TO "anon";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."activity_groups" TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."locations"       TO "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. View pubbliche
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW "public"."public_site_groups" AS
SELECT g.id, g.slug, g.name, g.description, g.image_url, g.color,
       g.seo_title, g.seo_description, g.display_order,
       COUNT(a.id) FILTER (WHERE a.deleted_at IS NULL AND COALESCE(a.is_active, true) = true) AS activity_count
  FROM public.activity_groups g
  LEFT JOIN public.activities a ON a.group_id = g.id
 WHERE g.is_active = true
 GROUP BY g.id, g.slug, g.name, g.description, g.image_url, g.color,
          g.seo_title, g.seo_description, g.display_order
 ORDER BY g.display_order, g.name;

ALTER VIEW "public"."public_site_groups" OWNER TO "postgres";
COMMENT ON VIEW "public"."public_site_groups" IS
    'Gruppi di attività per il sito pubblico. Espone solo colonne pubbliche, come le altre public_site_*.';

CREATE OR REPLACE VIEW "public"."public_site_locations" AS
SELECT l.id, l.slug, l.name, l.address_street, l.address_zip, l.city, l.province,
       l.map_url, l.latitude, l.longitude, l.access_notes, l.display_order
  FROM public.locations l
 WHERE l.is_active = true AND l.show_on_site = true
 ORDER BY l.display_order, l.city, l.name;

ALTER VIEW "public"."public_site_locations" OWNER TO "postgres";
COMMENT ON VIEW "public"."public_site_locations" IS
    'Luoghi da mostrare sul sito: alimentano "Dove siamo", i dati strutturati e le pagine per comune. La sede legale resta fuori, perché non è aperta al pubblico.';

GRANT SELECT ON TABLE "public"."public_site_groups"    TO "anon";
GRANT SELECT ON TABLE "public"."public_site_groups"    TO "authenticated";
GRANT SELECT ON TABLE "public"."public_site_locations" TO "anon";
GRANT SELECT ON TABLE "public"."public_site_locations" TO "authenticated";

-- Le due view esistenti si allargano: colonne in più, nessuna in meno, stesso ordine di prima.
CREATE OR REPLACE VIEW "public"."public_site_activities" AS
SELECT a.id, a.name, a.slug, a.description, a.discipline, a.color, a.duration_minutes,
       a.image_url, a.is_active, a.icon_name, a.landing_title, a.landing_subtitle,
       a.active_months, a.target_audience, a.program_objectives, a.why_participate,
       a.journey_structure, a.created_at, a.updated_at,
       a.group_id,
       g.slug AS group_slug,
       g.name AS group_name,
       loc.slug AS default_location_slug,
       loc.city AS default_location_city
  FROM public.activities a
  LEFT JOIN public.activity_groups g ON g.id = a.group_id AND g.is_active = true
  LEFT JOIN public.locations loc ON loc.id = a.default_location_id AND loc.show_on_site = true
 WHERE a.deleted_at IS NULL AND COALESCE(a.is_active, true) = true
 ORDER BY a.name;

CREATE OR REPLACE VIEW "public"."public_site_events" AS
SELECT e.id, e.name AS title, e.description, e.image_url,
       e.starts_at AS start_date, e.ends_at AS end_date,
       e.link AS registration_url, e.link AS link_url,
       e.created_at, e.updated_at,
       e.event_type,
       e.location_id,
       loc.slug AS location_slug,
       loc.name AS location_name,
       loc.city AS location_city,
       loc.map_url AS location_map_url
  FROM public.events e
  LEFT JOIN public.locations loc ON loc.id = e.location_id AND loc.show_on_site = true
 WHERE e.deleted_at IS NULL
 ORDER BY e.starts_at DESC;
