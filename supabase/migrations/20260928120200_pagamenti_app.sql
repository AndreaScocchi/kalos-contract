-- Migration 20260928120200: acquisti dall'app, eventi, avviso della prova (sessione 9)
--
-- 1. Acquisti dall'app con Stripe Checkout, sullo stesso webhook della sessione 5:
--    - un abbonamento (piano "in vendita nell'app", D5: parte dal primo ingresso);
--    - il contributo di un evento a cui si è già iscrittə ("prima il posto, poi il pagamento");
--    - un "da saldare" (abbonamento o evento registrato in studio senza incasso, E1).
--    Cinque funzioni per `authenticated`: tre `prepare_my_*` (si può pagare? l'importo lo decide il
--    database) e due letture (`get_my_open_payments`, `get_my_payment_status`), perché i clienti non
--    leggono `transactions`, `receipts` e `stripe_payments`.
-- 2. `stripe_apply_payment_state` resta l'unico punto che scrive un pagamento. Il blocco dell'incasso
--    passa in `internal.stripe_record_income`: quota e donazioni fanno esattamente quello di prima
--    (`online_payments.test.sql` non cambia); i rami nuovi creano l'abbonamento, collegano
--    l'iscrizione all'evento o saldano il "da saldare". Quello che non si può più fare (iscrizione
--    disdetta, già pagata in studio, "da saldare" annullato) diventa un doppione: registrato perché il
--    denaro è arrivato, senza ricevuta, mai collegato, da rimborsare.
-- 3. `book_event`: capienza controllata anche quando si riattiva un'iscrizione disdetta (prima la si
--    saltava) ed `EVENT_CONCLUDED` per gli eventi finiti. `cancel_event_booking`: dall'app non si
--    disdice un'iscrizione già pagata (`PAID_CONTACT_STUDIO`): il rimborso lo decide lo staff (D4).
-- 4. `book_trial_lesson` avvisa gli admin e l'operatrice della lezione (F6), con la categoria
--    `trial_booked_staff`. Un errore dell'avviso non fa mai fallire la prenotazione.
--
-- Pagamenti di prova: come nella sessione 5, niente registro (e quindi niente abbonamenti o saldi)
-- senza `stripe_test_ledger`, che esiste solo nel seed locale.
--
-- Compatibilità: funzioni nuove chiuse di partenza e aperte solo ad `authenticated`; i codici nuovi di
-- `book_event` e `cancel_event_booking` nella webapp compaiono come errore generico.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Aiuti
-- ─────────────────────────────────────────────────────────────────────────────

-- Regola "solo soci" per un gesto dell'app: NULL se si può, altrimenti la risposta da dare.
-- Stessa regola di `book_lesson` (chi ha la domanda in attesa o la quota nel periodo di grazia passa).
CREATE OR REPLACE FUNCTION "internal"."member_gate_response"("p_client_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_gate text;
BEGIN
    IF NOT "internal"."members_only_enabled"() THEN
        RETURN NULL;
    END IF;
    v_gate := "internal"."member_booking_status"(p_client_id);
    IF v_gate IN ('ok', 'fee_due_grace', 'pending_admission') THEN
        RETURN NULL;
    END IF;
    RETURN jsonb_build_object(
        'ok', false,
        'reason', CASE WHEN v_gate IN ('fee_unpaid', 'fee_overdue') THEN 'MEMBERSHIP_FEE_DUE' ELSE 'NOT_A_MEMBER' END,
        'member_status', v_gate);
END;
$$;

-- Prezzo di un piano con il suo sconto, come il gestionale (`subscriptionPriceCents`)
CREATE OR REPLACE FUNCTION "internal"."plan_price_cents"("p_price_cents" integer, "p_discount_percent" numeric)
    RETURNS integer
    LANGUAGE "sql"
    IMMUTABLE
    AS $$
    SELECT round(p_price_cents * (1 - COALESCE(NULLIF(p_discount_percent, 0), 0) / 100.0))::integer;
$$;

-- Un evento è concluso quando è finito; senza fine, alla mezzanotte (ora italiana) del suo giorno:
-- gli orari di `time_slots` stanno tutti nella stessa data.
CREATE OR REPLACE FUNCTION "internal"."event_concluded"("p_starts_at" timestamp with time zone, "p_ends_at" timestamp with time zone)
    RETURNS boolean
    LANGUAGE "sql"
    STABLE
    AS $$
    SELECT now() >= COALESCE(
        p_ends_at,
        (((p_starts_at AT TIME ZONE 'Europe/Rome')::date + 1)::timestamp AT TIME ZONE 'Europe/Rome'));
$$;

-- Email per la ricevuta di chi paga dall'app
CREATE OR REPLACE FUNCTION "internal"."client_payment_email"("p_client_id" "uuid")
    RETURNS "text"
    LANGUAGE "sql"
    STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT COALESCE(NULLIF(btrim(c.email), ''), p.email)
      FROM public.clients c
      LEFT JOIN public.profiles p ON p.id = c.profile_id
     WHERE c.id = p_client_id;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Si può pagare? (per `stripe-checkout` e per l'app)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."prepare_my_plan_purchase"("p_plan_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_gate      jsonb;
    v_plan      public.plans%ROWTYPE;
    v_amount    integer;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    IF NOT "internal"."payments_enabled"() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PAYMENTS_DISABLED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    -- Con "solo soci" accesa, un abbonamento serve solo a chi può prenotare
    v_gate := "internal"."member_gate_response"(v_client_id);
    IF v_gate IS NOT NULL THEN
        RETURN v_gate;
    END IF;

    SELECT * INTO v_plan FROM public.plans WHERE id = p_plan_id;
    IF NOT FOUND OR v_plan.deleted_at IS NOT NULL OR v_plan.is_active IS NOT TRUE THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PLAN_NOT_FOUND');
    END IF;

    IF NOT v_plan.sold_in_app THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PLAN_NOT_SOLD_IN_APP');
    END IF;

    v_amount := "internal"."plan_price_cents"(v_plan.price_cents, v_plan.discount_percent);
    IF v_amount IS NULL OR v_amount <= 0 OR v_plan.validity_days IS NULL OR v_plan.validity_days <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PLAN_NOT_SOLD_IN_APP');
    END IF;

    -- La fotografia del piano viaggia col pagamento: se il piano cambia mentre si paga, vale quello
    -- che la persona ha visto
    RETURN jsonb_build_object(
        'ok', true,
        'client_id', v_client_id,
        'amount_cents', v_amount,
        'email', "internal"."client_payment_email"(v_client_id),
        'plan', jsonb_build_object(
            'plan_id', v_plan.id,
            'name', v_plan.name,
            'entries', v_plan.entries,
            'validity_days', v_plan.validity_days,
            'price_cents', v_plan.price_cents,
            'discount_percent', v_plan.discount_percent,
            'activity_ids', COALESCE((SELECT jsonb_agg(pa.activity_id ORDER BY pa.activity_id)
                                        FROM public.plan_activities pa WHERE pa.plan_id = v_plan.id), '[]'::jsonb)
        )
    );
END;
$$;

COMMENT ON FUNCTION "public"."prepare_my_plan_purchase"("uuid") IS
    'Sessione 9: si può comprare questo piano dall''app? Pagamenti accesi, piano attivo e in vendita nell''app, regola "solo soci". Importo (con lo sconto del piano) e fotografia del piano li decide il database.';

CREATE OR REPLACE FUNCTION "public"."prepare_my_event_payment"("p_event_booking_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_eb        public.event_bookings%ROWTYPE;
    v_event     public.events%ROWTYPE;
    v_tx        public.transactions%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    IF NOT "internal"."payments_enabled"() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PAYMENTS_DISABLED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    SELECT * INTO v_eb FROM public.event_bookings WHERE id = p_event_booking_id;
    IF NOT FOUND OR v_eb.client_id IS DISTINCT FROM v_client_id THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
    END IF;

    SELECT * INTO v_event FROM public.events WHERE id = v_eb.event_id;
    IF NOT FOUND OR v_event.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_FOUND');
    END IF;

    IF v_eb.status = 'canceled' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_CANCELED');
    END IF;

    -- Dopo l'evento si paga solo se c'eri; una prenotazione mai segnata non resta un debito per sempre
    IF "internal"."event_concluded"(v_event.starts_at, v_event.ends_at) AND v_eb.status <> 'attended' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_CONCLUDED');
    END IF;

    SELECT * INTO v_tx
      FROM public.transactions
     WHERE event_booking_id = v_eb.id AND refund_of_id IS NULL AND status <> 'void'
     ORDER BY created_at
     LIMIT 1;

    IF FOUND AND v_tx.status <> 'pending' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_PAID');
    END IF;

    IF FOUND THEN
        -- Registrata in studio come "da saldare": si salda quella riga, con il suo importo
        RETURN jsonb_build_object(
            'ok', true, 'kind', 'settlement',
            'client_id', v_client_id,
            'transaction_id', v_tx.id,
            'event_booking_id', v_eb.id,
            'amount_cents', v_tx.amount_cents,
            'title', 'Contributo — ' || v_event.name,
            'email', "internal"."client_payment_email"(v_client_id));
    END IF;

    IF COALESCE(v_event.price_cents, 0) <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOTHING_TO_PAY');
    END IF;

    RETURN jsonb_build_object(
        'ok', true, 'kind', 'event_booking',
        'client_id', v_client_id,
        'event_booking_id', v_eb.id,
        'event_id', v_event.id,
        'amount_cents', v_event.price_cents,
        'title', 'Contributo — ' || v_event.name,
        'starts_at', v_event.starts_at,
        'email', "internal"."client_payment_email"(v_client_id));
END;
$$;

COMMENT ON FUNCTION "public"."prepare_my_event_payment"("uuid") IS
    'Sessione 9: si può pagare dall''app il contributo di questa iscrizione a un evento? Se lo staff l''ha registrata come "da saldare" risponde kind = settlement.';

CREATE OR REPLACE FUNCTION "public"."prepare_my_settlement"("p_transaction_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_tx        public.transactions%ROWTYPE;
    v_title     text;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    IF NOT "internal"."payments_enabled"() THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PAYMENTS_DISABLED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    SELECT * INTO v_tx FROM public.transactions WHERE id = p_transaction_id;
    IF NOT FOUND OR v_tx.client_id IS DISTINCT FROM v_client_id
       OR v_tx.refund_of_id IS NOT NULL OR v_tx.amount_cents <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'TRANSACTION_NOT_FOUND');
    END IF;

    IF v_tx.status <> 'pending' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_PENDING', 'status', v_tx.status);
    END IF;

    IF v_tx.kind NOT IN ('subscription', 'event', 'membership_fee') THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_PAYABLE_ONLINE');
    END IF;

    v_title := "internal"."transaction_title"(v_tx.id);

    RETURN jsonb_build_object(
        'ok', true, 'kind', 'settlement',
        'client_id', v_client_id,
        'transaction_id', v_tx.id,
        'transaction_kind', v_tx.kind,
        'amount_cents', v_tx.amount_cents,
        'title', v_title,
        'email', "internal"."client_payment_email"(v_client_id));
END;
$$;

-- Nome leggibile di un incasso: il piano, l'evento o la descrizione
CREATE OR REPLACE FUNCTION "internal"."transaction_title"("p_transaction_id" "uuid")
    RETURNS "text"
    LANGUAGE "sql"
    STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT COALESCE(
        CASE WHEN t.subscription_id IS NOT NULL
             THEN 'Abbonamento ' || COALESCE(s.custom_name, p.name) END,
        CASE WHEN t.event_booking_id IS NOT NULL THEN 'Contributo — ' || e.name END,
        CASE WHEN t.member_fee_id IS NOT NULL THEN 'Quota associativa ' || mf.year::text END,
        NULLIF(btrim(t.description), ''),
        'Pagamento')
      FROM public.transactions t
      LEFT JOIN public.subscriptions s ON s.id = t.subscription_id
      LEFT JOIN public.plans p ON p.id = s.plan_id
      LEFT JOIN public.event_bookings eb ON eb.id = t.event_booking_id
      LEFT JOIN public.events e ON e.id = eb.event_id
      LEFT JOIN public.member_fees mf ON mf.id = t.member_fee_id
     WHERE t.id = p_transaction_id;
$$;

COMMENT ON FUNCTION "public"."prepare_my_settlement"("uuid") IS
    'Sessione 9: si può saldare dall''app questo "da saldare" (abbonamento, evento o quota registrati in studio senza incasso)?';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Letture per l'app
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."get_my_open_payments"()
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
        RETURN jsonb_build_object('ok', true, 'payments_enabled', "internal"."payments_enabled"(), 'items', '[]'::jsonb);
    END IF;

    SELECT COALESCE(jsonb_agg(item ORDER BY item->>'due_on', item->>'title'), '[]'::jsonb) INTO v_items
      FROM (
        -- "Da saldare" registrati in studio
        SELECT jsonb_build_object(
                   'type', 'settlement',
                   'transaction_id', t.id,
                   'kind', t.kind,
                   'amount_cents', t.amount_cents,
                   'title', "internal"."transaction_title"(t.id),
                   'due_on', t.occurred_on,
                   'subscription_id', t.subscription_id,
                   'event_booking_id', t.event_booking_id) AS item
          FROM public.transactions t
         WHERE t.client_id = v_client_id
           AND t.status = 'pending'
           AND t.refund_of_id IS NULL
           AND t.amount_cents > 0
           AND t.kind IN ('subscription', 'event', 'membership_fee')
        UNION ALL
        -- Iscrizioni a eventi con contributo senza nessun incasso (fatte dall'app)
        SELECT jsonb_build_object(
                   'type', 'event_booking',
                   'event_booking_id', eb.id,
                   'event_id', e.id,
                   'kind', 'event',
                   'amount_cents', e.price_cents,
                   'title', 'Contributo — ' || e.name,
                   'due_on', (e.starts_at AT TIME ZONE 'Europe/Rome')::date,
                   'starts_at', e.starts_at)
          FROM public.event_bookings eb
          JOIN public.events e ON e.id = eb.event_id
         WHERE eb.client_id = v_client_id
           AND e.deleted_at IS NULL
           AND COALESCE(e.price_cents, 0) > 0
           AND (eb.status = 'attended'
                OR (eb.status = 'booked' AND NOT "internal"."event_concluded"(e.starts_at, e.ends_at)))
           AND NOT EXISTS (SELECT 1 FROM public.transactions t
                            WHERE t.event_booking_id = eb.id AND t.refund_of_id IS NULL AND t.status <> 'void')
      ) items;

    RETURN jsonb_build_object('ok', true, 'payments_enabled', "internal"."payments_enabled"(), 'items', v_items);
END;
$$;

COMMENT ON FUNCTION "public"."get_my_open_payments"() IS
    'Sessione 9: cosa c''è da pagare (i clienti non leggono `transactions`): i "da saldare" e le iscrizioni a eventi con contributo senza incasso.';

CREATE OR REPLACE FUNCTION "public"."get_my_payment_status"("p_payment_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_sp        public.stripe_payments%ROWTYPE;
    v_tx        public.transactions%ROWTYPE;
    v_receipt   public.receipts%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    SELECT * INTO v_sp FROM public.stripe_payments WHERE id = p_payment_id;
    IF NOT FOUND OR v_client_id IS NULL OR v_sp.client_id IS DISTINCT FROM v_client_id THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PAYMENT_NOT_FOUND');
    END IF;

    IF v_sp.transaction_id IS NOT NULL THEN
        SELECT * INTO v_tx FROM public.transactions WHERE id = v_sp.transaction_id;
        SELECT * INTO v_receipt FROM public.receipts
         WHERE transaction_id = v_sp.transaction_id AND voided_at IS NULL
         ORDER BY created_at LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'status', v_sp.status,
        'purpose', v_sp.purpose,
        'kind', COALESCE(v_sp.metadata->>'kind', v_sp.purpose::text),
        'amount_cents', v_sp.amount_cents,
        'title', COALESCE(v_sp.metadata->>'title', CASE WHEN v_tx.id IS NOT NULL THEN "internal"."transaction_title"(v_tx.id) END),
        'recorded', v_sp.transaction_id IS NOT NULL,
        'is_duplicate', v_sp.is_duplicate,
        'subscription_id', v_tx.subscription_id,
        'event_booking_id', COALESCE(v_tx.event_booking_id,
                                     CASE WHEN v_sp.metadata->>'kind' = 'event_booking' THEN v_sp.target_id END),
        'year', v_sp.metadata->>'year',
        'receipt_number', v_receipt.full_number,
        'receipt_sent_at', v_receipt.sent_at,
        'failure_message', v_sp.failure_message);
END;
$$;

COMMENT ON FUNCTION "public"."get_my_payment_status"("uuid") IS
    'Sessione 9: com''è andato un proprio pagamento online (pagina di ritorno dell''app): stato, cosa è nato, ricevuta.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. L'incasso di un pagamento riuscito
-- ─────────────────────────────────────────────────────────────────────────────

-- Ricevuta di un incasso online. Una ricevuta già emessa va bene così: rifallire farebbe ripetere il
-- webhook all'infinito.
CREATE OR REPLACE FUNCTION "internal"."stripe_issue_receipt"("p_transaction_id" "uuid", "p_causale" "text", "p_stripe_payment_id" "uuid")
    RETURNS void
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_receipt jsonb;
BEGIN
    v_receipt := "internal"."issue_receipt_core"(p_transaction_id, p_causale, NULL);
    IF COALESCE((v_receipt->>'ok')::boolean, false) = false
       AND COALESCE(v_receipt->>'reason', '') <> 'RECEIPT_ALREADY_ISSUED' THEN
        RAISE EXCEPTION 'Ricevuta non emessa per il pagamento %: %', p_stripe_payment_id, v_receipt->>'reason';
    END IF;
END;
$$;

-- Un "da saldare" pagato con carta: la stessa riga diventa pagata, come fa `staff_settle_transaction`
CREATE OR REPLACE FUNCTION "internal"."stripe_settle_pending"(
    "p_stripe_payment_id" "uuid", "p_transaction_id" "uuid", "p_paid_at" timestamp with time zone)
    RETURNS "public"."stripe_payments"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_sp public.stripe_payments%ROWTYPE;
    v_tx public.transactions%ROWTYPE;
BEGIN
    SELECT * INTO v_sp FROM public.stripe_payments WHERE id = p_stripe_payment_id;
    SELECT * INTO v_tx FROM public.transactions WHERE id = p_transaction_id;

    UPDATE public.transactions
       SET status            = 'paid',
           method            = 'stripe',
           source            = COALESCE(v_sp.source, 'app'),
           -- La data dell'incasso è quella dell'addebito in Italia (cassa), non quella del "da saldare"
           occurred_on       = (p_paid_at AT TIME ZONE 'Europe/Rome')::date,
           stripe_payment_id = v_sp.id,
           metadata          = COALESCE(metadata, '{}'::jsonb)
                               || jsonb_build_object('settled_online', true, 'method_before', v_tx.method)
     WHERE id = v_tx.id;

    IF v_tx.member_fee_id IS NOT NULL THEN
        UPDATE public.member_fees
           SET status = 'paid', paid_at = COALESCE(paid_at, p_paid_at), transaction_id = v_tx.id
         WHERE id = v_tx.member_fee_id AND status IN ('due', 'refunded');
    END IF;

    UPDATE public.stripe_payments
       SET transaction_id = v_tx.id, is_duplicate = false
     WHERE id = v_sp.id
    RETURNING * INTO v_sp;

    PERFORM "internal"."stripe_issue_receipt"(v_tx.id, NULL, v_sp.id);
    RETURN v_sp;
END;
$$;

-- L'incasso di un pagamento riuscito, una volta sola. Chiamata da `stripe_apply_payment_state` con la
-- riga del pagamento già bloccata e solo se il pagamento può scrivere nel registro.
CREATE OR REPLACE FUNCTION "internal"."stripe_record_income"(
    "p_stripe_payment_id" "uuid", "p_paid_at" timestamp with time zone, "p_currency" "text")
    RETURNS "public"."stripe_payments"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_sp            public.stripe_payments%ROWTYPE;
    v_mode          text;
    v_kind          public.transaction_kind;
    v_fee           public.member_fees%ROWTYPE;
    v_link_fee      boolean := false;
    v_duplicate     boolean := false;
    v_year          text;
    v_description   text;
    v_causale       text;
    v_tx_id         uuid;
    v_tx            public.transactions%ROWTYPE;
    v_eb            public.event_bookings%ROWTYPE;
    v_event_name    text;
    v_link_eb       uuid;
    v_sub_id        uuid;
    v_snap          jsonb;
    v_plan          public.plans%ROWTYPE;
    v_days          integer;
    v_entries       integer;
    v_paid_on       date := (p_paid_at AT TIME ZONE 'Europe/Rome')::date;
    v_refs          jsonb;
BEGIN
    SELECT * INTO v_sp FROM public.stripe_payments WHERE id = p_stripe_payment_id FOR UPDATE;
    IF v_sp.transaction_id IS NOT NULL THEN
        RETURN v_sp;
    END IF;

    v_mode := COALESCE(v_sp.metadata->>'kind', '');
    v_kind := CASE v_sp.purpose
        WHEN 'membership_fee' THEN 'membership_fee'
        WHEN 'subscription'   THEN 'subscription'
        WHEN 'event'          THEN 'event'
        WHEN 'donation'       THEN 'donation'
        ELSE 'other'
    END::public.transaction_kind;

    IF v_mode = 'settlement' THEN
        -- Un "da saldare": si salda la stessa riga, se è ancora da saldare e l'importo è quello
        SELECT * INTO v_tx FROM public.transactions WHERE id = v_sp.target_id FOR UPDATE;
        IF FOUND AND v_tx.status = 'pending' AND v_tx.refund_of_id IS NULL
           AND v_tx.client_id IS NOT DISTINCT FROM v_sp.client_id
           AND v_tx.amount_cents = v_sp.amount_cents THEN
            RETURN "internal"."stripe_settle_pending"(v_sp.id, v_tx.id, p_paid_at);
        END IF;
        -- Già saldato in studio, annullato o cambiato nel frattempo: denaro da restituire
        v_duplicate := true;
        v_refs := jsonb_build_object('settlement_of', v_sp.target_id);
        v_description := COALESCE(NULLIF(v_sp.metadata->>'title', ''), 'Pagamento online');

    ELSIF v_mode = 'event_booking' THEN
        SELECT * INTO v_eb FROM public.event_bookings WHERE id = v_sp.target_id FOR UPDATE;
        SELECT name INTO v_event_name FROM public.events WHERE id = v_eb.event_id;
        v_description := 'Contributo — ' || COALESCE(v_event_name, 'evento');

        IF v_eb.id IS NULL OR v_eb.client_id IS DISTINCT FROM v_sp.client_id OR v_eb.status = 'canceled' THEN
            v_duplicate := true;
        ELSE
            SELECT * INTO v_tx
              FROM public.transactions
             WHERE event_booking_id = v_eb.id AND refund_of_id IS NULL AND status <> 'void'
             ORDER BY created_at
             LIMIT 1
               FOR UPDATE;
            IF FOUND THEN
                IF v_tx.status = 'pending' AND v_tx.amount_cents = v_sp.amount_cents THEN
                    RETURN "internal"."stripe_settle_pending"(v_sp.id, v_tx.id, p_paid_at);
                END IF;
                -- Già pagata (in studio o con un altro checkout), o "da saldare" di un altro importo
                v_duplicate := true;
            ELSE
                v_link_eb := v_eb.id;
            END IF;
        END IF;
        IF v_duplicate THEN
            v_refs := jsonb_build_object('event_booking_id', v_sp.target_id);
        END IF;

    ELSIF v_mode = 'new_subscription' THEN
        v_snap := COALESCE(v_sp.metadata->'plan', '{}'::jsonb);
        SELECT * INTO v_plan FROM public.plans
         WHERE id = COALESCE(NULLIF(v_snap->>'plan_id', '')::uuid, v_sp.target_id);
        v_description := 'Abbonamento ' || COALESCE(v_snap->>'name', v_plan.name, '');

        IF v_sp.client_id IS NULL OR v_plan.id IS NULL
           OR NOT EXISTS (SELECT 1 FROM public.clients WHERE id = v_sp.client_id AND deleted_at IS NULL) THEN
            v_duplicate := true;
            v_refs := jsonb_build_object('plan_id', COALESCE(v_plan.id, v_sp.target_id));
        ELSE
            v_days := COALESCE(NULLIF(v_snap->>'validity_days', '')::integer, v_plan.validity_days);
            v_entries := CASE WHEN v_snap ? 'entries' THEN NULLIF(v_snap->>'entries', '')::integer
                              ELSE v_plan.entries END;

            -- D5: parte dal primo ingresso, entro 60 giorni dall'acquisto (vedi …120100)
            INSERT INTO public.subscriptions (
                plan_id, client_id, status, started_at, expires_at,
                custom_price_cents, custom_entries, custom_validity_days,
                starts_on_first_entry, activation_deadline, metadata
            ) VALUES (
                v_plan.id, v_sp.client_id, 'active', v_paid_on, v_paid_on + 60 + v_days,
                CASE WHEN v_sp.amount_cents IS DISTINCT FROM
                          "internal"."plan_price_cents"(v_plan.price_cents, v_plan.discount_percent)
                     THEN v_sp.amount_cents END,
                CASE WHEN v_entries IS DISTINCT FROM v_plan.entries THEN v_entries END,
                v_days,
                true, v_paid_on + 60,
                jsonb_build_object('source', 'app', 'stripe_payment_id', v_sp.id, 'plan_snapshot', v_snap)
            )
            RETURNING id INTO v_sub_id;
        END IF;

    ELSE
        -- Quota e donazioni: come nella sessione 5
        IF v_sp.purpose = 'membership_fee' THEN
            SELECT * INTO v_fee FROM public.member_fees WHERE id = v_sp.target_id FOR UPDATE;
            IF FOUND AND v_fee.status IN ('due', 'refunded') THEN
                v_link_fee := true;
            ELSE
                -- Già pagata (in studio, o con un altro checkout) o esonerata: il denaro va
                -- registrato comunque, e restituito
                v_duplicate := true;
            END IF;
            v_year := COALESCE(v_fee.year::text, v_sp.metadata->>'year');
        END IF;

        v_description := CASE v_sp.purpose
            WHEN 'membership_fee' THEN 'Quota associativa' || COALESCE(' ' || v_year, '')
            WHEN 'donation'       THEN 'Donazione'
            ELSE COALESCE(NULLIF(v_sp.metadata->>'description', ''), 'Pagamento online')
        END;
    END IF;

    INSERT INTO public.transactions (
        client_id, kind, amount_cents, currency, method, source, status, occurred_on,
        member_fee_id, subscription_id, event_booking_id, stripe_payment_id, description, metadata
    ) VALUES (
        v_sp.client_id, v_kind, v_sp.amount_cents, p_currency, 'stripe',
        COALESCE(v_sp.source, 'site'), 'paid',
        -- La data è quella dell'addebito in Italia: un pagamento del 31/12 riconsegnato dal
        -- webhook il 2/1 resta nell'anno (e nella numerazione) giusto
        v_paid_on,
        CASE WHEN v_link_fee THEN v_fee.id END,
        v_sub_id,
        v_link_eb,
        v_sp.id, v_description,
        jsonb_strip_nulls(jsonb_build_object(
            'payer', v_sp.metadata->'payer',
            'duplicate', CASE WHEN v_duplicate THEN true END,
            'refs', v_refs,
            'amount_expected_cents', v_sp.metadata->'amount_expected_cents'
        ))
    )
    RETURNING id INTO v_tx_id;

    IF v_link_fee THEN
        UPDATE public.member_fees
           SET status = 'paid', paid_at = p_paid_at, transaction_id = v_tx_id,
               amount_cents = v_sp.amount_cents, refunded_at = NULL, refund_reason = NULL
         WHERE id = v_fee.id;
    END IF;

    UPDATE public.stripe_payments
       SET transaction_id = v_tx_id, is_duplicate = v_duplicate
     WHERE id = v_sp.id
    RETURNING * INTO v_sp;

    -- Ricevuta, tranne per i doppioni: niente numero bruciato su soldi da restituire
    IF NOT v_duplicate THEN
        v_causale := CASE v_sp.purpose
            WHEN 'membership_fee' THEN 'Quota associativa' || COALESCE(' ' || v_year, '')
            WHEN 'donation'       THEN 'Erogazione liberale'
            ELSE NULL
        END;
        PERFORM "internal"."stripe_issue_receipt"(v_tx_id, v_causale, v_sp.id);
    END IF;

    RETURN v_sp;
END;
$$;

COMMENT ON FUNCTION "internal"."stripe_record_income"("uuid", timestamp with time zone, "text") IS
    'L''incasso di un pagamento online riuscito: quota, donazione, abbonamento nuovo (D5), contributo di un evento o saldo di un "da saldare". Quello che non si può più collegare diventa un doppione da rimborsare, senza ricevuta.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. stripe_apply_payment_state: il blocco dell'incasso passa a stripe_record_income
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."stripe_apply_payment_state"("p_payload" "jsonb")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_pi            jsonb := COALESCE(p_payload->'payment_intent', '{}'::jsonb);
    v_pi_id         text  := NULLIF(v_pi->>'id', '');
    v_pi_status     text  := v_pi->>'status';
    v_charge        jsonb := CASE WHEN jsonb_typeof(v_pi->'charge') = 'object' THEN v_pi->'charge' END;
    v_session_id    text  := NULLIF(p_payload->>'checkout_session_id', '');
    v_sp_ref        text  := NULLIF(p_payload->>'stripe_payment_id', '');
    v_livemode      boolean := COALESCE((v_pi->>'livemode')::boolean, false);
    v_sp            public.stripe_payments%ROWTYPE;
    v_ledger        boolean;
    v_expected      integer;
    v_amount        integer;
    v_currency      text;
    v_paid_at       timestamptz;
    v_refund        jsonb;
    v_existing      public.stripe_refunds%ROWTYPE;
    v_r_id          text;
    v_r_status      text;
    v_r_amount      integer;
    v_r_reason      text;
    v_r_by          uuid;
    v_r_on          date;
    v_r_result      jsonb;
    v_r_tx          uuid;
    v_tx_status     public.transaction_status;
    v_receipt_ids   uuid[];
BEGIN
    IF v_pi_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'MISSING_PAYMENT_INTENT');
    END IF;

    -- 1. La nostra riga, bloccata: tutte le consegne che riguardano questo pagamento passano di qui una
    --    alla volta.
    IF v_sp_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        SELECT * INTO v_sp FROM public.stripe_payments WHERE id = v_sp_ref::uuid FOR UPDATE;
    END IF;
    IF v_sp.id IS NULL THEN
        SELECT * INTO v_sp FROM public.stripe_payments WHERE payment_intent_id = v_pi_id FOR UPDATE;
    END IF;
    IF v_sp.id IS NULL AND v_session_id IS NOT NULL THEN
        SELECT * INTO v_sp FROM public.stripe_payments WHERE checkout_session_id = v_session_id FOR UPDATE;
    END IF;
    IF v_sp.id IS NULL THEN
        -- Un pagamento che non abbiamo aperto noi (link di pagamento, dashboard): il denaro è arrivato
        -- lo stesso, quindi si registra, come "altro", per chi controlla le Finanze.
        INSERT INTO public.stripe_payments (
            payment_intent_id, checkout_session_id, purpose, amount_cents, currency, livemode,
            status, source, metadata
        ) VALUES (
            v_pi_id, v_session_id, 'other',
            GREATEST(COALESCE((v_pi->>'amount_received')::integer, (v_pi->>'amount')::integer, 1), 1),
            upper(COALESCE(v_pi->>'currency', 'eur')), v_livemode, 'created', 'site',
            jsonb_build_object('unmatched', true)
        )
        RETURNING * INTO v_sp;
    END IF;

    IF v_sp.payment_intent_id IS NOT NULL AND v_sp.payment_intent_id <> v_pi_id THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'PAYMENT_INTENT_MISMATCH');
    END IF;

    v_ledger   := "internal"."stripe_ledger_allowed"(v_livemode);
    v_expected := v_sp.amount_cents;
    v_amount   := COALESCE((v_pi->>'amount_received')::integer, 0);
    v_currency := upper(COALESCE(NULLIF(v_pi->>'currency', ''), v_sp.currency, 'EUR'));
    v_paid_at  := CASE WHEN v_charge ? 'created'
                       THEN to_timestamp((v_charge->>'created')::bigint) END;

    -- 2. Il pagamento
    IF v_pi_status = 'succeeded' THEN
        v_paid_at := COALESCE(v_sp.succeeded_at, v_paid_at, now());

        UPDATE public.stripe_payments SET
            payment_intent_id   = v_pi_id,
            checkout_session_id = COALESCE(checkout_session_id, v_session_id),
            amount_cents        = CASE WHEN v_amount > 0 THEN v_amount ELSE amount_cents END,
            currency            = v_currency,
            livemode            = v_livemode,
            payment_method_type = COALESCE(NULLIF(v_pi->>'payment_method_type', ''), payment_method_type),
            receipt_email       = COALESCE(NULLIF(v_pi->>'receipt_email', ''), receipt_email),
            fee_cents           = COALESCE((v_charge->>'fee_cents')::integer, fee_cents),
            net_cents           = COALESCE((v_charge->>'net_cents')::integer, net_cents),
            succeeded_at        = v_paid_at,
            failure_message     = NULL,
            status              = CASE WHEN status IN ('refunded', 'partially_refunded') THEN status
                                       ELSE 'succeeded' END,
            metadata            = CASE WHEN v_amount > 0 AND v_amount <> v_expected
                                       THEN metadata || jsonb_build_object('amount_expected_cents', v_expected)
                                       ELSE metadata END
         WHERE id = v_sp.id
        RETURNING * INTO v_sp;

        -- L'incasso, una volta sola e solo se il pagamento può scrivere nel registro (un pagamento di
        -- prova in produzione non crea né incassi né abbonamenti)
        IF v_ledger AND v_sp.transaction_id IS NULL THEN
            v_sp := "internal"."stripe_record_income"(v_sp.id, v_paid_at, v_currency);
        END IF;

    ELSIF v_sp.status NOT IN ('succeeded', 'refunded', 'partially_refunded') THEN
        -- Non ancora riuscito: solo lo stato, il registro non si tocca
        UPDATE public.stripe_payments SET
            payment_intent_id = COALESCE(payment_intent_id, v_pi_id),
            livemode          = v_livemode,
            status            = CASE
                WHEN v_pi_status = 'processing' THEN 'processing'
                WHEN v_pi_status = 'canceled' THEN 'canceled'
                WHEN v_pi_status = 'requires_payment_method' AND NULLIF(v_pi->>'last_payment_error', '') IS NOT NULL
                    THEN 'failed'
                ELSE status
            END::public.stripe_payment_status,
            failure_message   = COALESCE(NULLIF(v_pi->>'last_payment_error', ''), failure_message)
         WHERE id = v_sp.id
        RETURNING * INTO v_sp;
    END IF;

    -- 3. I rimborsi: solo per un incasso già nel registro
    IF v_sp.transaction_id IS NOT NULL AND jsonb_typeof(p_payload->'refunds') = 'array' THEN
        FOR v_refund IN SELECT value FROM jsonb_array_elements(p_payload->'refunds') LOOP
            v_r_id     := NULLIF(v_refund->>'id', '');
            v_r_status := COALESCE(NULLIF(v_refund->>'status', ''), 'succeeded');
            v_r_amount := (v_refund->>'amount')::integer;
            CONTINUE WHEN v_r_id IS NULL OR COALESCE(v_r_amount, 0) <= 0;

            v_r_reason := COALESCE(
                NULLIF(btrim(v_refund->'metadata'->>'reason'), ''),
                'Rimborso da dashboard Stripe' || COALESCE(' (' || NULLIF(v_refund->>'reason', '') || ')', '')
            );
            v_r_by := NULL;
            IF (v_refund->'metadata'->>'created_by') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
                SELECT id INTO v_r_by FROM public.profiles WHERE id = (v_refund->'metadata'->>'created_by')::uuid;
            END IF;
            v_r_on := CASE WHEN v_refund ? 'created'
                           THEN (to_timestamp((v_refund->>'created')::bigint) AT TIME ZONE 'Europe/Rome')::date END;

            SELECT * INTO v_existing FROM public.stripe_refunds WHERE refund_id = v_r_id FOR UPDATE;

            IF NOT FOUND THEN
                v_r_tx := NULL;
                IF v_r_status IN ('pending', 'succeeded', 'requires_action') THEN
                    v_r_result := "internal"."refund_transaction_core"(
                        v_sp.transaction_id, v_r_amount, v_r_reason, v_r_by, v_r_on);
                    v_r_tx := (v_r_result->>'refund_transaction_id')::uuid;
                END IF;
                INSERT INTO public.stripe_refunds (
                    refund_id, stripe_payment_id, amount_cents, reason, status, transaction_id, created_by
                ) VALUES (
                    v_r_id, v_sp.id, v_r_amount, v_r_reason, v_r_status, v_r_tx, v_r_by
                );
            ELSIF v_existing.status IS DISTINCT FROM v_r_status THEN
                UPDATE public.stripe_refunds SET status = v_r_status WHERE id = v_existing.id;

                IF v_r_status IN ('failed', 'canceled') AND v_existing.transaction_id IS NOT NULL THEN
                    -- Il rimborso non è andato a buon fine: il denaro non è uscito, la riga si annulla
                    UPDATE public.transactions
                       SET status = 'void',
                           note = concat_ws(' — ', note, 'rimborso Stripe non riuscito')
                     WHERE id = v_existing.transaction_id AND status <> 'void';
                    PERFORM "internal"."recompute_refund_status"(v_sp.transaction_id, NULL);
                ELSIF v_r_status IN ('pending', 'succeeded', 'requires_action')
                      AND v_existing.transaction_id IS NULL THEN
                    v_r_result := "internal"."refund_transaction_core"(
                        v_sp.transaction_id, v_existing.amount_cents, v_existing.reason, v_existing.created_by, v_r_on);
                    UPDATE public.stripe_refunds
                       SET transaction_id = (v_r_result->>'refund_transaction_id')::uuid
                     WHERE id = v_existing.id;
                END IF;
            END IF;
        END LOOP;

        -- Lo stato del pagamento segue quello dell'incasso
        SELECT status INTO v_tx_status FROM public.transactions WHERE id = v_sp.transaction_id;
        UPDATE public.stripe_payments
           SET status = CASE v_tx_status
                   WHEN 'refunded' THEN 'refunded'
                   WHEN 'partially_refunded' THEN 'partially_refunded'
                   ELSE 'succeeded'
               END::public.stripe_payment_status
         WHERE id = v_sp.id AND status IN ('succeeded', 'refunded', 'partially_refunded')
        RETURNING * INTO v_sp;
    END IF;

    -- 4. Le ricevute ancora da mandare per email
    SELECT COALESCE(array_agg(r.id), '{}') INTO v_receipt_ids
      FROM public.receipts r
     WHERE v_sp.transaction_id IS NOT NULL
       AND r.transaction_id = v_sp.transaction_id
       AND r.sent_at IS NULL AND r.voided_at IS NULL;

    RETURN jsonb_build_object(
        'ok', true,
        'stripe_payment_id', v_sp.id,
        'status', v_sp.status,
        'transaction_id', v_sp.transaction_id,
        'is_duplicate', v_sp.is_duplicate,
        'ledger', v_ledger,
        'receipt_ids', to_jsonb(v_receipt_ids)
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Eventi: capienza alla riattivazione, eventi conclusi, disdetta di un'iscrizione pagata
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "public"."book_event"("p_event_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_member_gate text;
  v_user_id uuid := auth.uid();
  v_my_client_id uuid;
  v_event public.events%ROWTYPE;
  v_booked_count integer;
  v_booking_id uuid;
  v_reactivate_booking_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();

  -- Regola "solo soci" (H2): con l'interruttore acceso si prenota solo da sociə.
  -- Chi ha pagato la quota prenota subito, anche prima della delibera del Consiglio Direttivo (A7).
  IF "internal"."members_only_enabled"() THEN
    v_member_gate := "internal"."member_booking_status"(v_my_client_id);
    IF v_member_gate NOT IN ('ok', 'fee_due_grace', 'pending_admission') THEN
      RETURN jsonb_build_object(
        'ok', false,
        'reason', CASE WHEN v_member_gate IN ('fee_unpaid', 'fee_overdue')
                       THEN 'MEMBERSHIP_FEE_DUE' ELSE 'NOT_A_MEMBER' END,
        'member_status', v_member_gate);
    END IF;
  END IF;

  -- Lock event row per prevenire race conditions
  SELECT * INTO v_event FROM public.events WHERE id = p_event_id FOR UPDATE;

  IF NOT FOUND OR v_event.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_FOUND');
  END IF;

  IF v_event.is_active IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_NOT_ACTIVE');
  END IF;

  -- Sessione 9: a un evento finito non ci si iscrive più
  IF "internal"."event_concluded"(v_event.starts_at, v_event.ends_at) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'EVENT_CONCLUDED');
  END IF;

  -- Verifica che non sia già prenotato
  -- client_id è la fonte di verità: se l'utente ha un client_id, controlla solo quello
  IF v_my_client_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id AND client_id = v_my_client_id AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.event_bookings
      WHERE event_id = p_event_id AND user_id = v_user_id AND client_id IS NULL AND status = 'booked'
    ) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_BOOKED');
    END IF;
  END IF;

  -- Cerca se esiste una prenotazione cancellata da riattivare
  IF v_my_client_id IS NOT NULL THEN
    SELECT id INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id AND client_id = v_my_client_id AND status = 'canceled'
    LIMIT 1
    FOR UPDATE;
  ELSE
    SELECT id INTO v_reactivate_booking_id
    FROM public.event_bookings
    WHERE event_id = p_event_id AND user_id = v_user_id AND client_id IS NULL AND status = 'canceled'
    LIMIT 1
    FOR UPDATE;
  END IF;

  -- Capienza (se impostata), sempre: anche riattivando, il posto disdetto può essere stato preso
  -- da un'altra persona nel frattempo (sessione 9; prima la riattivazione saltava il controllo)
  IF v_event.capacity IS NOT NULL THEN
    SELECT count(*) INTO v_booked_count
    FROM public.event_bookings
    WHERE event_id = p_event_id
      AND status IN ('booked', 'attended', 'no_show');

    IF v_booked_count >= v_event.capacity THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'FULL');
    END IF;
  END IF;

  -- Riattiva prenotazione esistente o crea nuova
  -- client_id è la fonte di verità: se disponibile, usare SEMPRE client_id (user_id = NULL)
  IF v_reactivate_booking_id IS NOT NULL THEN
    UPDATE public.event_bookings
    SET status = 'booked',
        created_at = now()
    WHERE id = v_reactivate_booking_id;
    v_booking_id := v_reactivate_booking_id;
  ELSE
    INSERT INTO public.event_bookings (event_id, user_id, client_id, status)
    VALUES (
      p_event_id,
      CASE WHEN v_my_client_id IS NOT NULL THEN NULL ELSE v_user_id END,
      v_my_client_id,
      'booked'
    )
    RETURNING id INTO v_booking_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'reason', 'BOOKED',
    'booking_id', v_booking_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION "public"."cancel_event_booking"("p_booking_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_my_client_id uuid;
  v_is_staff boolean;
  v_booking_user_id uuid;
  v_booking_client_id uuid;
  v_status booking_status;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
  END IF;

  v_my_client_id := public.get_my_client_id();
  v_is_staff := public.is_staff();

  -- Recupera booking con lock
  SELECT user_id, client_id, status
  INTO v_booking_user_id, v_booking_client_id, v_status
  FROM public.event_bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'BOOKING_NOT_FOUND');
  END IF;

  -- Verifica ownership
  -- client_id è la fonte di verità: se l'utente ha un client_id, verificare solo quello
  IF NOT (
    v_is_staff
    OR (v_my_client_id IS NOT NULL AND v_booking_client_id = v_my_client_id)
    OR (v_my_client_id IS NULL AND v_booking_user_id = v_user_id AND v_booking_client_id IS NULL)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'UNAUTHORIZED');
  END IF;

  IF v_status = 'canceled' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ALREADY_CANCELED');
  END IF;

  IF v_status IN ('attended', 'no_show') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'CANNOT_CANCEL_CONCLUDED');
  END IF;

  -- Sessione 9: un'iscrizione già pagata si disdice parlando con lo studio, che decide il rimborso
  -- (D4). Lo staff la disdice come prima.
  IF NOT v_is_staff AND EXISTS (
    SELECT 1 FROM public.transactions
     WHERE event_booking_id = p_booking_id AND refund_of_id IS NULL
       AND status IN ('paid', 'partially_refunded')
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'PAID_CONTACT_STUDIO');
  END IF;

  UPDATE public.event_bookings
  SET status = 'canceled'::booking_status
  WHERE id = p_booking_id;

  RETURN jsonb_build_object('ok', true, 'reason', 'CANCELED');
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Prova prenotata dall'app: avviso agli admin e all'operatrice della lezione (F6)
-- ─────────────────────────────────────────────────────────────────────────────

-- Canale per un avviso allo staff. Le push partono oggi solo per il web (Web Push): con un token
-- dell'app nativa la notifica finirebbe "fallita" e nessuna email partirebbe. Quindi push solo con
-- un'iscrizione Web Push, altrimenti email.
CREATE OR REPLACE FUNCTION "internal"."staff_alert_channel"("p_client_id" "uuid", "p_category" "public"."notification_category")
    RETURNS "public"."notification_channel"
    LANGUAGE "plpgsql"
    STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_push  boolean := true;
    v_email boolean := true;
BEGIN
    SELECT push_enabled, email_enabled INTO v_push, v_email
      FROM public.notification_preferences
     WHERE client_id = p_client_id AND category = p_category;
    v_push := COALESCE(v_push, true);
    v_email := COALESCE(v_email, true);

    IF v_push AND EXISTS (
        SELECT 1 FROM public.device_tokens
         WHERE client_id = p_client_id AND is_active
           AND left(btrim(expo_push_token), 1) = '{'
           AND expo_push_token LIKE '%"endpoint"%'
    ) THEN
        RETURN 'push';
    END IF;
    IF v_email THEN
        RETURN 'email';
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION "internal"."queue_trial_booked_staff"("p_trial_id" "uuid")
    RETURNS void
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_trial     public.trials%ROWTYPE;
    v_lesson    public.lessons%ROWTYPE;
    v_person    text;
    v_activity  text;
    v_place     text;
    v_operator_profile uuid;
    v_rcpt      record;
    v_channel   public.notification_channel;
BEGIN
    SELECT * INTO v_trial FROM public.trials WHERE id = p_trial_id;
    IF NOT FOUND OR v_trial.lesson_id IS NULL THEN
        RETURN;
    END IF;

    SELECT * INTO v_lesson FROM public.lessons WHERE id = v_trial.lesson_id;
    SELECT full_name INTO v_person FROM public.clients WHERE id = v_trial.client_id;
    SELECT name INTO v_activity FROM public.activities WHERE id = v_trial.activity_id;
    SELECT profile_id INTO v_operator_profile FROM public.operators WHERE id = v_lesson.operator_id;
    v_place := "internal"."location_label"(v_lesson.location_id);

    -- Gli admin e l'operatrice della lezione, ognunə una volta, mai la persona che ha prenotato
    FOR v_rcpt IN
        SELECT DISTINCT ON (p.id) c.id AS client_id, c.email
          FROM public.profiles p
          JOIN public.clients c ON c.profile_id = p.id AND c.deleted_at IS NULL
         WHERE p.deleted_at IS NULL
           AND (p.role = 'admin' OR p.id = v_operator_profile)
           AND c.id <> v_trial.client_id
         ORDER BY p.id, c.created_at DESC
    LOOP
        v_channel := "internal"."staff_alert_channel"(v_rcpt.client_id, 'trial_booked_staff');
        CONTINUE WHEN v_channel IS NULL
                   OR (v_channel = 'email' AND NULLIF(btrim(COALESCE(v_rcpt.email, '')), '') IS NULL);

        INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
        VALUES (
            v_rcpt.client_id, 'trial_booked_staff', v_channel,
            'Nuova lezione di prova: ' || COALESCE(v_activity, 'Studio Kalòs'),
            COALESCE(v_person, 'Una persona') || ' ha prenotato dall''app una lezione di prova '
                || "internal"."format_when_it"(v_lesson.starts_at)
                || COALESCE(' presso ' || v_place, '') || '.',
            jsonb_build_object('lesson_id', v_lesson.id, 'trial_id', v_trial.id,
                               'client_id', v_trial.client_id, 'booking_id', v_trial.booking_id),
            now()
        );
    END LOOP;
END;
$$;

COMMENT ON FUNCTION "internal"."queue_trial_booked_staff"("uuid") IS
    'F6: avvisa gli admin e l''operatrice della lezione che qualcunə ha prenotato una prova dall''app. Push web se c''è, altrimenti email.';

CREATE OR REPLACE FUNCTION "public"."book_trial_lesson"("p_lesson_id" "uuid")
    RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_client_id uuid;
    v_result    jsonb;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'NOT_AUTHENTICATED');
    END IF;

    v_client_id := public.get_my_client_id();
    IF v_client_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'CLIENT_NOT_FOUND');
    END IF;

    v_result := "internal"."create_trial_booking"(p_lesson_id, v_client_id, auth.uid(), false);

    -- Sessione 9: lo staff lo sa. Un problema dell'avviso non fa mai fallire la prenotazione.
    IF COALESCE((v_result->>'ok')::boolean, false) THEN
        BEGIN
            PERFORM "internal"."queue_trial_booked_staff"((v_result->>'trial_id')::uuid);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Avviso allo staff per la prova % non accodato: %', v_result->>'trial_id', SQLERRM;
        END;
    END IF;

    RETURN v_result;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Permessi: le funzioni nuove nascono chiuse; si aprono solo queste, ad authenticated
-- ─────────────────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION "public"."prepare_my_plan_purchase"("uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."prepare_my_event_payment"("uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."prepare_my_settlement"("uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."get_my_open_payments"() TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."get_my_payment_status"("uuid") TO "authenticated";
