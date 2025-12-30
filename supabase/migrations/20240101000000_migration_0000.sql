-- Migration 0000: Initial schema
-- Types, Tables, and Base Indexes

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;
SET default_tablespace = '';
SET default_table_access_method = "heap";

CREATE TYPE "public"."booking_status" AS ENUM (
    'booked',
    'canceled',
    'attended',
    'no_show'
);
ALTER TYPE "public"."booking_status" OWNER TO "postgres";
CREATE TYPE "public"."subscription_status" AS ENUM (
    'active',
    'completed',
    'expired',
    'canceled'
);
ALTER TYPE "public"."subscription_status" OWNER TO "postgres";
CREATE TYPE "public"."user_role" AS ENUM (
    'user',
    'operator',
    'admin',
    'finance'
);
ALTER TYPE "public"."user_role" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "full_name" "text",
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "deleted_at" timestamp with time zone,
    "phone" "text",
    "notes" "text",
    "accepted_terms_at" timestamp with time zone,
    "accepted_privacy_at" timestamp with time zone,
    "role" "public"."user_role" DEFAULT 'user'::"public"."user_role" NOT NULL
);
ALTER TABLE "public"."profiles" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."activities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "discipline" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "deleted_at" timestamp with time zone,
    "color" "text"
);
ALTER TABLE "public"."activities" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lesson_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "status" "public"."booking_status" DEFAULT 'booked'::"public"."booking_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "subscription_id" "uuid",
    "client_id" "uuid",
    CONSTRAINT "bookings_user_client_xor" CHECK (((("user_id" IS NOT NULL) AND ("client_id" IS NULL)) OR (("user_id" IS NULL) AND ("client_id" IS NOT NULL))))
);
ALTER TABLE "public"."bookings" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."clients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "full_name" "text" NOT NULL,
    "phone" "text",
    "email" "text",
    "profile_id" "uuid",
    "notes" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);
ALTER TABLE "public"."clients" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."event_bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "event_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" "public"."booking_status" DEFAULT 'booked'::"public"."booking_status" NOT NULL
);
ALTER TABLE "public"."event_bookings" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "image_url" "text",
    "link" "text" NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "capacity" integer,
    "location" "text",
    "price_cents" integer DEFAULT 0,
    "currency" "text" DEFAULT 'EUR'::"text"
);
ALTER TABLE "public"."events" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."expenses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "amount_cents" integer NOT NULL,
    "expense_date" "date" NOT NULL,
    "category" "text" NOT NULL,
    "vendor" "text",
    "notes" "text",
    "is_fixed" boolean DEFAULT false NOT NULL,
    "activity_id" "uuid",
    "operator_id" "uuid",
    "lesson_id" "uuid",
    "event_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "expenses_category_check" CHECK (("category" = ANY (ARRAY['staff_compensation'::"text", 'materials'::"text", 'location_fee'::"text", 'software'::"text", 'marketing'::"text", 'utilities'::"text", 'rent'::"text", 'other'::"text"])))
);
ALTER TABLE "public"."expenses" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."lessons" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "activity_id" "uuid" NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone NOT NULL,
    "capacity" integer NOT NULL,
    "booking_deadline_minutes" integer DEFAULT 120,
    "cancel_deadline_minutes" integer DEFAULT 120,
    "notes" "text",
    "operator_id" "uuid",
    "deleted_at" timestamp with time zone,
    "recurring_series_id" "uuid",
    "is_individual" boolean DEFAULT false NOT NULL,
    "assigned_client_id" "uuid",
    CONSTRAINT "lessons_capacity_check" CHECK (("capacity" > 0)),
    CONSTRAINT "lessons_individual_capacity_check" CHECK ((("is_individual" = false) OR ("capacity" = 1))),
    CONSTRAINT "lessons_individual_check" CHECK ((("is_individual" = false) OR ("assigned_client_id" IS NOT NULL))),
    CONSTRAINT "lessons_individual_client_check" CHECK ((("is_individual" = true) OR ("assigned_client_id" IS NULL)))
);
ALTER TABLE "public"."lessons" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."plans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "discipline" "text",
    "price_cents" integer NOT NULL,
    "currency" "text" DEFAULT 'EUR'::"text",
    "entries" integer,
    "validity_days" integer NOT NULL,
    "description" "text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "deleted_at" timestamp with time zone,
    "discount_percent" numeric(5,2),
    CONSTRAINT "plans_discount_percent_check" CHECK ((("discount_percent" >= (0)::numeric) AND ("discount_percent" <= (100)::numeric)))
);
ALTER TABLE "public"."plans" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "plan_id" "uuid" NOT NULL,
    "status" "public"."subscription_status" DEFAULT 'active'::"public"."subscription_status" NOT NULL,
    "started_at" "date" DEFAULT CURRENT_DATE NOT NULL,
    "expires_at" "date" NOT NULL,
    "custom_name" "text",
    "custom_price_cents" integer,
    "custom_entries" integer,
    "custom_validity_days" integer,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "client_id" "uuid",
    CONSTRAINT "subscriptions_user_client_xor" CHECK (((("user_id" IS NOT NULL) AND ("client_id" IS NULL)) OR (("user_id" IS NULL) AND ("client_id" IS NOT NULL))))
);
ALTER TABLE "public"."subscriptions" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."operators" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "role" "text" NOT NULL,
    "bio" "text",
    "disciplines" "text"[],
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "profile_id" "uuid",
    "is_admin" boolean DEFAULT false,
    "deleted_at" timestamp with time zone
);
ALTER TABLE "public"."operators" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."payout_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "month" "date" NOT NULL,
    "cash_reserve_pct" numeric(5,2) DEFAULT 0 NOT NULL,
    "marketing_pct" numeric(5,2) DEFAULT 0 NOT NULL,
    "team_pct" numeric(5,2) DEFAULT 0 NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "payout_rules_cash_reserve_pct_check" CHECK ((("cash_reserve_pct" >= (0)::numeric) AND ("cash_reserve_pct" <= (100)::numeric))),
    CONSTRAINT "payout_rules_marketing_pct_check" CHECK ((("marketing_pct" >= (0)::numeric) AND ("marketing_pct" <= (100)::numeric))),
    CONSTRAINT "payout_rules_percentage_check" CHECK (((("cash_reserve_pct" + "marketing_pct") + "team_pct") <= (100)::numeric)),
    CONSTRAINT "payout_rules_team_pct_check" CHECK ((("team_pct" >= (0)::numeric) AND ("team_pct" <= (100)::numeric)))
);
ALTER TABLE "public"."payout_rules" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."payouts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "month" "date" NOT NULL,
    "operator_id" "uuid",
    "amount_cents" integer NOT NULL,
    "reason" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "paid_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "created_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "payouts_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'completed'::"text", 'cancelled'::"text"])))
);
ALTER TABLE "public"."payouts" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."plan_activities" (
    "plan_id" "uuid" NOT NULL,
    "activity_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);
ALTER TABLE "public"."plan_activities" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."promotions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "image_url" "text",
    "link" "text" NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "discount_percent" integer,
    "plan_id" "uuid",
    CONSTRAINT "promotions_discount_percent_check" CHECK ((("discount_percent" >= 0) AND ("discount_percent" <= 100)))
);
ALTER TABLE "public"."promotions" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."subscription_usages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "subscription_id" "uuid" NOT NULL,
    "booking_id" "uuid",
    "delta" integer NOT NULL,
    "reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);
ALTER TABLE "public"."subscription_usages" OWNER TO "postgres";
CREATE TABLE IF NOT EXISTS "public"."waitlist" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lesson_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);
ALTER TABLE "public"."waitlist" OWNER TO "postgres";
ALTER TABLE ONLY "public"."activities"
    ADD CONSTRAINT "activities_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."event_bookings"
    ADD CONSTRAINT "event_bookings_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."operators"
    ADD CONSTRAINT "operators_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."payout_rules"
    ADD CONSTRAINT "payout_rules_month_unique" UNIQUE ("month");
ALTER TABLE ONLY "public"."payout_rules"
    ADD CONSTRAINT "payout_rules_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."plan_activities"
    ADD CONSTRAINT "plan_activities_pkey" PRIMARY KEY ("plan_id", "activity_id");
ALTER TABLE ONLY "public"."plans"
    ADD CONSTRAINT "plans_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_email_key" UNIQUE ("email");
ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."subscription_usages"
    ADD CONSTRAINT "subscription_usages_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."waitlist"
    ADD CONSTRAINT "waitlist_lesson_id_user_id_key" UNIQUE ("lesson_id", "user_id");
ALTER TABLE ONLY "public"."waitlist"
    ADD CONSTRAINT "waitlist_pkey" PRIMARY KEY ("id");

CREATE UNIQUE INDEX "bookings_lesson_client_unique" ON "public"."bookings" USING "btree" ("lesson_id", "client_id") WHERE (("client_id" IS NOT NULL) AND ("status" = 'booked'::"public"."booking_status"));
CREATE UNIQUE INDEX "bookings_lesson_user_unique" ON "public"."bookings" USING "btree" ("lesson_id", "user_id") WHERE (("user_id" IS NOT NULL) AND ("status" = 'booked'::"public"."booking_status"));
CREATE UNIQUE INDEX "clients_email_unique" ON "public"."clients" USING "btree" ("email") WHERE ("email" IS NOT NULL);
CREATE INDEX "expenses_activity_id_idx" ON "public"."expenses" USING "btree" ("activity_id") WHERE ("activity_id" IS NOT NULL);
CREATE INDEX "expenses_category_idx" ON "public"."expenses" USING "btree" ("category");
CREATE INDEX "expenses_event_id_idx" ON "public"."expenses" USING "btree" ("event_id") WHERE ("event_id" IS NOT NULL);
CREATE INDEX "expenses_expense_date_idx" ON "public"."expenses" USING "btree" ("expense_date");
CREATE INDEX "expenses_is_fixed_idx" ON "public"."expenses" USING "btree" ("is_fixed");
CREATE INDEX "expenses_lesson_id_idx" ON "public"."expenses" USING "btree" ("lesson_id") WHERE ("lesson_id" IS NOT NULL);
CREATE INDEX "expenses_operator_id_idx" ON "public"."expenses" USING "btree" ("operator_id") WHERE ("operator_id" IS NOT NULL);
CREATE INDEX "idx_bookings_client" ON "public"."bookings" USING "btree" ("client_id") WHERE ("client_id" IS NOT NULL);
CREATE INDEX "idx_bookings_client_id" ON "public"."bookings" USING "btree" ("client_id") WHERE ("client_id" IS NOT NULL);
CREATE INDEX "idx_bookings_lesson_status" ON "public"."bookings" USING "btree" ("lesson_id", "status");
CREATE INDEX "idx_bookings_user" ON "public"."bookings" USING "btree" ("user_id");
CREATE INDEX "idx_bookings_user_id" ON "public"."bookings" USING "btree" ("user_id") WHERE ("user_id" IS NOT NULL);
CREATE INDEX "idx_clients_deleted_at" ON "public"."clients" USING "btree" ("deleted_at") WHERE ("deleted_at" IS NULL);
CREATE INDEX "idx_clients_email" ON "public"."clients" USING "btree" ("email");
CREATE INDEX "idx_clients_phone" ON "public"."clients" USING "btree" ("phone");
CREATE INDEX "idx_clients_profile_id" ON "public"."clients" USING "btree" ("profile_id");
CREATE INDEX "idx_event_bookings_event" ON "public"."event_bookings" USING "btree" ("event_id");
CREATE INDEX "idx_event_bookings_status" ON "public"."event_bookings" USING "btree" ("status");
CREATE INDEX "idx_event_bookings_user" ON "public"."event_bookings" USING "btree" ("user_id");
CREATE INDEX "idx_events_is_active" ON "public"."events" USING "btree" ("is_active");
CREATE INDEX "idx_events_starts_at" ON "public"."events" USING "btree" ("starts_at");
CREATE INDEX "idx_lessons_assigned_client_id" ON "public"."lessons" USING "btree" ("assigned_client_id") WHERE ("assigned_client_id" IS NOT NULL);
CREATE INDEX "idx_lessons_recurring_series_id" ON "public"."lessons" USING "btree" ("recurring_series_id");
CREATE INDEX "idx_lessons_starts_at" ON "public"."lessons" USING "btree" ("starts_at");
CREATE INDEX "idx_plan_activities_activity" ON "public"."plan_activities" USING "btree" ("activity_id");
CREATE INDEX "idx_plan_activities_activity_id" ON "public"."plan_activities" USING "btree" ("activity_id");
CREATE INDEX "idx_plan_activities_plan" ON "public"."plan_activities" USING "btree" ("plan_id");
CREATE INDEX "idx_plan_activities_plan_id" ON "public"."plan_activities" USING "btree" ("plan_id");
CREATE INDEX "idx_profiles_role" ON "public"."profiles" USING "btree" ("role");
CREATE INDEX "idx_promotions_ends_at" ON "public"."promotions" USING "btree" ("ends_at");
CREATE INDEX "idx_promotions_is_active" ON "public"."promotions" USING "btree" ("is_active");
CREATE INDEX "idx_promotions_starts_at" ON "public"."promotions" USING "btree" ("starts_at");
CREATE INDEX "idx_subscription_usages_booking" ON "public"."subscription_usages" USING "btree" ("booking_id");
CREATE INDEX "idx_subscription_usages_subscription" ON "public"."subscription_usages" USING "btree" ("subscription_id");
CREATE INDEX "idx_subscriptions_client" ON "public"."subscriptions" USING "btree" ("client_id") WHERE ("client_id" IS NOT NULL);
CREATE INDEX "idx_waitlist_lesson" ON "public"."waitlist" USING "btree" ("lesson_id");
CREATE INDEX "payout_rules_month_idx" ON "public"."payout_rules" USING "btree" ("month" DESC);
CREATE INDEX "payouts_month_idx" ON "public"."payouts" USING "btree" ("month" DESC);
CREATE INDEX "payouts_operator_id_idx" ON "public"."payouts" USING "btree" ("operator_id") WHERE ("operator_id" IS NOT NULL);
CREATE INDEX "payouts_status_idx" ON "public"."payouts" USING "btree" ("status");
CREATE OR REPLACE TRIGGER "sync_profile_on_client_change" AFTER INSERT OR UPDATE OF "full_name", "phone", "notes", "email", "profile_id" ON "public"."clients" FOR EACH ROW WHEN (("new"."profile_id" IS NOT NULL)) EXECUTE FUNCTION "public"."sync_profile_from_client"();
CREATE OR REPLACE TRIGGER "trg_link_client_to_profile_by_email" AFTER INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."link_client_to_profile_by_email"();
CREATE OR REPLACE TRIGGER "trigger_auto_create_booking_individual_lesson" AFTER INSERT ON "public"."lessons" FOR EACH ROW WHEN ((("new"."is_individual" = true) AND ("new"."assigned_client_id" IS NOT NULL))) EXECUTE FUNCTION "public"."auto_create_booking_for_individual_lesson"();
CREATE OR REPLACE TRIGGER "trigger_handle_individual_lesson_update" BEFORE UPDATE ON "public"."lessons" FOR EACH ROW WHEN ((("old"."is_individual" IS DISTINCT FROM "new"."is_individual") OR ("old"."assigned_client_id" IS DISTINCT FROM "new"."assigned_client_id"))) EXECUTE FUNCTION "public"."handle_individual_lesson_update"();
CREATE OR REPLACE TRIGGER "update_clients_updated_at" BEFORE UPDATE ON "public"."clients" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
CREATE OR REPLACE TRIGGER "update_event_bookings_updated_at" BEFORE UPDATE ON "public"."event_bookings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
CREATE OR REPLACE TRIGGER "update_events_updated_at" BEFORE UPDATE ON "public"."events" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
CREATE OR REPLACE TRIGGER "update_promotions_updated_at" BEFORE UPDATE ON "public"."promotions" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_subscription_id_fkey" FOREIGN KEY ("subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."event_bookings"
    ADD CONSTRAINT "event_bookings_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."event_bookings"
    ADD CONSTRAINT "event_bookings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id");
ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."events"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_assigned_client_id_fkey" FOREIGN KEY ("assigned_client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."lessons"
    ADD CONSTRAINT "lessons_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."operators"
    ADD CONSTRAINT "operators_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id");
ALTER TABLE ONLY "public"."payout_rules"
    ADD CONSTRAINT "payout_rules_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."payouts"
    ADD CONSTRAINT "payouts_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "public"."operators"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."plan_activities"
    ADD CONSTRAINT "plan_activities_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."plan_activities"
    ADD CONSTRAINT "plan_activities_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id");
ALTER TABLE ONLY "public"."subscription_usages"
    ADD CONSTRAINT "subscription_usages_subscription_id_fkey" FOREIGN KEY ("subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."plans"("id");
ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."waitlist"
    ADD CONSTRAINT "waitlist_lesson_id_fkey" FOREIGN KEY ("lesson_id") REFERENCES "public"."lessons"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."waitlist"
    ADD CONSTRAINT "waitlist_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
COMMENT ON FUNCTION "public"."book_lesson"("p_lesson_id" "uuid", "p_subscription_id" "uuid") IS 'Client booking RPC. Supports individual lessons (client_id) and public lessons (user_id).';
COMMENT ON COLUMN "public"."profiles"."role" IS 'Ruolo dell''utente: user (cliente), operator (staff), admin (amministratore)';
COMMENT ON FUNCTION "public"."get_my_client_id"() IS 'Returns the client_id linked to the current authenticated user via clients.profile_id.';
COMMENT ON FUNCTION "public"."handle_new_user"() IS 'Crea automaticamente un profilo quando viene creato un nuovo utente Auth. Se esiste un client con la stessa email, sincronizza i dati (full_name, phone, notes) e collega il client al profilo.';
COMMENT ON FUNCTION "public"."is_admin"() IS 'Verifica se l''utente corrente è admin';
COMMENT ON FUNCTION "public"."is_staff"() IS 'Verifica se l''utente corrente è staff (operator o admin)';
COMMENT ON FUNCTION "public"."staff_book_lesson"("p_lesson_id" "uuid", "p_client_id" "uuid", "p_subscription_id" "uuid") IS 'Prenota una lezione per un cliente (staff only). Supporta sia subscriptions collegate a client_id che a user_id (quando il cliente ha un account). Blocca prenotazioni su lezioni individuali per clienti non assegnati.';
COMMENT ON FUNCTION "public"."staff_update_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status") IS 'Permette allo staff di aggiornare lo stato di una prenotazione. Per le cancellazioni, si raccomanda di usare cancel_booking o staff_cancel_booking per garantire la corretta gestione degli ingressi.';
COMMENT ON FUNCTION "public"."sync_profile_from_client"() IS 'Sincronizza i dati da clients a profiles quando viene creato o aggiornato un client con un profile_id.';
COMMENT ON COLUMN "public"."activities"."deleted_at" IS 'Data e ora di archiviazione dell''attività. NULL se l''attività non è archiviata.';
COMMENT ON COLUMN "public"."activities"."color" IS 'Colore dell''attività selezionato dalla palette disponibile (turquoise, magenta, orange, purple, darkBlue, cyan, darkGreen, oliveGreen, lightGreen, brown, primaryGreen). NULL se non specificato.';
COMMENT ON TABLE "public"."event_bookings" IS 'Prenotazioni per eventi esterni';
COMMENT ON TABLE "public"."events" IS 'Eventi esterni (Eventbrite, ecc.) con link per registrazione';
COMMENT ON COLUMN "public"."events"."image_url" IS 'URL dell''immagine dell''evento';
COMMENT ON COLUMN "public"."events"."link" IS 'URL esterno per registrazione/partecipazione all''evento';
COMMENT ON COLUMN "public"."events"."is_active" IS 'Se false, l''evento non viene mostrato (anche se è futuro)';
COMMENT ON COLUMN "public"."events"."deleted_at" IS 'Data di cancellazione soft delete (null = attivo)';
COMMENT ON COLUMN "public"."lessons"."deleted_at" IS 'Data di cancellazione soft delete (null = attivo)';
COMMENT ON COLUMN "public"."lessons"."is_individual" IS 'Se true, questa è una lezione individuale/privata assegnata a un cliente specifico';
COMMENT ON COLUMN "public"."lessons"."assigned_client_id" IS 'Cliente assegnato alla lezione individuale. Deve essere null se is_individual=false, e non null se is_individual=true';
COMMENT ON COLUMN "public"."plans"."deleted_at" IS 'Data di cancellazione soft delete (null = attivo)';
COMMENT ON TABLE "public"."promotions" IS 'Promozioni e offerte speciali con link per dettagli/acquisto';
COMMENT ON COLUMN "public"."promotions"."image_url" IS 'URL dell''immagine della promozione';
COMMENT ON COLUMN "public"."promotions"."link" IS 'URL interno (es. piano) o esterno per la promozione';
COMMENT ON COLUMN "public"."promotions"."ends_at" IS 'Se null, la promozione non ha data di scadenza';
COMMENT ON COLUMN "public"."promotions"."is_active" IS 'Se false, la promozione non viene mostrata';
COMMENT ON COLUMN "public"."promotions"."deleted_at" IS 'Data di cancellazione soft delete (null = attivo)';
COMMENT ON POLICY "bookings update own or staff" ON "public"."bookings" IS 'Permette agli utenti di aggiornare le proprie prenotazioni, allo staff di aggiornare qualsiasi prenotazione, e ai clienti di aggiornare prenotazioni collegate al loro client_id tramite profile_id.';
