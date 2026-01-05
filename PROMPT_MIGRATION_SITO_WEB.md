# Prompt per Migrazione Sito Web (kalos-react)

## Contesto

Il database è stato standardizzato per usare **solo `client_id`** come campo di ownership per bookings e subscriptions. Il campo `user_id` è stato rimosso dalle tabelle `bookings` e `subscriptions`.

## Buone Notizie

**Il sito web probabilmente non richiede modifiche** perché:

1. Il sito web usa principalmente **views pubbliche** (`public_site_*`) che non includono `user_id` o `client_id`
2. Il sito web non gestisce direttamente bookings o subscriptions
3. Le views pubbliche sono già isolate e non dipendono dalla struttura interna delle tabelle

## Verifica Necessaria

Tuttavia, verifica se ci sono query dirette alle tabelle `bookings` o `subscriptions`:

### 1. Cerca Query Dirette

Cerca nel codice riferimenti a:
- `from('bookings')`
- `from('subscriptions')`
- `from('subscription_usages')`

Se non ci sono, **non serve fare nulla**.

### 2. Se Ci Sono Query Dirette

Se trovi query dirette che usano `user_id`, aggiornale:

```typescript
// ❌ PRIMA (se esiste)
const { data } = await supabase
  .from('bookings')
  .select('*')
  .eq('user_id', userId);

// ✅ DOPO
const { data } = await supabase
  .from('bookings')
  .select('*')
  .eq('client_id', clientId);
```

**Nota**: Il sito web pubblico non dovrebbe avere accesso a bookings/subscriptions tramite RLS, quindi queste query probabilmente non funzionerebbero comunque.

### 3. Verifica le Views Pubbliche

Le views pubbliche (`public_site_*`) non sono cambiate:

```typescript
// ✅ Queste continuano a funzionare come prima
const { data: activities } = await supabase
  .from('public_site_activities')
  .select('*');

const { data: operators } = await supabase
  .from('public_site_operators')
  .select('*');

const { data: events } = await supabase
  .from('public_site_events')
  .select('*');

const { data: schedule } = await supabase
  .from('public_site_schedule')
  .select('*');

const { data: pricing } = await supabase
  .from('public_site_pricing')
  .select('*');
```

### 4. Verifica le RPC Calls

Se il sito web chiama RPC functions, verifica che non ci siano problemi:

```typescript
// Se usi book_lesson (improbabile per sito pubblico)
// La RPC è già aggiornata e funziona automaticamente
```

## Checklist

- [ ] Cerca riferimenti a `bookings`, `subscriptions`, `subscription_usages`
- [ ] Se non ci sono, **nessuna modifica necessaria** ✅
- [ ] Se ci sono, verifica se usano `user_id` e aggiornale
- [ ] Verifica che le views pubbliche funzionino correttamente
- [ ] Testa il sito web per assicurarti che tutto funzioni

## Note Importanti

1. **Views pubbliche non cambiate**: Le views `public_site_*` non includono `user_id` o `client_id`, quindi non sono affette
2. **RLS non cambia per anon**: Gli utenti anonimi non possono accedere a `bookings` o `subscriptions` comunque
3. **Nessun breaking change**: Se il sito web usa solo le views pubbliche, non ci sono breaking changes

## Conclusione

**Se il sito web usa solo le views pubbliche e non fa query dirette a `bookings` o `subscriptions`, non serve fare nulla.** ✅

Se invece trovi query dirette, segui le istruzioni sopra per aggiornarle.

