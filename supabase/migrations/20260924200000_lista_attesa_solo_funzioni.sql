-- Migration 20260924200000: la lista d'attesa si scrive solo con le funzioni (sessione 8)
--
-- Nella sessione 3 la lista d'attesa è passata alle funzioni: `join_waitlist` e `leave_waitlist` per
-- chi è in fila, `staff_add_to_waitlist` e `staff_remove_from_waitlist` per lo staff, la promozione
-- automatica per il resto. Le policy della tabella sono diventate due: lettura delle proprie righe e
-- scrittura per lo staff.
--
-- Nello schema erano però rimaste due policy più vecchie, di quando la tabella aveva solo `user_id`:
-- `waitlist_insert_own` e `waitlist_delete_own_or_staff`. Le policy dello stesso comando si sommano,
-- quindi valevano ancora. Nessuna app le usa (la webapp non tocca la lista d'attesa, il gestionale
-- passa dalle funzioni): si tolgono, e da qui in poi stato, posizione e offerte li decidono solo le
-- funzioni.
--
-- Il test `access_model.test.sql` elenca ora anche le scritture dirette concesse ai clienti, così una
-- policy di questo tipo non può restare dimenticata.

DROP POLICY IF EXISTS "waitlist_insert_own" ON "public"."waitlist";
DROP POLICY IF EXISTS "waitlist_delete_own_or_staff" ON "public"."waitlist";
