-- Migration: RPC functions for notification queue management
--
-- Queste funzioni sono chiamate dai cron job per accodare le notifiche.
-- Ogni funzione controlla le condizioni e inserisce in notification_queue.

-- ============================================================================
-- 1. QUEUE LESSON REMINDERS
-- ============================================================================

-- Accoda promemoria lezioni: sera prima (20:00) + 2h prima
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
                ': ' || a.name || ' con ' || COALESCE(o.display_name, 'lo staff'),
            'Preparati per la tua lezione! Ti aspettiamo in studio.',
            jsonb_build_object(
                'lesson_id', l.id,
                'booking_id', b.id,
                'type', 'evening',
                'activity', a.name,
                'operator', o.display_name,
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

-- ============================================================================
-- 2. QUEUE SUBSCRIPTION EXPIRY
-- ============================================================================

-- Accoda notifiche scadenza abbonamento: 7 giorni e 2 giorni prima
CREATE OR REPLACE FUNCTION "public"."queue_subscription_expiry"()
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count_7d integer := 0;
    v_count_2d integer := 0;
    v_today date := CURRENT_DATE;
BEGIN
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
        'Il tuo abbonamento scade il ' || TO_CHAR(s.expires_at, 'DD/MM'),
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
        '7_days', v_count_7d,
        '2_days', v_count_2d
    );
END;
$$;

-- ============================================================================
-- 3. QUEUE LOW ENTRIES
-- ============================================================================

-- Accoda notifica ingressi quasi esauriti (quando rimangono 2)
CREATE OR REPLACE FUNCTION "public"."queue_entries_low"()
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count integer := 0;
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT DISTINCT ON (s.client_id)
        s.client_id,
        'entries_low'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(s.client_id, 'entries_low'),
            'push'::"public"."notification_channel"
        ),
        'Ti restano solo 2 ingressi',
        'Rinnova per continuare ad allenarti senza interruzioni.',
        jsonb_build_object(
            'subscription_id', s.id,
            'plan_name', COALESCE(s.custom_name, p.name),
            'entries_left', 2
        ),
        NOW()
    FROM "public"."subscriptions" s
    JOIN "public"."plans" p ON s.plan_id = p.id
    WHERE s.status = 'active'
      AND s.client_id IS NOT NULL
      -- Has entry-based plan
      AND COALESCE(s.custom_entries, p.entries) IS NOT NULL
      -- Calculate remaining entries = total - used
      AND (
          COALESCE(s.custom_entries, p.entries) -
          COALESCE((
              SELECT COALESCE(SUM(-su.delta), 0)
              FROM "public"."subscription_usages" su
              WHERE su.subscription_id = s.id
          ), 0)
      ) = 2
      -- Not already sent for this subscription
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = s.client_id
            AND nl.data->>'subscription_id' = s.id::text
            AND nl.category = 'entries_low'
      )
    ORDER BY s.client_id, s.expires_at;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;

-- ============================================================================
-- 4. QUEUE RE-ENGAGEMENT
-- ============================================================================

-- Accoda notifiche re-engagement: 4 giorni (solo push) e 7 giorni (push+email)
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
        'Sono passati alcuni giorni - il movimento fa bene al corpo e alla mente!',
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
        'Ci manchi! E'' passata una settimana',
        'Il tuo corpo ti ringraziera se riprendi - guarda le lezioni disponibili!',
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

-- ============================================================================
-- 5. QUEUE BIRTHDAY
-- ============================================================================

-- Accoda auguri di compleanno
CREATE OR REPLACE FUNCTION "public"."queue_birthday"()
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count integer := 0;
    v_today date := CURRENT_DATE;
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        'birthday'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 'birthday'),
            'email'::"public"."notification_channel"
        ),
        'Buon compleanno, ' || COALESCE(SPLIT_PART(c.full_name, ' ', 1), '') || '!',
        'Il team di Studio Kalos ti augura un meraviglioso compleanno!',
        jsonb_build_object(
            'year', EXTRACT(YEAR FROM v_today),
            'client_name', c.full_name
        ),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      AND c.birthday IS NOT NULL
      -- Birthday matches today (month and day)
      AND EXTRACT(MONTH FROM c.birthday) = EXTRACT(MONTH FROM v_today)
      AND EXTRACT(DAY FROM c.birthday) = EXTRACT(DAY FROM v_today)
      -- Not already sent this year
      AND NOT EXISTS (
          SELECT 1 FROM "public"."notification_logs" nl
          WHERE nl.client_id = c.id
            AND nl.category = 'birthday'
            AND (nl.data->>'year')::int = EXTRACT(YEAR FROM v_today)
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;

-- ============================================================================
-- 6. QUEUE MILESTONE
-- ============================================================================

-- Accoda notifica traguardo raggiunto (chiamata da trigger)
CREATE OR REPLACE FUNCTION "public"."queue_milestone"(
    "p_client_id" "uuid",
    "p_milestone" integer
)
RETURNS boolean
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Check if already sent
    IF "public"."milestone_already_sent"(p_client_id, p_milestone) THEN
        RETURN false;
    END IF;

    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    VALUES (
        p_client_id,
        'milestone'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(p_client_id, 'milestone'),
            'push'::"public"."notification_channel"
        ),
        p_milestone || ' lezioni completate!',
        'Stai costruendo un''abitudine fantastica. Continua cosi!',
        jsonb_build_object('milestone', p_milestone),
        NOW()
    );

    RETURN true;
END;
$$;

-- ============================================================================
-- 7. QUEUE FIRST LESSON
-- ============================================================================

-- Accoda celebrazione prima lezione (chiamata da trigger)
CREATE OR REPLACE FUNCTION "public"."queue_first_lesson"("p_client_id" "uuid")
RETURNS boolean
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Check if already sent
    IF EXISTS (
        SELECT 1 FROM "public"."notification_logs"
        WHERE client_id = p_client_id AND category = 'first_lesson'
    ) THEN
        RETURN false;
    END IF;

    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    VALUES (
        p_client_id,
        'first_lesson'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(p_client_id, 'first_lesson'),
            'push'::"public"."notification_channel"
        ),
        'Complimenti per la tua prima lezione!',
        'Il benessere inizia cosi, un passo alla volta.',
        jsonb_build_object('first_lesson', true),
        NOW()
    );

    RETURN true;
END;
$$;

-- ============================================================================
-- 8. QUEUE NEW EVENT
-- ============================================================================

-- Accoda notifica nuovo evento a tutti i clienti attivi
CREATE OR REPLACE FUNCTION "public"."queue_new_event"(
    "p_event_id" "uuid",
    "p_event_name" "text",
    "p_event_date" timestamp with time zone
)
RETURNS json
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_count integer := 0;
BEGIN
    INSERT INTO "public"."notification_queue" (
        client_id, category, channel, title, body, data, scheduled_for
    )
    SELECT
        c.id,
        'new_event'::"public"."notification_category",
        COALESCE(
            "public"."get_notification_channel"(c.id, 'new_event'),
            'email'::"public"."notification_channel"
        ),
        'Nuovo evento: ' || p_event_name,
        TO_CHAR(p_event_date AT TIME ZONE 'Europe/Rome', 'DD/MM alle HH24:MI') ||
            ' - I posti sono limitati, iscriviti ora!',
        jsonb_build_object(
            'event_id', p_event_id,
            'event_name', p_event_name,
            'event_date', p_event_date
        ),
        NOW()
    FROM "public"."clients" c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN json_build_object('queued', v_count);
END;
$$;

-- ============================================================================
-- 9. TRIGGER FOR MILESTONE AND FIRST LESSON
-- ============================================================================

-- Trigger function per controllare milestone quando una booking diventa 'attended'
CREATE OR REPLACE FUNCTION "public"."check_milestone_on_attended"()
RETURNS TRIGGER
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
DECLARE
    v_attended_count integer;
    v_milestones integer[] := ARRAY[10, 25, 50, 100];
    v_milestone integer;
BEGIN
    -- Only trigger when status changes to 'attended'
    IF NEW.status = 'attended' AND (OLD.status IS NULL OR OLD.status != 'attended') THEN
        -- Get attended count for this client
        v_attended_count := "public"."count_attended_lessons"(NEW.client_id);

        -- Check for first lesson
        IF v_attended_count = 1 THEN
            PERFORM "public"."queue_first_lesson"(NEW.client_id);
        END IF;

        -- Check for milestones
        FOREACH v_milestone IN ARRAY v_milestones LOOP
            IF v_attended_count = v_milestone THEN
                PERFORM "public"."queue_milestone"(NEW.client_id, v_milestone);
                EXIT; -- Only one milestone at a time
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

-- Create the trigger
DROP TRIGGER IF EXISTS "bookings_check_milestone" ON "public"."bookings";
CREATE TRIGGER "bookings_check_milestone"
    AFTER UPDATE ON "public"."bookings"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."check_milestone_on_attended"();

-- ============================================================================
-- 10. TRIGGER FOR NEW EVENT
-- ============================================================================

-- Trigger function per notificare nuovi eventi
CREATE OR REPLACE FUNCTION "public"."notify_new_event"()
RETURNS TRIGGER
LANGUAGE "plpgsql"
SECURITY DEFINER
AS $$
BEGIN
    -- Only trigger for new active events
    IF NEW.is_active = true THEN
        PERFORM "public"."queue_new_event"(NEW.id, NEW.name, NEW.starts_at);
    END IF;

    RETURN NEW;
END;
$$;

-- Create the trigger
DROP TRIGGER IF EXISTS "events_notify_new" ON "public"."events";
CREATE TRIGGER "events_notify_new"
    AFTER INSERT ON "public"."events"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."notify_new_event"();

-- ============================================================================
-- 11. COMMENTS
-- ============================================================================

COMMENT ON FUNCTION "public"."queue_lesson_reminders" IS
'Accoda promemoria lezioni: sera prima (20:00) e 2h prima. Chiamata ogni ora dal cron.';

COMMENT ON FUNCTION "public"."queue_subscription_expiry" IS
'Accoda notifiche scadenza abbonamento: 7 e 2 giorni prima. Chiamata giornalmente.';

COMMENT ON FUNCTION "public"."queue_entries_low" IS
'Accoda notifica ingressi esauriti quando rimangono esattamente 2. Chiamata giornalmente.';

COMMENT ON FUNCTION "public"."queue_re_engagement" IS
'Accoda re-engagement: 4gg (solo push) e 7gg (push+email). Anti-spam integrato.';

COMMENT ON FUNCTION "public"."queue_birthday" IS
'Accoda auguri compleanno. Chiamata giornalmente alle 9:00.';

COMMENT ON FUNCTION "public"."queue_milestone" IS
'Accoda notifica traguardo. Chiamata dal trigger su bookings.';

COMMENT ON FUNCTION "public"."queue_first_lesson" IS
'Accoda celebrazione prima lezione. Chiamata dal trigger su bookings.';

COMMENT ON FUNCTION "public"."queue_new_event" IS
'Accoda notifica nuovo evento a tutti i clienti. Chiamata dal trigger su events.';
