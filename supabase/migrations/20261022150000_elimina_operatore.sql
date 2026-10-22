-- Migration 20261022150000: eliminare un operatore dal gestionale
--
-- Richiesta dell'utente del 22/10/2026: dal gestionale si deve poter eliminare del tutto un
-- operatore, non solo disattivarlo. Decisione dell'utente: chi ha già lavorato sparisce, ma lo
-- storico (lezioni, eventi, compensi) continua a mostrarne il nome.
--
-- `staff_delete_operator(p_operator_id, p_dry_run)`, solo admin come le altre scritture di
-- `operators`:
--
--   * rifiuta se ha lezioni o eventi non ancora finiti (`UPCOMING`): prima si assegnano a un'altra
--     persona o si archiviano, altrimenti resterebbero in calendario con una persona che non c'è più;
--   * senza storico (nessuna lezione, anche archiviata, nessun evento, compenso congelato o pagato,
--     uscita, voce del registro dei volontari o vecchio payout) cancella la riga. Con lei se ne vanno
--     le assegnazioni dei modelli di compenso e la ritenuta (`ON DELETE CASCADE`): sono impostazioni,
--     non storico;
--   * con uno storico tiene la riga solo per il nome: `deleted_at`, non attiva, non sul sito, senza
--     bio, foto, discipline, ordine sul sito e collegamento all'account. Restano nome, ruolo e
--     rapporto con l'associazione, e le assegnazioni e la ritenuta: servono ai compensi dei mesi in
--     cui ha lavorato, finché non sono pagati;
--   * con `p_dry_run` dice soltanto cosa succederebbe, per la conferma nel gestionale;
--   * restituisce `image_url` (se nessun'altra scheda usa la stessa foto) perché il gestionale
--     cancelli la foto dallo storage: da SQL lo storage non si cancella.
--
-- Una scheda eliminata non torna attiva né visibile sul sito (vincolo). E le schede si eliminano
-- solo con la funzione: la policy `operators_write_admin` (ALL) diventa due policy, inserimento e
-- modifica, e authenticated perde DELETE su `operators`, che nessuna app usava. Una cancellazione
-- diretta toglierebbe il nome alle lezioni (`lessons.operator_id` è ON DELETE SET NULL).
--
-- Compatibilità: una funzione nuova; le letture di `operators` non cambiano (lo staff vede anche le
-- schede eliminate, per i nomi nello storico; anon e clienti vedono solo quelle attive, come prima).
--
-- migration-lint:allow revoke — reason: si toglie ad authenticated solo il DELETE diretto su operators, che nessun consumer usa (cercato in gestionale, app, webapp, sito e script il 22/10); la funzione nuova nasce chiusa ad anon

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Una scheda eliminata resta nascosta
-- ─────────────────────────────────────────────────────────────────────────────

-- In produzione nessuna scheda ha deleted_at (22/10/2026): vale per i dati di prova
UPDATE "public"."operators"
   SET "is_active" = false, "is_visible_on_site" = false
 WHERE "deleted_at" IS NOT NULL AND ("is_active" OR "is_visible_on_site");

DO $$ BEGIN
    ALTER TABLE "public"."operators"
        ADD CONSTRAINT "operators_deleted_is_hidden"
        CHECK ("deleted_at" IS NULL OR (NOT "is_active" AND NOT "is_visible_on_site"));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN "public"."operators"."deleted_at" IS
    'Scheda eliminata dal gestionale (staff_delete_operator) quando la persona ha uno storico: resta solo il nome per lezioni, eventi e compensi passati. NULL = scheda in uso. Una scheda eliminata non è attiva né visibile sul sito.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Si elimina solo con la funzione
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "operators_write_admin" ON "public"."operators";

DROP POLICY IF EXISTS "operators_insert_admin" ON "public"."operators";
CREATE POLICY "operators_insert_admin" ON "public"."operators"
    FOR INSERT TO "authenticated" WITH CHECK ("public"."is_admin"());

DROP POLICY IF EXISTS "operators_update_admin" ON "public"."operators";
CREATE POLICY "operators_update_admin" ON "public"."operators"
    FOR UPDATE TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());

REVOKE DELETE ON TABLE "public"."operators" FROM "authenticated";

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Eliminare un operatore
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_delete_operator"(
    "p_operator_id" "uuid",
    "p_dry_run" boolean DEFAULT false
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_op                public.operators%ROWTYPE;
    v_upcoming_lessons  integer;
    v_upcoming_events   integer;
    v_lessons           integer;
    v_events            integer;
    v_keeps_name        boolean;
    v_image_url         text;
BEGIN
    IF NOT public.is_admin() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_ADMIN');
    END IF;

    SELECT * INTO v_op FROM public.operators
     WHERE id = p_operator_id AND deleted_at IS NULL
     FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FOUND');
    END IF;

    -- Quello che non è ancora finito va prima dato a qualcun altro (o archiviato)
    SELECT count(*) INTO v_upcoming_lessons FROM public.lessons
     WHERE operator_id = p_operator_id AND deleted_at IS NULL AND ends_at > now();
    SELECT count(*) INTO v_upcoming_events
      FROM public.event_operators eo
      JOIN public.events e ON e.id = eo.event_id
     WHERE eo.operator_id = p_operator_id AND e.deleted_at IS NULL AND e.ends_at > now();

    IF v_upcoming_lessons > 0 OR v_upcoming_events > 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'UPCOMING',
            'upcoming_lessons', v_upcoming_lessons, 'upcoming_events', v_upcoming_events);
    END IF;

    SELECT count(*) INTO v_lessons FROM public.lessons WHERE operator_id = p_operator_id;
    SELECT count(*) INTO v_events FROM public.event_operators WHERE operator_id = p_operator_id;
    v_keeps_name := v_lessons > 0 OR v_events > 0
        OR EXISTS (SELECT 1 FROM public.compensation_entries WHERE operator_id = p_operator_id)
        OR EXISTS (SELECT 1 FROM public.compensation_payments WHERE operator_id = p_operator_id)
        OR EXISTS (SELECT 1 FROM public.expenses WHERE operator_id = p_operator_id)
        OR EXISTS (SELECT 1 FROM public.volunteers WHERE operator_id = p_operator_id)
        OR EXISTS (SELECT 1 FROM public.payouts WHERE operator_id = p_operator_id);

    IF p_dry_run THEN
        RETURN jsonb_build_object('ok', true, 'reason', 'DRY_RUN', 'keeps_name', v_keeps_name,
            'lessons', v_lessons, 'events', v_events);
    END IF;

    -- La foto la cancella il gestionale dallo storage, se nessun'altra scheda la usa
    IF v_op.image_url IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.operators WHERE image_url = v_op.image_url AND id <> p_operator_id
    ) THEN
        v_image_url := v_op.image_url;
    END IF;

    IF v_keeps_name THEN
        UPDATE public.operators
           SET deleted_at = now(),
               is_active = false,
               is_visible_on_site = false,
               bio = NULL,
               image_url = NULL,
               disciplines = NULL,
               display_order = NULL,
               profile_id = NULL,
               is_admin = false
         WHERE id = p_operator_id;
        RETURN jsonb_build_object('ok', true, 'reason', 'NAME_KEPT', 'keeps_name', true,
            'lessons', v_lessons, 'events', v_events, 'image_url', v_image_url);
    END IF;

    DELETE FROM public.operators WHERE id = p_operator_id;
    RETURN jsonb_build_object('ok', true, 'reason', 'DELETED', 'keeps_name', false,
        'lessons', 0, 'events', 0, 'image_url', v_image_url);
END;
$$;

ALTER FUNCTION "public"."staff_delete_operator"("uuid", boolean) OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."staff_delete_operator"("uuid", boolean) FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."staff_delete_operator"("uuid", boolean) TO "authenticated", "service_role";
COMMENT ON FUNCTION "public"."staff_delete_operator"("uuid", boolean) IS
    'Elimina la scheda di un operatore (solo admin). Rifiuta con lezioni o eventi non ancora finiti (UPCOMING). Senza storico cancella la riga (DELETED); con lezioni, eventi, compensi, uscite o registro dei volontari tiene solo il nome per lo storico (NAME_KEPT). Con p_dry_run dice soltanto cosa farebbe. Restituisce image_url da cancellare dallo storage.';
