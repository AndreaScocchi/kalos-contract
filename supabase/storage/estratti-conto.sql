-- Bucket `estratti-conto`: i PDF dei movimenti della banca caricati per la chiusura del mese
-- (Finanze → Banca e Stripe → Chiusura con l'estratto conto, contract v0.3.20). `bank_closings.file_path`
-- ne tiene il percorso, `<anno>/<dal>_<al>-<uuid>.pdf`.
--
-- NON è una migrazione: lo Storage locale è spento (vedi `documenti-spese.sql`). Si crea in produzione
-- lanciando questo file, che è idempotente:
--
--     npx supabase db query --linked -f supabase/storage/estratti-conto.sql
--
-- Chi può fare cosa: SOLO admin e Tesoriere (`can_access_finance()`), come le tabelle delle chiusure.
-- Bucket privato: l'estratto ha i nomi di chi ha fatto bonifici e il numero del conto. Si scarica con
-- link firmati. Solo PDF, fino a 10 MB. Nessun aggiornamento: un PDF si carica una volta e si toglie
-- se la chiusura si annulla.
--
-- Tutto in un solo blocco DO: `supabase db query` esegue una sola istruzione per volta.

DO $$
BEGIN
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('estratti-conto', 'estratti-conto', false, 10485760, ARRAY['application/pdf'])
    ON CONFLICT (id) DO UPDATE SET
        public             = false,
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

    DROP POLICY IF EXISTS "estratti_conto_finance_select" ON storage.objects;
    CREATE POLICY "estratti_conto_finance_select" ON storage.objects
        FOR SELECT TO authenticated
        USING (bucket_id = 'estratti-conto' AND public.can_access_finance());

    DROP POLICY IF EXISTS "estratti_conto_finance_insert" ON storage.objects;
    CREATE POLICY "estratti_conto_finance_insert" ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (bucket_id = 'estratti-conto' AND public.can_access_finance());

    DROP POLICY IF EXISTS "estratti_conto_finance_delete" ON storage.objects;
    CREATE POLICY "estratti_conto_finance_delete" ON storage.objects
        FOR DELETE TO authenticated
        USING (bucket_id = 'estratti-conto' AND public.can_access_finance());
END
$$;
