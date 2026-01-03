# Verifica Vista `public_site_activities`

## 1. Definizione SQL Completa della Vista (AGGIORNATA)

```sql
CREATE VIEW public.public_site_activities AS
SELECT 
  a.id,
  a.name,
  a.slug,
  a.description,
  a.discipline,
  a.color,
  a.duration_minutes,
  a.image_url,
  a.is_active,
  -- Campi landing page
  a.landing_title,
  a.landing_subtitle,
  a.active_months,
  a.target_audience,
  a.program_objectives,
  a.why_participate,
  a.journey_structure,
  a.created_at,
  a.updated_at
FROM public.activities a
WHERE 
  a.deleted_at IS NULL
ORDER BY a.name ASC;
```

**Permessi:**
```sql
GRANT SELECT ON public.public_site_activities TO anon;
GRANT SELECT ON public.public_site_activities TO authenticated;
```

## 2. Confronto Campi Richiesti vs Campi Disponibili

### ✅ Campi Presenti nella Vista (dalla tabella `activities`)

| Campo | Tipo | Nullable | Note |
|-------|------|----------|------|
| `id` | uuid | NO | ✅ Presente |
| `name` | text | NO | ✅ Presente |
| `description` | text | YES | ✅ Presente |
| `slug` | text | YES | ✅ Presente (aggiunto in migration 0010) |
| `duration_minutes` | integer | YES | ✅ Presente (aggiunto in migration 0009) |
| `created_at` | timestamptz | YES | ✅ Presente |
| `discipline` | text | NO | ✅ Presente |
| `color` | text | YES | ✅ Presente |
| `image_url` | text | YES | ✅ Presente (migration 0012) |
| `is_active` | boolean | YES | ✅ Presente (migration 0012, default: true) |
| `updated_at` | timestamptz | YES | ✅ Presente (migration 0012, con trigger) |
| `landing_title` | text | YES | ✅ Presente (migration 0012) |
| `landing_subtitle` | text | YES | ✅ Presente (migration 0012) |
| `active_months` | jsonb | YES | ✅ Presente (migration 0012) |
| `target_audience` | jsonb | YES | ✅ Presente (migration 0012) |
| `program_objectives` | jsonb | YES | ✅ Presente (migration 0012) |
| `why_participate` | jsonb | YES | ✅ Presente (migration 0012) |
| `journey_structure` | jsonb | YES | ✅ Presente (migration 0012) |

### ⚠️ Campo Legacy Non Presente

| Campo | Note |
|-------|------|
| `duration` | ⚠️ **NON esiste** (legacy - non è stato mai aggiunto, c'è solo `duration_minutes`) |

**Nota:** Il campo `duration` legacy non è stato aggiunto perché esiste già `duration_minutes`. Se necessario per compatibilità, può essere aggiunto in una migration futura.

## 3. Verifica Tipi di Dato

### Campi Array/JSONB

I campi array nella migration 0012 sono stati definiti come **`jsonb`** invece di `text[]`. Questo è corretto perché:

1. **`jsonb` è più flessibile**: Permette array di stringhe, array di oggetti, e strutture miste
2. **Coerenza con Supabase**: Supabase gestisce automaticamente il parsing di `jsonb` come oggetti/array JavaScript
3. **Documentazione originale**: Gli esempi nella documentazione originale usano formato JSON

**Campi JSONB definiti:**
- `active_months`: `jsonb` (array di stringhe: `["1", "2", "3"]`)
- `target_audience`: `jsonb` (array di oggetti: `[{"title": "...", "description": "..."}]`)
- `program_objectives`: `jsonb` (array di stringhe: `["...", "..."]`)
- `why_participate`: `jsonb` (array di stringhe: `["...", "..."]`)
- `journey_structure`: `jsonb` (array di stringhe: `["...", "..."]`)

**Nota:** Se fosse necessario convertire a `text[]`, si può fare con una migration successiva, ma `jsonb` è la scelta più appropriata per la flessibilità e la compatibilità con Supabase.

## 4. Query di Test Consigliata

```sql
-- Query per verificare tutti i campi (inclusi quelli landing page)
SELECT 
  id,
  name,
  slug,
  description,
  discipline,
  color,
  duration_minutes,
  landing_title,
  landing_subtitle,
  active_months,
  target_audience,
  program_objectives,
  why_participate,
  journey_structure,
  created_at
FROM public_site_activities
WHERE slug = 'meditazionemindfulness'
LIMIT 1;
```

**Query per verificare tutti i campi disponibili:**
```sql
-- Verifica struttura completa della vista
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'public_site_activities'
ORDER BY ordinal_position;
```

## 5. Permessi Verificati

✅ **GRANT SELECT TO anon**: La vista è accessibile con chiave anonima (per sito pubblico)
✅ **GRANT SELECT TO authenticated**: La vista è accessibile per utenti autenticati

## 6. Modifiche Implementate ✅

### ✅ Campi Aggiunti alla Tabella `activities` (Migration 0012)

1. **`image_url` (text, nullable)**: URL dell'immagine dell'attività
2. **`is_active` (boolean, default: true)**: Flag per mostrare/nascondere l'attività pubblicamente
3. **`updated_at` (timestamptz, default: now())**: Timestamp di ultimo aggiornamento con trigger automatico

### ✅ Trigger Aggiunto

- **`update_activities_updated_at`**: Trigger che aggiorna automaticamente `updated_at` ad ogni UPDATE sulla tabella `activities`

### ✅ Vista Aggiornata

La vista `public_site_activities` è stata aggiornata per includere tutti i campi:
- Campi base: `id`, `name`, `slug`, `description`, `discipline`, `color`, `duration_minutes`
- Campi aggiunti: `image_url`, `is_active`, `updated_at`
- Campi landing page: `landing_title`, `landing_subtitle`, `active_months`, `target_audience`, `program_objectives`, `why_participate`, `journey_structure`
- Timestamps: `created_at`, `updated_at`

### ✅ Tipi TypeScript Aggiornati

I tipi TypeScript in `src/types/database.ts` sono stati aggiornati per includere tutti i nuovi campi.

### Problema 2: Tipi Array (`text[]` vs `jsonb`)

Se il frontend si aspetta `text[]` invece di `jsonb` per `active_months`, `program_objectives`, `why_participate`, `journey_structure`:

**Nota:** `jsonb` è comunque compatibile - Supabase converte automaticamente `jsonb` array in array JavaScript. Se serve esplicitamente `text[]`, serve una migration per modificare i tipi.

### Problema 3: Campi `undefined` nel Frontend

Se i campi risultano `undefined` nel frontend, possibili cause:

1. **Migration non eseguita**: La migration 0012 potrebbe non essere stata eseguita sul database
2. **Tipi non rigenerati**: I tipi TypeScript potrebbero non essere stati rigenerati dopo la migration
3. **Cache del client**: Il client Supabase potrebbe avere cache vecchia

## 7. Checklist Verifica Completa

- [x] Vista `public_site_activities` definita correttamente
- [x] Tutti i campi esistenti nella tabella sono inclusi nella vista
- [x] Campi base aggiunti (`image_url`, `is_active`, `updated_at`) ✅
- [x] Campi landing page inclusi ✅
- [x] Trigger `updated_at` creato ✅
- [x] Permessi GRANT configurati correttamente ✅
- [x] Tipi TypeScript aggiornati ✅
- [ ] **Migration 0012 eseguita sul database** (da verificare)
- [ ] **Query di test eseguita con successo** (da verificare sul database reale)
- [ ] **Verifica nel frontend** che i campi siano accessibili e non `undefined`

## 8. Prossimi Passi Consigliati

1. ✅ **Migration 0012 creata** - Pronta per essere eseguita
2. ✅ **Tipi TypeScript aggiornati** - I tipi sono stati aggiornati manualmente
3. **Eseguire la migration 0012** sul database di sviluppo/staging
4. **Eseguire la query di test** per verificare che i campi siano accessibili
5. **Verificare nel frontend**: Testare che tutti i campi (inclusi `image_url`, `is_active`, `updated_at` e i campi landing page) siano accessibili e non `undefined`
6. **Testare il trigger**: Verificare che `updated_at` venga aggiornato automaticamente su UPDATE

## 9. Query di Verifica Post-Migration

Dopo aver eseguito la migration 0012, eseguire queste query per verificare:

```sql
-- 1. Verifica che i campi esistano nella tabella
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'activities'
  AND column_name IN ('image_url', 'is_active', 'updated_at', 'landing_title', 'landing_subtitle', 'active_months', 'target_audience', 'program_objectives', 'why_participate', 'journey_structure')
ORDER BY column_name;

-- 2. Verifica struttura completa della vista
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'public_site_activities'
ORDER BY ordinal_position;

-- 3. Verifica che il trigger esista
SELECT trigger_name, event_manipulation, event_object_table, action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'activities'
  AND trigger_name = 'update_activities_updated_at';

-- 4. Test query completa
SELECT 
  id,
  name,
  slug,
  description,
  discipline,
  color,
  duration_minutes,
  image_url,
  is_active,
  landing_title,
  landing_subtitle,
  active_months,
  target_audience,
  program_objectives,
  why_participate,
  journey_structure,
  created_at,
  updated_at
FROM public_site_activities
LIMIT 1;

-- 5. Test trigger updated_at (opzionale - dopo un UPDATE)
-- Eseguire un UPDATE e verificare che updated_at cambia
UPDATE public.activities SET name = name WHERE id = (SELECT id FROM public.activities LIMIT 1);
-- Poi verificare che updated_at sia stato aggiornato
```

