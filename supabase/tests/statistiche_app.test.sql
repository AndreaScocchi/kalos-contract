-- Statistiche d'uso dell'app (migrazione 20261103120000): solo totali. Due visite della stessa
-- persona fanno 2 visualizzazioni e 1 persona; lo staff non conta; niente righe a piacere; impronte
-- e chiavi scadute spariscono; nessuna tabella contiene un id di account.

BEGIN;
SELECT plan(36);

-- ── Persone e contenuti ──────────────────────────────────────────────────────

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('0f100000-0000-0000-0000-000000000001', 'usage-a@test.kalos', '{"full_name":"Cliente A"}', 'authenticated', 'authenticated'),
  ('0f100000-0000-0000-0000-000000000002', 'usage-b@test.kalos', '{"full_name":"Cliente B"}', 'authenticated', 'authenticated'),
  ('0f100000-0000-0000-0000-000000000003', 'usage-staff@test.kalos', '{"full_name":"Operatrice"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '0f100000-0000-0000-0000-000000000003';

INSERT INTO public.activities (id, name, discipline, duration_minutes)
VALUES ('0f102000-0000-0000-0000-000000000001', 'Usage Yoga', 'usage_yoga', 60);

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity) VALUES
  ('0f103000-0000-0000-0000-000000000001', '0f102000-0000-0000-0000-000000000001',
   now() + interval '1 day', now() + interval '1 day' + interval '1 hour', 10);

INSERT INTO public.clients (id, full_name) VALUES ('0f106000-0000-0000-0000-000000000001', 'Usage Individuale');

INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity, is_individual, assigned_client_id) VALUES
  ('0f103000-0000-0000-0000-000000000002', '0f102000-0000-0000-0000-000000000001',
   now() + interval '2 days', now() + interval '2 days' + interval '1 hour', 1, true, '0f106000-0000-0000-0000-000000000001');

INSERT INTO public.events (id, name, starts_at, ends_at) VALUES
  ('0f104000-0000-0000-0000-000000000001', 'Usage Evento', now() + interval '3 days', now() + interval '3 days' + interval '1 hour'),
  ('0f104000-0000-0000-0000-000000000002', 'Usage Evento 2', now() + interval '4 days', now() + interval '4 days' + interval '1 hour');

INSERT INTO public.practices (id, title, category) VALUES ('0f105000-0000-0000-0000-000000000001', 'Usage Pratica', 'meditazione');

-- I numeri del mese in corso, da postgres: la riga di una metrica, una pagina e un bersaglio
CREATE OR REPLACE FUNCTION pg_temp.month_count(p_metric text, p_page text DEFAULT NULL, p_target uuid DEFAULT NULL, p_step smallint DEFAULT NULL)
RETURNS TABLE(views integer, people integer) LANGUAGE sql AS $$
  SELECT c.views, c.people FROM internal.app_usage_counts c
   WHERE c.granularity = 'month' AND c.metric = p_metric
     AND c.page IS NOT DISTINCT FROM p_page
     AND c.target_id IS NOT DISTINCT FROM p_target
     AND c.step IS NOT DISTINCT FROM p_step;
$$;

-- ── Chi può chiamare cosa ────────────────────────────────────────────────────

SELECT ok(NOT has_function_privilege('anon', 'public.record_app_usage(jsonb)', 'EXECUTE'), 'anon non registra');
SELECT ok(NOT has_function_privilege('anon', 'public.staff_get_app_usage(date)', 'EXECUTE'), 'anon non legge');
SELECT ok(has_function_privilege('authenticated', 'public.record_app_usage(jsonb)', 'EXECUTE'), 'con il login si registra');
SELECT ok(NOT has_table_privilege('authenticated', 'internal.app_usage_counts', 'SELECT'), 'i contatori non si leggono dall''API');
SELECT ok(NOT has_table_privilege('authenticated', 'internal.app_usage_seen', 'SELECT'), 'le impronte non si leggono dall''API');
SELECT ok(NOT has_table_privilege('authenticated', 'internal.app_usage_salts', 'SELECT'), 'le chiavi non si leggono dall''API');

-- ── Stessa persona due volte, poi un'altra persona ───────────────────────────

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"0f100000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SELECT public.record_app_usage('[{"metric":"open"},{"metric":"page","page":"home"},{"metric":"page","page":"home"}]'::jsonb);
SELECT public.record_app_usage('[{"metric":"open"}]'::jsonb);
SELECT is((public.staff_get_app_usage(NULL)->>'reason'), 'NOT_STAFF', 'unə cliente non legge le statistiche');
RESET ROLE;

SELECT results_eq($$ SELECT views, people FROM pg_temp.month_count('open') $$, $$ VALUES (2, 1) $$,
  'due aperture della stessa persona: 2 visualizzazioni, 1 persona');
SELECT results_eq($$ SELECT views, people FROM pg_temp.month_count('page', 'home') $$, $$ VALUES (2, 1) $$,
  'due volte la stessa pagina: 2 visualizzazioni, 1 persona');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"0f100000-0000-0000-0000-000000000002","role":"authenticated"}', true);
SELECT public.record_app_usage('[{"metric":"open"},{"metric":"page","page":"home"}]'::jsonb);
RESET ROLE;

SELECT results_eq($$ SELECT views, people FROM pg_temp.month_count('open') $$, $$ VALUES (3, 2) $$,
  'due persone: 2 persone');
SELECT results_eq(
  $$ SELECT views, people FROM internal.app_usage_counts WHERE granularity = 'day' AND metric = 'open' $$,
  $$ VALUES (3, 2) $$, 'anche per giorno, e il giorno lo decide il server');
SELECT is(
  (SELECT period FROM internal.app_usage_counts WHERE granularity = 'day' AND metric = 'open' LIMIT 1),
  (now() AT TIME ZONE 'Europe/Rome')::date, 'il giorno è quello italiano');

-- ── Lo staff non conta ───────────────────────────────────────────────────────

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"0f100000-0000-0000-0000-000000000003","role":"authenticated"}', true);
SELECT public.record_app_usage('[{"metric":"open"},{"metric":"page","page":"calendar"}]'::jsonb);
RESET ROLE;

SELECT results_eq($$ SELECT views, people FROM pg_temp.month_count('open') $$, $$ VALUES (3, 2) $$,
  'le aperture dello staff non contano');
SELECT is_empty($$ SELECT 1 FROM pg_temp.month_count('page', 'calendar') $$, 'le pagine dello staff non contano');

-- ── Bersagli: esistono, solo nelle pagine previste ───────────────────────────

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"0f100000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SELECT public.record_app_usage($$[
  {"metric":"page","page":"event","target_id":"0f104000-0000-0000-0000-000000000001"},
  {"metric":"page","page":"event","target_id":"0f104000-0000-0000-0000-000000000002"},
  {"metric":"page","page":"event","target_id":"0f10ffff-0000-0000-0000-000000000000"},
  {"metric":"page","page":"event","target_id":"non-un-id"},
  {"metric":"page","page":"lesson","target_id":"0f103000-0000-0000-0000-000000000001"},
  {"metric":"page","page":"journal_entry","target_id":"0f104000-0000-0000-0000-000000000001"},
  {"metric":"page","page":"pagina_inventata"},
  {"metric":"page","page":"un'altra_inventata"},
  {"metric":"inventata","page":"home"},
  {"metric":"practice_start","target_id":"0f10ffff-0000-0000-0000-000000000000"},
  {"metric":"practice_step","target_id":"0f105000-0000-0000-0000-000000000001","step":"mille"},
  "non un oggetto"
]$$::jsonb);
RESET ROLE;

SELECT results_eq(
  $$ SELECT views, people FROM pg_temp.month_count('page', 'event', '0f104000-0000-0000-0000-000000000001') $$,
  $$ VALUES (1, 1) $$, 'l''evento aperto ha il suo numero');
SELECT results_eq($$ SELECT views, people FROM pg_temp.month_count('page', 'event') $$, $$ VALUES (4, 1) $$,
  'chi apre più eventi è una persona sola nella pagina Evento (e gli id sbagliati contano solo lì)');
SELECT is_empty(
  $$ SELECT 1 FROM internal.app_usage_counts WHERE target_id = '0f10ffff-0000-0000-0000-000000000000' $$,
  'un id inesistente non crea righe');
SELECT results_eq(
  $$ SELECT views, people FROM pg_temp.month_count('page', 'lesson', '0f102000-0000-0000-0000-000000000001') $$,
  $$ VALUES (1, 1) $$, 'una lezione si conta sulla sua attività');
SELECT is_empty(
  $$ SELECT 1 FROM internal.app_usage_counts WHERE target_id = '0f103000-0000-0000-0000-000000000001' $$,
  'l''id della lezione non si salva');
SELECT results_eq($$ SELECT views FROM pg_temp.month_count('page', 'journal_entry') $$, $$ VALUES (1) $$,
  'il Diario conta solo come pagina');
SELECT is_empty(
  $$ SELECT 1 FROM internal.app_usage_counts WHERE page = 'journal_entry' AND target_id IS NOT NULL $$,
  'senza dire quale voce');
SELECT results_eq($$ SELECT views, people FROM pg_temp.month_count('page', 'altro') $$, $$ VALUES (2, 1) $$,
  'una pagina sconosciuta finisce in «altro»');
SELECT is_empty($$ SELECT 1 FROM internal.app_usage_counts WHERE metric NOT IN ('open', 'page') $$,
  'metriche inventate e pratiche inesistenti non creano righe');

-- ── Lezione individuale, pratica, troppe voci ────────────────────────────────

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"0f100000-0000-0000-0000-000000000001","role":"authenticated"}', true);
SELECT public.record_app_usage($$[
  {"metric":"practice_start","target_id":"0f105000-0000-0000-0000-000000000001"},
  {"metric":"practice_step","target_id":"0f105000-0000-0000-0000-000000000001","step":0},
  {"metric":"practice_step","target_id":"0f105000-0000-0000-0000-000000000001","step":1},
  {"metric":"practice_audio","target_id":"0f105000-0000-0000-0000-000000000001"},
  {"metric":"practice_complete","target_id":"0f105000-0000-0000-0000-000000000001"}
]$$::jsonb);
SELECT public.record_app_usage((SELECT jsonb_agg(jsonb_build_object('metric', 'page', 'page', 'contacts')) FROM generate_series(1, 200)));
SELECT public.record_app_usage('[{"metric":"page","page":"lesson","target_id":"0f103000-0000-0000-0000-000000000002"}]'::jsonb);
RESET ROLE;

SELECT results_eq(
  $$ SELECT views FROM pg_temp.month_count('page', 'lesson', '0f102000-0000-0000-0000-000000000001') $$,
  $$ VALUES (1) $$, 'la lezione individuale non si conta sull''attività');
SELECT results_eq($$ SELECT views FROM pg_temp.month_count('page', 'lesson') $$, $$ VALUES (2) $$,
  'conta solo come pagina');

SELECT results_eq(
  $$ SELECT views FROM pg_temp.month_count('practice_step', NULL, '0f105000-0000-0000-0000-000000000001', 1::smallint) $$,
  $$ VALUES (1) $$, 'il passaggio raggiunto ha il suo numero');
SELECT results_eq($$ SELECT views FROM pg_temp.month_count('page', 'contacts') $$, $$ VALUES (30) $$,
  'una chiamata conta al massimo 30 voci');

-- ── Il gestionale legge i totali ─────────────────────────────────────────────

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"0f100000-0000-0000-0000-000000000003","role":"authenticated"}', true);
SELECT set_config('test.usage_read', public.staff_get_app_usage(NULL)::text, true);
RESET ROLE;
CREATE TEMP TABLE usage_read AS SELECT current_setting('test.usage_read')::jsonb AS r;

SELECT is((SELECT (r->'totals'->>'people')::int FROM usage_read), 2, 'lo staff legge le persone del mese');
SELECT is((SELECT (r->'totals'->>'opens')::int FROM usage_read), 3, 'e le aperture');
SELECT is(
  (SELECT (e->>'people')::int FROM usage_read, jsonb_array_elements(r->'events') e WHERE e->>'name' = 'Usage Evento'),
  1, 'gli eventi hanno il nome e il numero');
SELECT is(
  (SELECT (a->>'lesson_people')::int FROM usage_read, jsonb_array_elements(r->'activities') a WHERE a->>'name' = 'Usage Yoga'),
  1, 'le attività sommano chi apre le loro lezioni');
SELECT is(
  (SELECT (p->>'complete_people')::int FROM usage_read, jsonb_array_elements(r->'practices') p WHERE p->>'title' = 'Usage Pratica'),
  1, 'le pratiche dicono chi le ha completate');

-- ── Nessun id di account, e quello che scade sparisce ────────────────────────

SELECT is_empty(
  $$ SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'internal' AND table_name LIKE 'app_usage%'
        AND column_name IN ('client_id', 'user_id', 'profile_id', 'uid') $$,
  'nessuna colonna per persona');
SELECT is_empty(
  $$ SELECT 1 FROM internal.app_usage_counts c
       JOIN auth.users u ON u.id = c.target_id $$,
  'nessun contatore punta a un account');

-- Un'impronta e una chiave di ieri e del mese scorso: alla prossima chiamata non ci sono più
INSERT INTO internal.app_usage_seen (hash, expires_on)
VALUES ('\xdead'::bytea, (now() AT TIME ZONE 'Europe/Rome')::date - 1);
INSERT INTO internal.app_usage_salts (month)
VALUES ((date_trunc('month', (now() AT TIME ZONE 'Europe/Rome')::date) - interval '1 month')::date);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"0f100000-0000-0000-0000-000000000002","role":"authenticated"}', true);
SELECT public.record_app_usage('[{"metric":"open"}]'::jsonb);
RESET ROLE;

SELECT is_empty($$ SELECT 1 FROM internal.app_usage_seen WHERE hash = '\xdead'::bytea $$,
  'le impronte scadute spariscono');
SELECT results_eq($$ SELECT count(*)::int FROM internal.app_usage_salts $$, $$ VALUES (1) $$,
  'resta solo la chiave del mese');

SELECT * FROM finish();
ROLLBACK;
