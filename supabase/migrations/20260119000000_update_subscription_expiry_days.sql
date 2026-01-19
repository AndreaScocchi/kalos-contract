-- Migration: Update subscription expiry notification days
--
-- Cambia i giorni di notifica scadenza abbonamento da 7/2 a 21/7/2

-- ============================================================================
-- UPDATE QUEUE_SUBSCRIPTION_EXPIRY FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."queue_subscription_expiry"()
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count_21d integer := 0;
    v_count_7d integer := 0;
    v_count_2d integer := 0;
    v_today date := CURRENT_DATE;
BEGIN
    -- 21 days before expiry
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        s.client_id,
        'subscription_expiry'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(s.client_id, 'subscription_expiry'),
            'email'::"public"."notification_channel"
        ),
        'Il tuo abbonamento scade il ' || TO_CHAR(s.expires_at, 'DD/MM'),
        'Hai ancora 3 settimane per rinnovare e continuare il tuo percorso di benessere.',
        jsonb_build_object(
            'subscription_id', s.id,
            'plan_name', COALESCE(s.custom_name, p.name),
            'expires_at', s.expires_at,
            'days_left', 21
        ),
        NOW()
    FROM "public"."subscriptions" s
    JOIN "public"."plans" p ON s.plan_id = p.id
    WHERE s.status = 'active'
      AND s.client_id IS NOT NULL
      AND s.expires_at = v_today + 21
      -- Not already sent
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = s.client_id
            AND nl.data->>'subscription_id' = s.id::text
            AND nl.category = 'subscription_expiry'
            AND (nl.data->>'days_left')::int = 21
      );

    GET DIAGNOSTICS v_count_21d = ROW_COUNT;

    -- 7 days before expiry
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        s.client_id,
        'subscription_expiry'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(s.client_id, 'subscription_expiry'),
            'email'::"public"."notification_channel"
        ),
        'Il tuo abbonamento scade tra una settimana',
        'Rinnova ora per continuare il tuo percorso di benessere.',
        jsonb_build_object(
            'subscription_id', s.id,
            'plan_name', COALESCE(s.custom_name, p.name),
            'expires_at', s.expires_at,
            'days_left', 7
        ),
        NOW()
    FROM "public"."subscriptions" s
    JOIN "public"."plans" p ON s.plan_id = p.id
    WHERE s.status = 'active'
      AND s.client_id IS NOT NULL
      AND s.expires_at = v_today + 7
      -- Not already sent
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = s.client_id
            AND nl.data->>'subscription_id' = s.id::text
            AND nl.category = 'subscription_expiry'
            AND (nl.data->>'days_left')::int = 7
      );

    GET DIAGNOSTICS v_count_7d = ROW_COUNT;

    -- 2 days before expiry
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        s.client_id,
        'subscription_expiry'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(s.client_id, 'subscription_expiry'),
            'email'::"public"."notification_channel"
        ),
        'Ultimi 2 giorni del tuo abbonamento',
        'Non perdere l''accesso alle tue lezioni preferite!',
        jsonb_build_object(
            'subscription_id', s.id,
            'plan_name', COALESCE(s.custom_name, p.name),
            'expires_at', s.expires_at,
            'days_left', 2
        ),
        NOW()
    FROM "public"."subscriptions" s
    JOIN "public"."plans" p ON s.plan_id = p.id
    WHERE s.status = 'active'
      AND s.client_id IS NOT NULL
      AND s.expires_at = v_today + 2
      -- Not already sent
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = s.client_id
            AND nl.data->>'subscription_id' = s.id::text
            AND nl.category = 'subscription_expiry'
            AND (nl.data->>'days_left')::int = 2
      );

    GET DIAGNOSTICS v_count_2d = ROW_COUNT;

    RETURN json_build_object(
        '21_days', v_count_21d,
        '7_days', v_count_7d,
        '2_days', v_count_2d
    );
END;
$$;

-- Update comment
COMMENT ON FUNCTION "public"."queue_subscription_expiry" IS
'Accoda notifiche scadenza abbonamento: 21, 7 e 2 giorni prima. Chiamata giornalmente.';
