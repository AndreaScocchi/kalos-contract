-- Prove sempre gratuite (v0.3.13, decisione del 05/10/2026): comprare un abbonamento dopo la prova
-- non scala nessun ingresso, anche con un pacchetto da un ingresso solo. La prova resta «convertita»
-- per le statistiche del gestionale.

BEGIN;
SELECT plan(8);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('1e000000-0000-0000-0000-000000000001', 'pg-anna@test.kalos', '{"full_name":"Anna Prova"}', 'authenticated', 'authenticated');
UPDATE public.feature_flags SET enabled = false WHERE key = 'members_only';
UPDATE public.feature_flags SET enabled = true  WHERE key = 'trial_followup';

INSERT INTO public.activities (id, name, discipline, duration_minutes, trial_enabled) VALUES
  ('2e000000-0000-0000-0000-000000000001', 'PG Meditazione', 'pg_meditazione', 60, true);
INSERT INTO public.plans (id, name, price_cents, entries, validity_days) VALUES
  ('4e000000-0000-0000-0000-000000000001', 'PG 1 Ingresso', 1500, 1, 30);
INSERT INTO public.plan_activities (plan_id, activity_id) VALUES
  ('4e000000-0000-0000-0000-000000000001', '2e000000-0000-0000-0000-000000000001');

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity) VALUES
  ('3e000000-0000-0000-0000-000000000001', '2e000000-0000-0000-0000-000000000001',
   now() - interval '3 days', now() - interval '3 days' + interval '1 hour', 8);

-- La prova fatta
INSERT INTO public.bookings (id, lesson_id, client_id, status, is_trial)
SELECT '6e000000-0000-0000-0000-000000000001', '3e000000-0000-0000-0000-000000000001', c.id, 'attended', true
  FROM public.clients c WHERE c.email = 'pg-anna@test.kalos';
INSERT INTO public.trials (id, client_id, activity_id, lesson_id, booking_id, status)
SELECT '7e000000-0000-0000-0000-000000000001', c.id, '2e000000-0000-0000-0000-000000000001',
       '3e000000-0000-0000-0000-000000000001', '6e000000-0000-0000-0000-000000000001', 'attended'
  FROM public.clients c WHERE c.email = 'pg-anna@test.kalos';

-- Il messaggio dopo la prova, ancora da comprare: invito ai piani, senza «primo ingresso»
SELECT internal.queue_trial_followup('7e000000-0000-0000-0000-000000000001');
SELECT ok((SELECT body LIKE '%abbonamenti%' AND body NOT LIKE '%primo ingresso%'
             FROM public.notification_queue
            WHERE category = 'trial_followup' AND data->>'trial_id' = '7e000000-0000-0000-0000-000000000001'),
  'il messaggio dopo la prova invita agli abbonamenti senza dire che la prova si scala');

-- Poi compra il pacchetto da un ingresso che copre la prova
INSERT INTO public.subscriptions (id, client_id, plan_id, started_at, expires_at)
SELECT '5e000000-0000-0000-0000-000000000001', c.id, '4e000000-0000-0000-0000-000000000001',
       CURRENT_DATE, CURRENT_DATE + 30
  FROM public.clients c WHERE c.email = 'pg-anna@test.kalos';

SELECT is((SELECT count(*)::int FROM public.subscription_usages
            WHERE subscription_id = '5e000000-0000-0000-0000-000000000001'), 0,
  'comprando dopo la prova non si scala nessun ingresso');
SELECT is((SELECT remaining_entries::int FROM public.subscriptions_with_remaining
            WHERE id = '5e000000-0000-0000-0000-000000000001'), 1,
  'il pacchetto da un ingresso ha ancora il suo ingresso');
SELECT is((SELECT status::text FROM public.subscriptions WHERE id = '5e000000-0000-0000-0000-000000000001'),
  'active', 'e resta attivo, non «completato»');
SELECT is((SELECT status::text || ' | ' || converted_subscription_id::text FROM public.trials
            WHERE id = '7e000000-0000-0000-0000-000000000001'),
  'converted | 5e000000-0000-0000-0000-000000000001',
  'la prova risulta convertita, per le statistiche della pagina Prove');

-- Una riga `TRIAL` rimasta da prima (come in produzione): togliendola l'abbonamento torna attivo
INSERT INTO public.subscription_usages (subscription_id, booking_id, delta, reason)
VALUES ('5e000000-0000-0000-0000-000000000001', '6e000000-0000-0000-0000-000000000001', -1, 'TRIAL');
SELECT is((SELECT status::text FROM public.subscriptions WHERE id = '5e000000-0000-0000-0000-000000000001'),
  'completed', 'con la prova scalata il pacchetto da uno risultava completato');
DELETE FROM public.subscription_usages WHERE reason = 'TRIAL'
   AND subscription_id = '5e000000-0000-0000-0000-000000000001';
SELECT is((SELECT status::text FROM public.subscriptions WHERE id = '5e000000-0000-0000-0000-000000000001'),
  'active', 'tolta la riga della prova (come fa la migrazione) torna attivo');

SELECT is((SELECT count(*)::int FROM public.subscription_usages WHERE reason = 'TRIAL'
            AND subscription_id <> '5e000000-0000-0000-0000-000000000001'), 0,
  'dopo la migrazione non resta nessuna prova scalata');

SELECT * FROM finish();
ROLLBACK;
