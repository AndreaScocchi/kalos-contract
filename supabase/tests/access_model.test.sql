-- Test del modello di accesso (ACCESS_MODEL.md). Si lancia con `npm run test:db`.
--
-- Congela l'elenco esplicito di ciò che anon e authenticated possono fare: se una migrazione
-- apre una funzione, una tabella o una policy fuori elenco, questo test fallisce. Chi aggiunge
-- una funzione nuova da aprire aggiorna l'elenco qui e in ACCESS_MODEL.md, nella stessa PR.
--
-- Più alcuni comportamenti critici, simulando i ruoli come fa PostgREST (SET ROLE + claims JWT).

BEGIN;
SELECT plan(20);

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 1. Elenco esplicito: funzioni
-- ─────────────────────────────────────────────────────────────────────────────────────────────

SELECT set_eq(
  $$ SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
     FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace AND has_function_privilege('anon', p.oid, 'EXECUTE') $$,
  ARRAY[
    'can_access_finance()',
    'get_event_booking_count(p_event_id uuid)',
    'get_events_booking_counts(p_event_ids uuid[])',
    'get_my_client_id()',
    'is_admin()',
    'is_finance()',
    'is_staff()'
  ],
  'anon esegue solo gli helper delle policy e i conteggi pubblici degli eventi'
);

SELECT set_eq(
  $$ SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
     FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
       AND NOT has_function_privilege('anon', p.oid, 'EXECUTE') $$,
  ARRAY[
    'assign_membership(p_client_id uuid, p_tier_id uuid, p_started_at date, p_price_cents integer, p_note text)',
    'book_event(p_event_id uuid)',
    'book_lesson(p_lesson_id uuid, p_subscription_id uuid)',
    'calculate_next_announcement_occurrence(p_frequency announcement_recurrence_frequency, p_day_of_week smallint, p_day_of_month smallint, p_time time without time zone, p_from_date timestamp with time zone)',
    'calculate_operator_compensation(p_month_start date, p_month_end date, p_operator_id uuid)',
    'cancel_booking(p_booking_id uuid)',
    'cancel_bussola_request(p_request_id uuid)',
    'cancel_event_booking(p_booking_id uuid)',
    'cancel_membership(p_membership_id uuid)',
    'deactivate_device_token(p_token text)',
    'delete_campaign(campaign_id uuid)',
    'generate_slug_from_discipline(discipline_text text)',
    'get_activity_booking_counts()',
    'get_auth_email_stats(p_user_id uuid)',
    'get_financial_kpis(p_month_start date, p_month_end date)',
    'get_journey_summary()',
    'get_journey_timeline(p_limit integer, p_offset integer)',
    'get_monthly_revenue_by_client(p_month_start date, p_month_end date)',
    'get_monthly_revenue_by_plan(p_month_start date, p_month_end date)',
    'get_my_membership()',
    'get_my_notification_settings()',
    'get_my_notifications(p_limit integer, p_offset integer)',
    'get_practice_metrics()',
    'get_revenue_breakdown(p_month_start date, p_month_end date)',
    'get_unread_notifications_count()',
    'mark_all_notifications_read()',
    'mark_notification_read(p_notification_log_id uuid, p_announcement_id uuid)',
    'promote_profile_to_operator(p_profile_id uuid)',
    'queue_feedback_request(p_client_id uuid, p_kind feedback_kind, p_target_id uuid, p_scheduled_for timestamp with time zone)',
    'queue_new_event(p_event_id uuid, p_event_name text, p_event_date timestamp with time zone)',
    'queue_new_event(p_event_id uuid, p_event_name text, p_event_date timestamp with time zone, p_send_push boolean, p_send_email boolean)',
    'register_device_token(p_token text, p_platform text, p_device_id text, p_app_version text)',
    'request_bussola(p_preferred_at timestamp with time zone, p_note text)',
    'set_notification_quiet_hours(p_enabled boolean, p_start time without time zone, p_end time without time zone)',
    'staff_book_event(p_event_id uuid, p_client_id uuid)',
    'staff_book_lesson(p_lesson_id uuid, p_client_id uuid, p_subscription_id uuid)',
    'staff_cancel_booking(p_booking_id uuid)',
    'staff_cancel_event_booking(p_booking_id uuid)',
    'staff_get_user_email_status(p_user_id uuid)',
    'staff_update_booking_status(p_booking_id uuid, p_status booking_status)',
    'submit_feedback(p_kind feedback_kind, p_target_id uuid, p_rating smallint, p_comment text)'
  ],
  'authenticated esegue in più solo le RPC di clienti, staff e Finanze (con controlli interni)'
);

SELECT is_empty(
  $$ SELECT p.oid::regprocedure::text FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE') $$,
  'service_role (edge function) esegue tutte le funzioni di public'
);

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 2. Elenco esplicito: tabelle, view e policy per anon
-- ─────────────────────────────────────────────────────────────────────────────────────────────

SELECT set_eq(
  $$ SELECT c.relname::text FROM pg_class c
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v', 'm', 'p')
       AND has_table_privilege('anon', c.oid, 'SELECT') $$,
  ARRAY[
    'activities', 'events', 'feature_flags', 'lesson_occupancy', 'lessons', 'operators',
    'pass_tier_benefits', 'pass_tiers', 'plan_activities', 'plans', 'promotions',
    'public_site_activities', 'public_site_events', 'public_site_operators',
    'public_site_pricing', 'public_site_schedule'
  ],
  'anon legge solo i dati pubblici del sito'
);

SELECT is_empty(
  $$ SELECT c.relname || ':' || p FROM pg_class c,
       unnest(ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v', 'm', 'p')
       AND has_table_privilege('anon', c.oid, p) $$,
  'anon non scrive nessuna tabella'
);

SELECT is_empty(
  $$ SELECT c.relname || ':' || p FROM pg_class c, unnest(ARRAY['TRUNCATE', 'REFERENCES', 'TRIGGER']) p
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v', 'm', 'p')
       AND has_table_privilege('authenticated', c.oid, p) $$,
  'authenticated non ha i privilegi che l''API non usa'
);

SELECT is_empty(
  $$ SELECT tablename || '.' || policyname FROM pg_policies
     WHERE schemaname = 'public' AND 'anon' = ANY (roles) AND tablename <> 'events' $$,
  'nessuna policy dedicata ad anon fuori da events (vista pubblica degli eventi)'
);

SELECT is_empty(
  $$ SELECT 1 FROM pg_class
     WHERE oid = 'public.financial_monthly_summary'::regclass
       AND (has_table_privilege('authenticated', oid, 'SELECT') OR has_table_privilege('anon', oid, 'SELECT')) $$,
  'la stima delle entrate non è leggibile da operatrici e clienti'
);

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 3. Le funzioni future nascono chiuse
-- ─────────────────────────────────────────────────────────────────────────────────────────────

CREATE FUNCTION public.__access_model_probe() RETURNS int LANGUAGE sql AS 'SELECT 1';
SELECT ok(
  NOT has_function_privilege('anon', 'public.__access_model_probe()', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.__access_model_probe()', 'EXECUTE')
  AND has_function_privilege('service_role', 'public.__access_model_probe()', 'EXECUTE'),
  'una funzione nuova in public non è eseguibile da anon e authenticated, sì da service_role'
);

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 4. Comportamenti critici, con i ruoli simulati come fa PostgREST
-- ─────────────────────────────────────────────────────────────────────────────────────────────

-- Tre utenti: la registrazione (trigger on_auth_user_created) crea profilo e scheda cliente.
INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'am-cliente@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'am-operatrice@example.test'),
  ('33333333-3333-3333-3333-333333333333', 'am-admin@example.test');
UPDATE public.profiles SET role = 'operator' WHERE id = '22222222-2222-2222-2222-222222222222';
UPDATE public.profiles SET role = 'admin' WHERE id = '33333333-3333-3333-3333-333333333333';

SELECT is(
  (SELECT count(*)::int FROM public.clients WHERE profile_id = '11111111-1111-1111-1111-111111111111'),
  1, 'la registrazione crea la scheda cliente'
);

-- anon
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims = '{"role": "anon"}';
SELECT throws_ok('SELECT count(*) FROM public.clients', '42501', NULL, 'anon: clients non leggibile');
SELECT throws_ok($$ SELECT public.call_edge_function('noop', '{}'::jsonb) $$, '42501', NULL,
  'anon: call_edge_function non eseguibile');
SELECT throws_ok($$ SELECT * FROM public.get_monthly_revenue_by_client('1900-01-01', '1900-01-31') $$, '42501', NULL,
  'anon: Finanze non eseguibili');
RESET ROLE;

-- cliente
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
SELECT lives_ok($$ UPDATE public.profiles SET full_name = 'Cliente', phone = '333' WHERE id = auth.uid() $$,
  'cliente: modifica nome e telefono');
SELECT throws_ok($$ UPDATE public.profiles SET role = 'admin' WHERE id = auth.uid() $$, '42501', NULL,
  'cliente: non può darsi il ruolo admin');
SELECT throws_ok($$ UPDATE public.profiles SET email = 'altro@example.test' WHERE id = auth.uid() $$, '42501', NULL,
  'cliente: non può cambiare l''email del profilo (aggancio della scheda altrui)');
SELECT throws_ok($$ SELECT * FROM public.get_monthly_revenue_by_client('1900-01-01', '1900-01-31') $$, '42501', NULL,
  'cliente: Finanze rifiutate');
RESET ROLE;

-- operatrice
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
SELECT throws_ok($$ UPDATE public.profiles SET role = 'admin' WHERE id = auth.uid() $$, '42501', NULL,
  'operatrice: non può darsi il ruolo admin');
SELECT throws_ok($$ SELECT * FROM public.calculate_operator_compensation('1900-01-01', '1900-01-31', NULL) $$, '42501', NULL,
  'operatrice: Finanze rifiutate');
RESET ROLE;

-- admin
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
SELECT lives_ok($$ SELECT * FROM public.get_monthly_revenue_by_plan('1900-01-01', '1900-01-31') $$,
  'admin: Finanze accessibili');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
