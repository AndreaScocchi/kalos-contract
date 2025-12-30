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

## Note Importanti

- **Nessun env reading**: La libreria NON legge `process.env` o `import.meta.env`. I consumer devono passare URL e anon key.
- **Solo anon key**: Non includere mai la service role key nella libreria.
- **Compatibilità Expo**: La libreria è compatibile con Expo/Metro. Non usa Node-only APIs.
- **Source of truth**: Questa libreria è la fonte di verità per types e helper/query condivisi.

## Scripts

```bash
# Build
npm run build

# Type check
npm run typecheck

# Clean
npm run clean

# Prepublish (clean + build + typecheck)
npm run prepublishOnly
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
```

## License

MIT

