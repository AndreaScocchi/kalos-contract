# Codegen — tipi TS dallo schema

> Fonte di verità unica = **schema Postgres** (le migrazioni in `supabase/migrations/`).
> Da lì si generano i **tipi TypeScript** (`src/types/database.ts`) per sito, gestionale, app e
> webapp, versionati con lo stesso tag del contract.
>
> Fino al 23/11/2026 si generavano anche `codegen/schema.json` e i modelli Kotlin per l'app KMP.
> La KMP è archiviata: sono stati tolti, insieme a `scripts/introspect-schema.mjs` e
> `scripts/gen-kotlin-models.mjs` (restano nella storia di git).

## Pipeline

```
supabase/migrations/**                      (sorgente di verità)
        │  supabase start && supabase db reset --local
        ▼
   Postgres locale (ermetico)
        └─ supabase gen types typescript --local ──▶ src/types/database.ts
```

## Comandi (richiedono Docker attivo per il DB locale)

```bash
npm run codegen          # rigenera src/types/database.ts
npm run codegen:check    # rigenera e fallisce se database.ts era diverso (come la CI su una PR)
```

Flusso tipico dopo una **nuova migrazione**:
1. scrivi la migrazione additiva in `supabase/migrations/`;
2. con Docker: `npm run codegen` e committa `database.ts` **insieme** alla migrazione;
3. la CI (`.github/workflows/codegen.yml`) rigenera in ambiente pulito:
   - su una **PR** fallisce se `database.ts` è diverso;
   - su **`main`** lo rigenera e fa lei il commit (`chore(codegen): tipi TS rigenerati dalla CI…`,
     autore `github-actions[bot]`). Senza Docker in locale basta quindi mergiare e aspettare la CI.
4. **Il tag della versione si crea dopo che la CI è verde**, sull'ultimo commit di `main` (quello
   della CI, se c'è): un tag sul commit prima avrebbe i tipi vecchi. Prima del tag: `git pull`.

Se il rebase del commit della CI non riesce (nel frattempo un altro push su `main` ha cambiato
`database.ts`), il controllo fallisce e i tipi vanno rigenerati a mano.

## Versione della CLI Supabase (pinnata)

La CLI è **pinnata come devDependency** (`supabase` in `package.json`, versione esatta) e va invocata
sempre via `npx supabase` — sia in locale sia in CI (`npm ci` la installa).

Motivo: versioni diverse della CLI emettono lo **stesso schema con ordinamenti diversi** (es. l'ordine
degli overload delle RPC nell'union di `Database['public']['Functions']`). Se in locale generi con una
versione e la CI con un'altra (`setup-cli` con `version: latest`), il drift-check fallisce pur essendo
lo schema identico: *drift fantasma*.

⚠️ Non usare la CLI installata a livello globale (`/usr/local/bin/supabase`): può essere di un'altra
versione. Verifica con `npx supabase --version` che corrisponda al pin in `package.json`.

Per aggiornare la CLI:
```bash
npm i -D --save-exact supabase@<nuova-versione>
npm run codegen            # rigenera con la nuova versione
git add package.json package-lock.json src/types/database.ts
```
