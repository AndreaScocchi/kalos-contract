-- Migration 20261022170000: le operatrici in tutte le sezioni del gestionale
--
-- Richiesta dell'utente del 22/10/2026: «anche gli operatori devono avere accesso a tutte le
-- sezioni del gestionale». Fino a oggi le operatrici (ruolo `operator`) non vedevano Finanze,
-- rimborsi ai volontari, Marketing, Annunci e Segnalazioni, e nelle altre sezioni non potevano
-- annullare o rimborsare incassi, esonerare dalla quota, scegliere la voce del rendiconto.
-- Scelta dell'utente: tutte le sezioni con le azioni che contengono, per tutto il ruolo
-- (anche chi diventerà operatrice dopo). Nelle Finanze ognunə vede anche compensi e ritenute
-- di tuttə: detto all'utente, che ha confermato.
--
--   - `can_access_finance()` risponde vero per tutto lo staff (operator, admin, finance), come
--     `is_staff()`. Finanze, rimborsi ai volontari, annulli e rimborsi degli incassi, esoneri,
--     pagamenti con carta e i bucket `documenti-spese` ed `estratti-conto` passano tutti da qui:
--     policy, RPC ed edge function (`stripe-reconcile`) seguono senza altre modifiche. Il nome
--     resta, perché lo chiamano decine di policy e funzioni e l'edge function.
--   - Segnalazioni (`bug_reports`): lettura, modifica e cancellazione per tutto lo staff
--     (`is_staff()` al posto di `is_admin()`). Gli screenshot nel bucket `bug-reports` hanno le loro
--     policy in `supabase/storage/bug-reports.sql`, aggiornato nello stesso rilascio.
--   - Marketing e Annunci erano già aperti a tutto lo staff nel database (`is_staff()`): li
--     chiudeva solo il gestionale.
--
-- Restano solo all'admin (`is_admin()`), sempre per scelta dell'utente: le schede dello staff
-- (creare, modificare, eliminare), i ruoli (`promote_profile_to_operator`,
-- `guard_profile_privileged_columns`), i dati dell'associazione (`association_settings`), importo e
-- scadenza della quota (`association_years`), gli interruttori (`feature_flags`).
--
-- `is_finance()` (solo il ruolo `finance`) resta com'è: nessuna policy o funzione la usa.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Finanze per tutto lo staff
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."can_access_finance"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    return exists (
        select 1 from public.profiles
        where id = auth.uid()
        and role in ('operator', 'admin', 'finance')
    );
end;
$$;

COMMENT ON FUNCTION "public"."can_access_finance"() IS
    'Finanze e azioni sui soldi (annulli, rimborsi, esoneri). Dal 22/10/2026 tutto lo staff: operator, admin, finance.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Segnalazioni per tutto lo staff
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "bug_reports_select_own_or_admin" ON "public"."bug_reports";
DROP POLICY IF EXISTS "bug_reports_update_admin" ON "public"."bug_reports";
DROP POLICY IF EXISTS "bug_reports_delete_admin" ON "public"."bug_reports";

CREATE POLICY "bug_reports_select_own_or_staff" ON "public"."bug_reports"
    FOR SELECT TO "authenticated"
    USING ("public"."is_staff"() OR (("deleted_at" IS NULL) AND ("created_by_user_id" = "auth"."uid"()) AND ("created_by_client_id" IS NULL)));

CREATE POLICY "bug_reports_update_staff" ON "public"."bug_reports"
    FOR UPDATE TO "authenticated"
    USING ("public"."is_staff"()) WITH CHECK ("public"."is_staff"());

CREATE POLICY "bug_reports_delete_staff" ON "public"."bug_reports"
    FOR DELETE TO "authenticated"
    USING ("public"."is_staff"());

COMMENT ON TABLE "public"."bug_reports" IS
    'Segnalazioni di clienti e staff. Chi segnala vede le proprie; lo staff le vede e le gestisce tutte (dal 22/10/2026, prima solo gli admin).';
