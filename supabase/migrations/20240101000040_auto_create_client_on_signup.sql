-- Migration 0040: Auto-create client on user signup
--
-- Problema: Se un cliente si registra dall'app senza un record preesistente in clients,
-- viene creato solo il profilo ma non il client. Questo causa problemi perché:
-- - get_my_client_id() restituisce NULL
-- - book_lesson() e cancel_booking() falliscono con CLIENT_NOT_FOUND
-- - L'utente non può fare prenotazioni o vedere i propri dati
--
-- Soluzione: Modificare handle_new_user() per creare automaticamente un record in clients
-- quando un utente si registra senza un client preesistente con la stessa email.
--
-- Modifiche:
-- 1. Aggiornare handle_new_user() per creare un client quando non esiste
-- 2. Usare raw_user_meta_data per ottenere il nome completo se disponibile
-- 3. Fallback all'email se il nome non è disponibile (full_name è NOT NULL)

CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_client clients%rowtype;
  v_full_name text;
BEGIN
  -- Cerca se esiste un client con la stessa email
  SELECT * INTO v_client
  FROM clients
  WHERE email = new.email
    AND deleted_at IS NULL
  LIMIT 1;

  -- Se esiste un client con la stessa email, sincronizza i dati
  IF FOUND THEN
    -- Inserisci il profilo con i dati dal client
    INSERT INTO public.profiles (
      id, 
      email, 
      role,
      full_name,
      phone,
      notes
    )
    VALUES (
      new.id,
      new.email,
      'user'::user_role,
      v_client.full_name,
      v_client.phone,
      v_client.notes
    );

    -- Aggiorna il client con il profile_id per collegarli
    UPDATE clients
    SET profile_id = new.id
    WHERE id = v_client.id;
  ELSE
    -- Se non esiste un client, crea sia il profilo che il client
    -- Estrai il nome completo dai metadati se disponibile
    v_full_name := COALESCE(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      split_part(new.email, '@', 1),  -- Fallback: parte prima della @ nell'email
      'Utente'  -- Ultimo fallback
    );

    -- Crea il profilo minimale
    INSERT INTO public.profiles (id, email, role)
    VALUES (
      new.id,
      new.email,
      'user'::user_role
    );

    -- Crea un nuovo client collegato al profilo
    INSERT INTO public.clients (
      profile_id,
      email,
      full_name,
      phone,
      is_active
    )
    VALUES (
      new.id,
      new.email,
      v_full_name,
      new.raw_user_meta_data->>'phone',  -- Opzionale, può essere NULL
      true
    );
  END IF;

  RETURN new;
END;
$$;

COMMENT ON FUNCTION "public"."handle_new_user"() IS 
'Crea automaticamente un profilo quando viene creato un nuovo utente Auth. Se esiste un client con la stessa email, sincronizza i dati e collega il client al profilo. Se non esiste un client, crea automaticamente sia il profilo che il client per permettere all''utente di fare prenotazioni.';

