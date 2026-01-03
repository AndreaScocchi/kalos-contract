-- Migration 0013: Migrate client records to user_id when client is linked to profile
-- 
-- Quando un cliente viene collegato a un profilo (clients.profile_id viene impostato),
-- migra automaticamente tutti i record correlati da client_id a user_id:
-- - bookings: migra da client_id a user_id
-- - subscriptions: migra da client_id a user_id
--
-- Questo risolve il problema per cui se un cliente ha già prenotazioni/abbonamenti
-- creati dal gestionale (con client_id), quando l'utente si registra e viene collegato
-- al cliente, questi record non sono visibili nell'app perché l'app cerca per user_id.

-- ============================================================================
-- 1. Funzione per migrare bookings da client_id a user_id
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."migrate_client_bookings_to_user"(
  p_client_id uuid,
  p_user_id uuid
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_migrated_count integer := 0;
  v_booking_to_migrate_id uuid;
BEGIN
  -- Migra tutti i bookings con client_id che non hanno ancora user_id
  -- Per ogni booking, verifica se esiste già un booking con lo stesso lesson_id e user_id
  FOR v_booking_to_migrate_id IN
    SELECT id
    FROM bookings
    WHERE client_id = p_client_id
      AND user_id IS NULL
  LOOP
    DECLARE
      v_lesson_id uuid;
      v_booking_status booking_status;
      v_conflicting_booking_id uuid;
    BEGIN
      -- Recupera lesson_id e status del booking da migrare
      SELECT lesson_id, status INTO v_lesson_id, v_booking_status
      FROM bookings
      WHERE id = v_booking_to_migrate_id;

      -- Verifica se esiste già un booking con lo stesso lesson_id e user_id
      -- (solo per bookings con status = 'booked' a causa del constraint unico)
      IF v_booking_status = 'booked' THEN
        SELECT id INTO v_conflicting_booking_id
        FROM bookings
        WHERE lesson_id = v_lesson_id
          AND user_id = p_user_id
          AND status = 'booked'
        LIMIT 1;

        IF v_conflicting_booking_id IS NOT NULL THEN
          -- Esiste già un booking, elimina quello con client_id (duplicato)
          -- Nota: questo può succedere se l'utente ha prenotato manualmente dall'app
          -- e il gestionale ha creato un booking duplicato per lo stesso cliente
          DELETE FROM bookings WHERE id = v_booking_to_migrate_id;
          v_migrated_count := v_migrated_count + 1;
        ELSE
          -- Non esiste conflitto, migra il booking
          UPDATE bookings
          SET user_id = p_user_id,
              client_id = NULL
          WHERE id = v_booking_to_migrate_id;
          v_migrated_count := v_migrated_count + 1;
        END IF;
      ELSE
        -- Per bookings non 'booked', migra direttamente (nessun constraint unico)
        UPDATE bookings
        SET user_id = p_user_id,
            client_id = NULL
        WHERE id = v_booking_to_migrate_id;
        v_migrated_count := v_migrated_count + 1;
      END IF;
    END;
  END LOOP;

  RETURN v_migrated_count;
END;
$$;

COMMENT ON FUNCTION "public"."migrate_client_bookings_to_user"(uuid, uuid) IS 
'Migra tutti i bookings da client_id a user_id quando un cliente viene collegato a un profilo. Gestisce conflitti con bookings esistenti eliminando duplicati.';

-- ============================================================================
-- 2. Funzione per migrare subscriptions da client_id a user_id
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."migrate_client_subscriptions_to_user"(
  p_client_id uuid,
  p_user_id uuid
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_migrated_count integer := 0;
BEGIN
  -- Migra tutte le subscriptions con client_id che non hanno ancora user_id
  UPDATE subscriptions
  SET user_id = p_user_id,
      client_id = NULL
  WHERE client_id = p_client_id
    AND user_id IS NULL;

  GET DIAGNOSTICS v_migrated_count = ROW_COUNT;

  RETURN v_migrated_count;
END;
$$;

COMMENT ON FUNCTION "public"."migrate_client_subscriptions_to_user"(uuid, uuid) IS 
'Migra tutte le subscriptions da client_id a user_id quando un cliente viene collegato a un profilo.';

-- ============================================================================
-- 3. Funzione principale che chiama le migrazioni
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."migrate_client_records_to_user"(
  p_client_id uuid,
  p_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_bookings_migrated integer;
  v_subscriptions_migrated integer;
BEGIN
  -- Migra bookings
  v_bookings_migrated := migrate_client_bookings_to_user(p_client_id, p_user_id);
  
  -- Migra subscriptions
  v_subscriptions_migrated := migrate_client_subscriptions_to_user(p_client_id, p_user_id);

  RETURN jsonb_build_object(
    'bookings_migrated', v_bookings_migrated,
    'subscriptions_migrated', v_subscriptions_migrated
  );
END;
$$;

COMMENT ON FUNCTION "public"."migrate_client_records_to_user"(uuid, uuid) IS 
'Funzione principale che migra tutti i record (bookings e subscriptions) da client_id a user_id quando un cliente viene collegato a un profilo.';

-- ============================================================================
-- 4. Trigger che chiama la migrazione quando clients.profile_id viene impostato
-- ============================================================================

CREATE OR REPLACE FUNCTION "public"."trigger_migrate_client_to_user"() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Se profile_id viene impostato (o aggiornato da NULL a un valore)
  -- e il client_id non è NULL, migra i record
  IF NEW.profile_id IS NOT NULL 
     AND (OLD.profile_id IS NULL OR OLD.profile_id IS DISTINCT FROM NEW.profile_id)
     AND NEW.id IS NOT NULL THEN
    -- Chiama la funzione di migrazione
    PERFORM migrate_client_records_to_user(NEW.id, NEW.profile_id);
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION "public"."trigger_migrate_client_to_user"() IS 
'Trigger che migra automaticamente bookings e subscriptions da client_id a user_id quando un cliente viene collegato a un profilo.';

-- Crea il trigger
DROP TRIGGER IF EXISTS "trg_migrate_client_to_user" ON "public"."clients";
CREATE TRIGGER "trg_migrate_client_to_user"
  AFTER UPDATE OF "profile_id" ON "public"."clients"
  FOR EACH ROW
  WHEN (NEW.profile_id IS NOT NULL AND (OLD.profile_id IS NULL OR OLD.profile_id IS DISTINCT FROM NEW.profile_id))
  EXECUTE FUNCTION "public"."trigger_migrate_client_to_user"();

-- Il trigger viene eseguito anche su INSERT se profile_id viene impostato subito
-- (anche se raro, potrebbe succedere se il gestionale crea un client con profile_id già impostato)
CREATE TRIGGER "trg_migrate_client_to_user_on_insert"
  AFTER INSERT ON "public"."clients"
  FOR EACH ROW
  WHEN (NEW.profile_id IS NOT NULL)
  EXECUTE FUNCTION "public"."trigger_migrate_client_to_user"();

-- ============================================================================
-- 5. Grants per le funzioni (solo staff può chiamarle manualmente se necessario)
-- ============================================================================

REVOKE ALL ON FUNCTION "public"."migrate_client_bookings_to_user"(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."migrate_client_bookings_to_user"(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION "public"."migrate_client_subscriptions_to_user"(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."migrate_client_subscriptions_to_user"(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION "public"."migrate_client_records_to_user"(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."migrate_client_records_to_user"(uuid, uuid) TO authenticated;

