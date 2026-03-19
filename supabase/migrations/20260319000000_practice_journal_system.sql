-- Migration: Create practice and journal system
--
-- Obiettivo: Sistema "Pratica a casa" con contenuti guidati a step/blocchi,
-- diario personale utente, e tracking stato/progressi.

-- ============================================================================
-- 1. CREATE ENUMS
-- ============================================================================

CREATE TYPE "public"."practice_category" AS ENUM (
    'meditazione',
    'corpo',
    'respiro',
    'scrittura',
    'rilassamento'
);
ALTER TYPE "public"."practice_category" OWNER TO "postgres";

CREATE TYPE "public"."practice_level" AS ENUM (
    'principiante',
    'intermedio',
    'avanzato'
);
ALTER TYPE "public"."practice_level" OWNER TO "postgres";

CREATE TYPE "public"."practice_block_type" AS ENUM (
    'text',
    'image',
    'audio',
    'video'
);
ALTER TYPE "public"."practice_block_type" OWNER TO "postgres";

CREATE TYPE "public"."practice_user_status" AS ENUM (
    'started',
    'completed'
);
ALTER TYPE "public"."practice_user_status" OWNER TO "postgres";

-- ============================================================================
-- 2. CREATE practices TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."practices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "subtitle" "text",
    "description" "text",
    "duration_minutes" integer,
    "category" "public"."practice_category" NOT NULL,
    "level" "public"."practice_level" NOT NULL DEFAULT 'principiante'::"public"."practice_level",
    "goals" "jsonb" DEFAULT '[]'::"jsonb",
    "cover_image_url" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "is_featured" boolean DEFAULT false NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);
ALTER TABLE "public"."practices" OWNER TO "postgres";

ALTER TABLE "public"."practices"
    ADD CONSTRAINT "practices_pkey" PRIMARY KEY ("id");

-- Indexes
CREATE INDEX "idx_practices_active" ON "public"."practices" ("sort_order")
    WHERE "is_active" = true AND "deleted_at" IS NULL;

CREATE INDEX "idx_practices_category" ON "public"."practices" ("category")
    WHERE "deleted_at" IS NULL;

CREATE INDEX "idx_practices_featured" ON "public"."practices" ("sort_order")
    WHERE "is_featured" = true AND "is_active" = true AND "deleted_at" IS NULL;

-- Trigger
CREATE TRIGGER "practices_updated_at"
    BEFORE UPDATE ON "public"."practices"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ============================================================================
-- 3. CREATE practice_steps TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."practice_steps" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "practice_id" "uuid" NOT NULL,
    "title" "text",
    "sort_order" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."practice_steps" OWNER TO "postgres";

ALTER TABLE "public"."practice_steps"
    ADD CONSTRAINT "practice_steps_pkey" PRIMARY KEY ("id");

ALTER TABLE "public"."practice_steps"
    ADD CONSTRAINT "practice_steps_practice_id_fkey"
    FOREIGN KEY ("practice_id")
    REFERENCES "public"."practices"("id")
    ON DELETE CASCADE;

-- Index
CREATE INDEX "idx_practice_steps_practice_id" ON "public"."practice_steps" ("practice_id", "sort_order");

-- ============================================================================
-- 4. CREATE practice_blocks TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."practice_blocks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "step_id" "uuid" NOT NULL,
    "block_type" "public"."practice_block_type" NOT NULL,
    "content" "text" NOT NULL,
    "caption" "text",
    "sort_order" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."practice_blocks" OWNER TO "postgres";

ALTER TABLE "public"."practice_blocks"
    ADD CONSTRAINT "practice_blocks_pkey" PRIMARY KEY ("id");

ALTER TABLE "public"."practice_blocks"
    ADD CONSTRAINT "practice_blocks_step_id_fkey"
    FOREIGN KEY ("step_id")
    REFERENCES "public"."practice_steps"("id")
    ON DELETE CASCADE;

-- Index
CREATE INDEX "idx_practice_blocks_step_id" ON "public"."practice_blocks" ("step_id", "sort_order");

-- ============================================================================
-- 5. CREATE practice_activities JUNCTION TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."practice_activities" (
    "practice_id" "uuid" NOT NULL,
    "activity_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."practice_activities" OWNER TO "postgres";

ALTER TABLE "public"."practice_activities"
    ADD CONSTRAINT "practice_activities_pkey" PRIMARY KEY ("practice_id", "activity_id");

ALTER TABLE "public"."practice_activities"
    ADD CONSTRAINT "practice_activities_practice_id_fkey"
    FOREIGN KEY ("practice_id")
    REFERENCES "public"."practices"("id")
    ON DELETE CASCADE;

ALTER TABLE "public"."practice_activities"
    ADD CONSTRAINT "practice_activities_activity_id_fkey"
    FOREIGN KEY ("activity_id")
    REFERENCES "public"."activities"("id")
    ON DELETE CASCADE;

-- ============================================================================
-- 6. CREATE practice_user_state TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."practice_user_state" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "practice_id" "uuid" NOT NULL,
    "status" "public"."practice_user_status" DEFAULT 'started'::"public"."practice_user_status" NOT NULL,
    "current_step_index" integer DEFAULT 0 NOT NULL,
    "is_favorite" boolean DEFAULT false NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "last_accessed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "time_spent_seconds" integer DEFAULT 0 NOT NULL
);
ALTER TABLE "public"."practice_user_state" OWNER TO "postgres";

ALTER TABLE "public"."practice_user_state"
    ADD CONSTRAINT "practice_user_state_pkey" PRIMARY KEY ("id");

ALTER TABLE "public"."practice_user_state"
    ADD CONSTRAINT "practice_user_state_client_practice_unique" UNIQUE ("client_id", "practice_id");

ALTER TABLE "public"."practice_user_state"
    ADD CONSTRAINT "practice_user_state_client_id_fkey"
    FOREIGN KEY ("client_id")
    REFERENCES "public"."clients"("id")
    ON DELETE CASCADE;

ALTER TABLE "public"."practice_user_state"
    ADD CONSTRAINT "practice_user_state_practice_id_fkey"
    FOREIGN KEY ("practice_id")
    REFERENCES "public"."practices"("id")
    ON DELETE CASCADE;

-- Indexes
CREATE INDEX "idx_practice_user_state_client_id" ON "public"."practice_user_state" ("client_id");
CREATE INDEX "idx_practice_user_state_favorites" ON "public"."practice_user_state" ("client_id")
    WHERE "is_favorite" = true;

-- ============================================================================
-- 7. CREATE journal_entries TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."journal_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "title" "text",
    "body" "text" NOT NULL,
    "practice_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."journal_entries" OWNER TO "postgres";

ALTER TABLE "public"."journal_entries"
    ADD CONSTRAINT "journal_entries_pkey" PRIMARY KEY ("id");

ALTER TABLE "public"."journal_entries"
    ADD CONSTRAINT "journal_entries_client_id_fkey"
    FOREIGN KEY ("client_id")
    REFERENCES "public"."clients"("id")
    ON DELETE CASCADE;

ALTER TABLE "public"."journal_entries"
    ADD CONSTRAINT "journal_entries_practice_id_fkey"
    FOREIGN KEY ("practice_id")
    REFERENCES "public"."practices"("id")
    ON DELETE SET NULL;

-- Indexes
CREATE INDEX "idx_journal_entries_client_id" ON "public"."journal_entries" ("client_id", "created_at" DESC);
CREATE INDEX "idx_journal_entries_practice_id" ON "public"."journal_entries" ("practice_id")
    WHERE "practice_id" IS NOT NULL;

-- Trigger
CREATE TRIGGER "journal_entries_updated_at"
    BEFORE UPDATE ON "public"."journal_entries"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ============================================================================
-- 8. ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE "public"."practices" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."practice_steps" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."practice_blocks" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."practice_activities" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."practice_user_state" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."journal_entries" ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 9. RLS POLICIES
-- ============================================================================

-- practices: Authenticated users read active practices
CREATE POLICY "practices_select_active"
ON "public"."practices" FOR SELECT TO "authenticated"
USING ("is_active" = true AND "deleted_at" IS NULL);

-- practices: Staff can manage all
CREATE POLICY "practices_staff_all"
ON "public"."practices" FOR ALL TO "authenticated"
USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- practices: Service role full access
CREATE POLICY "practices_service_all"
ON "public"."practices" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- practice_steps: Users read steps of active practices
CREATE POLICY "practice_steps_select_active"
ON "public"."practice_steps" FOR SELECT TO "authenticated"
USING (
    EXISTS (
        SELECT 1 FROM "public"."practices" p
        WHERE p.id = "practice_id"
        AND p."is_active" = true
        AND p."deleted_at" IS NULL
    )
);

-- practice_steps: Staff can manage all
CREATE POLICY "practice_steps_staff_all"
ON "public"."practice_steps" FOR ALL TO "authenticated"
USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- practice_steps: Service role full access
CREATE POLICY "practice_steps_service_all"
ON "public"."practice_steps" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- practice_blocks: Users read blocks of active practices
CREATE POLICY "practice_blocks_select_active"
ON "public"."practice_blocks" FOR SELECT TO "authenticated"
USING (
    EXISTS (
        SELECT 1 FROM "public"."practice_steps" ps
        JOIN "public"."practices" p ON p.id = ps.practice_id
        WHERE ps.id = "step_id"
        AND p."is_active" = true
        AND p."deleted_at" IS NULL
    )
);

-- practice_blocks: Staff can manage all
CREATE POLICY "practice_blocks_staff_all"
ON "public"."practice_blocks" FOR ALL TO "authenticated"
USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- practice_blocks: Service role full access
CREATE POLICY "practice_blocks_service_all"
ON "public"."practice_blocks" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- practice_activities: Users read activities of active practices
CREATE POLICY "practice_activities_select_active"
ON "public"."practice_activities" FOR SELECT TO "authenticated"
USING (
    EXISTS (
        SELECT 1 FROM "public"."practices" p
        WHERE p.id = "practice_id"
        AND p."is_active" = true
        AND p."deleted_at" IS NULL
    )
);

-- practice_activities: Staff can manage all
CREATE POLICY "practice_activities_staff_all"
ON "public"."practice_activities" FOR ALL TO "authenticated"
USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

-- practice_activities: Service role full access
CREATE POLICY "practice_activities_service_all"
ON "public"."practice_activities" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- practice_user_state: Users manage their own state
CREATE POLICY "practice_user_state_select_own"
ON "public"."practice_user_state" FOR SELECT TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "practice_user_state_insert_own"
ON "public"."practice_user_state" FOR INSERT TO "authenticated"
WITH CHECK ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "practice_user_state_update_own"
ON "public"."practice_user_state" FOR UPDATE TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"())
WITH CHECK ("client_id" = "public"."get_my_client_id"());

-- practice_user_state: Staff can read for analytics
CREATE POLICY "practice_user_state_staff_select"
ON "public"."practice_user_state" FOR SELECT TO "authenticated"
USING ("public"."is_staff"());

-- practice_user_state: Service role full access
CREATE POLICY "practice_user_state_service_all"
ON "public"."practice_user_state" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- journal_entries: Users manage their own entries (private content)
CREATE POLICY "journal_entries_select_own"
ON "public"."journal_entries" FOR SELECT TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "journal_entries_insert_own"
ON "public"."journal_entries" FOR INSERT TO "authenticated"
WITH CHECK ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "journal_entries_update_own"
ON "public"."journal_entries" FOR UPDATE TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"())
WITH CHECK ("client_id" = "public"."get_my_client_id"());

CREATE POLICY "journal_entries_delete_own"
ON "public"."journal_entries" FOR DELETE TO "authenticated"
USING ("client_id" = "public"."get_my_client_id"());

-- journal_entries: Service role full access
CREATE POLICY "journal_entries_service_all"
ON "public"."journal_entries" FOR ALL TO "service_role"
USING (true) WITH CHECK (true);

-- ============================================================================
-- 10. STORAGE BUCKET
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'practices',
    'practices',
    true,  -- Public bucket: content accessible to app users
    52428800,  -- 50MB (for video files)
    ARRAY[
        'image/jpeg', 'image/png', 'image/webp',
        'audio/mpeg', 'audio/mp4', 'audio/wav',
        'video/mp4', 'video/webm'
    ]
)
ON CONFLICT (id) DO NOTHING;

-- Staff can upload
CREATE POLICY "practices_staff_insert" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'practices' AND
    "public"."is_staff"()
);

-- Staff can update
CREATE POLICY "practices_staff_update" ON storage.objects
FOR UPDATE TO authenticated
USING (
    bucket_id = 'practices' AND
    "public"."is_staff"()
)
WITH CHECK (
    bucket_id = 'practices' AND
    "public"."is_staff"()
);

-- Staff can delete
CREATE POLICY "practices_staff_delete" ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'practices' AND
    "public"."is_staff"()
);

-- Public read access
CREATE POLICY "practices_public_read" ON storage.objects
FOR SELECT TO public
USING (bucket_id = 'practices');

-- ============================================================================
-- 11. GRANTS
-- ============================================================================

GRANT ALL ON "public"."practices" TO "authenticated";
GRANT ALL ON "public"."practices" TO "service_role";
GRANT ALL ON "public"."practice_steps" TO "authenticated";
GRANT ALL ON "public"."practice_steps" TO "service_role";
GRANT ALL ON "public"."practice_blocks" TO "authenticated";
GRANT ALL ON "public"."practice_blocks" TO "service_role";
GRANT ALL ON "public"."practice_activities" TO "authenticated";
GRANT ALL ON "public"."practice_activities" TO "service_role";
GRANT ALL ON "public"."practice_user_state" TO "authenticated";
GRANT ALL ON "public"."practice_user_state" TO "service_role";
GRANT ALL ON "public"."journal_entries" TO "authenticated";
GRANT ALL ON "public"."journal_entries" TO "service_role";

-- ============================================================================
-- 12. COMMENTS
-- ============================================================================

COMMENT ON TABLE "public"."practices" IS
'Pratiche guidate per la pratica a casa. Ogni pratica ha step con blocchi di contenuto.';

COMMENT ON TABLE "public"."practice_steps" IS
'Passi ordinati di una pratica guidata. Ogni step contiene blocchi di contenuto.';

COMMENT ON TABLE "public"."practice_blocks" IS
'Blocchi di contenuto (testo, immagine, audio, video) dentro uno step di pratica.';

COMMENT ON TABLE "public"."practice_activities" IS
'Associazione tra pratiche e attivita/discipline correlate.';

COMMENT ON TABLE "public"."practice_user_state" IS
'Stato di avanzamento dell''utente per ogni pratica: progresso, preferiti, tempo speso.';

COMMENT ON TABLE "public"."journal_entries" IS
'Diario personale dell''utente. Puo essere collegato a una pratica completata.';

COMMENT ON COLUMN "public"."practices"."goals" IS
'Array JSON di obiettivi: calmarsi, energia, rallentare, sciogliere_tensioni, riconnettersi';

COMMENT ON COLUMN "public"."practices"."is_featured" IS
'Flag "In evidenza" per mostrare nella home dell''app';

COMMENT ON COLUMN "public"."practice_user_state"."current_step_index" IS
'Indice dell''ultimo step raggiunto dall''utente (0-based)';

COMMENT ON COLUMN "public"."practice_user_state"."time_spent_seconds" IS
'Tempo totale accumulato dall''utente sulla pratica in secondi';

COMMENT ON COLUMN "public"."journal_entries"."practice_id" IS
'Se la nota e stata creata al termine di una pratica, riferimento alla pratica';
