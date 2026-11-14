-- Calendario collegato (migrazione 20261114120000): ognunə ha un indirizzo segreto con le proprie
-- prenotazioni, che l'edge function `calendar-feed` legge con la chiave di sistema.

BEGIN;
SELECT plan(24);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('1f000000-0000-0000-0000-000000000001', 'cal-anna@test.kalos', '{"full_name":"Anna Calendario"}', 'authenticated', 'authenticated'),
  ('1f000000-0000-0000-0000-000000000002', 'cal-bruno@test.kalos', '{"full_name":"Bruno Calendario"}', 'authenticated', 'authenticated');

INSERT INTO public.locations (id, slug, name, address_street, address_zip, city, province) VALUES
  ('2f000000-0000-0000-0000-000000000001', 'cal-sala', 'Sala del Parco', 'Via dei Tigli 3', '34077', 'Ronchi dei Legionari', 'GO');
INSERT INTO public.activities (id, name, discipline, duration_minutes, default_location_id) VALUES
  ('2f100000-0000-0000-0000-000000000001', 'Cal Yoga', 'cal_yoga', 60, '2f000000-0000-0000-0000-000000000001');
INSERT INTO public.lessons (id, activity_id, starts_at, ends_at, capacity) VALUES
  ('2f200000-0000-0000-0000-000000000001', '2f100000-0000-0000-0000-000000000001', now() + interval '2 days', now() + interval '2 days 1 hour', 10),
  ('2f200000-0000-0000-0000-000000000002', '2f100000-0000-0000-0000-000000000001', now() + interval '3 days', now() + interval '3 days 1 hour', 10),
  ('2f200000-0000-0000-0000-000000000003', '2f100000-0000-0000-0000-000000000001', now() - interval '90 days', now() - interval '90 days' + interval '1 hour', 10),
  ('2f200000-0000-0000-0000-000000000004', '2f100000-0000-0000-0000-000000000001', now() + interval '4 days', now() + interval '4 days 1 hour', 10);
UPDATE public.lessons SET deleted_at = now() WHERE id = '2f200000-0000-0000-0000-000000000004';
INSERT INTO public.events (id, name, starts_at, ends_at, location) VALUES
  ('2f300000-0000-0000-0000-000000000001', 'Cal Laboratorio', now() + interval '5 days', NULL, 'Biblioteca di Staranzano');

INSERT INTO public.bookings (lesson_id, client_id, status)
SELECT l, c.id, s::public.booking_status
FROM (VALUES
  ('2f200000-0000-0000-0000-000000000001'::uuid, 'booked'),
  ('2f200000-0000-0000-0000-000000000002'::uuid, 'canceled'),
  ('2f200000-0000-0000-0000-000000000003'::uuid, 'attended'),
  ('2f200000-0000-0000-0000-000000000004'::uuid, 'booked')
) v(l, s)
CROSS JOIN public.clients c WHERE c.profile_id = '1f000000-0000-0000-0000-000000000001';
INSERT INTO public.event_bookings (event_id, client_id)
SELECT '2f300000-0000-0000-0000-000000000001', id FROM public.clients WHERE profile_id = '1f000000-0000-0000-0000-000000000001';

-- Permessi
SELECT ok(NOT has_function_privilege('anon', 'public.get_my_calendar_feed()', 'EXECUTE'), 'anon non chiede un indirizzo');
SELECT ok(has_function_privilege('authenticated', 'public.get_my_calendar_feed()', 'EXECUTE'), 'chi ha l''account lo chiede');
SELECT ok(NOT has_function_privilege('authenticated', 'public.calendar_feed_items(text)', 'EXECUTE'), 'le prenotazioni di un indirizzo le legge solo il sistema');
SELECT ok(NOT has_function_privilege('anon', 'public.calendar_feed_items(text)', 'EXECUTE'), 'anche anon no');
SELECT ok(has_function_privilege('service_role', 'public.calendar_feed_items(text)', 'EXECUTE'), 'service_role sì');
SELECT ok(NOT has_table_privilege('authenticated', 'internal.calendar_feeds', 'SELECT'), 'la tabella degli indirizzi è fuori dall''API');

-- Anna chiede il suo indirizzo: nasce la prima volta, poi resta quello
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1f000000-0000-0000-0000-000000000001","role":"authenticated"}';
CREATE TEMP TABLE cal_tokens (who text, token text) ON COMMIT DROP;
GRANT ALL ON cal_tokens TO authenticated, service_role;
INSERT INTO cal_tokens SELECT 'anna1', public.get_my_calendar_feed()->>'token';
INSERT INTO cal_tokens SELECT 'anna2', public.get_my_calendar_feed()->>'token';

SELECT ok((SELECT token ~ '^[0-9a-f]{64}$' FROM cal_tokens WHERE who = 'anna1'), 'il token è di 64 cifre esadecimali');
SELECT is((SELECT token FROM cal_tokens WHERE who = 'anna2'), (SELECT token FROM cal_tokens WHERE who = 'anna1'), 'richiesto di nuovo, è lo stesso');

-- Bruno ha il suo, diverso
SET LOCAL request.jwt.claims = '{"sub":"1f000000-0000-0000-0000-000000000002","role":"authenticated"}';
INSERT INTO cal_tokens SELECT 'bruno', public.get_my_calendar_feed()->>'token';
SELECT isnt((SELECT token FROM cal_tokens WHERE who = 'bruno'), (SELECT token FROM cal_tokens WHERE who = 'anna1'), 'ognunə ha il suo indirizzo');

-- Senza login: niente
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated"}';
SELECT is(public.get_my_calendar_feed()->>'reason', 'NOT_AUTHENTICATED', 'senza account non c''è indirizzo');
RESET ROLE;

-- Le prenotazioni di Anna, lette dal sistema
SET LOCAL ROLE service_role;
CREATE TEMP TABLE cal_feed AS
  SELECT public.calendar_feed_items((SELECT token FROM cal_tokens WHERE who = 'anna1')) AS feed;
SELECT is((SELECT feed->>'found' FROM cal_feed), 'true', 'il token di Anna è riconosciuto');
SELECT is((SELECT jsonb_array_length(feed->'items') FROM cal_feed), 2,
  'solo la lezione prenotata e l''evento: niente disdette, lezioni archiviate o più vecchie di 60 giorni');
SELECT is((SELECT feed->'items'->0->>'title' FROM cal_feed), 'Cal Yoga', 'prima la lezione, in ordine di data');
SELECT is((SELECT feed->'items'->0->>'place' FROM cal_feed), 'Sala del Parco', 'col luogo predefinito dell''attività');
SELECT is((SELECT feed->'items'->0->>'address' FROM cal_feed), 'Via dei Tigli 3, 34077 Ronchi dei Legionari, GO', 'e il suo indirizzo');
SELECT is((SELECT feed->'items'->1->>'kind' FROM cal_feed), 'event', 'poi l''evento');
SELECT is((SELECT feed->'items'->1->>'place' FROM cal_feed), 'Biblioteca di Staranzano', 'col luogo scritto dallo staff');
SELECT is((SELECT (feed->'items'->1->>'ends_at')::timestamptz - (feed->'items'->1->>'starts_at')::timestamptz FROM cal_feed),
  interval '2 hours', 'un evento senza fine dura due ore');
SELECT is((SELECT feed->>'found' FROM (SELECT public.calendar_feed_items(repeat('0', 64)) AS feed) f), 'false', 'un token sconosciuto non trova nulla');
SELECT is((SELECT feed->>'found' FROM (SELECT public.calendar_feed_items('../../etc') AS feed) f), 'false', 'né uno scritto male');
RESET ROLE;

-- Anna cambia indirizzo: il vecchio non vale più
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1f000000-0000-0000-0000-000000000001","role":"authenticated"}';
INSERT INTO cal_tokens SELECT 'anna3', public.reset_my_calendar_feed()->>'token';
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT is(public.calendar_feed_items((SELECT token FROM cal_tokens WHERE who = 'anna1'))->>'found', 'false', 'dopo il cambio il vecchio indirizzo non trova nulla');
SELECT is(public.calendar_feed_items((SELECT token FROM cal_tokens WHERE who = 'anna3'))->>'found', 'true', 'il nuovo sì');
RESET ROLE;

-- La scheda perde l'account (eliminazione dell'account): l'indirizzo se ne va
UPDATE public.clients SET profile_id = NULL WHERE profile_id = '1f000000-0000-0000-0000-000000000001';
SELECT is((SELECT count(*)::int FROM internal.calendar_feeds f JOIN public.clients c ON c.id = f.client_id WHERE c.email = 'cal-anna@test.kalos'),
  0, 'senza account la scheda non ha più un indirizzo');
SET LOCAL ROLE service_role;
SELECT is(public.calendar_feed_items((SELECT token FROM cal_tokens WHERE who = 'anna3'))->>'found', 'false', 'e il calendario collegato si svuota');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
