-- Migration 20260930120000: «Ci manchi!» di nuovo ogni mese
--
-- Decisione dell'utente del 30/09/2026: il promemoria per chi non viene da un po' deve ripetersi
-- ogni 30 giorni finché la persona non torna, come prima della migrazione 20260930100000 (che lo
-- mandava una volta sola per assenza e mai oltre 60 giorni).
--
-- Resta tutto il resto della 20260930100000: il canale segue le preferenze e l'indirizzo (niente
-- email a chi non ce l'ha o l'ha spenta), e il controllo dei 30 giorni guarda anche le righe già in
-- coda o saltate, così un invio saltato non si riaccoda ogni giorno.
--
-- Compatibilità: stessa firma.

CREATE OR REPLACE FUNCTION "internal"."can_send_re_engagement"(p_client_id uuid, p_days integer DEFAULT 7)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_last_lesson timestamptz;
BEGIN
    -- Chi ha già una lezione in programma sta tornando.
    IF EXISTS (
        SELECT 1
          FROM "public"."bookings" b
          JOIN "public"."lessons" l ON l.id = b.lesson_id
         WHERE b.client_id = p_client_id
           AND b.status = 'booked'
           AND l.deleted_at IS NULL
           AND l.starts_at > now()
    ) THEN
        RETURN false;
    END IF;

    SELECT max(l.starts_at) INTO v_last_lesson
      FROM "public"."bookings" b
      JOIN "public"."lessons" l ON l.id = b.lesson_id
     WHERE b.client_id = p_client_id
       AND b.status IN ('booked', 'attended')
       AND l.starts_at < now();

    -- Mai venutə, oppure non ancora abbastanza giorni dall'ultima lezione.
    IF v_last_lesson IS NULL OR v_last_lesson > now() - make_interval(days => p_days) THEN
        RETURN false;
    END IF;

    -- Al massimo uno ogni 30 giorni per tipo (4 o 7 giorni), finché la persona non torna.
    RETURN NOT "internal"."notification_exists"(
        p_client_id, 're_engagement', jsonb_build_object('days', p_days), now() - interval '30 days'
    );
END;
$$;
