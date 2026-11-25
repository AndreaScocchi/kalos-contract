-- «Rendi amministratore» dal gestionale (migrazione 20261125120000, richiesta dell'utente del
-- 25/11/2026): solo un admin rende admin un altro account, da qualsiasi ruolo; non declassa mai,
-- non tocca gli account eliminati e non riscrive chi è già admin.

BEGIN;
SELECT plan(13);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('0f250000-0000-0000-0000-000000000001', 'ra-admin@test.kalos', '{"full_name":"Admin Ruoli"}', 'authenticated', 'authenticated'),
  ('0f250000-0000-0000-0000-000000000002', 'ra-operatrice@test.kalos', '{"full_name":"Operatrice Ruoli"}', 'authenticated', 'authenticated'),
  ('0f250000-0000-0000-0000-000000000003', 'ra-cliente@test.kalos', '{"full_name":"Cliente Ruoli"}', 'authenticated', 'authenticated'),
  ('0f250000-0000-0000-0000-000000000004', 'ra-tesoriere@test.kalos', '{"full_name":"Tesoriere Ruoli"}', 'authenticated', 'authenticated'),
  ('0f250000-0000-0000-0000-000000000005', 'ra-eliminato@test.kalos', '{"full_name":"Account Eliminato"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'admin' WHERE id = '0f250000-0000-0000-0000-000000000001';
UPDATE public.profiles SET role = 'operator' WHERE id = '0f250000-0000-0000-0000-000000000002';
UPDATE public.profiles SET role = 'finance' WHERE id = '0f250000-0000-0000-0000-000000000004';
UPDATE public.profiles SET deleted_at = now() WHERE id = '0f250000-0000-0000-0000-000000000005';

SELECT ok(NOT has_function_privilege('anon', 'public.promote_profile_to_admin(uuid)', 'EXECUTE'),
  'anon non esegue promote_profile_to_admin');

-- ── Chi non è admin non promuove ─────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"0f250000-0000-0000-0000-000000000003","role":"authenticated"}';
SELECT is(public.promote_profile_to_admin('0f250000-0000-0000-0000-000000000003')->>'reason', 'FORBIDDEN',
  'un cliente non si rende admin da solə');

SET LOCAL request.jwt.claims = '{"sub":"0f250000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(public.promote_profile_to_admin('0f250000-0000-0000-0000-000000000003')->>'reason', 'FORBIDDEN',
  'un''operatrice non rende admin nessunə');
SELECT is(public.promote_profile_to_admin('0f250000-0000-0000-0000-000000000002')->>'reason', 'FORBIDDEN',
  'un''operatrice non si rende admin da sola');

RESET ROLE;
SELECT is((SELECT role::text FROM public.profiles WHERE id = '0f250000-0000-0000-0000-000000000003'), 'user',
  'dopo i rifiuti il cliente resta user');

-- ── L'admin ──────────────────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"0f250000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(public.promote_profile_to_admin('0f250000-0000-0000-0000-000000000003'),
  '{"ok": true, "role": "admin", "previous_role": "user"}'::jsonb,
  'l''admin rende admin un cliente');
SELECT is(public.promote_profile_to_admin('0f250000-0000-0000-0000-000000000002')->>'previous_role', 'operator',
  'l''admin rende admin un''operatrice');
SELECT is(public.promote_profile_to_admin('0f250000-0000-0000-0000-000000000004')->>'previous_role', 'finance',
  'l''admin rende admin il Tesoriere');
SELECT is(public.promote_profile_to_admin('0f250000-0000-0000-0000-000000000001')->>'reason', 'ALREADY_ADMIN',
  'chi è già admin resta com''è');
SELECT is(public.promote_profile_to_admin('0f250000-0000-0000-0000-000000000005')->>'reason', 'PROFILE_NOT_FOUND',
  'un account eliminato non si promuove');
SELECT is(public.promote_profile_to_admin('00000000-0000-0000-0000-000000000000')->>'reason', 'PROFILE_NOT_FOUND',
  'un account inesistente risponde PROFILE_NOT_FOUND');

RESET ROLE;
SELECT is(
  (SELECT string_agg(role::text, ',' ORDER BY id) FROM public.profiles
   WHERE id IN ('0f250000-0000-0000-0000-000000000002', '0f250000-0000-0000-0000-000000000003',
                '0f250000-0000-0000-0000-000000000004')),
  'admin,admin,admin',
  'i tre account sono admin nel database');
SELECT is((SELECT role::text FROM public.profiles WHERE id = '0f250000-0000-0000-0000-000000000005'), 'user',
  'l''account eliminato resta user');

SELECT * FROM finish();
ROLLBACK;
