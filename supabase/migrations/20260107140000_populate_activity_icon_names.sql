-- Migration: Populate icon_name field for existing activities
--
-- Obiettivo: Popolare il campo icon_name per le attività esistenti basandosi
-- sul mapping degli slug alle icone utilizzato nell'app.
--
-- Il mapping è basato sugli slug delle attività (generati da discipline):
-- - yogavinyasa -> Sun1
-- - yogagravidanza -> Star1
-- - yogapostparto -> HeartAdd
-- - mamamoves -> Wind
-- - arteterapia -> Brush
-- - scritturaintrospettiva -> Magicpen
-- - bussolainteriore -> Location
-- - meditazione -> Moon
-- - meditazionemindfulness -> Moon
-- - radicifemminili -> Woman
-- - semimaternita -> Woman
-- - semidimaternita -> Woman
-- - kalosmomcafe -> Coffee
-- - kalosseniorcafe -> Coffee
-- - laboratori -> Brush
--
-- Per attività che non corrispondono a nessuno slug nel mapping, icon_name rimane NULL
-- e l'app utilizzerà un'icona di default.

-- ============================================================================
-- 1. Popola icon_name basandosi sullo slug delle attività
-- ============================================================================

UPDATE public.activities
SET icon_name = CASE
  -- Mapping esatto degli slug alle icone
  WHEN slug = 'yogavinyasa' THEN 'Sun1'
  WHEN slug = 'yogagravidanza' THEN 'Star1'
  WHEN slug = 'yogapostparto' THEN 'HeartAdd'
  WHEN slug = 'mamamoves' THEN 'Wind'
  WHEN slug = 'arteterapia' THEN 'Brush'
  WHEN slug = 'scritturaintrospettiva' THEN 'Magicpen'
  WHEN slug = 'bussolainteriore' THEN 'Location'
  WHEN slug = 'meditazione' THEN 'Moon'
  WHEN slug = 'meditazionemindfulness' THEN 'Moon'
  WHEN slug = 'radicifemminili' THEN 'Woman'
  WHEN slug = 'semimaternita' THEN 'Woman'
  WHEN slug = 'semidimaternita' THEN 'Woman'
  WHEN slug = 'kalosmomcafe' THEN 'Coffee'
  WHEN slug = 'kalosseniorcafe' THEN 'Coffee'
  WHEN slug = 'laboratori' THEN 'Brush'
  -- Se lo slug non corrisponde a nessun mapping, lascia NULL (icona default)
  ELSE NULL
END
WHERE 
  deleted_at IS NULL
  -- Aggiorna solo se icon_name è NULL o vuoto (per non sovrascrivere valori già impostati manualmente)
  AND (icon_name IS NULL OR icon_name = '');

-- ============================================================================
-- 2. Commento esplicativo
-- ============================================================================

COMMENT ON COLUMN public.activities.icon_name IS 
  'Nome esatto dell''icona della libreria iconsax-react. Popolato automaticamente per le attività esistenti basandosi sul mapping slug->icona. Può essere modificato manualmente dal gestionale. Se NULL, l''app utilizzerà un''icona di default.';

