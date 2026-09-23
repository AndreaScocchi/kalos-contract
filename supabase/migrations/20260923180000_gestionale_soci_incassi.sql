-- Migration 20260923180000: le tre funzioni che mancavano al gestionale per soci e incassi
-- (sessione 4)
--
-- La sessione 3 ha dato al database soci, quote, transazioni e ricevute. Scrivendo il gestionale
-- sono emersi tre gesti che lo schema non permetteva di fare bene:
--
--   1. `staff_settle_transaction` — saldare un "da saldare" (E2). Le operatrici registrano gli
--      incassi ma non possono modificare una transazione già scritta (`transactions_update_finance`,
--      E3): senza questa funzione un abbonamento segnato "da saldare" restava tale finché non
--      interveniva un admin. Qui si fa UNA cosa sola: `pending` → `paid`, con metodo e data
--      dell'incasso vero, più la ricevuta. Correggere o annullare resta cosa da Finanze.
--   2. `staff_pay_member_fee`     — incassare la quota di un anno in un gesto solo: crea la riga
--      della quota se manca, rifiuta il doppio pagamento, registra l'incasso e la ricevuta, tutto
--      nella stessa transazione. Farlo dal gestionale con `staff_set_member_fee` più
--      `staff_register_payment` voleva dire due chiamate, e `staff_set_member_fee(…, 'due')` su una
--      quota già pagata la riportava a "da pagare".
--   3. `staff_get_member_statuses` — lo stato rispetto all'iscrizione di più persone insieme, per il
--      segno accanto a chi è prenotatə ma ancora in attesa di ammissione (A7). La regola vive in
--      `internal.member_booking_status`, che dall'API non si raggiunge: questa funzione la espone
--      allo staff invece di ricopiarla nel gestionale, dove prima o poi andrebbe fuori sincrono.
--
-- In più (§4) una correzione a `issue_receipt`: la ricevuta della quota, pagata prima della delibera,
-- usciva senza codice fiscale né indirizzo.
--
-- Compatibilità: tre funzioni nuove e il corpo di `issue_receipt` corretto a firma invariata; nessuna
-- tabella, colonna o firma esistente toccata.
-- Vedi docs/PIANO-APS-E-NUOVA-APP.md §3 (A5, A7, A8, E2, E3) e ACCESS_MODEL.md.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Saldare un incasso "da saldare"
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_settle_transaction"(
    "p_transaction_id" "uuid",
    "p_method" "public"."payment_method" DEFAULT NULL,
    "p_occurred_on" "date" DEFAULT NULL,
    "p_issue_receipt" boolean DEFAULT true,
    "p_causale" "text" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_tx        public.transactions%ROWTYPE;
    v_receipt   jsonb := NULL;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    SELECT * INTO v_tx FROM public.transactions WHERE id = p_transaction_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_FOUND');
    END IF;

    -- Solo un "da saldare" si salda: un incasso già pagato, rimborsato o annullato si corregge
    -- dalle Finanze, non da qui.
    IF v_tx.status <> 'pending' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_PENDING', 'status', v_tx.status);
    END IF;

    -- La data dell'incasso è quella in cui il denaro arriva, non quella in cui è nato l'abbonamento:
    -- da qui dipende anche l'anno della ricevuta.
    UPDATE public.transactions
       SET status      = 'paid',
           method      = COALESCE(p_method, v_tx.method),
           occurred_on = COALESCE(p_occurred_on, CURRENT_DATE)
     WHERE id = p_transaction_id;

    IF v_tx.member_fee_id IS NOT NULL THEN
        UPDATE public.member_fees
           SET status = 'paid', paid_at = COALESCE(paid_at, now()), transaction_id = p_transaction_id
         WHERE id = v_tx.member_fee_id;
    END IF;

    IF p_issue_receipt THEN
        v_receipt := public.issue_receipt(p_transaction_id, NULLIF(btrim(COALESCE(p_causale, '')), ''));
    END IF;

    RETURN jsonb_build_object('ok', true, 'reason', 'SETTLED',
                              'transaction_id', p_transaction_id, 'receipt', v_receipt);
END;
$$;

ALTER FUNCTION "public"."staff_settle_transaction"("uuid", "public"."payment_method", "date", boolean, "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_settle_transaction"("uuid", "public"."payment_method", "date", boolean, "text") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_settle_transaction"("uuid", "public"."payment_method", "date", boolean, "text") IS
    'Salda un incasso "da saldare" (E2): da pending a paid, con metodo e data dell''incasso vero, ed emette la ricevuta. Lo può fare tutto lo staff; correggere o annullare un incasso resta alle Finanze (E3).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Incassare la quota di un anno
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_pay_member_fee"(
    "p_client_id" "uuid",
    "p_year" integer,
    "p_amount_cents" integer DEFAULT NULL,
    "p_method" "public"."payment_method" DEFAULT 'cash'::"public"."payment_method",
    "p_occurred_on" "date" DEFAULT NULL,
    "p_issue_receipt" boolean DEFAULT true,
    "p_note" "text" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_year_row  public.association_years%ROWTYPE;
    v_fee       public.member_fees%ROWTYPE;
    v_amount    integer;
    v_payment   jsonb;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.clients WHERE id = p_client_id AND deleted_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    SELECT * INTO v_year_row FROM public.association_years WHERE year = p_year;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'YEAR_NOT_FOUND');
    END IF;
    IF v_year_row.is_open = false THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'YEAR_NOT_OPEN');
    END IF;

    -- L'importo lo delibera il Consiglio Direttivo (A8). Finché è NULL si può comunque incassare
    -- indicandolo a mano, ma non si inventa.
    v_amount := COALESCE(p_amount_cents, v_year_row.fee_cents);
    IF v_amount IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'FEE_AMOUNT_NOT_SET');
    END IF;
    IF v_amount <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'INVALID_AMOUNT');
    END IF;

    SELECT * INTO v_fee FROM public.member_fees
     WHERE client_id = p_client_id AND year = p_year
       FOR UPDATE;

    IF FOUND THEN
        IF v_fee.status = 'paid' THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'FEE_ALREADY_PAID', 'fee_id', v_fee.id);
        END IF;
        IF v_fee.status = 'waived' THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'FEE_WAIVED', 'fee_id', v_fee.id);
        END IF;
        -- `due`, oppure `refunded` (domanda respinta e poi ripresentata): si paga di nuovo
        UPDATE public.member_fees
           SET amount_cents = v_amount,
               note = COALESCE(NULLIF(btrim(COALESCE(p_note, '')), ''), note)
         WHERE id = v_fee.id;
    ELSE
        INSERT INTO public.member_fees (client_id, year, amount_cents, status, note, created_by)
        VALUES (p_client_id, p_year, v_amount, 'due',
                NULLIF(btrim(COALESCE(p_note, '')), ''), auth.uid())
        RETURNING * INTO v_fee;
    END IF;

    -- Stesso gesto di ogni altro incasso: `staff_register_payment` segna la quota come pagata e
    -- collega la transazione. Tutto nella stessa transazione del database: o riesce tutto o niente.
    v_payment := public.staff_register_payment(jsonb_build_object(
        'client_id', p_client_id,
        'kind', 'membership_fee',
        'amount_cents', v_amount,
        'method', p_method,
        'source', 'studio',
        'status', 'paid',
        'occurred_on', COALESCE(p_occurred_on, CURRENT_DATE),
        'member_fee_id', v_fee.id,
        'description', 'Quota associativa ' || p_year::text,
        'note', p_note,
        'issue_receipt', p_issue_receipt,
        'causale', 'Quota associativa ' || p_year::text
    ));

    IF COALESCE((v_payment->>'ok')::boolean, false) = false THEN
        RAISE EXCEPTION 'staff_register_payment ha rifiutato la quota: %', v_payment->>'reason';
    END IF;

    RETURN jsonb_build_object(
        'ok', true, 'reason', 'PAID',
        'fee_id', v_fee.id,
        'amount_cents', v_amount,
        'transaction_id', v_payment->>'transaction_id',
        'receipt', v_payment->'receipt'
    );
END;
$$;

ALTER FUNCTION "public"."staff_pay_member_fee"("uuid", integer, integer, "public"."payment_method", "date", boolean, "text") OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_pay_member_fee"("uuid", integer, integer, "public"."payment_method", "date", boolean, "text") TO "authenticated";
COMMENT ON FUNCTION "public"."staff_pay_member_fee"("uuid", integer, integer, "public"."payment_method", "date", boolean, "text") IS
    'Incassa la quota associativa di un anno in un gesto solo: crea la quota se manca, rifiuta il doppio pagamento, registra l''incasso ed emette la ricevuta (A8, E2).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Lo stato di più persone rispetto all'iscrizione
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."staff_get_member_statuses"("p_client_ids" "uuid"[])
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    STABLE
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_statuses jsonb;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    SELECT COALESCE(jsonb_object_agg(ids.client_id, "internal"."member_booking_status"(ids.client_id)), '{}'::jsonb)
      INTO v_statuses
      FROM (SELECT DISTINCT unnest(p_client_ids) AS client_id) ids
     WHERE ids.client_id IS NOT NULL;

    RETURN jsonb_build_object(
        'ok', true,
        'members_only', "internal"."members_only_enabled"(),
        'statuses', v_statuses
    );
END;
$$;

ALTER FUNCTION "public"."staff_get_member_statuses"("uuid"[]) OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION "public"."staff_get_member_statuses"("uuid"[]) TO "authenticated";
COMMENT ON FUNCTION "public"."staff_get_member_statuses"("uuid"[]) IS
    'Stato rispetto all''iscrizione di più persone (ok, fee_due_grace, pending_admission, fee_unpaid, fee_overdue, ceased, no_application) e se la regola "solo soci" è accesa. Espone allo staff la regola di internal.member_booking_status senza ricopiarla.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Ricevuta: i dati di chi paga anche prima dell'ammissione
-- ─────────────────────────────────────────────────────────────────────────────
--
-- `issue_receipt` prendeva codice fiscale e indirizzo solo dalla domanda di chi è GIÀ sociə
-- (members.application_id). Ma la quota si paga prima della delibera (A7): la ricevuta della quota,
-- la prima e la più importante, usciva sempre senza codice fiscale. Ora, se la persona non è ancora
-- nel libro soci, si usa la sua domanda più recente non respinta né ritirata.
-- Già che c'è, l'indirizzo si scrive come si legge: "Via…, 34074 Monfalcone (GO)".
-- Firma, permessi e tutto il resto del corpo restano identici.

CREATE OR REPLACE FUNCTION public.issue_receipt(p_transaction_id uuid, p_causale text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_tx            public.transactions%ROWTYPE;
    v_settings      public.association_settings%ROWTYPE;
    v_year          integer;
    v_number        integer;
    v_full_number   text;
    v_name          text;
    v_fiscal_code   text;
    v_address       text;
    v_stamp         integer := 0;
    v_causale       text;
    v_receipt_id    uuid;
BEGIN
    IF NOT public.is_staff() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_STAFF');
    END IF;

    SELECT * INTO v_tx FROM public.transactions WHERE id = p_transaction_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_FOUND');
    END IF;

    IF v_tx.amount_cents <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AN_INCOME');
    END IF;

    IF v_tx.status <> 'paid' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_PAID');
    END IF;

    IF EXISTS (SELECT 1 FROM public.receipts WHERE transaction_id = p_transaction_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'RECEIPT_ALREADY_ISSUED');
    END IF;

    SELECT * INTO v_settings FROM public.association_settings WHERE id = true;

    -- Dati di chi riceve: prima la domanda con cui è entratə nel libro soci; se non è ancora sociə
    -- (la quota si paga prima della delibera), la sua domanda più recente ancora valida.
    SELECT COALESCE(c.full_name, btrim(a.first_name || ' ' || a.last_name)),
           a.fiscal_code,
           NULLIF(concat_ws(', ',
               NULLIF(btrim(a.address_street), ''),
               NULLIF(btrim(concat_ws(' ',
                   NULLIF(btrim(a.address_zip), ''),
                   NULLIF(btrim(a.address_city), ''),
                   CASE WHEN NULLIF(btrim(a.address_province), '') IS NOT NULL
                        THEN '(' || btrim(a.address_province) || ')' END)), '')
           ), '')
      INTO v_name, v_fiscal_code, v_address
      FROM public.clients c
      LEFT JOIN public.members m ON m.client_id = c.id
      LEFT JOIN LATERAL (
          SELECT ap.*
            FROM public.member_applications ap
           WHERE ap.id = m.application_id
              OR (m.application_id IS NULL
                  AND ap.client_id = c.id
                  AND ap.status IN ('pending', 'approved'))
           ORDER BY (ap.id = m.application_id) DESC NULLS LAST, ap.submitted_at DESC
           LIMIT 1
      ) a ON true
     WHERE c.id = v_tx.client_id;

    IF v_name IS NULL THEN
        v_name := COALESCE(v_tx.description, 'Non indicato');
    END IF;

    v_year := EXTRACT(YEAR FROM v_tx.occurred_on)::integer;
    v_number := "internal"."next_receipt_number"(v_year);
    v_full_number := COALESCE(NULLIF(v_settings.receipt_prefix, ''), '') || v_number::text || '/' || v_year::text;

    IF v_settings.stamp_duty_threshold_cents > 0
       AND v_tx.amount_cents > v_settings.stamp_duty_threshold_cents THEN
        v_stamp := v_settings.stamp_duty_cents;
    END IF;

    v_causale := COALESCE(NULLIF(btrim(COALESCE(p_causale, '')), ''), CASE v_tx.kind
        WHEN 'membership_fee' THEN 'Quota associativa'
        WHEN 'subscription'   THEN 'Contributo per attività associative'
        WHEN 'event'          THEN 'Contributo per evento o laboratorio'
        WHEN 'trial'          THEN 'Lezione di prova'
        WHEN 'donation'       THEN 'Erogazione liberale'
        WHEN 'commercial'     THEN 'Corrispettivo'
        ELSE 'Contributo'
    END);

    INSERT INTO public.receipts (
        transaction_id, year, number, full_number,
        recipient_name, recipient_fiscal_code, recipient_address,
        issuer_snapshot, causale, amount_cents, stamp_duty_cents, created_by
    ) VALUES (
        p_transaction_id, v_year, v_number, v_full_number,
        v_name, v_fiscal_code, v_address,
        jsonb_build_object(
            'legal_name', v_settings.legal_name,
            'short_legal_name', v_settings.short_legal_name,
            'fiscal_code', v_settings.fiscal_code,
            'vat_number', v_settings.vat_number,
            'address', v_settings.address_street || ', ' || v_settings.address_zip || ' '
                       || v_settings.address_city || ' (' || v_settings.address_province || ')',
            'pec', v_settings.pec,
            'email', v_settings.email,
            'footer', v_settings.receipt_footer
        ),
        v_causale, v_tx.amount_cents, v_stamp, auth.uid()
    )
    RETURNING id INTO v_receipt_id;

    RETURN jsonb_build_object(
        'ok', true, 'reason', 'ISSUED',
        'receipt_id', v_receipt_id, 'full_number', v_full_number,
        'number', v_number, 'year', v_year, 'stamp_duty_cents', v_stamp
    );
END;
$function$;
