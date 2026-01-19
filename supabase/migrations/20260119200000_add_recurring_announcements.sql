-- Add recurring announcement support
-- Allows announcements to be scheduled on a recurring basis (e.g., every Sunday evening)

-- Create enum for recurrence frequency
CREATE TYPE announcement_recurrence_frequency AS ENUM (
  'daily',
  'weekly',
  'biweekly',
  'monthly'
);

-- Add recurring columns to announcements table
ALTER TABLE announcements
ADD COLUMN is_recurring boolean NOT NULL DEFAULT false,
ADD COLUMN recurrence_frequency announcement_recurrence_frequency,
ADD COLUMN recurrence_day_of_week smallint CHECK (recurrence_day_of_week IS NULL OR (recurrence_day_of_week >= 0 AND recurrence_day_of_week <= 6)),
ADD COLUMN recurrence_day_of_month smallint CHECK (recurrence_day_of_month IS NULL OR (recurrence_day_of_month >= 1 AND recurrence_day_of_month <= 31)),
ADD COLUMN recurrence_time time,
ADD COLUMN next_occurrence_at timestamptz,
ADD COLUMN last_sent_at timestamptz;

-- Add comment explaining day_of_week values
COMMENT ON COLUMN announcements.recurrence_day_of_week IS '0=Sunday, 1=Monday, ..., 6=Saturday (JS convention)';

-- Create function to calculate next occurrence
CREATE OR REPLACE FUNCTION calculate_next_announcement_occurrence(
  p_frequency announcement_recurrence_frequency,
  p_day_of_week smallint,
  p_day_of_month smallint,
  p_time time,
  p_from_date timestamptz DEFAULT now()
) RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_next timestamptz;
  v_target_date date;
  v_current_dow smallint;
BEGIN
  -- Get current day of week (0=Sunday in PostgreSQL with extract(dow))
  v_current_dow := extract(dow from p_from_date)::smallint;
  v_target_date := p_from_date::date;

  CASE p_frequency
    WHEN 'daily' THEN
      -- Next occurrence is today at the specified time, or tomorrow if already past
      v_next := v_target_date + p_time;
      IF v_next <= p_from_date THEN
        v_next := v_next + interval '1 day';
      END IF;

    WHEN 'weekly' THEN
      -- Find next occurrence of the target day
      IF p_day_of_week IS NULL THEN
        RETURN NULL;
      END IF;

      -- Calculate days until target day
      IF v_current_dow <= p_day_of_week THEN
        v_target_date := v_target_date + (p_day_of_week - v_current_dow);
      ELSE
        v_target_date := v_target_date + (7 - v_current_dow + p_day_of_week);
      END IF;

      v_next := v_target_date + p_time;
      -- If it's today but already past the time, move to next week
      IF v_next <= p_from_date THEN
        v_next := v_next + interval '7 days';
      END IF;

    WHEN 'biweekly' THEN
      -- Same as weekly but add 2 weeks
      IF p_day_of_week IS NULL THEN
        RETURN NULL;
      END IF;

      IF v_current_dow <= p_day_of_week THEN
        v_target_date := v_target_date + (p_day_of_week - v_current_dow);
      ELSE
        v_target_date := v_target_date + (7 - v_current_dow + p_day_of_week);
      END IF;

      v_next := v_target_date + p_time;
      IF v_next <= p_from_date THEN
        v_next := v_next + interval '14 days';
      END IF;

    WHEN 'monthly' THEN
      -- Find next occurrence of the target day of month
      IF p_day_of_month IS NULL THEN
        RETURN NULL;
      END IF;

      -- Try this month first
      v_target_date := date_trunc('month', v_target_date)::date + (p_day_of_month - 1);

      -- Handle months with fewer days
      IF extract(day from (date_trunc('month', v_target_date) + interval '1 month' - interval '1 day')) < p_day_of_month THEN
        -- Use last day of month
        v_target_date := (date_trunc('month', v_target_date) + interval '1 month' - interval '1 day')::date;
      END IF;

      v_next := v_target_date + p_time;

      IF v_next <= p_from_date THEN
        -- Move to next month
        v_target_date := (date_trunc('month', v_target_date) + interval '1 month')::date + (p_day_of_month - 1);
        IF extract(day from (date_trunc('month', v_target_date) + interval '1 month' - interval '1 day')) < p_day_of_month THEN
          v_target_date := (date_trunc('month', v_target_date) + interval '1 month' - interval '1 day')::date;
        END IF;
        v_next := v_target_date + p_time;
      END IF;

    ELSE
      RETURN NULL;
  END CASE;

  RETURN v_next;
END;
$$;

-- Create function to process recurring announcements (called by cron)
CREATE OR REPLACE FUNCTION process_recurring_announcements()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_announcement record;
  v_now timestamptz := now();
BEGIN
  -- Find recurring announcements that are due
  FOR v_announcement IN
    SELECT *
    FROM announcements
    WHERE is_recurring = true
      AND is_active = true
      AND deleted_at IS NULL
      AND next_occurrence_at IS NOT NULL
      AND next_occurrence_at <= v_now
      AND (ends_at IS NULL OR ends_at > v_now)
  LOOP
    -- Queue push notifications for all clients with active tokens
    INSERT INTO notification_queue (
      client_id,
      category,
      channel,
      title,
      body,
      data,
      scheduled_for,
      status
    )
    SELECT
      c.id,
      'announcement',
      'push',
      v_announcement.title,
      v_announcement.body,
      jsonb_build_object(
        'announcementId', v_announcement.id,
        'category', v_announcement.category,
        'imageUrl', v_announcement.image_url,
        'linkUrl', v_announcement.link_url,
        'linkLabel', v_announcement.link_label
      ),
      v_now,
      'pending'
    FROM clients c
    WHERE c.deleted_at IS NULL
      AND c.is_active = true
      AND EXISTS (
        SELECT 1 FROM device_tokens dt
        WHERE dt.client_id = c.id
          AND dt.is_active = true
      );

    -- Update the announcement's last_sent_at and calculate next occurrence
    UPDATE announcements
    SET
      last_sent_at = v_now,
      next_occurrence_at = calculate_next_announcement_occurrence(
        recurrence_frequency,
        recurrence_day_of_week,
        recurrence_day_of_month,
        recurrence_time,
        v_now + interval '1 minute' -- Add 1 minute to avoid immediate re-trigger
      )
    WHERE id = v_announcement.id;
  END LOOP;
END;
$$;

-- Create trigger to auto-calculate next_occurrence_at on insert/update
CREATE OR REPLACE FUNCTION update_announcement_next_occurrence()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.is_recurring = true AND NEW.recurrence_frequency IS NOT NULL THEN
    NEW.next_occurrence_at := calculate_next_announcement_occurrence(
      NEW.recurrence_frequency,
      NEW.recurrence_day_of_week,
      NEW.recurrence_day_of_month,
      NEW.recurrence_time,
      COALESCE(NEW.starts_at, now())
    );
  ELSE
    NEW.next_occurrence_at := NULL;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER announcements_update_next_occurrence
BEFORE INSERT OR UPDATE ON announcements
FOR EACH ROW
EXECUTE FUNCTION update_announcement_next_occurrence();

-- Add cron job to process recurring announcements every 5 minutes
SELECT cron.schedule(
  'process-recurring-announcements',
  '*/5 * * * *',
  $$SELECT process_recurring_announcements()$$
);
