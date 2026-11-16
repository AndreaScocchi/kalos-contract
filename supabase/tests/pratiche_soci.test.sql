-- La Pratica a casa è dei soci (migrazione 20261116120000): tuttə vedono le pratiche, ma passaggi e
-- blocchi li leggono solo lo staff e chi è sociə in regola (quota pagata o esonerata, o dell'anno e
-- non ancora scaduta).

BEGIN;
SELECT plan(19);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('3a000000-0000-0000-0000-000000000001', 'ps-nonsocia@test.kalos', '{"full_name":"Nina Nonsocia"}', 'authenticated', 'authenticated'),
  ('3a000000-0000-0000-0000-000000000002', 'ps-socia@test.kalos', '{"full_name":"Sara Socia"}', 'authenticated', 'authenticated'),
  ('3a000000-0000-0000-0000-000000000003', 'ps-attesa@test.kalos', '{"full_name":"Tina Inattesa"}', 'authenticated', 'authenticated'),
  ('3a000000-0000-0000-0000-000000000004', 'ps-scaduta@test.kalos', '{"full_name":"Ugo Scaduto"}', 'authenticated', 'authenticated'),
  ('3a000000-0000-0000-0000-000000000005', 'ps-staff@test.kalos', '{"full_name":"Olga Operatrice"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '3a000000-0000-0000-0000-000000000005';

-- Quota dell'anno: 35 €, scade fra 30 giorni
INSERT INTO public.association_years (year, fee_cents, fee_due_date, is_open)
VALUES (extract(year FROM internal.rome_today())::int, 3500, internal.rome_today() + 30, true)
ON CONFLICT (year) DO UPDATE SET fee_cents = 3500, fee_due_date = internal.rome_today() + 30, is_open = true;

-- Sara: sociə con la quota pagata. Tina: sociə con la quota da pagare, non ancora scaduta.
-- Ugo: sociə, poi la quota scade (più sotto). Nina: nessuna domanda.
INSERT INTO public.members (client_id, member_number, admitted_on, status)
SELECT c.id, v.num, internal.rome_today() - 60, 'active'
  FROM (VALUES
    ('3a000000-0000-0000-0000-000000000002'::uuid, 'PS-0001'),
    ('3a000000-0000-0000-0000-000000000003'::uuid, 'PS-0002'),
    ('3a000000-0000-0000-0000-000000000004'::uuid, 'PS-0003')
  ) AS v(uid, num)
  JOIN public.clients c ON c.profile_id = v.uid;
INSERT INTO public.member_fees (client_id, year, amount_cents, status, paid_at)
SELECT c.id, extract(year FROM internal.rome_today())::int, 3500, 'paid', now()
  FROM public.clients c WHERE c.profile_id = '3a000000-0000-0000-0000-000000000002';

INSERT INTO public.practices (id, title, category) VALUES
  ('3a100000-0000-0000-0000-000000000001', 'PS Respiro', 'meditazione');
INSERT INTO public.practices (id, title, category, is_active) VALUES
  ('3a100000-0000-0000-0000-000000000002', 'PS Spenta', 'corpo', false);
INSERT INTO public.practice_steps (id, practice_id, title, sort_order) VALUES
  ('3a200000-0000-0000-0000-000000000001', '3a100000-0000-0000-0000-000000000001', 'Arrivare', 0),
  ('3a200000-0000-0000-0000-000000000002', '3a100000-0000-0000-0000-000000000002', 'Spento', 0);
INSERT INTO public.practice_blocks (step_id, block_type, content, sort_order) VALUES
  ('3a200000-0000-0000-0000-000000000001', 'audio', 'pratiche/respiro.m4a', 0),
  ('3a200000-0000-0000-0000-000000000002', 'text', 'Spento', 0);

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

-- ── Chi può chiamare la funzione ─────────────────────────────────────────────

SELECT ok(NOT has_function_privilege('anon', 'public.has_active_membership()', 'EXECUTE'), 'anon non la chiama');
SELECT ok(has_function_privilege('authenticated', 'public.has_active_membership()', 'EXECUTE'), 'con il login sì');

-- ── Non sociə: vede la pratica, non i contenuti ──────────────────────────────

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('3a000000-0000-0000-0000-000000000001');
SELECT is(public.has_active_membership(), false, 'chi non è sociə non è in regola');
SELECT is((SELECT count(*)::int FROM public.practices WHERE id = '3a100000-0000-0000-0000-000000000001'), 1,
  'chi non è sociə vede la pratica');
SELECT is((SELECT count(*)::int FROM public.practice_steps WHERE practice_id = '3a100000-0000-0000-0000-000000000001'), 0,
  'ma non i suoi passaggi');
SELECT is((SELECT count(*)::int FROM public.practice_blocks WHERE step_id = '3a200000-0000-0000-0000-000000000001'), 0,
  'né i blocchi');

-- ── Sociə con la quota pagata ────────────────────────────────────────────────

SELECT pg_temp.as_user('3a000000-0000-0000-0000-000000000002');
SELECT is(public.has_active_membership(), true, 'sociə con la quota pagata: in regola');
SELECT is((SELECT count(*)::int FROM public.practice_steps WHERE practice_id = '3a100000-0000-0000-0000-000000000001'), 1,
  'legge i passaggi');
SELECT is((SELECT content FROM public.practice_blocks WHERE step_id = '3a200000-0000-0000-0000-000000000001'),
  'pratiche/respiro.m4a', 'e i blocchi');
SELECT is((SELECT count(*)::int FROM public.practice_steps WHERE practice_id = '3a100000-0000-0000-0000-000000000002'), 0,
  'ma non quelli di una pratica spenta');
SELECT is((SELECT count(*)::int FROM public.practice_blocks WHERE step_id = '3a200000-0000-0000-0000-000000000002'), 0,
  'né i suoi blocchi');

-- ── Sociə con la quota ancora da pagare, prima della scadenza ────────────────

SELECT pg_temp.as_user('3a000000-0000-0000-0000-000000000003');
SELECT is(public.has_active_membership(), true, 'quota da pagare ma non scaduta: in regola');
SELECT is((SELECT count(*)::int FROM public.practice_blocks WHERE step_id = '3a200000-0000-0000-0000-000000000001'), 1,
  'legge i blocchi');

-- ── Quota scaduta ────────────────────────────────────────────────────────────

RESET ROLE;
UPDATE public.association_years SET fee_due_date = internal.rome_today() - 1
 WHERE year = extract(year FROM internal.rome_today())::int;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('3a000000-0000-0000-0000-000000000004');
SELECT is(public.has_active_membership(), false, 'quota scaduta: non in regola');
SELECT is((SELECT count(*)::int FROM public.practice_steps WHERE practice_id = '3a100000-0000-0000-0000-000000000001'), 0,
  'non legge più i passaggi');
SELECT pg_temp.as_user('3a000000-0000-0000-0000-000000000002');
SELECT is(public.has_active_membership(), true, 'chi ha pagato resta in regola');

-- ── Staff: tutto, anche le pratiche spente ───────────────────────────────────

SELECT pg_temp.as_user('3a000000-0000-0000-0000-000000000005');
SELECT is(public.has_active_membership(), false, 'lo staff non è sociə');
SELECT is((SELECT count(*)::int FROM public.practice_blocks
            WHERE step_id IN ('3a200000-0000-0000-0000-000000000001', '3a200000-0000-0000-0000-000000000002')), 2,
  'ma legge tutti i blocchi, anche delle pratiche spente');

-- ── Senza login ──────────────────────────────────────────────────────────────

RESET ROLE;
SELECT is((SELECT roles::text FROM pg_policies
            WHERE tablename = 'practice_blocks' AND policyname = 'practice_blocks_select_active'),
  '{authenticated}', 'senza login i blocchi non si leggono');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
