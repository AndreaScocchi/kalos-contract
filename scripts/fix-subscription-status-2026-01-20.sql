-- Script di correzione abbonamenti con stato errato
-- Data: 2026-01-20
-- Abbonamenti da correggere: 10 (9 active->expired, 1 completed->expired)

-- ============================================================================
-- CORREZIONE: Imposta stato 'expired' per gli abbonamenti identificati
-- ============================================================================

UPDATE public.subscriptions
SET status = 'expired'
WHERE id IN (
  '56b7c8d0-f55d-41cd-9097-b1443e799c5c',  -- Laboratorio - Decora La Tua Candela (null client)
  '3cd2f949-07e1-404e-bf09-35d75d451582',  -- Martina Macor - Scrittura Introspettiva Illimitato
  '1437005b-16c1-4385-ba03-0b6cd67b4279',  -- Edda Papais - Kalos Senior Cafe
  'abc2da82-2609-4680-8c2d-b8b9290695bf',  -- Manuela Badin - Promo Open Day
  'b1174a2d-7aca-43ab-8992-346fa2c24201',  -- Sara Crystal Quispe Pascual - Yoga Gravidanza
  'bb9267f1-effd-4dc9-a3f4-804247bbf8f1',  -- Siria Braida - Laboratorio Emozioni
  'd4d017e5-949a-4a72-b71e-14751a365e97',  -- Giovanni Visentini - Laboratorio Emozioni
  'ec68e87a-d8e1-4ab6-8175-d00301de9636',  -- Giovanni Visentini - Laboratorio Emozioni (2)
  '1e608c91-4bda-4f90-a38e-449522d3278d',  -- Sara Consoli - Promo Open Day
  '90f4e874-7bef-473e-a19b-eb6393651f36'   -- Francesca Vischi - Promo Open Day (era completed)
);

-- ============================================================================
-- VERIFICA: Controlla che la correzione sia stata applicata
-- ============================================================================

SELECT
  id,
  status,
  expires_at
FROM public.subscriptions
WHERE id IN (
  '56b7c8d0-f55d-41cd-9097-b1443e799c5c',
  '3cd2f949-07e1-404e-bf09-35d75d451582',
  '1437005b-16c1-4385-ba03-0b6cd67b4279',
  'abc2da82-2609-4680-8c2d-b8b9290695bf',
  'b1174a2d-7aca-43ab-8992-346fa2c24201',
  'bb9267f1-effd-4dc9-a3f4-804247bbf8f1',
  'd4d017e5-949a-4a72-b71e-14751a365e97',
  'ec68e87a-d8e1-4ab6-8175-d00301de9636',
  '1e608c91-4bda-4f90-a38e-449522d3278d',
  '90f4e874-7bef-473e-a19b-eb6393651f36'
);
