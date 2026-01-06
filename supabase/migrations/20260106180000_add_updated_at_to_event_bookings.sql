-- Migration: Add updated_at column to event_bookings
--
-- Problema: Il trigger update_event_bookings_updated_at cerca di aggiornare
-- new.updated_at ma la tabella event_bookings non ha questo campo, causando
-- l'errore: "record "new" has no field "updated_at""
--
-- Soluzione: Aggiungere la colonna updated_at alla tabella event_bookings
-- per essere coerenti con altre tabelle come events che hanno questo campo.

-- Aggiungi colonna updated_at se non esiste
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'event_bookings' 
      AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE public.event_bookings 
      ADD COLUMN updated_at timestamp with time zone DEFAULT now() NOT NULL;
    
    -- Aggiorna i record esistenti con il valore di created_at o now()
    UPDATE public.event_bookings 
    SET updated_at = COALESCE(created_at, now())
    WHERE updated_at IS NULL;
    
    RAISE NOTICE 'Colonna updated_at aggiunta a event_bookings';
  ELSE
    RAISE NOTICE 'Colonna updated_at già presente in event_bookings';
  END IF;
END $$;

COMMENT ON COLUMN public.event_bookings.updated_at IS 
  'Timestamp dell''ultimo aggiornamento della prenotazione. Aggiornato automaticamente dal trigger update_event_bookings_updated_at.';

