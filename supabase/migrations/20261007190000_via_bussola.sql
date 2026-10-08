-- Migration 20261007190000: via la Bussola (contract v0.3.16)
--
-- La Bussola era una consulenza 1:1 di 15' per i soci in regola (D6, sessione 10): si chiedeva
-- dall'app (`request_bussola`) e lo staff la fissava come lezione individuale da Ascolto → Bussola.
-- Il 07/10/2026 l'utente ha deciso di toglierla con tutta la sua gestione. In produzione non c'era
-- nessuna richiesta, quindi non si perde niente; se nel frattempo ne è arrivata una aperta la
-- migrazione si ferma, invece di cancellarla.
--
--   - `delete_account_data` non annulla più le richieste di Bussola (unica funzione che la toccava,
--     a parte le due della Bussola). Il resto del corpo è quello di produzione al 07/10.
--   - Vanno via `request_bussola`, `cancel_bussola_request`, la tabella `bussola_requests` (con le
--     sue policy, il trigger e gli indici) e il tipo `bussola_request_status`.
--   - Community Pass (spento dalla sessione 3, nessuna app lo usa): via il vantaggio «Bussola
--     inclusa» e il valore `bussola` di `pass_benefit_type`. Un valore di enum non si toglie: il
--     tipo si ricrea uguale senza `bussola`; lo usa solo `pass_tier_benefits.benefit_type`, senza
--     default né indici.
--
-- Non si tocca «Bussola Interiore»: è un'attività passata (cancellata, con le sue lezioni nello
-- storico), non la consulenza. Nemmeno le «Bussole» del brand, che sono i valori.
--
-- Prima di questa migrazione sono stati pubblicati app e gestionale senza la Bussola: nessuna
-- versione online chiama più le funzioni che qui spariscono.
--
-- migration-lint:allow drop-table,drop-type,rename-table — reason: la Bussola è tolta per decisione dell'utente del 07/10/2026; tabella senza righe in produzione (controllato qui sotto), nessun consumer la usa più dal rilascio di app e gestionale; il tipo pass_benefit_type si rinomina solo per ricrearlo senza il valore bussola

-- Una richiesta arrivata dopo il controllo del 07/10 non si cancella in silenzio
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.bussola_requests WHERE status IN ('pending', 'scheduled')) THEN
        RAISE EXCEPTION 'Ci sono richieste di Bussola aperte: decidere cosa farne prima di toglierla';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Eliminazione dell'account senza la Bussola
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.delete_account_data(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_role      public.user_role;
    v_client_id uuid;
    v_lesson_id uuid;
    v_today     text := to_char((now() AT TIME ZONE 'Europe/Rome')::date, 'DD/MM/YYYY');
    v_clients   uuid[] := ARRAY[]::uuid[];
BEGIN
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'USER_NOT_FOUND');
    END IF;

    SELECT role INTO v_role FROM public.profiles WHERE id = p_user_id;
    -- Chi lavora nello studio chiude l'account parlando con un admin: il suo profilo regge lezioni,
    -- compensi, annunci e registri
    IF v_role IS NOT NULL AND v_role <> 'user' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'STAFF_ACCOUNT');
    END IF;

    FOR v_client_id IN SELECT id FROM public.clients WHERE profile_id = p_user_id LOOP
        v_clients := v_clients || v_client_id;

        -- Prenotazioni future: disdette come dall'app (i trigger restituiscono l'ingresso e offrono
        -- il posto a chi è in lista d'attesa). Quelle passate restano: sono presenze e Finanze.
        UPDATE public.bookings b
           SET status = 'canceled'
          FROM public.lessons l
         WHERE l.id = b.lesson_id
           AND b.client_id = v_client_id
           AND b.status = 'booked'
           AND l.starts_at > now();

        -- Iscrizioni a eventi futuri, tranne quelle già pagate: il rimborso lo decide lo staff (D4)
        UPDATE public.event_bookings eb
           SET status = 'canceled'
          FROM public.events e
         WHERE e.id = eb.event_id
           AND eb.client_id = v_client_id
           AND eb.status = 'booked'
           AND e.starts_at > now()
           AND NOT EXISTS (
               SELECT 1 FROM public.transactions t
                WHERE t.event_booking_id = eb.id AND t.status IN ('paid', 'partially_refunded'));

        -- Lista d'attesa: il posto passa a chi viene dopo
        FOR v_lesson_id IN
            UPDATE public.waitlist SET status = 'left'
             WHERE client_id = v_client_id AND status IN ('waiting', 'offered')
            RETURNING lesson_id
        LOOP
            PERFORM "internal"."fill_waitlist_offers"(v_lesson_id);
        END LOOP;

        -- I contenuti personali dell'app
        DELETE FROM public.journal_entries          WHERE client_id = v_client_id;
        DELETE FROM public.practice_user_state      WHERE client_id = v_client_id;
        DELETE FROM public.notification_queue       WHERE client_id = v_client_id;
        DELETE FROM public.notification_reads       WHERE client_id = v_client_id;
        DELETE FROM public.notification_logs        WHERE client_id = v_client_id;
        DELETE FROM public.notification_preferences WHERE client_id = v_client_id;
        DELETE FROM public.notification_settings    WHERE client_id = v_client_id;
        DELETE FROM public.device_tokens            WHERE client_id = v_client_id;

        -- La scheda resta (libro soci, quote, ricevute e incassi la usano), senza i dati che non
        -- servono più. Nome ed email restano: chi torna con la stessa email la ritrova.
        UPDATE public.clients
           SET is_active = false,
               deleted_at = COALESCE(deleted_at, now()),
               phone = NULL,
               birthday = NULL,
               newsletter_subscribed = false
         WHERE id = v_client_id;

        PERFORM "internal"."append_client_staff_note"(
            v_client_id, 'Account dell''app eliminato dalla persona il ' || v_today || '.');

        -- Le segnalazioni restano allo staff, intestate alla scheda
        UPDATE public.bug_reports
           SET created_by_client_id = v_client_id, created_by_user_id = NULL
         WHERE created_by_user_id = p_user_id;

        -- Vecchie iscrizioni agli eventi legate all'utente (prima delle schede): passano alla scheda
        UPDATE public.event_bookings
           SET client_id = v_client_id, user_id = NULL
         WHERE user_id = p_user_id;
    END LOOP;

    -- Senza scheda non c'è a chi intestarle: vanno via con l'account
    DELETE FROM public.bug_reports    WHERE created_by_user_id = p_user_id;
    DELETE FROM public.event_bookings WHERE user_id = p_user_id;

    UPDATE public.profiles
       SET deleted_at = COALESCE(deleted_at, now()),
           full_name = 'Account eliminato',
           phone = NULL,
           avatar_url = NULL,
           notes = NULL
     WHERE id = p_user_id;

    RETURN jsonb_build_object('ok', true, 'client_ids', to_jsonb(v_clients));
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Funzioni, tabella e tipo della Bussola
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS "public"."request_bussola"(timestamp with time zone, "text");
DROP FUNCTION IF EXISTS "public"."cancel_bussola_request"("uuid");

DROP TABLE IF EXISTS "public"."bussola_requests";
DROP TYPE IF EXISTS "public"."bussola_request_status";

-- ---------------------------------------------------------------------------
-- 3. Community Pass: niente più «Bussola inclusa»
-- ---------------------------------------------------------------------------

DELETE FROM "public"."pass_tier_benefits" WHERE "benefit_type" = 'bussola';

ALTER TYPE "public"."pass_benefit_type" RENAME TO "pass_benefit_type_old";

CREATE TYPE "public"."pass_benefit_type" AS ENUM (
    'subscription_discount',  -- sconto % su abbonamenti
    'event_discount',         -- sconto % su eventi/lab
    'community_access',       -- accesso agevolato ai servizi comunità (per lo più informativo)
    'priority_booking',       -- finestra di prenotazione anticipata (futuro)
    'other'                   -- vantaggio descrittivo generico
);

ALTER TABLE "public"."pass_tier_benefits"
    ALTER COLUMN "benefit_type" TYPE "public"."pass_benefit_type"
    USING "benefit_type"::"text"::"public"."pass_benefit_type";

DROP TYPE "public"."pass_benefit_type_old";

COMMENT ON COLUMN "public"."pass_tier_benefits"."benefit_type" IS
    'Tipo di vantaggio: subscription_discount, event_discount, community_access, priority_booking, other.';
