-- Pratiche con citazioni e domande per il Diario (migrazione 20261112120000): lo staff scrive i
-- blocchi nuovi dal gestionale, chi usa l'app li legge solo da una pratica attiva e salva la
-- risposta come propria nota del Diario, collegata alla pratica.

BEGIN;
SELECT plan(8);

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('1e000000-0000-0000-0000-000000000001', 'pd-anna@test.kalos', '{"full_name":"Anna Diario"}', 'authenticated', 'authenticated'),
  ('1e000000-0000-0000-0000-000000000002', 'pd-op@test.kalos',   '{"full_name":"Olga Diario"}', 'authenticated', 'authenticated');
UPDATE public.profiles SET role = 'operator' WHERE id = '1e000000-0000-0000-0000-000000000002';

SELECT ok(
  enum_range(NULL::public.practice_block_type) @> ARRAY['quote', 'journal_prompt']::public.practice_block_type[],
  'i blocchi «citazione» e «domanda per il Diario» esistono');

-- Staff: una pratica attiva e una ancora spenta, con i blocchi nuovi
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"1e000000-0000-0000-0000-000000000002","role":"authenticated"}';

SELECT lives_ok($$
  INSERT INTO public.practices (id, title, category, is_active) VALUES
    ('6e000000-0000-0000-0000-000000000001', 'PD Attiva', 'scrittura', true),
    ('6e000000-0000-0000-0000-000000000002', 'PD Spenta', 'scrittura', false);
  INSERT INTO public.practice_steps (id, practice_id, title, sort_order) VALUES
    ('7e000000-0000-0000-0000-000000000001', '6e000000-0000-0000-0000-000000000001', 'Passo', 0),
    ('7e000000-0000-0000-0000-000000000002', '6e000000-0000-0000-0000-000000000002', 'Passo', 0);
  INSERT INTO public.practice_blocks (step_id, block_type, content, caption, sort_order) VALUES
    ('7e000000-0000-0000-0000-000000000001', 'quote', 'Un brano.', 'Autrice, Titolo, Editore, 2021', 0),
    ('7e000000-0000-0000-0000-000000000001', 'journal_prompt', 'Che cosa senti?', NULL, 1),
    ('7e000000-0000-0000-0000-000000000002', 'journal_prompt', 'Domanda nascosta', NULL, 0);
$$, 'lo staff salva citazioni e domande per il Diario');

-- Cliente: legge i blocchi della pratica attiva, non quelli della spenta
SET LOCAL request.jwt.claims = '{"sub":"1e000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(
  (SELECT count(*)::int FROM public.practice_blocks
    WHERE step_id = '7e000000-0000-0000-0000-000000000001' AND block_type IN ('quote', 'journal_prompt')),
  2, 'chi usa l''app legge citazione e domanda di una pratica attiva');
SELECT is(
  (SELECT count(*)::int FROM public.practice_blocks WHERE step_id = '7e000000-0000-0000-0000-000000000002'),
  0, 'e non vede i blocchi di una pratica spenta');

SELECT throws_ok($$
  INSERT INTO public.practice_blocks (step_id, block_type, content, sort_order)
  VALUES ('7e000000-0000-0000-0000-000000000001', 'journal_prompt', 'Intrusa', 9)
$$, '42501', NULL, 'chi usa l''app non scrive blocchi');

-- La risposta diventa una nota propria, collegata alla pratica
SELECT lives_ok($$
  INSERT INTO public.journal_entries (client_id, title, body, practice_id)
  VALUES (public.get_my_client_id(), NULL, E'Che cosa senti?\n\nCalma.', '6e000000-0000-0000-0000-000000000001')
$$, 'la risposta si salva nel proprio Diario');
SELECT is(
  (SELECT practice_id FROM public.journal_entries WHERE client_id = public.get_my_client_id()),
  '6e000000-0000-0000-0000-000000000001'::uuid, 'collegata alla pratica');

-- Staff: il Diario resta privato
SET LOCAL request.jwt.claims = '{"sub":"1e000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is(
  (SELECT count(*)::int FROM public.journal_entries WHERE practice_id = '6e000000-0000-0000-0000-000000000001'),
  0, 'lo staff non legge le note del Diario');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
