-- Migration 20260930100600: permessi e pulizia
--
-- Dalla verifica generale del 30/09/2026 (docs/ISSUES.md §3.1 e §6).
--
-- 1. `search_path` fisso su tutte le funzioni SECURITY DEFINER che non l'avevano ancora (regola di
--    ACCESS_MODEL.md): `public, extensions, pg_temp`, cioè quello che già usavano da PostgREST e da
--    pg_cron, ma senza dipendere da chi le chiama.
-- 2. `operators`: il sito e l'app senza accesso non leggono più `engagement_type`, `is_admin` e
--    `profile_id` (rapporto con l'associazione e collegamento all'account: dati interni). Restano
--    nome, ruolo, bio, discipline, foto e ordine. Lo staff legge tutto come prima.
-- 3. `social_connections.access_token` (i token delle pagine Meta) non si legge più dall'API: prima
--    qualsiasi membro dello staff poteva prenderlo e pubblicare come Studio Kalòs. Lo usano solo le
--    edge function del marketing, con la chiave di sistema.
-- 4. Funzioni senza chiamanti (verificato su sito, gestionale, webapp, app ed edge function), alcune
--    aperte a chiunque abbia un account: `register_device_token` (KMP), `get_financial_kpis` e
--    `get_revenue_breakdown` (vecchie Finanze, contavano due volte lo stesso denaro),
--    `set_notification_quiet_hours` e `get_my_notification_settings` (nessun invio guardava la
--    fascia oraria), `get_practice_metrics`, `get_activity_booking_counts` (senza controllo del
--    ruolo), `get_auth_email_stats`.
-- 5. Due indici doppi su `bookings`.
--
-- Compatibilità: nessun consumer chiama le funzioni tolte; i tipi generati le perdono.
--
-- migration-lint:allow revoke — reason: le colonne tolte ad anon su operators non le legge nessun consumer senza accesso (il sito usa le view, l'app seleziona colonne esplicite); access_token di social_connections lo leggono solo le edge function con la chiave di sistema; il gestionale del 30/09 seleziona le colonne senza token

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. search_path fisso
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS fn
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname IN ('public', 'internal')
           AND p.prosecdef
           AND (p.proconfig IS NULL
                OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))
    LOOP
        EXECUTE format('ALTER FUNCTION %s SET search_path = public, extensions, pg_temp', r.fn);
    END LOOP;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. operators: colonne interne chiuse ad anon
-- ─────────────────────────────────────────────────────────────────────────────

REVOKE SELECT ON TABLE "public"."operators" FROM anon;
GRANT SELECT ("id", "name", "role", "bio", "disciplines", "is_active", "created_at", "deleted_at",
              "image_url", "display_order", "is_visible_on_site")
    ON TABLE "public"."operators" TO anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Token delle pagine Meta
-- ─────────────────────────────────────────────────────────────────────────────

REVOKE SELECT ON TABLE "public"."social_connections" FROM authenticated;
GRANT SELECT ("id", "operator_id", "platform", "account_id", "account_name", "page_id", "page_name",
              "instagram_business_id", "instagram_username", "token_expires_at", "permissions",
              "is_active", "last_used_at", "last_error", "created_at", "updated_at", "is_test")
    ON TABLE "public"."social_connections" TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Funzioni senza chiamanti
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS "public"."register_device_token"(text, text, text, text);
DROP FUNCTION IF EXISTS "public"."get_financial_kpis"(date, date);
DROP FUNCTION IF EXISTS "public"."get_revenue_breakdown"(date, date);
DROP FUNCTION IF EXISTS "public"."set_notification_quiet_hours"(boolean, time without time zone, time without time zone);
DROP FUNCTION IF EXISTS "public"."get_my_notification_settings"();
DROP FUNCTION IF EXISTS "public"."get_practice_metrics"();
DROP FUNCTION IF EXISTS "public"."get_activity_booking_counts"();
DROP FUNCTION IF EXISTS "public"."get_auth_email_stats"(uuid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Indici doppi
-- ─────────────────────────────────────────────────────────────────────────────

-- Identici a `bookings_lesson_client_unique` e `idx_bookings_client_id`.
DROP INDEX IF EXISTS "public"."idx_booking_lesson_client_active";
DROP INDEX IF EXISTS "public"."idx_bookings_client";
