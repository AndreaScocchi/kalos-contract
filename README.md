# @kalos/contract

Libreria contract condivisa per i progetti Kalos. Fornisce types TypeScript, factory per client Supabase, wrapper RPC, e query pubbliche.

## Installazione

Installa la libreria usando GitHub dependency (tag Git):

```json
{
  "dependencies": {
    "@kalos/contract": "github:ORG/kalos-contract#v0.1.0"
  }
}
```

Sostituisci `ORG` con il nome della tua organizzazione GitHub e `v0.1.0` con la versione/tag desiderato.

Poi esegui:
```bash
npm install
# o
yarn install
# o
pnpm install
```

## Utilizzo

### 1. Gestionale (React web - Vite)

Il gestionale usa `createSupabaseBrowserClient` con supporto per localStorage, detectSessionInUrl, e timeout fetch.

```typescript
import { createSupabaseBrowserClient } from '@kalos/contract';
import type { SupabaseClient } from '@supabase/supabase-js';

// Crea il client con configurazione per gestionale
const supabase: SupabaseClient = createSupabaseBrowserClient({
  url: import.meta.env.VITE_SUPABASE_URL,
  anonKey: import.meta.env.VITE_SUPABASE_ANON_KEY,
  detectSessionInUrl: true, // Per gestire reset password/login via URL
  enableTimeoutMs: 30000, // Timeout 30 secondi per fetch
  storageKey: 'sb-auth-token', // Opzionale, default è 'sb-auth-token'
});

// Esempio uso RPC
import { bookLesson, cancelBooking } from '@kalos/contract';

// Prenota una lezione
const result = await bookLesson(supabase, {
  lessonId: '123',
  subscriptionId: '456', // opzionale
});

// Cancella una prenotazione
const cancelResult = await cancelBooking(supabase, {
  bookingId: '789',
});
```

### 2. Sito (React web - Vite)

Il sito usa solo views pubbliche in sola lettura. Non richiede autenticazione.

```typescript
import { 
  createSupabaseBrowserClient, 
  getPublicSchedule, 
  getPublicPricing 
} from '@kalos/contract';

// Crea client anonimo (nessuna autenticazione richiesta)
const supabase = createSupabaseBrowserClient({
  url: import.meta.env.VITE_SUPABASE_URL,
  anonKey: import.meta.env.VITE_SUPABASE_ANON_KEY,
  // Non serve detectSessionInUrl per un sito pubblico
  detectSessionInUrl: false,
});

// Recupera schedule pubblico
const schedule = await getPublicSchedule(supabase, {
  from: '2024-01-01',
  to: '2024-12-31',
});

// Recupera prezzi pubblici
const pricing = await getPublicPricing(supabase);
```

### 3. App Clienti (React Native + Expo PWA)

L'app Expo usa `createSupabaseExpoClient` che non assume localStorage. Devi passare uno storage compatibile.

```typescript
import { createSupabaseExpoClient } from '@kalos/contract';
import * as SecureStore from 'expo-secure-store';
// oppure
// import AsyncStorage from '@react-native-async-storage/async-storage';

// Crea storage adapter per Expo SecureStore
const expoStorage = {
  getItem: (key: string) => {
    return SecureStore.getItemAsync(key);
  },
  setItem: (key: string, value: string) => {
    return SecureStore.setItemAsync(key, value);
  },
  removeItem: (key: string) => {
    return SecureStore.deleteItemAsync(key);
  },
};

// Oppure con AsyncStorage:
// const asyncStorage = {
//   getItem: (key: string) => AsyncStorage.getItem(key),
//   setItem: (key: string, value: string) => AsyncStorage.setItem(key, value),
//   removeItem: (key: string) => AsyncStorage.removeItem(key),
// };

// Crea il client con storage custom
const supabase = createSupabaseExpoClient({
  url: process.env.EXPO_PUBLIC_SUPABASE_URL!, // Expo usa EXPO_PUBLIC_ prefix
  anonKey: process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!,
  storage: expoStorage, // oppure asyncStorage
  storageKey: 'sb-auth-token', // Opzionale
});

// Usa RPC come nel gestionale
import { bookLesson, cancelBooking } from '@kalos/contract';

const result = await bookLesson(supabase, {
  lessonId: '123',
  subscriptionId: '456',
});
```

## Types

La libreria esporta i types del database e helper types:

```typescript
import type { 
  Database, 
  Tables, 
  TablesInsert, 
  TablesUpdate, 
  Enums 
} from '@kalos/contract';

// Usa i types per tipizzare le tue query
type User = Tables<'users'>;
type NewUser = TablesInsert<'users'>;
type UserUpdate = TablesUpdate<'users'>;
```

## Aggiornare il Contract

Quando lo schema del database cambia, segui questi passi:

1. **Rigenera i types da Supabase** (nel repo contract):
   ```bash
   # Con Supabase CLI
   supabase gen types typescript --project-id <your-project-id> > src/types/database.ts
   
   # Oppure per Supabase locale
   supabase gen types typescript --local > src/types/database.ts
   ```

2. **Sostituisci il file** `src/types/database.ts` con il contenuto generato.

3. **Verifica che compili**:
   ```bash
   npm run typecheck
   npm run build
   ```

4. **Bumpa la versione** in `package.json` (es. `0.1.0` → `0.1.1`).

5. **Commit e tag**:
   ```bash
   git add .
   git commit -m "chore: update database types"
   git tag v0.1.1
   git push origin main --tags
   ```

6. **Aggiorna la dependency** nei 3 repository consumer:
   ```json
   {
     "dependencies": {
       "@kalos/contract": "github:ORG/kalos-contract#v0.1.1"
     }
   }
   ```
   Poi esegui `npm install` (o yarn/pnpm equivalent).

## Supported Supabase JS Version

Questa libreria è compatibile con `@supabase/supabase-js` versione **^2.39.0** o superiore.

La libreria esporta `@supabase/supabase-js` come `peerDependency`, quindi i consumer devono installare la versione corretta:

```json
{
  "dependencies": {
    "@supabase/supabase-js": "^2.39.0"
  }
}
```

**Nota**: La libreria non forza una versione specifica per evitare conflitti con i consumer. Verifica sempre la compatibilità quando aggiorni `@supabase/supabase-js` nei consumer.

## Database Workflow

Questo repository è la **source of truth** per il database Supabase. Contiene migrations, functions, seed data e configurazione.

**📖 Vedi [DATABASE_WORKFLOW.md](./DATABASE_WORKFLOW.md) per la documentazione completa del workflow migrations.**

### Struttura Supabase

```
supabase/
  ├── migrations/          # Migrations canoniche (source of truth)
  ├── functions/           # Edge functions
  ├── seed.sql            # Seed data per sviluppo locale
  ├── config.toml         # Configurazione Supabase CLI
  ├── _legacy/            # Import storici da altri repo (solo archivio)
  │   ├── kalos-app/
  │   └── kalos-app-management/
  └── _remote/            # Migration list remota (gitignored)
```

### Workflow Migrations (Sintesi)

**⚠️ IMPORTANTE**: Vedi [DATABASE_WORKFLOW.md](./DATABASE_WORKFLOW.md) per la documentazione completa.

**Workflow rapido**:

1. **Crea migration**:
   ```bash
   npm run db:diff  # oppure crea manualmente
   ```

2. **Verifica** (OBBLIGATORIO prima di commit):
   ```bash
   npm run verify
   ```

3. **Test locale**:
   ```bash
   npm run db:start
   supabase db reset
   ```

4. **Applica a produzione**:
   ```bash
   npm run db:link
   npm run db:push
   ```

5. **Rigenera types e release**:
   ```bash
   supabase gen types typescript --project-id <id> > src/types/database.ts
   npm run verify
   # Bump versione, commit, tag
   ```

### Scripts Database

```bash
# Autenticazione e collegamento
npm run db:login           # Login a Supabase CLI
npm run db:projects        # Lista progetti disponibili
npm run db:link            # Collega al progetto remoto

# Migrations
npm run db:migrations:list # Genera lista migrations remote
npm run db:canonical:select # Seleziona set canonico da legacy
npm run db:diff            # Mostra differenze schema
npm run db:push            # Applica migrations a remoto
npm run db:pull            # Pull migrations da remoto (ATTENZIONE: può fallire se history mismatch)

# Sviluppo locale
npm run db:start           # Avvia Supabase locale
npm run db:stop            # Ferma Supabase locale

# Utilità
npm run db:import:legacy   # Importa supabase/ dai repo legacy
npm run db:unify           # Unifica functions/seed/config canonici
npm run db:init:migrations # Inizializza migrations placeholder da remote list
npm run db:dump:schema     # Genera dump completo dello schema remoto
npm run db:fill:migrations # Riempie migrations placeholder con contenuto da dump
npm run db:repair:history  # Ripara migration history dopo sincronizzazione (usa con cautela)
```

### ⚠️ Avvertenze Importanti

- **Non modificare lo schema dal dashboard** senza poi trasformarlo in migration
- **Non committare segreti** in `supabase/config.toml` o altri file
- `db:pull` può fallire se c'è mismatch nella migration history
- Prima di fare `db:push` a produzione, verifica sempre le migrations in locale

### Setup Iniziale (solo la prima volta)

Se hai appena clonato il repo e devi collegarlo al progetto Supabase:

```bash
# 1. Login
npm run db:login

# 2. Collega al progetto
npm run db:link

# 3. Genera lista migrations remote
npm run db:migrations:list

# 4. Inizializza migrations locali (crea placeholder)
npm run db:init:migrations

# 5. (Opzionale) Genera dump completo dello schema per riferimento
npm run db:dump:schema

# 6. Riempi le migrations placeholder con il contenuto SQL reale
npm run db:fill:migrations

# 7. (Se necessario) Ripara la migration history per sincronizzare remote e local
npm run db:repair:history
```

**Nota importante**: 
- Lo script `db:init:migrations` crea solo migrations placeholder vuote
- Usa `db:fill:migrations` per riempirle automaticamente dal dump dello schema
- Lo script divide lo schema in modo logico: 0000 (types/tables), 0001 (functions), 0002 (views), 0003 (RLS/grants)
- `db:repair:history` modifica la migration history table remota - usa solo se sei sicuro che le migrations locali rappresentano correttamente lo stato del database

## Note Importanti

- **Nessun env reading**: La libreria NON legge `process.env` o `import.meta.env`. I consumer devono passare URL e anon key.
- **Solo anon key**: Non includere mai la service role key nella libreria.
- **Compatibilità Expo**: La libreria è compatibile con Expo/Metro. Non usa Node-only APIs.
- **Source of truth**: Questa libreria è la fonte di verità per types, migrations, functions e helper/query condivisi.

## Scripts

### Build e sviluppo

```bash
# Build
npm run build

# Type check
npm run typecheck

# Clean
npm run clean

# Prepublish (clean + build + typecheck)
npm run prepublishOnly

# Verifica completa (types + build + migrations)
npm run verify
```

### Database (Supabase)

Vedi sezione "Database Workflow" e [DATABASE_WORKFLOW.md](./DATABASE_WORKFLOW.md) per dettagli completi.

```bash
# Verifica migrations e contract
npm run verify:migrations

# Altri script database (vedi sezione Database Workflow)
```

## Struttura

```
src/
  ├── index.ts              # Entry point con tutte le esportazioni
  ├── types/
  │   ├── database.ts       # Types del database (da generare con Supabase CLI)
  │   └── helpers.ts        # Helper types (Tables, TablesInsert, ecc.)
  ├── supabase/
  │   └── client.ts         # Factory per client browser ed Expo
  ├── rpc/
  │   └── index.ts          # Wrapper RPC (bookLesson, cancelBooking)
  └── queries/
      └── public.ts         # Query per views pubbliche (sito)

supabase/
  ├── migrations/           # Migrations canoniche (source of truth)
  ├── functions/            # Edge functions
  ├── seed.sql             # Seed data
  ├── config.toml          # Configurazione Supabase CLI
  ├── _legacy/             # Import storici (archivio)
  └── _remote/             # Migration list remota (gitignored)

scripts/
  ├── import-legacy-supabase.mjs      # Importa supabase/ dai repo legacy
  ├── select-canonical-migrations.mjs # Seleziona set canonico
  └── unify-canonical-files.mjs       # Unifica functions/seed/config
```

## License

MIT

