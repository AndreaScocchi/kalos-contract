# Prompt per Migrazione Gestionale (kalos-app-management)

## Contesto

Il database è stato standardizzato per usare **solo `client_id`** come campo di ownership per bookings e subscriptions. Il campo `user_id` è stato rimosso dalle tabelle `bookings` e `subscriptions`.

## Cambiamenti nel Database

1. **Rimosso campo `user_id`** da `bookings` e `subscriptions`
2. **Solo `client_id`** viene usato per identificare il proprietario
3. **RPC aggiornata**: `staff_book_lesson()` ora usa solo `client_id` (semplificata)
4. **RLS aggiornate**: Le policies ora filtrano solo per `client_id`

## Cosa Devi Fare

### 1. Aggiorna le Query su Bookings

Cerca tutti i riferimenti a `user_id` nelle query:

```typescript
// ❌ PRIMA (non funziona più)
const { data: bookings } = await supabase
  .from('bookings')
  .select('*, profiles!inner(*)')
  .eq('user_id', userId);

// ✅ DOPO (usa client_id)
const { data: bookings } = await supabase
  .from('bookings')
  .select('*, clients!inner(*)')
  .eq('client_id', clientId);
```

### 2. Aggiorna le Query su Subscriptions

```typescript
// ❌ PRIMA
const { data: subscriptions } = await supabase
  .from('subscriptions')
  .select('*, profiles!inner(*)')
  .eq('user_id', userId);

// ✅ DOPO
const { data: subscriptions } = await supabase
  .from('subscriptions')
  .select('*, clients!inner(*)')
  .eq('client_id', clientId);
```

### 3. Aggiorna le Join con Profiles

Se facevi join con `profiles` tramite `user_id`, ora devi fare join tramite `clients.profile_id`:

```typescript
// ❌ PRIMA
const { data } = await supabase
  .from('bookings')
  .select(`
    *,
    profiles!bookings_user_id_fkey(*)
  `)
  .eq('user_id', userId);

// ✅ DOPO
const { data } = await supabase
  .from('bookings')
  .select(`
    *,
    clients!bookings_client_id_fkey(
      *,
      profiles!clients_profile_id_fkey(*)
    )
  `)
  .eq('client_id', clientId);
```

### 4. Aggiorna le Query per Trovare Bookings di un Utente

Se vuoi trovare i bookings di un utente tramite il suo `profile_id`:

```typescript
// ✅ DOPO - Trova client tramite profile_id, poi bookings
const { data: client } = await supabase
  .from('clients')
  .select('id')
  .eq('profile_id', userId)
  .single();

if (client) {
  const { data: bookings } = await supabase
    .from('bookings')
    .select('*')
    .eq('client_id', client.id);
}
```

### 5. Aggiorna le Query per Trovare Subscriptions di un Utente

```typescript
// ✅ DOPO - Trova client tramite profile_id, poi subscriptions
const { data: client } = await supabase
  .from('clients')
  .select('id')
  .eq('profile_id', userId)
  .single();

if (client) {
  const { data: subscriptions } = await supabase
    .from('subscriptions')
    .select('*')
    .eq('client_id', client.id);
}
```

### 6. Verifica le RPC Calls Staff

La RPC `staff_book_lesson()` è già aggiornata e ora usa solo `client_id`:

```typescript
// ✅ Non cambia - usa sempre client_id
const { data, error } = await supabase.rpc('staff_book_lesson', {
  p_lesson_id: lessonId,
  p_client_id: clientId,  // Sempre client_id
  p_subscription_id: subscriptionId || null,
});
```

### 7. Aggiorna le Query su Subscription Usages

```typescript
// ❌ PRIMA
const { data: usages } = await supabase
  .from('subscription_usages')
  .select('*, subscriptions!inner(user_id)')
  .eq('subscriptions.user_id', userId);

// ✅ DOPO
const { data: usages } = await supabase
  .from('subscription_usages')
  .select('*, subscriptions!inner(client_id)')
  .eq('subscriptions.client_id', clientId);
```

### 8. Aggiorna le Funzioni di Filtro/Report

Se hai funzioni che filtrano per `user_id`, aggiornale:

```typescript
// ❌ PRIMA
function getBookingsForUser(userId: string) {
  return supabase
    .from('bookings')
    .select('*')
    .eq('user_id', userId);
}

// ✅ DOPO
async function getBookingsForUser(userId: string) {
  // Prima trova il client
  const { data: client } = await supabase
    .from('clients')
    .select('id')
    .eq('profile_id', userId)
    .single();

  if (!client) return { data: [], error: null };

  // Poi trova i bookings
  return supabase
    .from('bookings')
    .select('*')
    .eq('client_id', client.id);
}
```

### 9. Aggiorna le Views/Report

Se crei report o statistiche che raggruppano per `user_id`, aggiornale per usare `client_id`:

```typescript
// ❌ PRIMA
const { data } = await supabase
  .from('bookings')
  .select('user_id, count(*)')
  .group('user_id');

// ✅ DOPO
const { data } = await supabase
  .from('bookings')
  .select('client_id, count(*)')
  .group('client_id');
```

### 10. Aggiorna i Types TypeScript

Dopo aver aggiornato il contract `@kalos/contract`, rigenera i types:

```bash
npm install @kalos/contract@latest
```

I types aggiornati non avranno più `user_id` in `bookings` e `subscriptions`.

## Checklist

- [ ] Cerca tutti i riferimenti a `user_id` nel codice
- [ ] Sostituisci con `client_id` nelle query su `bookings`
- [ ] Sostituisci con `client_id` nelle query su `subscriptions`
- [ ] Aggiorna le join con `profiles` per usare `clients.profile_id`
- [ ] Aggiorna le funzioni che filtrano per utente
- [ ] Aggiorna le query su `subscription_usages`
- [ ] Aggiorna report e statistiche
- [ ] Verifica che le RPC calls staff funzionino correttamente
- [ ] Aggiorna i types TypeScript dal contract
- [ ] Testa tutte le funzionalità di gestione bookings
- [ ] Testa tutte le funzionalità di gestione subscriptions
- [ ] Testa la creazione di bookings per clienti
- [ ] Testa i report e le statistiche

## Note Importanti

1. **Non usare più `user_id`**: Il campo non esiste più nelle tabelle `bookings` e `subscriptions`
2. **Usa sempre `client_id`**: Anche per utenti con account, usa sempre `client_id`
3. **Join con profiles**: Se devi accedere ai dati del profilo, fai join tramite `clients.profile_id`
4. **RLS aggiornata**: Le RLS policies ora filtrano solo per `client_id`, quindi le query dovrebbero funzionare automaticamente
5. **Staff può vedere tutto**: Le RLS policies permettono allo staff di vedere tutti i bookings e subscriptions

## Esempi Completi

### Esempio: Carica Bookings con Dati Cliente e Profilo

```typescript
async function getBookingsWithClientInfo() {
  const { data, error } = await supabase
    .from('bookings')
    .select(`
      *,
      clients!inner(
        *,
        profiles:profiles!clients_profile_id_fkey(*)
      ),
      lessons!inner(
        *,
        activities!inner(*)
      )
    `)
    .order('created_at', { ascending: false });

  if (error) throw error;
  return data;
}
```

### Esempio: Carica Subscriptions con Dati Cliente

```typescript
async function getSubscriptionsWithClientInfo() {
  const { data, error } = await supabase
    .from('subscriptions')
    .select(`
      *,
      clients!inner(
        *,
        profiles:profiles!clients_profile_id_fkey(*)
      ),
      plans!inner(*)
    `)
    .order('created_at', { ascending: false });

  if (error) throw error;
  return data;
}
```

### Esempio: Trova Bookings di un Utente Specifico

```typescript
async function getBookingsForUser(userId: string) {
  // Trova il client collegato all'utente
  const { data: client, error: clientError } = await supabase
    .from('clients')
    .select('id')
    .eq('profile_id', userId)
    .single();

  if (clientError || !client) {
    return { data: [], error: clientError };
  }

  // Trova i bookings del client
  const { data, error } = await supabase
    .from('bookings')
    .select(`
      *,
      lessons!inner(
        *,
        activities!inner(*)
      )
    `)
    .eq('client_id', client.id)
    .order('created_at', { ascending: false });

  return { data, error };
}
```

### Esempio: Report Bookings per Cliente

```typescript
async function getBookingsReport() {
  const { data, error } = await supabase
    .from('bookings')
    .select(`
      client_id,
      clients!inner(
        full_name,
        email,
        profiles:profiles!clients_profile_id_fkey(email)
      ),
      count
    `)
    .eq('status', 'booked')
    .group('client_id, clients.full_name, clients.email, clients.profile_id');

  if (error) throw error;
  return data;
}
```

