-- Migration 20260930100500: funzioni per il gestionale (piani e lezioni archiviate)
--
-- Dalla verifica generale del 30/09/2026 (docs/ISSUES.md §3.2).
--
-- 1. `staff_save_plan`: piano e attività in una transazione sola. Prima il gestionale salvava il
--    piano e poi, in una seconda chiamata, cancellava e reinseriva le attività: un errore a metà
--    lasciava un piano senza attività, cioè valido per TUTTE (book_lesson). Almeno un'attività è
--    obbligatoria (decisione del 29/09).
-- 2. `staff_archive_lessons`: archiviare lezioni future con delle prenotazioni prima le lasciava
--    «prenotate» su una lezione sparita, senza restituire l'ingresso né avvisare nessuno (e i
--    promemoria saltavano la lezione archiviata). Ora, per ogni lezione futura: la lista d'attesa si
--    chiude senza offrire posti, le prenotazioni si disdicono (l'ingresso torna all'abbonamento con
--    il trigger di sempre), chi era prenotatə riceve «Lezione annullata», e la lezione si archivia.
--    Una lezione passata con prenotazioni o presenze non si archivia da qui (cambierebbe ingressi e
--    compensi senza dirlo): la funzione la salta e lo dice.
--
-- Compatibilità: due funzioni nuove, aperte solo ad `authenticated` e controllate dentro con
-- `is_staff()`; nessuna modifica a tabelle.
--
-- migration-lint:allow revoke — reason: le REVOKE riguardano solo le due funzioni nuove di questa migrazione (chiuse ad anon)

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Piano con le sue attività
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_save_plan"(
    p_plan_id uuid,
    p_plan jsonb,
    p_activity_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_plan_id uuid := p_plan_id;
    v_activity_ids uuid[];
    v_name text := NULLIF(btrim(COALESCE(p_plan->>'name', '')), '');
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    SELECT COALESCE(array_agg(DISTINCT a.id), '{}') INTO v_activity_ids
      FROM unnest(COALESCE(p_activity_ids, '{}')) x(id)
      JOIN public.activities a ON a.id = x.id AND a.deleted_at IS NULL;

    IF cardinality(v_activity_ids) = 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ACTIVITIES_REQUIRED');
    END IF;
    IF v_name IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NAME_REQUIRED');
    END IF;
    IF (p_plan->>'price_cents') IS NULL OR (p_plan->>'price_cents')::integer < 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_PRICE');
    END IF;
    IF (p_plan->>'validity_days') IS NULL OR (p_plan->>'validity_days')::integer <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_VALIDITY');
    END IF;
    IF (p_plan->>'entries') IS NOT NULL AND (p_plan->>'entries')::integer <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_ENTRIES');
    END IF;

    IF v_plan_id IS NULL THEN
        INSERT INTO public.plans (name, discipline, price_cents, currency, entries, validity_days,
                                  description, is_active, discount_percent, sold_in_app)
        VALUES (v_name,
                NULLIF(btrim(COALESCE(p_plan->>'discipline', '')), ''),
                (p_plan->>'price_cents')::integer,
                COALESCE(NULLIF(p_plan->>'currency', ''), 'EUR'),
                (p_plan->>'entries')::integer,
                (p_plan->>'validity_days')::integer,
                NULLIF(p_plan->>'description', ''),
                COALESCE((p_plan->>'is_active')::boolean, true),
                (p_plan->>'discount_percent')::numeric,
                COALESCE((p_plan->>'sold_in_app')::boolean, false))
        RETURNING id INTO v_plan_id;
    ELSE
        UPDATE public.plans
           SET name = v_name,
               discipline = NULLIF(btrim(COALESCE(p_plan->>'discipline', '')), ''),
               price_cents = (p_plan->>'price_cents')::integer,
               currency = COALESCE(NULLIF(p_plan->>'currency', ''), currency),
               entries = (p_plan->>'entries')::integer,
               validity_days = (p_plan->>'validity_days')::integer,
               description = NULLIF(p_plan->>'description', ''),
               is_active = COALESCE((p_plan->>'is_active')::boolean, is_active),
               discount_percent = (p_plan->>'discount_percent')::numeric,
               sold_in_app = COALESCE((p_plan->>'sold_in_app')::boolean, sold_in_app)
         WHERE id = v_plan_id AND deleted_at IS NULL;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'PLAN_NOT_FOUND');
        END IF;
    END IF;

    DELETE FROM public.plan_activities
     WHERE plan_id = v_plan_id AND NOT (activity_id = ANY (v_activity_ids));
    INSERT INTO public.plan_activities (plan_id, activity_id)
    SELECT v_plan_id, x FROM unnest(v_activity_ids) x
    ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object('ok', true, 'plan_id', v_plan_id);
END;
$$;

COMMENT ON FUNCTION "public"."staff_save_plan"(uuid, jsonb, uuid[]) IS
  'Crea o modifica un piano con le sue attività in una transazione (almeno un''attività). p_plan: name, discipline, price_cents, currency, entries (NULL = illimitato), validity_days, description, is_active, discount_percent, sold_in_app.';

REVOKE ALL ON FUNCTION "public"."staff_save_plan"(uuid, jsonb, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION "public"."staff_save_plan"(uuid, jsonb, uuid[]) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Lezioni archiviate: disdette, ingressi restituiti, avviso
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_archive_lessons"(p_lesson_ids uuid[], p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_lesson record;
    v_booking record;
    v_channel "public"."notification_channel";
    v_archived integer := 0;
    v_canceled integer := 0;
    v_skipped uuid[] := '{}';
    v_when text;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    FOR v_lesson IN
        SELECT l.*, a.name AS activity_name
          FROM public.lessons l
          JOIN public.activities a ON a.id = l.activity_id
         WHERE l.id = ANY (COALESCE(p_lesson_ids, '{}'))
           AND l.deleted_at IS NULL
         ORDER BY l.starts_at
           FOR UPDATE OF l
    LOOP
        IF v_lesson.starts_at <= now() THEN
            -- Già iniziata: si archivia solo se nessunə era prenotatə o presente.
            IF EXISTS (SELECT 1 FROM public.bookings
                        WHERE lesson_id = v_lesson.id AND status IN ('booked', 'attended', 'no_show')) THEN
                v_skipped := v_skipped || v_lesson.id;
                CONTINUE;
            END IF;
        ELSE
            -- La fila si chiude senza offrire il posto (la lezione non ci sarà).
            UPDATE public.waitlist SET status = 'expired'
             WHERE lesson_id = v_lesson.id AND status IN ('waiting', 'offered');

            v_when := to_char(v_lesson.starts_at AT TIME ZONE 'Europe/Rome', 'DD/MM "alle" HH24:MI');

            FOR v_booking IN
                SELECT b.id, b.client_id FROM public.bookings b
                 WHERE b.lesson_id = v_lesson.id AND b.status = 'booked'
            LOOP
                UPDATE public.bookings SET status = 'canceled' WHERE id = v_booking.id;
                v_canceled := v_canceled + 1;

                IF v_booking.client_id IS NOT NULL THEN
                    v_channel := "internal"."get_notification_channel"(v_booking.client_id, 'lesson_canceled');
                    IF v_channel IS NOT NULL THEN
                        INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
                        VALUES (v_booking.client_id, 'lesson_canceled', v_channel,
                                'Lezione annullata',
                                'La lezione di ' || v_lesson.activity_name || ' del ' || v_when
                                    || ' è stata annullata. L''ingresso è tornato al tuo abbonamento.'
                                    || COALESCE(' ' || NULLIF(btrim(p_reason), ''), ''),
                                jsonb_build_object('lesson_id', v_lesson.id, 'booking_id', v_booking.id,
                                                   'url', '/bookings'),
                                now());
                    END IF;
                END IF;
            END LOOP;
        END IF;

        UPDATE public.lessons SET deleted_at = now() WHERE id = v_lesson.id;
        v_archived := v_archived + 1;
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'archived', v_archived, 'canceled_bookings', v_canceled,
                              'skipped', to_jsonb(v_skipped));
END;
$$;

COMMENT ON FUNCTION "public"."staff_archive_lessons"(uuid[], text) IS
  'Archivia lezioni: per quelle future chiude la lista d''attesa, disdice le prenotazioni (ingressi restituiti) e avvisa con «Lezione annullata»; quelle già iniziate con prenotazioni o presenze le salta (skipped).';

REVOKE ALL ON FUNCTION "public"."staff_archive_lessons"(uuid[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION "public"."staff_archive_lessons"(uuid[], text) TO authenticated, service_role;
