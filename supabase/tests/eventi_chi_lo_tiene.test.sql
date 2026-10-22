-- Chi tiene l'evento sul sito (v0.3.18): `public_site_events.performer_names` ha i nomi di chi tiene
-- l'evento, solo le persone visibili sul sito, e anon la legge senza leggere `event_operators`.

BEGIN;
SELECT plan(5);

INSERT INTO public.operators (id, name, role, is_visible_on_site) VALUES
  ('0e180000-0000-0000-0000-000000000001', 'V318 Zoe Visibile', 'istruttrice', true),
  ('0e180000-0000-0000-0000-000000000002', 'V318 Anna Visibile', 'istruttrice', true),
  ('0e180000-0000-0000-0000-000000000003', 'V318 Nascosta', 'ospite', false);

INSERT INTO public.events (id, name, starts_at, ends_at, price_cents) VALUES
  ('0e181000-0000-0000-0000-000000000001', 'V318 Con due', now() + interval '7 days', now() + interval '7 days 2 hours', 0),
  ('0e181000-0000-0000-0000-000000000002', 'V318 Solo nascosta', now() + interval '8 days', now() + interval '8 days 2 hours', 0),
  ('0e181000-0000-0000-0000-000000000003', 'V318 Senza nessuno', now() + interval '9 days', now() + interval '9 days 2 hours', 0);

INSERT INTO public.event_operators (event_id, operator_id) VALUES
  ('0e181000-0000-0000-0000-000000000001', '0e180000-0000-0000-0000-000000000001'),
  ('0e181000-0000-0000-0000-000000000001', '0e180000-0000-0000-0000-000000000002'),
  ('0e181000-0000-0000-0000-000000000001', '0e180000-0000-0000-0000-000000000003'),
  ('0e181000-0000-0000-0000-000000000002', '0e180000-0000-0000-0000-000000000003');

SET LOCAL ROLE anon;

SELECT ok(NOT has_table_privilege('anon', 'public.event_operators', 'SELECT'),
  'anon non legge event_operators');
SELECT is(
  (SELECT performer_names FROM public.public_site_events WHERE id = '0e181000-0000-0000-0000-000000000001'),
  ARRAY['V318 Anna Visibile', 'V318 Zoe Visibile']::text[],
  'le persone visibili sul sito, in ordine alfabetico, senza chi è nascostə');
SELECT is(
  (SELECT performer_names FROM public.public_site_events WHERE id = '0e181000-0000-0000-0000-000000000002'),
  ARRAY[]::text[], 'chi non è visibile sul sito non compare');
SELECT is(
  (SELECT performer_names FROM public.public_site_events WHERE id = '0e181000-0000-0000-0000-000000000003'),
  ARRAY[]::text[], 'nessunə: array vuoto');

RESET ROLE;
UPDATE public.operators SET is_active = false WHERE id = '0e180000-0000-0000-0000-000000000002';
SET LOCAL ROLE anon;
SELECT is(
  (SELECT performer_names FROM public.public_site_events WHERE id = '0e181000-0000-0000-0000-000000000001'),
  ARRAY['V318 Zoe Visibile']::text[], 'una persona non più attiva non compare');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
