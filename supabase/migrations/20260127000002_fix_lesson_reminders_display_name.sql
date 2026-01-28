-- Migration: Fix queue_lesson_reminders - replace display_name with name
--
-- Problema: La funzione usa o.display_name ma la colonna non esiste
-- nella tabella operators. La colonna corretta è o.name.

CREATE OR REPLACE FUNCTION "public"."queue_lesson_reminders"()
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count_evening integer := 0;
    v_count_2h integer := 0;
    v_now timestamp with time zone := NOW();
    v_today_8pm timestamp with time zone;
    v_tomorrow date;
BEGIN
    -- Calculate today at 20:00 Rome time
    v_today_8pm := DATE_TRUNC('day', v_now AT TIME ZONE 'Europe/Rome') + INTERVAL '20 hours';
    v_today_8pm := v_today_8pm AT TIME ZONE 'Europe/Rome';
    v_tomorrow := (v_now AT TIME ZONE 'Europe/Rome')::date + 1;

    -- Evening reminder: lessons tomorrow, schedule for 20:00 today
    -- Only queue if it's before 20:00
    IF v_now < v_today_8pm THEN
        INSERT INTO "public"."notification_queue" (
            client_id, category, channel, title, body, data, scheduled_for
        )
        SELECT
            b.client_id,
            'lesson_reminder'::"public"."notification_category",
            COALESCE(
                "public"."get_notification_channel"(b.client_id, 'lesson_reminder'),
                'email'::"public"."notification_channel"
            ),
            'Domani alle ' || TO_CHAR(l.starts_at AT TIME ZONE 'Europe/Rome', 'HH24:MI') ||
                ': ' || a.name || ' con ' || COALESCE(o.name, 'lo staff'),
            'Preparati per la tua lezione! Ti aspettiamo in studio.',
            jsonb_build_object(
                'lesson_id', l.id,
                'booking_id', b.id,
                'type', 'evening',
                'activity', a.name,
                'operator', o.name,
                'starts_at', l.starts_at
            ),
            v_today_8pm
        FROM "public"."bookings" b
        JOIN "public"."lessons" l ON b.lesson_id = l.id
        JOIN "public"."activities" a ON l.activity_id = a.id
        LEFT JOIN "public"."operators" o ON l.operator_id = o.id
        WHERE b.status = 'booked'
          AND b.client_id IS NOT NULL
          AND (l.starts_at AT TIME ZONE 'Europe/Rome')::date = v_tomorrow
          -- Not already queued for this booking
          AND NOT EXISTS (
              SELECT 1 FROM "public"."notification_queue" nq
              WHERE nq.client_id = b.client_id
                AND nq.data->>'booking_id' = b.id::text
                AND nq.category = 'lesson_reminder'
                AND nq.data->>'type' = 'evening'
          )
          -- Not already sent for this booking
          AND NOT EXISTS (
              SELECT 1 FROM "public"."notification_logs" nl
              WHERE nl.client_id = b.client_id
                AND nl.data->>'booking_id' = b.id::text
                AND nl.category = 'lesson_reminder'
                AND nl.data->>'type' = 'evening'
          );

        GET DIAGNOSTICS v_count_evening = ROW_COUNT;
    END IF;

    -- 2h reminder: lessons starting in 2-3 hours from now
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        b.client_id,
        'lesson_reminder'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(b.client_id, 'lesson_reminder'),
            'push'::"public"."notification_channel"  -- Default to push for 2h reminder
        ),
        'La tua lezione inizia tra 2 ore',
        a.name || ' alle ' || TO_CHAR(l.starts_at AT TIME ZONE 'Europe/Rome', 'HH24:MI') ||
            ' - ci vediamo presto!',
        jsonb_build_object(
            'lesson_id', l.id,
            'booking_id', b.id,
            'type', '2h',
            'activity', a.name,
            'starts_at', l.starts_at
        ),
        l.starts_at - INTERVAL '2 hours'
    FROM "public"."bookings" b
    JOIN "public"."lessons" l ON b.lesson_id = l.id
    JOIN "public"."activities" a ON l.activity_id = a.id
    WHERE b.status = 'booked'
      AND b.client_id IS NOT NULL
      AND l.starts_at > v_now + INTERVAL '2 hours'
      AND l.starts_at <= v_now + INTERVAL '3 hours'
      -- Not already queued
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_queue" nq
          WHERE nq.client_id = b.client_id
            AND nq.data->>'booking_id' = b.id::text
            AND nq.category = 'lesson_reminder'
            AND nq.data->>'type' = '2h'
      )
      -- Not already sent
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = b.client_id
            AND nl.data->>'booking_id' = b.id::text
            AND nl.category = 'lesson_reminder'
            AND nl.data->>'type' = '2h'
      );

    GET DIAGNOSTICS v_count_2h = ROW_COUNT;

    RETURN json_build_object(
        'evening_reminders', v_count_evening,
        '2h_reminders', v_count_2h,
        'timestamp', v_now
    );
END;
$$;

COMMENT ON FUNCTION "public"."queue_lesson_reminders" IS
'Accoda promemoria lezioni: sera prima (20:00) e 2h prima. Chiamata ogni ora dal cron.';
