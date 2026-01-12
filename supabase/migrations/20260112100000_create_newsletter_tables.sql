-- Migration: Create newsletter tables for email campaigns
--
-- Obiettivo: Permettere allo staff di creare e inviare newsletter ai clienti
-- con tracking di aperture, click e bounce via Resend webhooks.

-- ============================================================================
-- 1. CREATE ENUMS
-- ============================================================================

CREATE TYPE "public"."newsletter_campaign_status" AS ENUM (
    'draft',
    'scheduled',
    'sending',
    'sent',
    'failed'
);
ALTER TYPE "public"."newsletter_campaign_status" OWNER TO "postgres";

CREATE TYPE "public"."newsletter_email_status" AS ENUM (
    'pending',
    'sent',
    'delivered',
    'opened',
    'clicked',
    'bounced',
    'complained',
    'failed'
);
ALTER TYPE "public"."newsletter_email_status" OWNER TO "postgres";

CREATE TYPE "public"."newsletter_event_type" AS ENUM (
    'delivered',
    'opened',
    'clicked',
    'bounced',
    'complained'
);
ALTER TYPE "public"."newsletter_event_type" OWNER TO "postgres";

-- ============================================================================
-- 2. CREATE newsletter_templates TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."newsletter_templates" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "subject_template" "text" NOT NULL,
    "content_html_template" "text" NOT NULL,
    "content_text_template" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."newsletter_templates" OWNER TO "postgres";

ALTER TABLE "public"."newsletter_templates" ADD CONSTRAINT "newsletter_templates_pkey" PRIMARY KEY ("id");

-- ============================================================================
-- 3. CREATE newsletter_campaigns TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."newsletter_campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "subject" "text" NOT NULL,
    "content_html" "text" NOT NULL,
    "content_text" "text",
    "template_id" "text",
    "status" "public"."newsletter_campaign_status" DEFAULT 'draft'::"public"."newsletter_campaign_status" NOT NULL,
    "scheduled_at" timestamp with time zone,
    "sent_at" timestamp with time zone,
    "recipient_count" integer DEFAULT 0 NOT NULL,
    "delivered_count" integer DEFAULT 0 NOT NULL,
    "opened_count" integer DEFAULT 0 NOT NULL,
    "clicked_count" integer DEFAULT 0 NOT NULL,
    "bounced_count" integer DEFAULT 0 NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone
);
ALTER TABLE "public"."newsletter_campaigns" OWNER TO "postgres";

ALTER TABLE "public"."newsletter_campaigns" ADD CONSTRAINT "newsletter_campaigns_pkey" PRIMARY KEY ("id");

-- ============================================================================
-- 4. CREATE newsletter_emails TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."newsletter_emails" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "email_address" "text" NOT NULL,
    "client_name" "text" NOT NULL,
    "resend_id" "text",
    "status" "public"."newsletter_email_status" DEFAULT 'pending'::"public"."newsletter_email_status" NOT NULL,
    "sent_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "opened_at" timestamp with time zone,
    "clicked_at" timestamp with time zone,
    "bounced_at" timestamp with time zone,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."newsletter_emails" OWNER TO "postgres";

ALTER TABLE "public"."newsletter_emails" ADD CONSTRAINT "newsletter_emails_pkey" PRIMARY KEY ("id");

-- Unique constraint: one email per campaign per client
ALTER TABLE "public"."newsletter_emails"
    ADD CONSTRAINT "newsletter_emails_campaign_client_unique" UNIQUE ("campaign_id", "client_id");

-- ============================================================================
-- 5. CREATE newsletter_tracking_events TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS "public"."newsletter_tracking_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email_id" "uuid" NOT NULL,
    "event_type" "public"."newsletter_event_type" NOT NULL,
    "event_data" "jsonb",
    "occurred_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."newsletter_tracking_events" OWNER TO "postgres";

ALTER TABLE "public"."newsletter_tracking_events" ADD CONSTRAINT "newsletter_tracking_events_pkey" PRIMARY KEY ("id");

-- ============================================================================
-- 6. INDEXES
-- ============================================================================

-- Campaigns
CREATE INDEX "idx_newsletter_campaigns_status" ON "public"."newsletter_campaigns" ("status");
CREATE INDEX "idx_newsletter_campaigns_created_at" ON "public"."newsletter_campaigns" ("created_at" DESC);
CREATE INDEX "idx_newsletter_campaigns_deleted_at" ON "public"."newsletter_campaigns" ("deleted_at") WHERE "deleted_at" IS NULL;

-- Emails
CREATE INDEX "idx_newsletter_emails_campaign_id" ON "public"."newsletter_emails" ("campaign_id");
CREATE INDEX "idx_newsletter_emails_client_id" ON "public"."newsletter_emails" ("client_id");
CREATE INDEX "idx_newsletter_emails_status" ON "public"."newsletter_emails" ("status");
CREATE INDEX "idx_newsletter_emails_resend_id" ON "public"."newsletter_emails" ("resend_id") WHERE "resend_id" IS NOT NULL;

-- Tracking events
CREATE INDEX "idx_newsletter_tracking_events_email_id" ON "public"."newsletter_tracking_events" ("email_id");
CREATE INDEX "idx_newsletter_tracking_events_type" ON "public"."newsletter_tracking_events" ("event_type");

-- ============================================================================
-- 7. FOREIGN KEYS
-- ============================================================================

ALTER TABLE "public"."newsletter_campaigns"
    ADD CONSTRAINT "newsletter_campaigns_template_id_fkey"
    FOREIGN KEY ("template_id")
    REFERENCES "public"."newsletter_templates"("id")
    ON DELETE SET NULL;

ALTER TABLE "public"."newsletter_campaigns"
    ADD CONSTRAINT "newsletter_campaigns_created_by_fkey"
    FOREIGN KEY ("created_by")
    REFERENCES "public"."profiles"("id")
    ON DELETE SET NULL;

ALTER TABLE "public"."newsletter_emails"
    ADD CONSTRAINT "newsletter_emails_campaign_id_fkey"
    FOREIGN KEY ("campaign_id")
    REFERENCES "public"."newsletter_campaigns"("id")
    ON DELETE CASCADE;

ALTER TABLE "public"."newsletter_emails"
    ADD CONSTRAINT "newsletter_emails_client_id_fkey"
    FOREIGN KEY ("client_id")
    REFERENCES "public"."clients"("id")
    ON DELETE CASCADE;

ALTER TABLE "public"."newsletter_tracking_events"
    ADD CONSTRAINT "newsletter_tracking_events_email_id_fkey"
    FOREIGN KEY ("email_id")
    REFERENCES "public"."newsletter_emails"("id")
    ON DELETE CASCADE;

-- ============================================================================
-- 8. TRIGGERS FOR updated_at
-- ============================================================================

CREATE TRIGGER "newsletter_templates_updated_at"
    BEFORE UPDATE ON "public"."newsletter_templates"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."update_updated_at_column"();

CREATE TRIGGER "newsletter_campaigns_updated_at"
    BEFORE UPDATE ON "public"."newsletter_campaigns"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."update_updated_at_column"();

-- ============================================================================
-- 9. ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE "public"."newsletter_templates" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."newsletter_campaigns" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."newsletter_emails" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."newsletter_tracking_events" ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 10. RLS POLICIES
-- ============================================================================

-- Templates: Staff can read, admin can manage
CREATE POLICY "newsletter_templates_select_staff"
ON "public"."newsletter_templates"
FOR SELECT
TO "authenticated"
USING ("public"."is_staff"());

CREATE POLICY "newsletter_templates_all_admin"
ON "public"."newsletter_templates"
FOR ALL
TO "authenticated"
USING ("public"."is_admin"())
WITH CHECK ("public"."is_admin"());

-- Campaigns: Staff can manage (excluding soft-deleted for non-admin)
CREATE POLICY "newsletter_campaigns_select_staff"
ON "public"."newsletter_campaigns"
FOR SELECT
TO "authenticated"
USING (
    "public"."is_staff"()
    AND ("deleted_at" IS NULL OR "public"."is_admin"())
);

CREATE POLICY "newsletter_campaigns_insert_staff"
ON "public"."newsletter_campaigns"
FOR INSERT
TO "authenticated"
WITH CHECK ("public"."is_staff"());

CREATE POLICY "newsletter_campaigns_update_staff"
ON "public"."newsletter_campaigns"
FOR UPDATE
TO "authenticated"
USING ("public"."is_staff"())
WITH CHECK ("public"."is_staff"());

CREATE POLICY "newsletter_campaigns_delete_staff"
ON "public"."newsletter_campaigns"
FOR DELETE
TO "authenticated"
USING ("public"."is_staff"());

-- Emails: Staff can read
CREATE POLICY "newsletter_emails_select_staff"
ON "public"."newsletter_emails"
FOR SELECT
TO "authenticated"
USING ("public"."is_staff"());

-- Emails: Service role can insert/update (for Edge Functions)
CREATE POLICY "newsletter_emails_insert_service"
ON "public"."newsletter_emails"
FOR INSERT
TO "service_role"
WITH CHECK (true);

CREATE POLICY "newsletter_emails_update_service"
ON "public"."newsletter_emails"
FOR UPDATE
TO "service_role"
USING (true)
WITH CHECK (true);

-- Tracking events: Staff can read
CREATE POLICY "newsletter_tracking_events_select_staff"
ON "public"."newsletter_tracking_events"
FOR SELECT
TO "authenticated"
USING ("public"."is_staff"());

-- Tracking events: Service role can insert (for webhooks)
CREATE POLICY "newsletter_tracking_events_insert_service"
ON "public"."newsletter_tracking_events"
FOR INSERT
TO "service_role"
WITH CHECK (true);

-- ============================================================================
-- 11. SEED DEFAULT TEMPLATES
-- ============================================================================

INSERT INTO "public"."newsletter_templates" ("id", "name", "description", "subject_template", "content_html_template", "content_text_template") VALUES
(
    'new_lesson',
    'Nuova Lezione',
    'Annuncio di una nuova attivita o lezione',
    'Novita: {{activity_name}}',
    '<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: "Jost", Arial, sans-serif; line-height: 1.6; color: #0F2D3B; margin: 0; padding: 20px; }
        .container { max-width: 600px; margin: 0 auto; }
        h1 { color: #036257; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Nuova Attivita!</h1>
        <p>Caro/a {{client_name}},</p>
        <p>Siamo lieti di annunciare una nuova attivita presso Studio Kalos:</p>
        <p><strong>{{activity_name}}</strong></p>
        <p>{{custom_content}}</p>
        <p>Ti aspettiamo!</p>
        <p>Il Team di Studio Kalos</p>
        <div class="footer">
            <p>Studio Kalos - Via Example 123, Milano</p>
        </div>
    </div>
</body>
</html>',
    'Caro/a {{client_name}},

Siamo lieti di annunciare una nuova attivita presso Studio Kalos:

{{activity_name}}

{{custom_content}}

Ti aspettiamo!

Il Team di Studio Kalos'
),
(
    'promotion',
    'Promozione',
    'Offerte e sconti speciali',
    'Offerta Speciale per te!',
    '<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: "Jost", Arial, sans-serif; line-height: 1.6; color: #0F2D3B; margin: 0; padding: 20px; }
        .container { max-width: 600px; margin: 0 auto; }
        h1 { color: #036257; }
        .highlight { background-color: #FFC300; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Offerta Esclusiva</h1>
        <p>Caro/a {{client_name}},</p>
        <p>Abbiamo una promozione speciale riservata a te:</p>
        <div class="highlight">
            {{custom_content}}
        </div>
        <p>Non perdere questa occasione!</p>
        <p>Il Team di Studio Kalos</p>
        <div class="footer">
            <p>Studio Kalos - Via Example 123, Milano</p>
        </div>
    </div>
</body>
</html>',
    'Caro/a {{client_name}},

Abbiamo una promozione speciale riservata a te:

{{custom_content}}

Non perdere questa occasione!

Il Team di Studio Kalos'
),
(
    'greeting',
    'Auguri',
    'Messaggi di auguri (festivita, compleanni)',
    'Tanti Auguri da Studio Kalos!',
    '<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: "Jost", Arial, sans-serif; line-height: 1.6; color: #0F2D3B; margin: 0; padding: 20px; }
        .container { max-width: 600px; margin: 0 auto; text-align: center; }
        h1 { color: #A40DAD; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Auguri!</h1>
        <p>Caro/a {{client_name}},</p>
        <p>{{custom_content}}</p>
        <p>Con affetto,<br>Il Team di Studio Kalos</p>
        <div class="footer">
            <p>Studio Kalos - Via Example 123, Milano</p>
        </div>
    </div>
</body>
</html>',
    'Caro/a {{client_name}},

{{custom_content}}

Con affetto,
Il Team di Studio Kalos'
),
(
    'custom',
    'Personalizzato',
    'Template vuoto per contenuti completamente personalizzati',
    '{{subject}}',
    '<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: "Jost", Arial, sans-serif; line-height: 1.6; color: #0F2D3B; margin: 0; padding: 20px; }
        .container { max-width: 600px; margin: 0 auto; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        {{content}}
        <div class="footer">
            <p>Studio Kalos - Via Example 123, Milano</p>
        </div>
    </div>
</body>
</html>',
    '{{content}}

--
Studio Kalos'
);

-- ============================================================================
-- 12. COMMENTS
-- ============================================================================

COMMENT ON TABLE "public"."newsletter_templates" IS
'Template predefiniti per le newsletter. I template usano variabili come {{client_name}}, {{custom_content}}, ecc.';

COMMENT ON TABLE "public"."newsletter_campaigns" IS
'Campagne newsletter create dallo staff. Ogni campagna contiene il contenuto email e le statistiche aggregate.';

COMMENT ON TABLE "public"."newsletter_emails" IS
'Singole email inviate come parte di una campagna. Traccia lo stato di ogni email inviata.';

COMMENT ON TABLE "public"."newsletter_tracking_events" IS
'Eventi di tracking ricevuti dai webhook Resend (aperture, click, bounce).';

COMMENT ON COLUMN "public"."newsletter_campaigns"."status" IS
'Stato della campagna: draft (bozza), scheduled (programmata), sending (in invio), sent (inviata), failed (fallita)';

COMMENT ON COLUMN "public"."newsletter_emails"."resend_id" IS
'ID univoco dell email restituito da Resend, usato per tracciare gli eventi webhook';

COMMENT ON COLUMN "public"."newsletter_emails"."status" IS
'Stato dell email: pending, sent, delivered, opened, clicked, bounced, complained, failed';