-- ============================================================================
-- SEED DI TEST · Pratiche da casa (practices / practice_steps / practice_blocks)
-- ----------------------------------------------------------------------------
-- Dati di esempio per testare la funzionalità "Pratica a casa" dall'app KMP.
-- Idempotente: UUID fissi + ON CONFLICT DO NOTHING → ri-eseguibile in sicurezza.
-- Richiede service_role (o sessione staff): vedi RLS practices_*_all.
--
-- Per RIMUOVERE i dati di test:
--   delete from practices where id in (
--     '11111111-0000-4000-a000-000000000001',
--     '11111111-0000-4000-a000-000000000002',
--     '11111111-0000-4000-a000-000000000003',
--     '11111111-0000-4000-a000-000000000004',
--     '11111111-0000-4000-a000-000000000005'
--   );  -- step, blocchi, activities e user_state cadono in CASCADE; journal_entries.practice_id -> NULL
-- ============================================================================

begin;

-- ─── 1. RESPIRO · "Tre minuti di respiro" (principiante, in evidenza) ─────────
insert into public.practices
  (id, title, subtitle, description, duration_minutes, category, level, goals,
   cover_image_url, is_active, is_featured, sort_order)
values
  ('11111111-0000-4000-a000-000000000001',
   'Tre minuti di respiro',
   'Un reset veloce, ovunque tu sia',
   'Una pratica breve per riportare l''attenzione al respiro e sciogliere la fretta. Perfetta tra un impegno e l''altro.',
   3, 'respiro', 'principiante',
   '["calmarsi","rallentare"]'::jsonb,
   'https://images.unsplash.com/photo-1506126613408-eca07ce68773?w=1200&q=80',
   true, true, 1)
on conflict (id) do nothing;

insert into public.practice_steps (id, practice_id, title, sort_order) values
  ('21111111-0000-4000-a000-000000000001', '11111111-0000-4000-a000-000000000001', 'Trova la posizione', 0),
  ('21111111-0000-4000-a000-000000000002', '11111111-0000-4000-a000-000000000001', 'Respira', 1),
  ('21111111-0000-4000-a000-000000000003', '11111111-0000-4000-a000-000000000001', 'Chiudi', 2)
on conflict (id) do nothing;

insert into public.practice_blocks (id, step_id, block_type, content, caption, sort_order) values
  ('31111111-0000-4000-a000-000000000001', '21111111-0000-4000-a000-000000000001', 'text',
   'Siediti comodo, con la schiena dritta ma non rigida. Appoggia le mani sulle gambe e lascia cadere le spalle.', null, 0),
  ('41111111-0000-4000-a000-000000000001', '21111111-0000-4000-a000-000000000001', 'image',
   'https://images.unsplash.com/photo-1545205597-3d9d02c29597?w=1200&q=80', 'La postura seduta: schiena lunga, spalle morbide.', 1),
  ('31111111-0000-4000-a000-000000000002', '21111111-0000-4000-a000-000000000002', 'text',
   'Inspira lentamente dal naso contando fino a quattro. Trattieni un istante. Espira dalla bocca contando fino a sei. Ripeti per dieci respiri.', null, 0),
  ('31111111-0000-4000-a000-000000000003', '21111111-0000-4000-a000-000000000003', 'text',
   'Riporta il respiro al suo ritmo naturale. Nota come ti senti adesso, senza giudicare. Quando sei pronto, riapri gli occhi.', null, 0)
on conflict (id) do nothing;

-- ─── 2. MEDITAZIONE · "Meditazione del mattino" (principiante) ────────────────
insert into public.practices
  (id, title, subtitle, description, duration_minutes, category, level, goals,
   cover_image_url, is_active, is_featured, sort_order)
values
  ('11111111-0000-4000-a000-000000000002',
   'Meditazione del mattino',
   'Inizia la giornata con presenza',
   'Dieci minuti per risvegliare corpo e mente con dolcezza, prima che la giornata inizi a correre.',
   10, 'meditazione', 'principiante',
   '["energia","riconnettersi"]'::jsonb,
   'https://images.unsplash.com/photo-1518241353330-0f7941c2d9b5?w=1200&q=80',
   true, true, 2)
on conflict (id) do nothing;

insert into public.practice_steps (id, practice_id, title, sort_order) values
  ('21111111-0000-4000-a000-000000000011', '11111111-0000-4000-a000-000000000002', 'Risveglio', 0),
  ('21111111-0000-4000-a000-000000000012', '11111111-0000-4000-a000-000000000002', 'Ascolto del corpo', 1),
  ('21111111-0000-4000-a000-000000000013', '11111111-0000-4000-a000-000000000002', 'Intenzione', 2),
  ('21111111-0000-4000-a000-000000000014', '11111111-0000-4000-a000-000000000002', 'Apertura', 3)
on conflict (id) do nothing;

insert into public.practice_blocks (id, step_id, block_type, content, caption, sort_order) values
  ('31111111-0000-4000-a000-000000000011', '21111111-0000-4000-a000-000000000011', 'text',
   'Appena sveglio, prima di alzarti, resta disteso. Senti il peso del corpo sul materasso e fai tre respiri profondi.', null, 0),
  ('41111111-0000-4000-a000-000000000011', '21111111-0000-4000-a000-000000000011', 'audio',
   'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3', 'Audio guida al risveglio (campione di test).', 1),
  ('31111111-0000-4000-a000-000000000012', '21111111-0000-4000-a000-000000000012', 'text',
   'Porta l''attenzione ai piedi, poi sali lentamente: gambe, bacino, pancia, petto, braccia, viso. Saluta ogni parte del corpo.', null, 0),
  ('31111111-0000-4000-a000-000000000013', '21111111-0000-4000-a000-000000000013', 'text',
   'Scegli una parola o un''intenzione per oggi: calma, gentilezza, coraggio. Ripetila a te stesso tre volte.', null, 0),
  ('31111111-0000-4000-a000-000000000014', '21111111-0000-4000-a000-000000000014', 'text',
   'Muovi piano le dita di mani e piedi. Quando sei pronto, apri gli occhi e siediti. La giornata può cominciare.', null, 0)
on conflict (id) do nothing;

-- ─── 3. CORPO · "Sciogliere le spalle" (principiante) ─────────────────────────
insert into public.practices
  (id, title, subtitle, description, duration_minutes, category, level, goals,
   cover_image_url, is_active, is_featured, sort_order)
values
  ('11111111-0000-4000-a000-000000000003',
   'Sciogliere le spalle',
   'Libera le tensioni della giornata',
   'Una sequenza dolce per allentare collo e spalle, ideale dopo molte ore davanti allo schermo.',
   8, 'corpo', 'principiante',
   '["sciogliere_tensioni"]'::jsonb,
   'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=1200&q=80',
   true, false, 3)
on conflict (id) do nothing;

insert into public.practice_steps (id, practice_id, title, sort_order) values
  ('21111111-0000-4000-a000-000000000021', '11111111-0000-4000-a000-000000000003', 'Preparazione', 0),
  ('21111111-0000-4000-a000-000000000022', '11111111-0000-4000-a000-000000000003', 'Rotazioni', 1),
  ('21111111-0000-4000-a000-000000000023', '11111111-0000-4000-a000-000000000003', 'Allungamento del collo', 2)
on conflict (id) do nothing;

insert into public.practice_blocks (id, step_id, block_type, content, caption, sort_order) values
  ('31111111-0000-4000-a000-000000000021', '21111111-0000-4000-a000-000000000021', 'text',
   'In piedi o seduto, allunga la colonna verso l''alto. Lascia le braccia morbide lungo i fianchi e respira profondamente.', null, 0),
  ('31111111-0000-4000-a000-000000000022', '21111111-0000-4000-a000-000000000022', 'text',
   'Solleva le spalle verso le orecchie, poi falle ruotare lentamente all''indietro. Ripeti cinque volte, poi cambia direzione.', null, 0),
  ('41111111-0000-4000-a000-000000000022', '21111111-0000-4000-a000-000000000022', 'video',
   'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4', 'Dimostrazione del movimento (campione di test).', 1),
  ('31111111-0000-4000-a000-000000000023', '21111111-0000-4000-a000-000000000023', 'text',
   'Inclina dolcemente la testa verso destra, senti l''allungamento sul lato del collo. Resta tre respiri, poi cambia lato.', null, 0)
on conflict (id) do nothing;

-- ─── 4. SCRITTURA · "Diario della sera" (intermedio) ──────────────────────────
insert into public.practices
  (id, title, subtitle, description, duration_minutes, category, level, goals,
   cover_image_url, is_active, is_featured, sort_order)
values
  ('11111111-0000-4000-a000-000000000004',
   'Diario della sera',
   'Chiudi la giornata con consapevolezza',
   'Un momento di scrittura per rileggere la giornata, lasciare andare ciò che pesa e riconoscere ciò che è andato bene.',
   15, 'scrittura', 'intermedio',
   '["rallentare","riconnettersi"]'::jsonb,
   'https://images.unsplash.com/photo-1517842645767-c639042777db?w=1200&q=80',
   true, false, 4)
on conflict (id) do nothing;

insert into public.practice_steps (id, practice_id, title, sort_order) values
  ('21111111-0000-4000-a000-000000000031', '11111111-0000-4000-a000-000000000004', 'Crea lo spazio', 0),
  ('21111111-0000-4000-a000-000000000032', '11111111-0000-4000-a000-000000000004', 'Tre domande', 1),
  ('21111111-0000-4000-a000-000000000033', '11111111-0000-4000-a000-000000000004', 'Gratitudine', 2)
on conflict (id) do nothing;

insert into public.practice_blocks (id, step_id, block_type, content, caption, sort_order) values
  ('31111111-0000-4000-a000-000000000031', '21111111-0000-4000-a000-000000000031', 'text',
   'Prendi un quaderno e una penna. Trova un angolo tranquillo, abbassa le luci e fai un respiro lungo prima di iniziare.', null, 0),
  ('41111111-0000-4000-a000-000000000031', '21111111-0000-4000-a000-000000000031', 'image',
   'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=1200&q=80', 'Un quaderno, una penna, un momento per te.', 1),
  ('31111111-0000-4000-a000-000000000032', '21111111-0000-4000-a000-000000000032', 'text',
   'Scrivi rispondendo a queste domande, senza fretta: Cosa mi ha dato energia oggi? Cosa mi ha pesato? Cosa voglio lasciare andare prima di dormire?', null, 0),
  ('31111111-0000-4000-a000-000000000033', '21111111-0000-4000-a000-000000000033', 'text',
   'Concludi annotando tre cose per cui sei grato oggi, anche piccole. Rileggile, chiudi il quaderno e concediti riposo.', null, 0)
on conflict (id) do nothing;

-- ─── 5. RILASSAMENTO · "Rilassamento profondo" (intermedio) ───────────────────
insert into public.practices
  (id, title, subtitle, description, duration_minutes, category, level, goals,
   cover_image_url, is_active, is_featured, sort_order)
values
  ('11111111-0000-4000-a000-000000000005',
   'Rilassamento profondo',
   'Lascia andare, un muscolo alla volta',
   'Un percorso di rilassamento guidato del corpo intero, per sciogliere la tensione accumulata e ritrovare la calma prima di dormire.',
   20, 'rilassamento', 'intermedio',
   '["calmarsi","sciogliere_tensioni"]'::jsonb,
   'https://images.unsplash.com/photo-1499209974431-9dddcece7f88?w=1200&q=80',
   true, false, 5)
on conflict (id) do nothing;

insert into public.practice_steps (id, practice_id, title, sort_order) values
  ('21111111-0000-4000-a000-000000000041', '11111111-0000-4000-a000-000000000005', 'Sdraiati', 0),
  ('21111111-0000-4000-a000-000000000042', '11111111-0000-4000-a000-000000000005', 'Parte bassa', 1),
  ('21111111-0000-4000-a000-000000000043', '11111111-0000-4000-a000-000000000005', 'Parte alta', 2),
  ('21111111-0000-4000-a000-000000000044', '11111111-0000-4000-a000-000000000005', 'Quiete', 3)
on conflict (id) do nothing;

insert into public.practice_blocks (id, step_id, block_type, content, caption, sort_order) values
  ('31111111-0000-4000-a000-000000000041', '21111111-0000-4000-a000-000000000041', 'text',
   'Distenditi su una superficie comoda. Lascia che le braccia riposino lungo i fianchi, i palmi verso l''alto. Chiudi gli occhi.', null, 0),
  ('41111111-0000-4000-a000-000000000041', '21111111-0000-4000-a000-000000000041', 'video',
   'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4', 'Visualizzazione guidata (campione di test).', 1),
  ('31111111-0000-4000-a000-000000000042', '21111111-0000-4000-a000-000000000042', 'text',
   'Porta l''attenzione ai piedi: contraili per tre secondi, poi rilascia. Sali ai polpacci, alle cosce, ai glutei. Tendi e rilascia ogni gruppo muscolare.', null, 0),
  ('31111111-0000-4000-a000-000000000043', '21111111-0000-4000-a000-000000000043', 'text',
   'Continua con pancia, mani, braccia, spalle e viso. Tendi delicatamente, poi lascia andare ogni tensione con l''espirazione.', null, 0),
  ('31111111-0000-4000-a000-000000000044', '21111111-0000-4000-a000-000000000044', 'text',
   'Ora tutto il corpo è morbido e pesante. Resta qui ad ascoltare il respiro per qualche minuto. Non c''è nulla da fare, solo riposare.', null, 0),
  ('41111111-0000-4000-a000-000000000044', '21111111-0000-4000-a000-000000000044', 'audio',
   'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3', 'Sottofondo per la quiete (campione di test).', 1)
on conflict (id) do nothing;

commit;

-- Verifica:
--   select title, category, level, duration_minutes, is_featured
--   from practices where id like '11111111-0000-4000-a000-%' order by sort_order;
