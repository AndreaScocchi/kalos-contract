-- Bucket `bug-reports`: gli screenshot allegati alle segnalazioni (`bug_reports.image_url` ne tiene il
-- percorso, non un link). Esiste in produzione da prima del contract; questo file lo descrive com'è
-- lì (verificato il 29/09/2026, sessione 11), così si può ricreare. Idempotente:
--
--     npx supabase db query --linked -f supabase/storage/bug-reports.sql
--
-- NON è una migrazione: lo Storage locale è spento (vedi `documenti-spese.sql`).
--
-- Chi può fare cosa: ognunə carica, legge, cambia e cancella solo i file della propria cartella
-- (`<id utente>/<nome>`); gli admin vedono e gestiscono tutto (Gestionale → Segnalazioni). Bucket
-- privato: le immagini si aprono con link firmati. Solo JPEG e PNG, fino a 5 MB (l'app manda JPEG).
--
-- Tutto in un solo blocco DO: `supabase db query` esegue una sola istruzione per volta.

DO $$
BEGIN
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('bug-reports', 'bug-reports', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/jpg'])
    ON CONFLICT (id) DO UPDATE SET
        public             = false,
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

    DROP POLICY IF EXISTS "bug_reports_users_upload_own_folder" ON storage.objects;
    CREATE POLICY "bug_reports_users_upload_own_folder" ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (bucket_id = 'bug-reports' AND (storage.foldername(name))[1] = auth.uid()::text);

    DROP POLICY IF EXISTS "bug_reports_users_view_own_files" ON storage.objects;
    CREATE POLICY "bug_reports_users_view_own_files" ON storage.objects
        FOR SELECT TO authenticated
        USING (bucket_id = 'bug-reports' AND (storage.foldername(name))[1] = auth.uid()::text);

    DROP POLICY IF EXISTS "bug_reports_users_update_own_files" ON storage.objects;
    CREATE POLICY "bug_reports_users_update_own_files" ON storage.objects
        FOR UPDATE TO authenticated
        USING (bucket_id = 'bug-reports' AND (storage.foldername(name))[1] = auth.uid()::text)
        WITH CHECK (bucket_id = 'bug-reports' AND (storage.foldername(name))[1] = auth.uid()::text);

    DROP POLICY IF EXISTS "bug_reports_users_delete_own_files" ON storage.objects;
    CREATE POLICY "bug_reports_users_delete_own_files" ON storage.objects
        FOR DELETE TO authenticated
        USING (bucket_id = 'bug-reports' AND (storage.foldername(name))[1] = auth.uid()::text);

    DROP POLICY IF EXISTS "bug_reports_admins_upload_all" ON storage.objects;
    CREATE POLICY "bug_reports_admins_upload_all" ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (bucket_id = 'bug-reports' AND public.is_admin());

    DROP POLICY IF EXISTS "bug_reports_admins_view_all_files" ON storage.objects;
    CREATE POLICY "bug_reports_admins_view_all_files" ON storage.objects
        FOR SELECT TO authenticated
        USING (bucket_id = 'bug-reports' AND public.is_admin());

    DROP POLICY IF EXISTS "bug_reports_admins_update_all_files" ON storage.objects;
    CREATE POLICY "bug_reports_admins_update_all_files" ON storage.objects
        FOR UPDATE TO authenticated
        USING (bucket_id = 'bug-reports' AND public.is_admin());

    DROP POLICY IF EXISTS "bug_reports_admins_delete_all_files" ON storage.objects;
    CREATE POLICY "bug_reports_admins_delete_all_files" ON storage.objects
        FOR DELETE TO authenticated
        USING (bucket_id = 'bug-reports' AND public.is_admin());
END
$$;
