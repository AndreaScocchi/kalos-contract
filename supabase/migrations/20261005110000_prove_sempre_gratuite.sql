-- Migration 20261005110000: la lezione di prova è sempre gratuita (decisione del 05/10/2026)
--
-- Fino a qui (F1/F2 del piano) la prova era gratuita solo se poi non si comprava: con un abbonamento
-- che copriva l'attività, la prova diventava il primo ingresso e l'abbonamento ne aveva uno in meno.
-- Con un pacchetto da un ingresso l'acquisto finiva tutto nella prova già fatta: il 03/10 un
-- abbonamento comprato dall'app è nato «completato», senza nessuna lezione da prenotare. Dal 05/10 la
-- prova non scala mai un ingresso, in nessun caso.
--
--   - `internal.convert_trial_on_new_subscription`: la prova diventa ancora «convertita» (vuol dire
--     «ha comprato un abbonamento dopo la prova»: la pagina Prove del gestionale la conta), ma senza
--     la riga di consumo `TRIAL`.
--   - `internal.queue_trial_followup`: il messaggio dopo la prova non dice più che vale come primo
--     ingresso.
--   - Le prove già scalate tornano agli abbonamenti: si tolgono le righe `TRIAL` di
--     `subscription_usages`. Il trigger sulla cancellazione
--     (`internal.update_subscription_status_on_usage_after_delete`) ricalcola lo stato: chi era
--     «completato» solo per la prova torna «attivo».
--   - `staff_unconvert_trial` resta com'è: riporta la prova allo stato di prima e toglierebbe una riga
--     `TRIAL`, che non c'è più.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. La conversione non scala più un ingresso
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."convert_trial_on_new_subscription"()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_trial public.trials%ROWTYPE;
BEGIN
    IF NEW.client_id IS NULL OR NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- La prova più vecchia ancora da convertire, fra quelle coperte dall'abbonamento: fatta, o
    -- prenotata e ancora da fare. Una prova a cui non si è venutə non conta.
    SELECT t.* INTO v_trial
      FROM public.trials t
     WHERE t.client_id = NEW.client_id
       AND t.status IN ('booked', 'attended')
       AND "internal"."subscription_covers_activity"(NEW.id, t.activity_id)
     ORDER BY t.booked_at
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- Solo la statistica (pagina Prove): la prova resta gratuita e l'abbonamento ha tutti i suoi
    -- ingressi (05/10/2026).
    UPDATE public.trials
       SET status = 'converted', converted_subscription_id = NEW.id, converted_at = now()
     WHERE id = v_trial.id;

    RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Il messaggio dopo la prova (stesso corpo della sessione 11, cambia solo la frase finale)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION "internal"."queue_trial_followup"("p_trial_id" uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_trial    public.trials%ROWTYPE;
    v_client   public.clients%ROWTYPE;
    v_ends_at  timestamptz;
    v_activity text;
    v_channel  public.notification_channel;
    v_at       timestamptz;
    v_local    timestamp;
BEGIN
    IF NOT COALESCE((SELECT enabled FROM public.feature_flags WHERE key = 'trial_followup'), false) THEN
        RETURN;
    END IF;

    SELECT * INTO v_trial FROM public.trials WHERE id = p_trial_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Una volta sola: né un secondo messaggio né uno a chi ha già risposto
    IF EXISTS (SELECT 1 FROM public.notification_queue
                WHERE category = 'trial_followup' AND data->>'trial_id' = p_trial_id::text)
       OR EXISTS (SELECT 1 FROM public.feedback WHERE trial_id = p_trial_id) THEN
        RETURN;
    END IF;

    SELECT * INTO v_client FROM public.clients WHERE id = v_trial.client_id;
    IF NOT FOUND OR v_client.deleted_at IS NOT NULL THEN
        RETURN;
    END IF;

    v_channel := "internal"."get_notification_channel"(v_trial.client_id, 'trial_followup');
    IF v_channel IS NULL OR (v_channel = 'email' AND NULLIF(btrim(COALESCE(v_client.email, '')), '') IS NULL) THEN
        RETURN;
    END IF;

    SELECT ends_at INTO v_ends_at FROM public.lessons WHERE id = v_trial.lesson_id;
    SELECT name INTO v_activity FROM public.activities WHERE id = v_trial.activity_id;

    v_at := GREATEST(now(), COALESCE(v_ends_at, now()) + interval '1 hour');
    v_local := v_at AT TIME ZONE 'Europe/Rome';
    IF extract(hour FROM v_local) >= 21 THEN
        v_at := ((v_local::date + 1) + time '09:00') AT TIME ZONE 'Europe/Rome';
    ELSIF extract(hour FROM v_local) < 9 THEN
        v_at := (v_local::date + time '09:00') AT TIME ZONE 'Europe/Rome';
    END IF;

    INSERT INTO public.notification_queue (client_id, category, channel, title, body, data, scheduled_for)
    VALUES (
        v_trial.client_id, 'trial_followup', v_channel,
        'Com''è andata la prova' || COALESCE(' di ' || v_activity, '') || '?',
        'Grazie di essere venutə. Ci racconti com''è andata? Sono tre domande, un minuto.'
            || CASE WHEN v_trial.status = 'converted' THEN ''
                    ELSE ' E se vuoi continuare, nell''app trovi gli abbonamenti.'
               END,
        jsonb_build_object('trial_id', v_trial.id, 'lesson_id', v_trial.lesson_id,
                           'activity_id', v_trial.activity_id,
                           'url', '/feedback/trial/' || v_trial.id),
        v_at
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Le prove già scalate tornano agli abbonamenti
-- ─────────────────────────────────────────────────────────────────────────────

-- Il trigger sulla cancellazione ricalcola lo stato di ciascun abbonamento toccato
DELETE FROM public.subscription_usages WHERE reason = 'TRIAL';
