-- Migration 20260930100100: soci, quote, note dello staff, registrazione e newsletter
--
-- Dalla verifica generale del 30/09/2026 (docs/ISSUES.md §1 punti 7 e 11, §3.1). Decisioni
-- dell'associazione del 30/09: decadenza della quota 2026 al 31/12/2026, nessuna tolleranza per chi è
-- ammessə dopo la decadenza, newsletter con possibilità di rifiuto («soft spam», art. 130 c.4).
--
-- 1. Stato di sociə (`internal.member_booking_status`): la data è quella italiana; una quota senza
--    importo deliberato non si può pagare, quindi non scade mai; chi era cessatə e rifà domanda segue
--    la domanda nuova (prima restava «cessatə» per sempre). La decadenza 2026 passa dal 31/03/2026,
--    messa di default prima che l'associazione nascesse, al 31/12/2026: oggi tutti e 15 i soci
--    risultavano «quota scaduta» e nessunə poteva chiedere la Bussola.
-- 2. Esonero, «pagata» senza incasso e rimborso di una quota: solo admin e Tesoriere, come deciso
--    nella sessione 4 (prima qualsiasi operatrice). Anche le scritture dirette su `member_fees`.
-- 3. Domanda d'ammissione: canale, IP e dispositivo documentano l'accettazione e ora valgono solo se
--    li scrive l'edge function `member-application` (chiave di sistema, utente preso dal token).
--    Chiamando la funzione direttamente non si possono più inventare.
-- 4. Domanda su carta per una persona nuova: la scheda nasce dentro `staff_create_member_application`,
--    dopo i controlli (prima il gestionale la creava prima, e restava anche a domanda rifiutata).
-- 5. Le note interne dello staff sulla scheda cliente passano in `client_staff_notes`, leggibile solo
--    dallo staff. Prima `clients.notes` (copiata anche in `profiles.notes`) la leggeva anche la
--    persona interessata. Il gestionale di oggi che scrive ancora `clients.notes` non perde nulla: un
--    trigger sposta il testo nella tabella nuova.
-- 6. Registrazione: l'email si confronta senza maiuscole (una scheda «Mario@…» non genera più un
--    doppione per «mario@…»); privacy e termini accettati nel modulo si registrano con l'ora del
--    server; chi spunta «Non voglio ricevere la newsletter» (`newsletter_opt_out`) nasce disiscrittə.
-- 7. `set_my_newsletter_subscription`: la persona accende e spegne la newsletter dall'app.
--
-- Compatibilità: firme invariate; `staff_create_member_application` accetta anche `p_client_id`
-- NULL e restituisce `client_id`. Tabella e funzione nuove, un trigger nuovo.
--
-- migration-lint:allow revoke — reason: le REVOKE riguardano solo funzioni e tabelle nuove di questa migrazione (anon non legge le note dello staff); nessun accesso esistente si restringe

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Stato di sociə e quota 2026
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."member_booking_status"(p_client_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_today     date := "internal"."rome_today"();
    v_year      integer := extract(year FROM v_today)::integer;
    v_member    public.members%ROWTYPE;
    v_fee       public.member_fees%ROWTYPE;
    v_year_row  public.association_years%ROWTYPE;
    v_has_app   boolean;
BEGIN
    IF p_client_id IS NULL THEN
        RETURN 'no_application';
    END IF;

    SELECT * INTO v_member FROM public.members WHERE client_id = p_client_id;
    SELECT * INTO v_fee FROM public.member_fees WHERE client_id = p_client_id AND year = v_year;
    SELECT * INTO v_year_row FROM public.association_years WHERE year = v_year;

    SELECT EXISTS (
        SELECT 1 FROM public.member_applications
         WHERE client_id = p_client_id AND status = 'pending'
    ) INTO v_has_app;

    IF v_member.id IS NOT NULL AND v_member.status = 'ceased' AND NOT v_has_app THEN
        RETURN 'ceased';
    END IF;

    IF v_member.id IS NOT NULL AND v_member.status <> 'ceased' THEN
        IF v_fee.id IS NOT NULL AND v_fee.status IN ('paid', 'waived') THEN
            RETURN 'ok';
        END IF;
        -- Non ancora pagata: resta sociə fino alla decadenza dell'anno (art. 5, A8). Una quota
        -- senza importo deliberato non si può pagare, quindi non scade.
        IF v_year_row.fee_due_date IS NULL
           OR v_year_row.fee_cents IS NULL
           OR v_today <= v_year_row.fee_due_date THEN
            RETURN 'fee_due_grace';
        END IF;
        RETURN 'fee_overdue';
    END IF;

    -- Non ancora sociə (o cessatə con una domanda nuova): servono domanda e quota (A7).
    IF NOT v_has_app THEN
        RETURN 'no_application';
    END IF;

    IF v_fee.id IS NOT NULL AND v_fee.status IN ('paid', 'waived') THEN
        RETURN 'pending_admission';
    END IF;

    RETURN 'fee_unpaid';
END;
$$;

-- Decadenza 2026 (decisione del 30/09/2026): per il primo anno la quota si versa entro fine anno.
UPDATE "public"."association_years"
   SET fee_due_date = DATE '2026-12-31', updated_at = now()
 WHERE year = 2026 AND fee_due_date = DATE '2026-03-31';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Quote: esonero, «pagata» senza incasso e rimborso solo per admin e Tesoriere
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_set_member_fee"(
    p_client_id uuid,
    p_year integer,
    p_status "public"."member_fee_status",
    p_amount_cents integer DEFAULT NULL,
    p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_amount integer;
    v_fee_id uuid;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    -- Esonerare, segnare pagata senza un incasso o rimborsata cambia i conti: admin e Tesoriere.
    -- Le operatrici incassano la quota con `staff_pay_member_fee`, che registra l'incasso.
    IF p_status IN ('waived', 'paid', 'refunded') AND NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'FINANCE_ONLY');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.association_years WHERE year = p_year) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'YEAR_NOT_FOUND');
    END IF;

    SELECT COALESCE(p_amount_cents, fee_cents) INTO v_amount
      FROM public.association_years WHERE year = p_year;

    INSERT INTO public.member_fees (client_id, year, amount_cents, status, paid_at, refunded_at, note, created_by)
    VALUES (
        p_client_id, p_year, v_amount, p_status,
        CASE WHEN p_status = 'paid' THEN now() ELSE NULL END,
        CASE WHEN p_status = 'refunded' THEN now() ELSE NULL END,
        p_note, auth.uid()
    )
    ON CONFLICT (client_id, year) DO UPDATE SET
        amount_cents = COALESCE(EXCLUDED.amount_cents, public.member_fees.amount_cents),
        status       = EXCLUDED.status,
        paid_at      = CASE WHEN EXCLUDED.status = 'paid'
                            THEN COALESCE(public.member_fees.paid_at, now()) ELSE public.member_fees.paid_at END,
        refunded_at  = CASE WHEN EXCLUDED.status = 'refunded'
                            THEN COALESCE(public.member_fees.refunded_at, now()) ELSE public.member_fees.refunded_at END,
        note         = COALESCE(EXCLUDED.note, public.member_fees.note)
    RETURNING id INTO v_fee_id;

    RETURN jsonb_build_object('ok', true, 'reason', 'SAVED', 'fee_id', v_fee_id, 'amount_cents', v_amount);
END;
$$;

-- Le scritture dirette su `member_fees` (il gestionale non ne fa: passa dalle funzioni) solo per
-- admin e Tesoriere. La lettura resta com'è.
ALTER POLICY "member_fees_write_staff" ON "public"."member_fees"
    USING (public.can_access_finance())
    WITH CHECK (public.can_access_finance());

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Domanda d'ammissione: canale, IP e dispositivo solo dall'edge function
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.submit_member_application(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_trusted           boolean := (auth.role() = 'service_role');
    v_profile_id        uuid;
    v_client_id         uuid;
    v_year              integer := COALESCE((p_payload->>'year')::integer, EXTRACT(YEAR FROM "internal"."rome_today"())::integer);
    v_year_row          public.association_years%ROWTYPE;
    v_birth_date        date;
    v_is_minor          boolean;
    v_full_name         text;
    v_application_id    uuid;
BEGIN
    -- Chi fa la domanda: con la chiave di sistema (edge function member-application, che ha già
    -- verificato il token) l'utente arriva nel payload; altrimenti è chi chiama.
    IF v_trusted THEN
        v_profile_id := NULLIF(p_payload->>'user_id', '')::uuid;
    ELSE
        v_profile_id := auth.uid();
    END IF;

    IF v_profile_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    SELECT * INTO v_year_row FROM public.association_years WHERE year = v_year;
    IF NOT FOUND OR v_year_row.is_open = false THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'YEAR_NOT_OPEN');
    END IF;

    IF COALESCE(btrim(p_payload->>'first_name'), '') = ''
       OR COALESCE(btrim(p_payload->>'last_name'), '') = ''
       OR (p_payload->>'birth_date') IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MISSING_REQUIRED_FIELDS');
    END IF;

    IF (p_payload->>'accepted_statute') IS DISTINCT FROM 'true'
       OR (p_payload->>'accepted_privacy') IS DISTINCT FROM 'true' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ACCEPTANCE_REQUIRED');
    END IF;

    v_birth_date := (p_payload->>'birth_date')::date;
    v_is_minor := v_birth_date > ("internal"."rome_today"() - INTERVAL '18 years');

    IF v_is_minor AND (
        COALESCE(btrim(p_payload->>'guardian_full_name'), '') = ''
        OR (p_payload->>'guardian_consent') IS DISTINCT FROM 'true'
    ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'GUARDIAN_REQUIRED');
    END IF;

    v_full_name := btrim(p_payload->>'first_name') || ' ' || btrim(p_payload->>'last_name');

    -- Scheda cliente: la propria, oppure una nuova collegata al profilo
    SELECT c.id INTO v_client_id
      FROM public.clients c
     WHERE c.profile_id = v_profile_id
     ORDER BY c.created_at DESC NULLS LAST
     LIMIT 1;
    IF v_client_id IS NULL THEN
        INSERT INTO public.clients (full_name, email, phone, profile_id)
        SELECT v_full_name,
               COALESCE(NULLIF(btrim(p_payload->>'email'), ''), p.email),
               NULLIF(btrim(p_payload->>'phone'), ''),
               v_profile_id
        FROM public.profiles p WHERE p.id = v_profile_id
        RETURNING id INTO v_client_id;
    END IF;

    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.member_applications
        WHERE client_id = v_client_id AND year = v_year AND status = 'pending'
    ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'APPLICATION_ALREADY_PENDING');
    END IF;

    IF EXISTS (SELECT 1 FROM public.members WHERE client_id = v_client_id AND status = 'active') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_MEMBER');
    END IF;

    INSERT INTO public.member_applications (
        client_id, profile_id, year, channel, status,
        first_name, last_name, fiscal_code, birth_date, birth_place, birth_province,
        address_street, address_city, address_zip, address_province, email, phone,
        minor_at_submission, guardian_full_name, guardian_fiscal_code, guardian_relationship,
        guardian_email, guardian_phone, guardian_consent_at,
        accepted_statute_at, accepted_privacy_at, image_release, health_declaration,
        submitted_ip, submitted_user_agent
    )
    VALUES (
        v_client_id, v_profile_id, v_year,
        -- Canale, IP e dispositivo documentano l'accettazione (A7): valgono solo se li scrive
        -- l'edge function; chiamata direttamente, la domanda è «app» senza IP né dispositivo.
        CASE WHEN v_trusted AND p_payload->>'channel' IN ('app', 'site')
             THEN (p_payload->>'channel')::public.member_application_channel
             ELSE 'app'::public.member_application_channel END,
        'pending',
        btrim(p_payload->>'first_name'), btrim(p_payload->>'last_name'),
        NULLIF(btrim(upper(COALESCE(p_payload->>'fiscal_code', ''))), ''),
        v_birth_date,
        NULLIF(btrim(p_payload->>'birth_place'), ''), NULLIF(btrim(p_payload->>'birth_province'), ''),
        NULLIF(btrim(p_payload->>'address_street'), ''), NULLIF(btrim(p_payload->>'address_city'), ''),
        NULLIF(btrim(p_payload->>'address_zip'), ''), NULLIF(btrim(p_payload->>'address_province'), ''),
        NULLIF(btrim(p_payload->>'email'), ''), NULLIF(btrim(p_payload->>'phone'), ''),
        v_is_minor,
        NULLIF(btrim(p_payload->>'guardian_full_name'), ''),
        NULLIF(btrim(upper(COALESCE(p_payload->>'guardian_fiscal_code', ''))), ''),
        NULLIF(btrim(p_payload->>'guardian_relationship'), ''),
        NULLIF(btrim(p_payload->>'guardian_email'), ''),
        NULLIF(btrim(p_payload->>'guardian_phone'), ''),
        CASE WHEN v_is_minor THEN now() ELSE NULL END,
        now(), now(),
        CASE WHEN (p_payload->>'image_release') IS NULL THEN NULL
             ELSE (p_payload->>'image_release') = 'true' END,
        CASE WHEN (p_payload->>'health_declaration') IS NULL THEN NULL
             ELSE (p_payload->>'health_declaration') = 'true' END,
        CASE WHEN v_trusted THEN NULLIF(p_payload->>'ip', '')::inet END,
        CASE WHEN v_trusted THEN left(NULLIF(p_payload->>'user_agent', ''), 500) END
    )
    RETURNING id INTO v_application_id;

    -- La quota dell'anno diventa dovuta
    INSERT INTO public.member_fees (client_id, year, amount_cents, status)
    VALUES (v_client_id, v_year, v_year_row.fee_cents, 'due')
    ON CONFLICT (client_id, year) DO NOTHING;

    RETURN jsonb_build_object(
        'ok', true,
        'reason', 'SUBMITTED',
        'application_id', v_application_id,
        'client_id', v_client_id,
        'year', v_year,
        'fee_cents', v_year_row.fee_cents
    );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Domanda su carta per una persona nuova
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.staff_create_member_application(p_client_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_year              integer := COALESCE((p_payload->>'year')::integer, EXTRACT(YEAR FROM "internal"."rome_today"())::integer);
    v_year_row          public.association_years%ROWTYPE;
    v_birth_date        date;
    v_is_minor          boolean;
    v_application_id    uuid;
    v_client_id         uuid := p_client_id;
    v_email             text := NULLIF(btrim(p_payload->>'email'), '');
    v_existing          uuid;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF v_client_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.clients WHERE id = v_client_id AND deleted_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    SELECT * INTO v_year_row FROM public.association_years WHERE year = v_year;
    IF NOT FOUND OR v_year_row.is_open = false THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'YEAR_NOT_OPEN');
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.member_applications
        WHERE client_id = v_client_id AND year = v_year AND status = 'pending'
    ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'APPLICATION_ALREADY_PENDING');
    END IF;

    v_birth_date := (p_payload->>'birth_date')::date;
    IF v_birth_date IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MISSING_REQUIRED_FIELDS');
    END IF;
    v_is_minor := v_birth_date > ("internal"."rome_today"() - INTERVAL '18 years');

    -- Persona nuova: la scheda nasce qui, dopo tutti i controlli e nella stessa transazione della
    -- domanda (prima la creava il gestionale e restava anche se la domanda veniva rifiutata).
    IF v_client_id IS NULL THEN
        IF COALESCE(btrim(p_payload->>'first_name'), '') = '' OR COALESCE(btrim(p_payload->>'last_name'), '') = '' THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'MISSING_REQUIRED_FIELDS');
        END IF;
        IF v_email IS NOT NULL THEN
            SELECT id INTO v_existing FROM public.clients WHERE lower(email) = lower(v_email) LIMIT 1;
            IF v_existing IS NOT NULL THEN
                RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_EMAIL_EXISTS', 'client_id', v_existing);
            END IF;
        END IF;
        INSERT INTO public.clients (full_name, email, phone, birthday, is_active)
        VALUES (btrim(p_payload->>'first_name') || ' ' || btrim(p_payload->>'last_name'),
                v_email, NULLIF(btrim(p_payload->>'phone'), ''), v_birth_date, true)
        RETURNING id INTO v_client_id;
    END IF;

    INSERT INTO public.member_applications (
        client_id, year, channel, status,
        first_name, last_name, fiscal_code, birth_date, birth_place, birth_province,
        address_street, address_city, address_zip, address_province, email, phone,
        minor_at_submission, guardian_full_name, guardian_fiscal_code, guardian_relationship,
        guardian_email, guardian_phone, guardian_consent_at,
        accepted_statute_at, accepted_privacy_at, image_release, health_declaration,
        submitted_at
    )
    VALUES (
        v_client_id, v_year, 'paper', 'pending',
        btrim(p_payload->>'first_name'), btrim(p_payload->>'last_name'),
        NULLIF(btrim(upper(COALESCE(p_payload->>'fiscal_code', ''))), ''),
        v_birth_date,
        NULLIF(btrim(p_payload->>'birth_place'), ''), NULLIF(btrim(p_payload->>'birth_province'), ''),
        NULLIF(btrim(p_payload->>'address_street'), ''), NULLIF(btrim(p_payload->>'address_city'), ''),
        NULLIF(btrim(p_payload->>'address_zip'), ''), NULLIF(btrim(p_payload->>'address_province'), ''),
        NULLIF(btrim(p_payload->>'email'), ''), NULLIF(btrim(p_payload->>'phone'), ''),
        v_is_minor,
        NULLIF(btrim(p_payload->>'guardian_full_name'), ''),
        NULLIF(btrim(upper(COALESCE(p_payload->>'guardian_fiscal_code', ''))), ''),
        NULLIF(btrim(p_payload->>'guardian_relationship'), ''),
        NULLIF(btrim(p_payload->>'guardian_email'), ''),
        NULLIF(btrim(p_payload->>'guardian_phone'), ''),
        CASE WHEN v_is_minor THEN COALESCE((p_payload->>'guardian_consent_at')::timestamptz, now()) ELSE NULL END,
        COALESCE((p_payload->>'accepted_statute_at')::timestamptz, now()),
        COALESCE((p_payload->>'accepted_privacy_at')::timestamptz, now()),
        CASE WHEN (p_payload->>'image_release') IS NULL THEN NULL
             ELSE (p_payload->>'image_release') = 'true' END,
        CASE WHEN (p_payload->>'health_declaration') IS NULL THEN NULL
             ELSE (p_payload->>'health_declaration') = 'true' END,
        COALESCE((p_payload->>'submitted_at')::timestamptz, now())
    )
    RETURNING id INTO v_application_id;

    INSERT INTO public.member_fees (client_id, year, amount_cents, status, created_by)
    VALUES (v_client_id, v_year, v_year_row.fee_cents, 'due', auth.uid())
    ON CONFLICT (client_id, year) DO NOTHING;

    RETURN jsonb_build_object('ok', true, 'reason', 'CREATED', 'application_id', v_application_id, 'client_id', v_client_id);
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Note interne dello staff
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS "public"."client_staff_notes" (
    "client_id"  uuid PRIMARY KEY REFERENCES "public"."clients"("id") ON DELETE CASCADE,
    "notes"      text NOT NULL DEFAULT '',
    "updated_at" timestamptz NOT NULL DEFAULT now(),
    "updated_by" uuid
);

COMMENT ON TABLE "public"."client_staff_notes" IS
  'Note interne dello staff su una scheda cliente: le legge e le scrive solo lo staff (prima stavano in clients.notes, leggibile dalla persona).';

ALTER TABLE "public"."client_staff_notes" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "client_staff_notes_staff_all" ON "public"."client_staff_notes"
    AS PERMISSIVE FOR ALL TO authenticated
    USING (public.is_staff()) WITH CHECK (public.is_staff());

REVOKE ALL ON TABLE "public"."client_staff_notes" FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."client_staff_notes" TO authenticated;
GRANT ALL ON TABLE "public"."client_staff_notes" TO service_role;

CREATE OR REPLACE TRIGGER "update_client_staff_notes_updated_at"
BEFORE UPDATE ON "public"."client_staff_notes"
FOR EACH ROW EXECUTE FUNCTION "internal"."update_updated_at_column"();

-- Aggiunge una riga in fondo alle note (per i messaggi automatici: account eliminato, ricreato).
CREATE OR REPLACE FUNCTION "internal"."append_client_staff_note"(p_client_id uuid, p_line text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  INSERT INTO public.client_staff_notes (client_id, notes)
  VALUES (p_client_id, btrim(p_line))
  ON CONFLICT (client_id) DO UPDATE
     SET notes = concat_ws(E'\n', NULLIF(btrim(public.client_staff_notes.notes), ''), btrim(p_line)),
         updated_at = now();
$$;

-- Il gestionale di prima scrive ancora il testo intero in `clients.notes`: lo si sposta nelle note
-- dello staff e sulla scheda resta vuoto. Un testo vuoto non cancella le note (un modulo che non
-- le ha mai lette non deve azzerarle).
CREATE OR REPLACE FUNCTION "internal"."divert_client_notes"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NULLIF(btrim(COALESCE(NEW.notes, '')), '') IS NOT NULL THEN
        IF TG_OP = 'INSERT' THEN
            -- La riga della scheda non esiste ancora: le note si scrivono dopo (trigger AFTER).
            RETURN NEW;
        END IF;
        INSERT INTO public.client_staff_notes (client_id, notes, updated_by)
        VALUES (NEW.id, btrim(NEW.notes), auth.uid())
        ON CONFLICT (client_id) DO UPDATE
           SET notes = EXCLUDED.notes, updated_at = now(), updated_by = EXCLUDED.updated_by;
    END IF;
    NEW.notes := NULL;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "internal"."divert_client_notes_after_insert"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NULLIF(btrim(COALESCE(NEW.notes, '')), '') IS NOT NULL THEN
        INSERT INTO public.client_staff_notes (client_id, notes, updated_by)
        VALUES (NEW.id, btrim(NEW.notes), auth.uid())
        ON CONFLICT (client_id) DO UPDATE
           SET notes = EXCLUDED.notes, updated_at = now(), updated_by = EXCLUDED.updated_by;
        UPDATE public.clients SET notes = NULL WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "clients_divert_notes" ON "public"."clients";
CREATE TRIGGER "clients_divert_notes"
BEFORE UPDATE OF "notes" ON "public"."clients"
FOR EACH ROW EXECUTE FUNCTION "internal"."divert_client_notes"();

DROP TRIGGER IF EXISTS "clients_divert_notes_insert" ON "public"."clients";
CREATE TRIGGER "clients_divert_notes_insert"
AFTER INSERT ON "public"."clients"
FOR EACH ROW EXECUTE FUNCTION "internal"."divert_client_notes_after_insert"();

-- Le note che ci sono oggi passano nella tabella nuova; scheda e profilo restano senza.
INSERT INTO "public"."client_staff_notes" (client_id, notes)
SELECT id, btrim(notes) FROM "public"."clients"
 WHERE NULLIF(btrim(COALESCE(notes, '')), '') IS NOT NULL
ON CONFLICT (client_id) DO NOTHING;

ALTER TABLE "public"."clients" DISABLE TRIGGER "clients_divert_notes";
UPDATE "public"."clients" SET notes = NULL WHERE notes IS NOT NULL;
ALTER TABLE "public"."clients" ENABLE TRIGGER "clients_divert_notes";
UPDATE "public"."profiles" SET notes = NULL WHERE notes IS NOT NULL;

COMMENT ON COLUMN "public"."clients"."notes" IS
  'Non usare: le note dello staff stanno in client_staff_notes (un trigger ci sposta quello che arriva qui).';

-- Il profilo non copia più le note della scheda.
CREATE OR REPLACE FUNCTION "internal"."sync_profile_from_client"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.profile_id IS NOT NULL THEN
        UPDATE public.profiles
           SET full_name = NEW.full_name,
               phone = NEW.phone,
               email = COALESCE(NEW.email, profiles.email)
         WHERE id = NEW.profile_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_account_data(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_role      public.user_role;
    v_client_id uuid;
    v_lesson_id uuid;
    v_today     text := to_char((now() AT TIME ZONE 'Europe/Rome')::date, 'DD/MM/YYYY');
    v_clients   uuid[] := ARRAY[]::uuid[];
BEGIN
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'USER_NOT_FOUND');
    END IF;

    SELECT role INTO v_role FROM public.profiles WHERE id = p_user_id;
    -- Chi lavora nello studio chiude l'account parlando con un admin: il suo profilo regge lezioni,
    -- compensi, annunci e registri
    IF v_role IS NOT NULL AND v_role <> 'user' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'STAFF_ACCOUNT');
    END IF;

    FOR v_client_id IN SELECT id FROM public.clients WHERE profile_id = p_user_id LOOP
        v_clients := v_clients || v_client_id;

        -- Prenotazioni future: disdette come dall'app (i trigger restituiscono l'ingresso e offrono
        -- il posto a chi è in lista d'attesa). Quelle passate restano: sono presenze e Finanze.
        UPDATE public.bookings b
           SET status = 'canceled'
          FROM public.lessons l
         WHERE l.id = b.lesson_id
           AND b.client_id = v_client_id
           AND b.status = 'booked'
           AND l.starts_at > now();

        -- Iscrizioni a eventi futuri, tranne quelle già pagate: il rimborso lo decide lo staff (D4)
        UPDATE public.event_bookings eb
           SET status = 'canceled'
          FROM public.events e
         WHERE e.id = eb.event_id
           AND eb.client_id = v_client_id
           AND eb.status = 'booked'
           AND e.starts_at > now()
           AND NOT EXISTS (
               SELECT 1 FROM public.transactions t
                WHERE t.event_booking_id = eb.id AND t.status IN ('paid', 'partially_refunded'));

        -- Lista d'attesa: il posto passa a chi viene dopo
        FOR v_lesson_id IN
            UPDATE public.waitlist SET status = 'left'
             WHERE client_id = v_client_id AND status IN ('waiting', 'offered')
            RETURNING lesson_id
        LOOP
            PERFORM "internal"."fill_waitlist_offers"(v_lesson_id);
        END LOOP;

        UPDATE public.bussola_requests SET status = 'cancelled'
         WHERE client_id = v_client_id AND status = 'pending';

        -- I contenuti personali dell'app
        DELETE FROM public.journal_entries          WHERE client_id = v_client_id;
        DELETE FROM public.practice_user_state      WHERE client_id = v_client_id;
        DELETE FROM public.notification_queue       WHERE client_id = v_client_id;
        DELETE FROM public.notification_reads       WHERE client_id = v_client_id;
        DELETE FROM public.notification_logs        WHERE client_id = v_client_id;
        DELETE FROM public.notification_preferences WHERE client_id = v_client_id;
        DELETE FROM public.notification_settings    WHERE client_id = v_client_id;
        DELETE FROM public.device_tokens            WHERE client_id = v_client_id;

        -- La scheda resta (libro soci, quote, ricevute e incassi la usano), senza i dati che non
        -- servono più. Nome ed email restano: chi torna con la stessa email la ritrova.
        UPDATE public.clients
           SET is_active = false,
               deleted_at = COALESCE(deleted_at, now()),
               phone = NULL,
               birthday = NULL,
               newsletter_subscribed = false
         WHERE id = v_client_id;

        PERFORM "internal"."append_client_staff_note"(
            v_client_id, 'Account dell''app eliminato dalla persona il ' || v_today || '.');

        -- Le segnalazioni restano allo staff, intestate alla scheda
        UPDATE public.bug_reports
           SET created_by_client_id = v_client_id, created_by_user_id = NULL
         WHERE created_by_user_id = p_user_id;

        -- Vecchie iscrizioni agli eventi legate all'utente (prima delle schede): passano alla scheda
        UPDATE public.event_bookings
           SET client_id = v_client_id, user_id = NULL
         WHERE user_id = p_user_id;
    END LOOP;

    -- Senza scheda non c'è a chi intestarle: vanno via con l'account
    DELETE FROM public.bug_reports    WHERE created_by_user_id = p_user_id;
    DELETE FROM public.event_bookings WHERE user_id = p_user_id;

    UPDATE public.profiles
       SET deleted_at = COALESCE(deleted_at, now()),
           full_name = 'Account eliminato',
           phone = NULL,
           avatar_url = NULL,
           notes = NULL
     WHERE id = p_user_id;

    RETURN jsonb_build_object('ok', true, 'client_ids', to_jsonb(v_clients));
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Registrazione
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."handle_new_user"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_client clients%ROWTYPE;
    v_found boolean := false;
    v_full_name text;
    v_meta jsonb := COALESCE(new.raw_user_meta_data, '{}'::jsonb);
    v_opt_out boolean := lower(COALESCE(v_meta->>'newsletter_opt_out', '')) IN ('true', '1', 'yes');
    v_privacy boolean := NULLIF(btrim(COALESCE(v_meta->>'accepted_privacy_at', '')), '') IS NOT NULL;
    v_terms boolean := NULLIF(btrim(COALESCE(v_meta->>'accepted_terms_at', '')), '') IS NOT NULL;
BEGIN
    -- Una scheda con la stessa email, senza guardare le maiuscole: prima quella scritta uguale,
    -- poi quella non ancora collegata a un account.
    SELECT * INTO v_client
      FROM clients
     WHERE lower(email) = lower(new.email)
       AND deleted_at IS NULL
     ORDER BY (email = new.email) DESC, (profile_id IS NULL) DESC, created_at
     LIMIT 1;
    v_found := FOUND;

    -- Altrimenti la scheda di chi aveva eliminato l'account (senza profilo): torna attiva.
    IF NOT v_found THEN
        SELECT * INTO v_client
          FROM clients
         WHERE lower(email) = lower(new.email)
           AND deleted_at IS NOT NULL
           AND profile_id IS NULL
         ORDER BY deleted_at DESC
         LIMIT 1;
        v_found := FOUND;

        IF v_found THEN
            UPDATE clients SET deleted_at = NULL, is_active = true
             WHERE id = v_client.id
             RETURNING * INTO v_client;
            PERFORM "internal"."append_client_staff_note"(
                v_client.id,
                'Account dell''app ricreato il ' || to_char("internal"."rome_today"(), 'DD/MM/YYYY') || '.');
        END IF;
    END IF;

    IF v_found THEN
        INSERT INTO public.profiles (id, email, role, full_name, phone, accepted_privacy_at, accepted_terms_at)
        VALUES (new.id, new.email, 'user'::user_role, v_client.full_name, v_client.phone,
                CASE WHEN v_privacy THEN now() END, CASE WHEN v_terms THEN now() END);

        UPDATE clients
           SET profile_id = new.id,
               newsletter_subscribed = CASE WHEN v_opt_out THEN false ELSE newsletter_subscribed END
         WHERE id = v_client.id;
    ELSE
        v_full_name := COALESCE(
            NULLIF(btrim(v_meta->>'full_name'), ''),
            NULLIF(btrim(v_meta->>'name'), ''),
            split_part(new.email, '@', 1),
            'Utente'
        );

        INSERT INTO public.profiles (id, email, role, accepted_privacy_at, accepted_terms_at)
        VALUES (new.id, new.email, 'user'::user_role,
                CASE WHEN v_privacy THEN now() END, CASE WHEN v_terms THEN now() END);

        INSERT INTO public.clients (profile_id, email, full_name, phone, is_active, newsletter_subscribed)
        VALUES (new.id, new.email, v_full_name, NULLIF(btrim(v_meta->>'phone'), ''), true, NOT v_opt_out);
    END IF;

    RETURN new;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Newsletter dall'app
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."set_my_newsletter_subscription"(p_subscribed boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_client_id uuid := public.get_my_client_id();
BEGIN
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;
    IF p_subscribed IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_VALUE');
    END IF;

    UPDATE public.clients SET newsletter_subscribed = p_subscribed WHERE id = v_client_id;
    RETURN jsonb_build_object('ok', true, 'subscribed', p_subscribed);
END;
$$;

COMMENT ON FUNCTION "public"."set_my_newsletter_subscription"(boolean) IS
  'La persona si iscrive o si disiscrive dalla newsletter (dall''app).';

REVOKE ALL ON FUNCTION "public"."set_my_newsletter_subscription"(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION "public"."set_my_newsletter_subscription"(boolean) TO authenticated, service_role;

REVOKE ALL ON FUNCTION "internal"."append_client_staff_note"(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION "internal"."divert_client_notes"() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION "internal"."divert_client_notes_after_insert"() FROM PUBLIC, anon, authenticated;
