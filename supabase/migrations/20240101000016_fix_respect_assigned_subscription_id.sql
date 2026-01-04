-- Migration 0016: Fix - Respect assigned_subscription_id in Individual Lessons
-- 
-- Problema: Le funzioni che creano automaticamente i booking per le lezioni individuali
-- ignorano assigned_subscription_id e cercano sempre un abbonamento attivo.
--
-- Soluzione: Modificare le funzioni per:
-- 1. Verificare prima se assigned_subscription_id è presente
-- 2. Se presente, usarlo direttamente (anche se scaduto/inattivo)
-- 3. Solo se NULL, cercare un abbonamento attivo come fallback
--
-- Funzioni modificate:
-- - auto_create_booking_for_individual_lesson() (trigger su INSERT)
-- - handle_individual_lesson_update() (trigger su UPDATE)

-- ============================================================================
-- 1. FIX: auto_create_booking_for_individual_lesson()
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."auto_create_booking_for_individual_lesson"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client_profile_id uuid;
  v_subscription_id uuid;
  v_booking_id uuid;
  v_total_entries integer;
BEGIN
  -- Only process if this is an individual lesson with assigned client
  IF NEW.is_individual = true AND NEW.assigned_client_id IS NOT NULL THEN
    -- Get client's profile_id if available
    SELECT profile_id INTO v_client_profile_id
    FROM clients
    WHERE id = NEW.assigned_client_id AND deleted_at IS NULL;
    
    -- ✅ PRIORITÀ 1: Usa assigned_subscription_id se specificato
    IF NEW.assigned_subscription_id IS NOT NULL THEN
      v_subscription_id := NEW.assigned_subscription_id;
    ELSE
      -- ✅ PRIORITÀ 2: Fallback - cerca un abbonamento attivo solo se non specificato
      IF v_client_profile_id IS NOT NULL THEN
        -- Client has account: check both client_id and user_id subscriptions
        SELECT id INTO v_subscription_id
        FROM subscriptions_with_remaining
        WHERE (
          (client_id = NEW.assigned_client_id) OR (user_id = v_client_profile_id)
        )
        AND status = 'active'
        AND current_date BETWEEN started_at::date AND expires_at::date
        AND (remaining_entries IS NULL OR remaining_entries > 0)
        ORDER BY expires_at DESC NULLS LAST
        LIMIT 1;
      ELSE
        -- Client without account: check only client_id subscriptions
        SELECT id INTO v_subscription_id
        FROM subscriptions_with_remaining
        WHERE client_id = NEW.assigned_client_id
        AND status = 'active'
        AND current_date BETWEEN started_at::date AND expires_at::date
        AND (remaining_entries IS NULL OR remaining_entries > 0)
        ORDER BY expires_at DESC NULLS LAST
        LIMIT 1;
      END IF;
    END IF;
    
    -- Check if booking already exists (to avoid duplicates on UPDATE)
    SELECT id INTO v_booking_id
    FROM bookings
    WHERE lesson_id = NEW.id
    AND (
      (client_id = NEW.assigned_client_id) OR
      (v_client_profile_id IS NOT NULL AND user_id = v_client_profile_id)
    )
    AND status IN ('booked', 'attended', 'no_show')
    LIMIT 1;
    
    -- Create booking if it doesn't exist
    IF v_booking_id IS NULL THEN
      INSERT INTO bookings (lesson_id, client_id, subscription_id, status)
      VALUES (NEW.id, NEW.assigned_client_id, v_subscription_id, 'booked')
      RETURNING id INTO v_booking_id;
      
      -- Handle subscription usage if subscription was found
      IF v_subscription_id IS NOT NULL THEN
        -- Check if subscription has limited entries
        SELECT COALESCE(s.custom_entries, p.entries) INTO v_total_entries
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        WHERE s.id = v_subscription_id;
        
        -- Only create usage record if subscription has limited entries
        IF v_total_entries IS NOT NULL THEN
          INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
          VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_auto_booking');
        END IF;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- ============================================================================
-- 2. FIX: handle_individual_lesson_update()
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."handle_individual_lesson_update"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client_profile_id uuid;
  v_subscription_id uuid;
  v_booking_id uuid;
  v_old_booking_id uuid;
  v_subscription_changed boolean;
  v_old_subscription_id uuid;
  v_total_entries integer;
BEGIN
  -- If lesson is being changed from individual to non-individual, clean up
  IF OLD.is_individual = true AND NEW.is_individual = false THEN
    -- Set assigned_client_id to NULL (this will be enforced by constraint)
    NEW.assigned_client_id := NULL;
    -- Note: We don't delete existing bookings, just remove the assignment
    -- Staff can manually manage bookings if needed
    RETURN NEW;
  END IF;
  
  -- Check if assigned_subscription_id changed
  v_subscription_changed := OLD.assigned_subscription_id IS DISTINCT FROM NEW.assigned_subscription_id;
  
  -- If assigned_client_id is changing on an individual lesson
  IF NEW.is_individual = true AND NEW.assigned_client_id IS NOT NULL THEN
    -- If client changed, delete old booking and create new one
    IF OLD.assigned_client_id IS DISTINCT FROM NEW.assigned_client_id AND OLD.assigned_client_id IS NOT NULL THEN
      -- Find and delete old booking
      SELECT id INTO v_old_booking_id
      FROM bookings
      WHERE lesson_id = NEW.id
      AND client_id = OLD.assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
      LIMIT 1;
      
      IF v_old_booking_id IS NOT NULL THEN
        -- Cancel the old booking (this will restore subscription entries if applicable)
        -- We use the cancel_booking logic but as staff
        UPDATE bookings
        SET status = 'canceled'
        WHERE id = v_old_booking_id;
        
        -- Restore subscription entry if it was used
        UPDATE subscription_usages
        SET delta = +1, reason = 'individual_lesson_client_changed'
        WHERE booking_id = v_old_booking_id
        AND delta = -1
        AND NOT EXISTS (
          SELECT 1 FROM subscription_usages
          WHERE booking_id = v_old_booking_id
          AND delta = +1
          AND reason = 'individual_lesson_client_changed'
        );
      END IF;
    END IF;
    
    -- Create/update booking for assigned client
    SELECT profile_id INTO v_client_profile_id
    FROM clients
    WHERE id = NEW.assigned_client_id AND deleted_at IS NULL;
    
    -- Check if booking already exists for client
    IF v_client_profile_id IS NOT NULL THEN
      SELECT id INTO v_booking_id
      FROM bookings
      WHERE lesson_id = NEW.id
      AND (
        (client_id = NEW.assigned_client_id) OR (user_id = v_client_profile_id)
      )
      AND status IN ('booked', 'attended', 'no_show')
      LIMIT 1;
    ELSE
      SELECT id INTO v_booking_id
      FROM bookings
      WHERE lesson_id = NEW.id
      AND client_id = NEW.assigned_client_id
      AND status IN ('booked', 'attended', 'no_show')
      LIMIT 1;
    END IF;
    
    -- If booking exists and subscription changed, update it
    IF v_booking_id IS NOT NULL AND v_subscription_changed THEN
      -- Restore old subscription entry if it was used
      SELECT subscription_id INTO v_old_subscription_id
      FROM bookings
      WHERE id = v_booking_id;
      
      IF v_old_subscription_id IS NOT NULL THEN
        SELECT COALESCE(s.custom_entries, p.entries) INTO v_total_entries
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        WHERE s.id = v_old_subscription_id;
        
        -- Restore entry if subscription has limited entries
        IF v_total_entries IS NOT NULL THEN
          UPDATE subscription_usages
          SET delta = +1, reason = 'individual_lesson_subscription_changed'
          WHERE booking_id = v_booking_id
          AND subscription_id = v_old_subscription_id
          AND delta = -1
          AND NOT EXISTS (
            SELECT 1 FROM subscription_usages
            WHERE booking_id = v_booking_id
            AND subscription_id = v_old_subscription_id
            AND delta = +1
            AND reason = 'individual_lesson_subscription_changed'
          );
        END IF;
      END IF;
      
      -- Update booking with new subscription
      -- ✅ PRIORITÀ 1: Usa assigned_subscription_id se specificato
      IF NEW.assigned_subscription_id IS NOT NULL THEN
        v_subscription_id := NEW.assigned_subscription_id;
      ELSE
        -- ✅ PRIORITÀ 2: Fallback - cerca un abbonamento attivo solo se non specificato
        IF v_client_profile_id IS NOT NULL THEN
          SELECT id INTO v_subscription_id
          FROM subscriptions_with_remaining
          WHERE (
            (client_id = NEW.assigned_client_id) OR (user_id = v_client_profile_id)
          )
          AND status = 'active'
          AND current_date BETWEEN started_at::date AND expires_at::date
          AND (remaining_entries IS NULL OR remaining_entries > 0)
          ORDER BY expires_at DESC NULLS LAST
          LIMIT 1;
        ELSE
          SELECT id INTO v_subscription_id
          FROM subscriptions_with_remaining
          WHERE client_id = NEW.assigned_client_id
          AND status = 'active'
          AND current_date BETWEEN started_at::date AND expires_at::date
          AND (remaining_entries IS NULL OR remaining_entries > 0)
          ORDER BY expires_at DESC NULLS LAST
          LIMIT 1;
        END IF;
      END IF;
      
      UPDATE bookings
      SET subscription_id = v_subscription_id
      WHERE id = v_booking_id;
      
      -- Handle subscription usage for new subscription
      IF v_subscription_id IS NOT NULL THEN
        SELECT COALESCE(s.custom_entries, p.entries) INTO v_total_entries
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        WHERE s.id = v_subscription_id;
        
        IF v_total_entries IS NOT NULL THEN
          INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
          VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_subscription_changed')
          ON CONFLICT DO NOTHING;
        END IF;
      END IF;
    ELSIF v_booking_id IS NULL THEN
      -- Create booking if it doesn't exist
      -- ✅ PRIORITÀ 1: Usa assigned_subscription_id se specificato
      IF NEW.assigned_subscription_id IS NOT NULL THEN
        v_subscription_id := NEW.assigned_subscription_id;
      ELSE
        -- ✅ PRIORITÀ 2: Fallback - cerca un abbonamento attivo solo se non specificato
        IF v_client_profile_id IS NOT NULL THEN
          SELECT id INTO v_subscription_id
          FROM subscriptions_with_remaining
          WHERE (
            (client_id = NEW.assigned_client_id) OR (user_id = v_client_profile_id)
          )
          AND status = 'active'
          AND current_date BETWEEN started_at::date AND expires_at::date
          AND (remaining_entries IS NULL OR remaining_entries > 0)
          ORDER BY expires_at DESC NULLS LAST
          LIMIT 1;
        ELSE
          SELECT id INTO v_subscription_id
          FROM subscriptions_with_remaining
          WHERE client_id = NEW.assigned_client_id
          AND status = 'active'
          AND current_date BETWEEN started_at::date AND expires_at::date
          AND (remaining_entries IS NULL OR remaining_entries > 0)
          ORDER BY expires_at DESC NULLS LAST
          LIMIT 1;
        END IF;
      END IF;
      
      INSERT INTO bookings (lesson_id, client_id, subscription_id, status)
      VALUES (NEW.id, NEW.assigned_client_id, v_subscription_id, 'booked')
      RETURNING id INTO v_booking_id;
      
      -- Handle subscription usage
      IF v_subscription_id IS NOT NULL THEN
        SELECT COALESCE(s.custom_entries, p.entries) INTO v_total_entries
        FROM subscriptions s
        LEFT JOIN plans p ON p.id = s.plan_id
        WHERE s.id = v_subscription_id;
        
        IF v_total_entries IS NOT NULL THEN
          INSERT INTO subscription_usages (subscription_id, booking_id, delta, reason)
          VALUES (v_subscription_id, v_booking_id, -1, 'individual_lesson_auto_booking');
        END IF;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- ============================================================================
-- 3. UPDATE TRIGGER: Add assigned_subscription_id to trigger condition
-- ============================================================================

-- Update the trigger to also fire when assigned_subscription_id changes
DROP TRIGGER IF EXISTS trigger_handle_individual_lesson_update ON public.lessons;

CREATE TRIGGER trigger_handle_individual_lesson_update 
  BEFORE UPDATE ON public.lessons 
  FOR EACH ROW 
  WHEN (
    (OLD.is_individual IS DISTINCT FROM NEW.is_individual) OR 
    (OLD.assigned_client_id IS DISTINCT FROM NEW.assigned_client_id) OR
    (OLD.assigned_subscription_id IS DISTINCT FROM NEW.assigned_subscription_id)
  ) 
  EXECUTE FUNCTION public.handle_individual_lesson_update();

