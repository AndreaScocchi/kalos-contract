# Codegen — sync ecosistema (TS + Kotlin) dallo schema

> Fonte di verità unica = **schema Postgres** (le migrazioni in `supabase/migrations/`).
> Da lì generiamo, versionati con lo **stesso tag** del contract:
> - i **tipi TypeScript** (`src/types/database.ts`) per website + gestionale + PWA;
> - i **modelli Kotlin** (`codegen/kotlin/models/`) `@Serializable` per la nuova app KMP.
>
> Un **drift-check** in CI fa fallire la build se i file generati e committati non combaciano con lo schema.
> Vedi `../docs` del monorepo: NEW_APP_PLAN.md §4 e CONTRACT_DISCIPLINE.md.

## Pipeline

```
supabase/migrations/**                      (sorgente di verità)
        │  supabase start && supabase db reset --local
        ▼
   Postgres locale (ermetico)
        ├─ supabase gen types typescript --local ──▶ src/types/database.ts   (TS)
        └─ node scripts/introspect-schema.mjs ─────▶ codegen/schema.json      (tipi PG precisi)
                                                            │
                                                            ▼
                              node scripts/gen-kotlin-models.mjs ──▶ codegen/kotlin/models/*.kt
```

- `codegen/schema.json` è la **rappresentazione intermedia** con tipi Postgres precisi
  (int4/int8/numeric/uuid/timestamptz/enum/array…). Garantisce modelli Kotlin tipizzati bene,
  non un generico "number" come darebbe il TS.
- I modelli Kotlin derivano da `schema.json`, quindi **non possono divergere** dallo schema.

## Comandi (richiedono Docker attivo per il DB locale)

```bash
npm run codegen          # rigenera TUTTO: tipi TS + schema.json + modelli Kotlin
npm run gen:types        # solo tipi TS
npm run gen:schema       # solo schema.json (richiede DB raggiungibile)
npm run gen:kotlin       # solo modelli Kotlin (offline, da schema.json)
npm run codegen:check    # rigenera e fallisce se c'è drift (come la CI)
```

Flusso tipico dopo una **nuova migrazione**:
1. scrivi la migrazione additiva in `supabase/migrations/`;
2. `npm run codegen` (rigenera TS + Kotlin);
3. committa i file generati **insieme** alla migrazione;
4. la CI (`.github/workflows/codegen.yml`) rigenera in ambiente pulito e verifica zero drift.

## Mappatura tipi (Postgres → Kotlin)

| Postgres | Kotlin |
|---|---|
| `uuid`, `text`, `varchar`, `bytea`, `inet`… | `String` |
| `int2`, `int4` | `Int` |
| `int8`, `oid` | `Long` |
| `float4` | `Float` |
| `float8`, `numeric` | `Double` |
| `bool` | `Boolean` |
| `json`, `jsonb` | `JsonElement` |
| `date`, `time`, `timestamp`, `timestamptz` | `String` (ISO-8601) |
| enum | `enum class` dedicata (`@SerialName` per ogni valore) |
| array `_X` | `List<X>` |

Colonne `NULL` → proprietà `Type? = null`. Colonne snake_case → proprietà camelCase con `@SerialName`.
Le date sono `String` finché la app KMP non adotterà `kotlinx-datetime` (cambio centralizzato in
`scripts/gen-kotlin-models.mjs`).

## Bootstrap (prima generazione)

Gli artefatti generati (`schema.json`, `codegen/kotlin/`, refresh di `src/types/database.ts`) vanno
**committati una prima volta** da un run ermetico locale (`npm run codegen` con Docker attivo), così la
CI ha un baseline contro cui fare drift-check.
