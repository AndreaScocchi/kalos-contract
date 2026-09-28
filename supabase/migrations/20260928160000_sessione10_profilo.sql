-- Migration 20260928160000: profilo e contenuti dell'app (sessione 10)
--
-- 1. La Bussola è dei soci (D6). Il Community Pass è spento e inutilizzato dalla sessione 3, ma
--    `request_bussola` chiedeva ancora un Pass attivo: nessunə poteva chiederla. Ora la chiede chi è
--    sociə in regola, cioè chi può partecipare alle attività (`internal.member_booking_status` in
--    `ok` o `fee_due_grace`), sempre, anche con "solo soci" spenta: è un vantaggio dei soci.
--    `cancel_bussola_request`: dall'app si ritira solo una richiesta ancora da fissare; quella già
--    fissata ha la sua lezione individuale, e la si sposta parlando con lo studio.
-- 2. Le proprie ricevute. I clienti non leggono `transactions` (ci sono le note dello staff) né
--    `receipts`: due funzioni restituiscono solo le ricevute degli incassi della propria scheda,
--    `get_my_receipts` per l'elenco e `get_my_receipt` con i dati del PDF, che `receipt-pdf` usa
--    quando chi chiede non è staff.
-- 3. L'interruttore `home_practice`, spento: finché non ci sono pratiche vere (oggi solo quelle di
--    prova) la Pratica a casa nell'app la vede solo lo staff.
--
-- Compatibilità: nessuna tabella o colonna toccata; `request_bussola` e `cancel_bussola_request`
-- hanno la stessa firma (le usava solo la KMP, archiviata); due funzioni nuove, aperte solo ad
-- `authenticated`; un interruttore nuovo, spento.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 D6, H5 e §0-decies.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. La Bussola per i soci
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."request_bussola"(
    "p_preferred_at" timestamp with time zone DEFAULT NULL,
    "p_note"         "text"                   DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_gate      text;
    v_note      text := NULLIF(btrim(COALESCE(p_note, '')), '');
    v_id        uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    v_gate := "internal"."member_booking_status"(v_client_id);

    -- Chi può partecipare alle attività: sociə ammessə, con la quota versata o ancora nei tempi
    IF v_gate NOT IN ('ok', 'fee_due_grace') THEN
        RETURN jsonb_build_object(
            'ok', false,
            'reason', CASE
                WHEN v_gate IN ('pending_admission', 'fee_unpaid') THEN 'PENDING_ADMISSION'
                WHEN v_gate = 'fee_overdue' THEN 'MEMBERSHIP_FEE_DUE'
                ELSE 'NOT_A_MEMBER'
            END,
            'member_status', v_gate);
    END IF;

    IF length(v_note) > 1000 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOTE_TOO_LONG');
    END IF;

    -- Una sola richiesta aperta (da fissare o fissata) alla volta
    IF EXISTS (
        SELECT 1 FROM public.bussola_requests
         WHERE client_id = v_client_id AND status IN ('pending', 'scheduled')
    ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_OPEN');
    END IF;

    BEGIN
        INSERT INTO public.bussola_requests (client_id, status, preferred_at, note, metadata)
        VALUES (v_client_id, 'pending', p_preferred_at, v_note, jsonb_build_object('channel', 'app'))
        RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
        -- Due tocchi insieme: l'indice di una richiesta aperta per persona tiene la prima
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_OPEN');
    END;

    RETURN jsonb_build_object('ok', true, 'request_id', v_id);
END;
$$;

COMMENT ON FUNCTION "public"."request_bussola"(timestamp with time zone, "text") IS
    'Sessione 10 (D6): unə sociə in regola chiede una Bussola (consulenza 1:1 di 15''). Una richiesta aperta per volta; lo staff la fissa come lezione individuale.';

CREATE OR REPLACE FUNCTION "public"."cancel_bussola_request"("p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_req       public.bussola_requests%ROWTYPE;
    v_staff     boolean := public.is_staff();
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    SELECT * INTO v_req FROM public.bussola_requests WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FOUND');
    END IF;

    -- Lo staff annulla qualsiasi richiesta; il cliente solo le proprie
    IF NOT v_staff THEN
        v_client_id := public.get_my_client_id();
        IF v_client_id IS NULL OR v_req.client_id <> v_client_id THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FOUND');
        END IF;
    END IF;

    IF v_req.status NOT IN ('pending', 'scheduled') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_CANCELLABLE');
    END IF;

    -- Già fissata: c'è una lezione individuale, la si sposta o si disdice parlando con lo studio
    IF NOT v_staff AND v_req.status = 'scheduled' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_SCHEDULED');
    END IF;

    UPDATE public.bussola_requests
       SET status = 'cancelled', updated_at = now()
     WHERE id = p_request_id;

    RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION "public"."cancel_bussola_request"("uuid") IS
    'Annulla una richiesta Bussola: lo staff qualsiasi richiesta aperta, il cliente solo la propria ancora da fissare (sessione 10).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Le proprie ricevute
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."get_my_receipts"()
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_items     jsonb;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', true, 'items', '[]'::jsonb);
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id', r.id,
               'full_number', r.full_number,
               'year', r.year,
               'number', r.number,
               'issued_at', r.issued_at,
               'occurred_on', t.occurred_on,
               'causale', r.causale,
               'amount_cents', r.amount_cents,
               'kind', t.kind,
               'method', t.method,
               'source', t.source,
               'transaction_status', t.status,
               'voided_at', r.voided_at,
               'sent_at', r.sent_at)
             ORDER BY r.issued_at DESC, r.number DESC), '[]'::jsonb)
      INTO v_items
      FROM public.receipts r
      JOIN public.transactions t ON t.id = r.transaction_id
     WHERE t.client_id = v_client_id;

    RETURN jsonb_build_object('ok', true, 'items', v_items);
END;
$$;

COMMENT ON FUNCTION "public"."get_my_receipts"() IS
    'Sessione 10: le ricevute degli incassi della propria scheda, dalla più recente (i clienti non leggono `receipts` e `transactions`).';

-- Gli stessi campi che `receipt-pdf` legge per lo staff (`RECEIPT_PDF_SELECT`), per una ricevuta propria
CREATE OR REPLACE FUNCTION "public"."get_my_receipt"("p_receipt_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_receipt   public.receipts%ROWTYPE;
    v_tx        public.transactions%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    SELECT * INTO v_receipt FROM public.receipts WHERE id = p_receipt_id;
    IF FOUND THEN
        SELECT * INTO v_tx FROM public.transactions WHERE id = v_receipt.transaction_id;
    END IF;
    -- Inesistente o di un'altra persona: la stessa risposta
    IF v_receipt.id IS NULL OR v_client_id IS NULL OR v_tx.client_id IS DISTINCT FROM v_client_id THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'RECEIPT_NOT_FOUND');
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'receipt', jsonb_build_object(
            'id', v_receipt.id,
            'full_number', v_receipt.full_number,
            'issued_at', v_receipt.issued_at,
            'recipient_name', v_receipt.recipient_name,
            'recipient_fiscal_code', v_receipt.recipient_fiscal_code,
            'recipient_address', v_receipt.recipient_address,
            'issuer_snapshot', v_receipt.issuer_snapshot,
            'causale', v_receipt.causale,
            'amount_cents', v_receipt.amount_cents,
            'stamp_duty_cents', v_receipt.stamp_duty_cents,
            'voided_at', v_receipt.voided_at,
            'void_reason', v_receipt.void_reason,
            'transaction', jsonb_build_object('method', v_tx.method, 'occurred_on', v_tx.occurred_on)));
END;
$$;

COMMENT ON FUNCTION "public"."get_my_receipt"("uuid") IS
    'Sessione 10: i dati per il PDF di una propria ricevuta (la usa `receipt-pdf` quando chi chiede non è staff).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Pratica a casa: l'interruttore
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO "public"."feature_flags" ("key", "enabled", "description") VALUES
    ('home_practice', false,
     'Pratica a casa nell''app per chi frequenta. Spento: la vede solo lo staff, finché non ci sono pratiche vere (sessione 10).')
ON CONFLICT ("key") DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Permessi: le funzioni nuove nascono chiuse; si aprono solo queste, ad authenticated
-- ─────────────────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION "public"."get_my_receipts"() TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."get_my_receipt"("uuid") TO "authenticated";
