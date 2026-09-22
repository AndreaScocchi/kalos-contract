-- Migration 20260922150100: fix del trigger handle_individual_lesson_update
--
-- Obiettivo: modificare una lezione individuale andava in errore se il cliente assegnato aveva
-- l'account app. Il trigger, in quel caso, cercava la prenotazione anche per bookings.user_id e
-- l'abbonamento per subscriptions_with_remaining.user_id: colonne che non esistono più da quando
-- client_id è l'unica fonte di verità (errore 42703 "column ... does not exist").
--
-- Correzione: si tolgono i rami su user_id e resta la ricerca per client_id, identica a quella che
-- il trigger già usava per i clienti senza account. Il resto della logica non cambia.
--
-- Compatibilità: nessuna modifica di firma; i grant restano quelli della migrazione precedente.

CREATE OR REPLACE FUNCTION "public"."handle_individual_lesson_update"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_subscription_id uuid;
  v_booking_id uuid;
  v_old_booking_id uuid;
  v_subscription_changed boolean;
  v_old_subscription_id uuid;
BEGIN
  -- If lesson is being changed from individual to non-individual, clean up
  IF OLD.is_individual = true AND NEW.is_individual = false THEN
    NEW.assigned_client_id := NULL;
    RETURN NEW;
  END IF;

  -- Track subscription change via assigned_subscription_id
  v_subscription_changed := OLD.assigned_subscription_id IS DISTINCT FROM NEW.assigned_subscription_id;

  -- Validate any explicit assigned_subscription_id against activity
  IF NEW.is_individual = true
     AND NEW.assigned_subscription_id IS NOT NULL
     AND NOT public.subscription_covers_activity(NEW.assigned_subscription_id, NEW.activity_id) THEN
    RAISE EXCEPTION 'SUBSCRIPTION_DISCIPLINE_MISMATCH: subscription % does not cover activity %',
      NEW.assigned_subscription_id, NEW.activity_id
      USING ERRCODE = 'check_violation';
  END IF;

  -- If assigned_client_id is changing on an individual lesson
  IF NEW.is_individual = true AND NEW.assigned_client_id IS NOT NULL THEN
    -- If client changed, cancel old booking and restore usage
    IF OLD.assigned_client_id IS DISTINCT FROM NEW.assigned_client_id AND OLD.assigned_client_id IS NOT NULL THEN
      SELECT id INTO v_old_booking_id
      FROM public.bookings
      WHERE lesson_id = NEW.id
        AND client_id = OLD.assigned_client_id
        AND status IN ('booked', 'attended', 'no_show')
      LIMIT 1;

      IF v_old_booking_id IS NOT NULL THEN
        UPDATE public.bookings
        SET status = 'canceled'
        WHERE id = v_old_booking_id;

        UPDATE public.subscription_usages
        SET delta = +1, reason = 'individual_lesson_client_changed'
        WHERE booking_id = v_old_booking_id
          AND delta = -1
          AND NOT EXISTS (
            SELECT 1 FROM public.subscription_usages
            WHERE booking_id = v_old_booking_id
              AND delta = +1
              AND reason = 'individual_lesson_client_changed'
          );
      END IF;
    END IF;

    -- Check if booking already exists for client (client_id è l'unica fonte di verità)
    SELECT id INTO v_booking_id
    FROM public.bookings
    WHERE lesson_id = NEW.id
      AND client_id = NEW.assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
    LIMIT 1;

    -- If booking exists and assigned_subscription_id changed, update it
    IF v_booking_id IS NOT NULL AND v_subscription_changed THEN
      SELECT subscription_id INTO v_old_subscription_id
      FROM public.bookings
      WHERE id = v_booking_id;

      IF v_old_subscription_id IS NOT NULL THEN
        UPDATE public.subscription_usages
        SET delta = +1, reason = 'individual_lesson_subscription_changed'
        WHERE booking_id = v_booking_id
          AND subscription_id = v_old_subscription_id
          AND delta = -1
          AND NOT EXISTS (
            SELECT 1 FROM public.subscription_usages
            WHERE booking_id = v_booking_id
              AND subscription_id = v_old_subscription_id
              AND delta = +1
              AND reason = 'individual_lesson_subscription_changed'
          );
      END IF;

      -- Priority: use assigned_subscription_id if present (already validated above);
      -- else pick a valid sub that covers the activity
      IF NEW.assigned_subscription_id IS NOT NULL THEN
        v_subscription_id := NEW.assigned_subscription_id;
      ELSE
        SELECT swr.id INTO v_subscription_id
        FROM public.subscriptions_with_remaining swr
        WHERE swr.client_id = NEW.assigned_client_id
          AND swr.status = 'active'
          AND NEW.starts_at::date BETWEEN swr.started_at::date AND swr.expires_at::date
          AND (swr.remaining_entries IS NULL OR swr.remaining_entries > 0)
          AND public.subscription_covers_activity(swr.id, NEW.activity_id)
        ORDER BY swr.expires_at DESC NULLS LAST
        LIMIT 1;
      END IF;

      UPDATE public.bookings
      SET subscription_id = v_subscription_id
      WHERE id = v_booking_id;

      IF v_subscription_id IS NOT NULL THEN
        INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
        VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_subscription_changed')
        ON CONFLICT DO NOTHING;
      END IF;
    ELSIF v_booking_id IS NULL THEN
      -- Create booking if it doesn't exist
      IF NEW.assigned_subscription_id IS NOT NULL THEN
        v_subscription_id := NEW.assigned_subscription_id;
      ELSE
        SELECT swr.id INTO v_subscription_id
        FROM public.subscriptions_with_remaining swr
        WHERE swr.client_id = NEW.assigned_client_id
          AND swr.status = 'active'
          AND NEW.starts_at::date BETWEEN swr.started_at::date AND swr.expires_at::date
          AND (swr.remaining_entries IS NULL OR swr.remaining_entries > 0)
          AND public.subscription_covers_activity(swr.id, NEW.activity_id)
        ORDER BY swr.expires_at DESC NULLS LAST
        LIMIT 1;
      END IF;

      INSERT INTO public.bookings (lesson_id, client_id, subscription_id, status)
      VALUES (NEW.id, NEW.assigned_client_id, v_subscription_id, 'booked')
      RETURNING id INTO v_booking_id;

      IF v_subscription_id IS NOT NULL THEN
        INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
        VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_auto_booking');
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
