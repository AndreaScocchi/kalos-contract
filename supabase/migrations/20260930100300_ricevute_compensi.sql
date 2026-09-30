-- Migration 20260930100300: ricevuta sostitutiva e annullo dei compensi
--
-- Dalla verifica generale del 30/09/2026 (docs/ISSUES.md §3.1).
--
-- 1. Una ricevuta annullata (per esempio «importo sbagliato») si può sostituire con una nuova per lo
--    stesso incasso. Prima `issue_receipt` rispondeva `RECEIPT_ALREADY_ISSUED` anche se l'unica
--    ricevuta era annullata, e l'incasso restava senza una ricevuta valida. Ora, emettendo la nuova,
--    quella annullata si stacca dall'incasso: resta col suo numero (la numerazione non ha buchi) e
--    `receipts.replaced_transaction_id` dice di quale incasso era. Il vincolo unico su
--    `receipts.transaction_id` resta: per PostgREST incasso e ricevuta restano «uno a uno», e le
--    letture del gestionale non cambiano forma. La persona vede ancora la ricevuta annullata fra le
--    sue (`get_my_receipts`, `get_my_receipt`).
-- 2. Annullare il pagamento di un compenso cancellava anche la ritenuta già versata con l'F24
--    (uscita confermata): ora risponde `WITHHOLDING_ALREADY_PAID`.
--
-- Compatibilità: colonna nuova; `receipts.transaction_id` accetta NULL solo per una ricevuta
-- annullata e sostituita (vincolo); stesse firme.

ALTER TABLE "public"."receipts"
    ADD COLUMN IF NOT EXISTS "replaced_transaction_id" uuid;

COMMENT ON COLUMN "public"."receipts"."replaced_transaction_id" IS
  'Per una ricevuta annullata e poi sostituita: l''incasso a cui apparteneva (transaction_id è passato alla ricevuta nuova). Senza chiave esterna di proposito: una seconda relazione verso transactions renderebbe ambigui gli incorporamenti di PostgREST (transaction:transactions, receipt:receipts).';

ALTER TABLE "public"."receipts" ALTER COLUMN "transaction_id" DROP NOT NULL;

ALTER TABLE "public"."receipts" ADD CONSTRAINT "receipts_transaction_or_replaced"
    CHECK ("transaction_id" IS NOT NULL
           OR ("voided_at" IS NOT NULL AND "replaced_transaction_id" IS NOT NULL));

CREATE INDEX IF NOT EXISTS "idx_receipts_replaced_transaction_id"
    ON "public"."receipts" ("replaced_transaction_id") WHERE "replaced_transaction_id" IS NOT NULL;

CREATE OR REPLACE FUNCTION internal.issue_receipt_core(p_transaction_id uuid, p_causale text, p_created_by uuid)
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

    IF EXISTS (SELECT 1 FROM public.receipts
                WHERE transaction_id = p_transaction_id AND voided_at IS NULL) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'RECEIPT_ALREADY_ISSUED');
    END IF;

    -- Una ricevuta annullata si sostituisce: si stacca dall'incasso (resta col suo numero, e
    -- `replaced_transaction_id` dice di quale incasso era) e se ne emette una nuova.
    UPDATE public.receipts
       SET replaced_transaction_id = transaction_id, transaction_id = NULL
     WHERE transaction_id = p_transaction_id AND voided_at IS NOT NULL;

    SELECT * INTO v_settings FROM public.association_settings WHERE id = true;

    -- Dati di chi riceve: prima la domanda con cui è entratə nel libro soci; se non è ancora sociə
    -- (la quota si paga prima della delibera), la sua domanda più recente ancora valida. Il nome
    -- viene dalla domanda, che è il dato formale del libro soci: la scheda di chi si registra dal
    -- sito nasce con la parte dell'email prima della "@" come nome.
    SELECT COALESCE(NULLIF(btrim(a.first_name || ' ' || a.last_name), ''), c.full_name),
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

    -- Nessuna scheda cliente (donazione dal sito): i dati che ha scritto chi ha pagato
    IF v_name IS NULL AND jsonb_typeof(v_tx.metadata->'payer') = 'object' THEN
        v_name        := NULLIF(btrim(v_tx.metadata->'payer'->>'name'), '');
        v_fiscal_code := NULLIF(upper(btrim(COALESCE(v_tx.metadata->'payer'->>'fiscal_code', ''))), '');
        v_address     := NULLIF(btrim(COALESCE(v_tx.metadata->'payer'->>'address', '')), '');
    END IF;

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
        v_causale, v_tx.amount_cents, v_stamp, p_created_by
    )
    RETURNING id INTO v_receipt_id;

    RETURN jsonb_build_object(
        'ok', true, 'reason', 'ISSUED',
        'receipt_id', v_receipt_id, 'full_number', v_full_number,
        'number', v_number, 'year', v_year, 'stamp_duty_cents', v_stamp
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_receipt(p_receipt_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        SELECT * INTO v_tx FROM public.transactions
         WHERE id = COALESCE(v_receipt.transaction_id, v_receipt.replaced_transaction_id);
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
$function$;

CREATE OR REPLACE FUNCTION public.get_my_receipts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      JOIN public.transactions t ON t.id = COALESCE(r.transaction_id, r.replaced_transaction_id)
     WHERE t.client_id = v_client_id;

    RETURN jsonb_build_object('ok', true, 'items', v_items);
END;
$function$;

CREATE OR REPLACE FUNCTION public.staff_undo_compensation_payment(p_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_payment public.compensation_payments%ROWTYPE;
BEGIN
    IF NOT public.can_access_finance() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_FINANCE');
    END IF;

    SELECT * INTO v_payment FROM public.compensation_payments WHERE id = p_payment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PAYMENT_NOT_FOUND');
    END IF;

    -- La ritenuta già versata con l'F24 (uscita confermata) non si cancella da qui: prima si toglie
    -- la conferma dalle Uscite, poi si annulla il pagamento.
    IF v_payment.withholding_expense_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.expenses
         WHERE id = v_payment.withholding_expense_id AND confirmed_at IS NOT NULL
    ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'WITHHOLDING_ALREADY_PAID');
    END IF;

    UPDATE public.compensation_entries
       SET status = 'pending', paid_at = NULL, payment_id = NULL, expense_id = NULL
     WHERE payment_id = p_payment_id;

    DELETE FROM public.compensation_payments WHERE id = p_payment_id;

    DELETE FROM public.expenses
     WHERE id IN (v_payment.net_expense_id, v_payment.withholding_expense_id);

    RETURN jsonb_build_object('ok', true, 'reason', 'UNDONE');
END;
$function$;
