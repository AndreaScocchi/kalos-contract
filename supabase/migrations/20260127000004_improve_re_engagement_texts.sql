-- Migration: Improve re-engagement notification texts
--
-- Rende i testi più motivazionali e neutri (maschile/femminile)

CREATE OR REPLACE FUNCTION "public"."queue_re_engagement"()
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count_4d integer := 0;
    v_count_7d integer := 0;
BEGIN
    -- 4 days re-engagement (push only)
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        're_engagement'::"public"."notification_category",
        'push'::"public"."notification_channel",
        'Ti aspettiamo!',
        'Ti va di riprendere? Ti aspettiamo in studio!',
        jsonb_build_object(
            'days', 4,
            'last_booking_date', (
                SELECT MAX(l.starts_at)
                FROM "public"."bookings" b
                JOIN "public"."lessons" l ON b.lesson_id = l.id
                WHERE b.client_id = c.id AND b.status IN ('booked', 'attended')
            )::text
        ),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      -- Has push token (required for this notification)
      AND "public"."client_has_active_push_tokens"(c.id)
      -- Passes anti-spam check for 4 days
      AND "public"."can_send_re_engagement"(c.id, 4);

    GET DIAGNOSTICS v_count_4d = ROW_COUNT;

    -- 7 days re-engagement (push + email)
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        're_engagement'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 're_engagement'),
            'email'::"public"."notification_channel"
        ),
        'Ci manchi!',
        'Riprendi da dove hai lasciato - scopri le lezioni della settimana!',
        jsonb_build_object(
            'days', 7,
            'last_booking_date', (
                SELECT MAX(l.starts_at)
                FROM "public"."bookings" b
                JOIN "public"."lessons" l ON b.lesson_id = l.id
                WHERE b.client_id = c.id AND b.status IN ('booked', 'attended')
            )::text
        ),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      -- Passes anti-spam check for 7 days
      AND "public"."can_send_re_engagement"(c.id, 7);

    GET DIAGNOSTICS v_count_7d = ROW_COUNT;

    RETURN json_build_object(
        '4_days', v_count_4d,
        '7_days', v_count_7d
    );
END;
$$;

COMMENT ON FUNCTION "public"."queue_re_engagement" IS
'Accoda re-engagement: 4gg (solo push) e 7gg (push+email). Anti-spam integrato.';
