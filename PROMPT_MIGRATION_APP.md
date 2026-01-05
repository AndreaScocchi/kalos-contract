# Prompt per Migrazione App Utente (kalos-app)

## Contesto

Il database è stato standardizzato per usare **solo `client_id`** come campo di ownership per bookings e subscriptions. Il campo `user_id` è stato rimosso dalle tabelle `bookings` e `subscriptions`.

## Cambiamenti nel Database

1. **Rimosso campo `user_id`** da `bookings` e `subscriptions`
2. **Solo `client_id`** viene usato per identificare il proprietario
3. **Funzione helper**: `get_my_client_id()` restituisce il `client_id` dell'utente autenticato
4. **RPC aggiornate**: `book_lesson()` e `cancel_booking()` ora usano sempre `client_id`

## Cosa Devi Fare

### 1. Aggiorna le Query TypeScript

Cerca tutti i riferimenti a `user_id` nelle query su `bookings` e `subscriptions`:

```typescript
// ❌ PRIMA (non funziona più)
const { data } = await supabase
  .from('bookings')
  .select('*')
  .eq('user_id', userId);

// ✅ DOPO (usa client_id)
const clientId = await getMyClientId(); // Usa la funzione helper
const { data } = await supabase
  .from('bookings')
  .select('*')
  .eq('client_id', clientId);
```

### 2. Aggiorna le Funzioni Helper

Crea o aggiorna una funzione per ottenere il `client_id`:

```typescript
// Esempio di funzione helper
async function getMyClientId(): Promise<string | null> {
  const { data, error } = await supabase.rpc('get_my_client_id');
  if (error || !data) return null;
  return data;
}
```

### 3. Aggiorna le Query su Bookings

Cerca tutte le query che filtrano per `user_id`:

```typescript
// ❌ PRIMA
const { data: bookings } = await supabase
  .from('bookings')
  .select('*')
  .eq('user_id', userId);

// ✅ DOPO
const clientId = await getMyClientId();
if (!clientId) throw new Error('Client not found');

const { data: bookings } = await supabase
  .from('bookings')
  .select('*')
  .eq('client_id', clientId);
```

### 4. Aggiorna le Query su Subscriptions

```typescript
// ❌ PRIMA
const { data: subscriptions } = await supabase
  .from('subscriptions')
  .select('*')
  .eq('user_id', userId);

// ✅ DOPO
const clientId = await getMyClientId();
if (!clientId) throw new Error('Client not found');

const { data: subscriptions } = await supabase
  .from('subscriptions')
  .select('*')
  .eq('client_id', clientId);
```

### 5. Aggiorna le Query su Subscription Usages

Le query su `subscription_usages` devono filtrare tramite `subscriptions.client_id`:

```typescript
// ❌ PRIMA (se filtravi direttamente)
const { data: usages } = await supabase
  .from('subscription_usages')
  .select('*, subscriptions!inner(user_id)')
  .eq('subscriptions.user_id', userId);

// ✅ DOPO
const clientId = await getMyClientId();
if (!clientId) throw new Error('Client not found');

const { data: usages } = await supabase
  .from('subscription_usages')
  .select('*, subscriptions!inner(client_id)')
  .eq('subscriptions.client_id', clientId);
```

### 6. Verifica le RPC Calls

Le RPC `book_lesson()` e `cancel_booking()` sono già aggiornate nel database, ma verifica che le chiamate siano corrette:

```typescript
// ✅ book_lesson - non cambia, usa sempre auth.uid() internamente
const { data, error } = await supabase.rpc('book_lesson', {
  p_lesson_id: lessonId,
  p_subscription_id: subscriptionId || null,
});

// ✅ cancel_booking - non cambia
const { data, error } = await supabase.rpc('cancel_booking', {
  p_booking_id: bookingId,
});
```

### 7. Aggiorna i Types TypeScript

Dopo aver aggiornato il contract `@kalos/contract`, rigenera i types:

```bash
npm install @kalos/contract@latest
```

I types aggiornati non avranno più `user_id` in `bookings` e `subscriptions`.

### 8. Gestisci il Caso Client Non Trovato

Se `get_my_client_id()` restituisce `null`, significa che l'utente non ha un client collegato. Questo non dovrebbe succedere (il sistema crea automaticamente un client alla registrazione), ma gestisci il caso:

```typescript
const clientId = await getMyClientId();
if (!clientId) {
  // Mostra errore all'utente o richiedi supporto
  throw new Error('Il tuo account non è collegato a un cliente. Contatta il supporto.');
}
```

## Checklist

- [ ] Cerca tutti i riferimenti a `user_id` nel codice
- [ ] Sostituisci con `client_id` usando `get_my_client_id()`
- [ ] Aggiorna tutte le query su `bookings`
- [ ] Aggiorna tutte le query su `subscriptions`
- [ ] Aggiorna tutte le query su `subscription_usages`
- [ ] Verifica che le RPC calls funzionino correttamente
- [ ] Aggiorna i types TypeScript dal contract
- [ ] Testa tutte le funzionalità di prenotazione
- [ ] Testa la visualizzazione delle subscriptions
- [ ] Testa la cancellazione delle prenotazioni

## Note Importanti

1. **Non usare più `user_id`**: Il campo non esiste più nelle tabelle `bookings` e `subscriptions`
2. **Sempre usare `get_my_client_id()`**: Non assumere che `auth.uid()` corrisponda direttamente a un `client_id`
3. **RLS aggiornata**: Le RLS policies ora filtrano solo per `client_id`, quindi le query dovrebbero funzionare automaticamente
4. **Backward compatibility**: Se hai dati vecchi con `user_id`, sono già stati migrati automaticamente dal database

## Esempi Completi

### Esempio: Carica Bookings dell'Utente

```typescript
async function getUserBookings() {
  const clientId = await getMyClientId();
  if (!clientId) throw new Error('Client not found');

  const { data, error } = await supabase
    .from('bookings')
    .select(`
      *,
      lessons!inner(
        *,
        activities!inner(*)
      )
    `)
    .eq('client_id', clientId)
    .order('created_at', { ascending: false });

  if (error) throw error;
  return data;
}
```

### Esempio: Carica Subscriptions dell'Utente

```typescript
async function getUserSubscriptions() {
  const clientId = await getMyClientId();
  if (!clientId) throw new Error('Client not found');

  const { data, error } = await supabase
    .from('subscriptions')
    .select(`
      *,
      plans!inner(*)
    `)
    .eq('client_id', clientId)
    .order('created_at', { ascending: false });

  if (error) throw error;
  return data;
}
```

