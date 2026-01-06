-- Migration: Fix event_bookings user_id nullable
--
-- Problema: La colonna user_id in event_bookings è NOT NULL, ma quando si aggiunge
-- un partecipante dal gestionale usando solo client_id, user_id deve essere NULL.
-- Questo causa l'errore: "null value in column "user_id" of relation "event_bookings" violates not-null constraint"
--
-- Soluzione: Rendere user_id nullable per supportare prenotazioni con solo client_id
-- (come già fatto per la tabella bookings)

-- Rendere user_id nullable per supportare prenotazioni con solo client_id
DO $$
BEGIN
  -- Verifica se user_id è ancora NOT NULL e rendilo nullable
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'event_bookings' 
      AND column_name = 'user_id' 
      AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE public.event_bookings 
      ALTER COLUMN user_id DROP NOT NULL;
    
    RAISE NOTICE 'Colonna user_id resa nullable in event_bookings';
  ELSE
    RAISE NOTICE 'Colonna user_id è già nullable in event_bookings';
  END IF;
END $$;

-- Verifica che client_id esista (dovrebbe essere stata aggiunta dalla migrazione 39)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'event_bookings' 
      AND column_name = 'client_id'
  ) THEN
    -- Se client_id non esiste, aggiungilo
    ALTER TABLE public.event_bookings 
      ADD COLUMN client_id uuid;
    
    -- Aggiungi foreign key verso clients
    ALTER TABLE public.event_bookings 
      ADD CONSTRAINT event_bookings_client_id_fkey 
      FOREIGN KEY (client_id) 
      REFERENCES public.clients(id) 
      ON DELETE SET NULL;
    
    -- Aggiungi constraint XOR se non esiste
    IF NOT EXISTS (
      SELECT 1 
      FROM information_schema.table_constraints 
      WHERE constraint_schema = 'public' 
        AND table_name = 'event_bookings' 
        AND constraint_name = 'event_bookings_user_client_xor'
    ) THEN
      ALTER TABLE public.event_bookings 
        ADD CONSTRAINT event_bookings_user_client_xor 
        CHECK (
          (user_id IS NOT NULL AND client_id IS NULL) OR 
          (user_id IS NULL AND client_id IS NOT NULL)
        );
    END IF;
    
    RAISE NOTICE 'Colonna client_id aggiunta a event_bookings';
  ELSE
    RAISE NOTICE 'Colonna client_id già presente in event_bookings';
  END IF;
END $$;

COMMENT ON COLUMN public.event_bookings.user_id IS 
  'ID dell''utente con account che ha prenotato. NULL se client_id è impostato.';

COMMENT ON COLUMN public.event_bookings.client_id IS 
  'ID del cliente CRM (senza account) che ha prenotato. NULL se user_id è impostato.';

