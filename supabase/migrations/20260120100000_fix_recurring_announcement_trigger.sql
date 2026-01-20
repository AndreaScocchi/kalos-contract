-- Migration: Fix Recurring Announcement Trigger
--
-- Problema: Gli annunci periodici (is_recurring=true) ricevono una notifica push
-- immediata dal trigger notify_new_announcement(), invece di aspettare la prima
-- occorrenza schedulata (next_occurrence_at).
--
-- Causa: Il trigger notify_new_announcement() non distingue tra annunci normali
-- e annunci periodici. Si attiva su tutti gli INSERT e accoda subito la notifica.
--
-- Soluzione: Modificare il trigger per escludere gli annunci periodici.
-- Gli annunci periodici vengono gestiti dal cron process_recurring_announcements().

-- ============================================================================
-- UPDATE notify_new_announcement() - esclude annunci periodici
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."notify_new_announcement"()
RETURNS trigger
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Invia push solo se:
    -- 1. L'announcement e' attivo
    -- 2. NON e' un annuncio periodico (quelli vengono gestiti dal cron)
    -- scheduled_for = starts_at, cosi' il push parte quando l'annuncio diventa visibile
    IF NEW.is_active = true AND (NEW.is_recurring IS NULL OR NEW.is_recurring = false) THEN
        PERFORM "public"."queue_announcement"(
            NEW.id,
            NEW.title,
            NEW.body,
            NEW.starts_at
        );
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION "public"."notify_new_announcement"() IS
'Trigger function: accoda push quando viene creato un announcement attivo e NON periodico. Gli annunci periodici sono gestiti dal cron process_recurring_announcements().';
