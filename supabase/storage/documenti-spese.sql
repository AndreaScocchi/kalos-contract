-- Bucket `documenti-spese`: documenti di spesa (scontrini, fatture, biglietti) allegati ai rimborsi
-- dei volontari (art. 23: senza documento il rimborso non si registra) e, dalla sessione 7, alle
-- uscite delle Finanze.
--
-- NON è una migrazione: lo Storage locale è spento (supabase/config.toml, incompatibilità del CLI con
-- le migrazioni interne di Storage), quindi un bucket creato da migrazione non si potrebbe provare in
-- locale. Come per il bucket `newsletter`, si crea in produzione lanciando questo file, che è
-- idempotente (si può rilanciare senza danni):
--
--     npx supabase db query --linked -f supabase/storage/documenti-spese.sql
--
-- Chi può fare cosa: SOLO admin e Tesoriere (`can_access_finance()`), come per le tabelle dei rimborsi
-- e delle uscite (E3). Bucket privato: i file si aprono con link firmati che scadono dopo 5 minuti.
-- Il gestionale salva i file in `rimborsi/<id volontariə>/<uuid>-<nome>`.
--
-- Tutto in un solo blocco DO: `supabase db query` esegue una sola istruzione per volta.

DO $$
BEGIN
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES (
        'documenti-spese',
        'documenti-spese',
        false,
        10485760, -- 10 MB, come il limite del modulo nel gestionale
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf']
    )
    ON CONFLICT (id) DO UPDATE SET
        public             = false,
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

    DROP POLICY IF EXISTS "documenti_spese_finance_select" ON storage.objects;
    CREATE POLICY "documenti_spese_finance_select" ON storage.objects
        FOR SELECT TO authenticated
        USING (bucket_id = 'documenti-spese' AND public.can_access_finance());

    DROP POLICY IF EXISTS "documenti_spese_finance_insert" ON storage.objects;
    CREATE POLICY "documenti_spese_finance_insert" ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (bucket_id = 'documenti-spese' AND public.can_access_finance());

    DROP POLICY IF EXISTS "documenti_spese_finance_update" ON storage.objects;
    CREATE POLICY "documenti_spese_finance_update" ON storage.objects
        FOR UPDATE TO authenticated
        USING (bucket_id = 'documenti-spese' AND public.can_access_finance())
        WITH CHECK (bucket_id = 'documenti-spese' AND public.can_access_finance());

    DROP POLICY IF EXISTS "documenti_spese_finance_delete" ON storage.objects;
    CREATE POLICY "documenti_spese_finance_delete" ON storage.objects
        FOR DELETE TO authenticated
        USING (bucket_id = 'documenti-spese' AND public.can_access_finance());
END
$$;
