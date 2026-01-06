# Fix: client_id come Fonte di Verità - App Cliente

## 🐛 Problema Risolto

Nelle prenotazioni degli eventi, `user_id` e `client_id` non venivano usati propriamente. È stato stabilito che **`client_id` è la fonte di verità** quando disponibile.

### Cosa è cambiato nel database:

1. **Funzione `bookEvent`**: Ora se l'utente ha un `client_id` associato (ha un account collegato a un cliente CRM), viene **sempre usato `client_id`** (con `user_id = NULL`) invece di `user_id`.

2. **Funzione `cancelEventBooking`**: Ora verifica ownership usando `client_id` come fonte di verità quando disponibile.

3. **Verifiche prenotazione esistente**: Le verifiche ora controllano principalmente `client_id` quando l'utente ha un cliente associato.

## ✅ Cosa Verificare nell'App

### 1. Query per Recuperare Prenotazioni Eventi

Assicurati che le query per recuperare le prenotazioni dell'utente gestiscano correttamente sia `client_id` che `user_id`:

```typescript
// ✅ CORRETTO: Query che gestisce entrambi i casi
const { data: myBookings } = await supabase
  .from('event_bookings')
  .select(`
    id,
    status,
    created_at,
    client_id,
    user_id,
    events (
      id,
      name,
      description,
      starts_at,
      ends_at,
      location,
      image_url
    )
  `)
  .or(`client_id.eq.${myClientId},and(user_id.eq.${userId},client_id.is.null)`)
  .eq('status', 'booked')
  .order('events.starts_at', { ascending: true });
```

**NOTA**: Il RLS dovrebbe già gestire questo automaticamente, ma verifica che la query funzioni correttamente.

### 2. Verifica Stato Prenotazione Evento

Quando verifichi se l'utente ha già prenotato un evento, non assumere che usi solo `user_id`. La prenotazione potrebbe essere salvata con `client_id`:

```typescript
// ❌ SBAGLIATO: Assumere che usi sempre user_id
const { data: existingBooking } = await supabase
  .from('event_bookings')
  .select('id')
  .eq('event_id', eventId)
  .eq('user_id', userId)  // ❌ Potrebbe non funzionare se la prenotazione usa client_id
  .eq('status', 'booked')
  .maybeSingle();

// ✅ CORRETTO: Lasciare che RLS gestisca la verifica, oppure controllare entrambi
const { data: existingBooking } = await supabase
  .from('event_bookings')
  .select('id')
  .eq('event_id', eventId)
  .or(`client_id.eq.${myClientId},and(user_id.eq.${userId},client_id.is.null)`)
  .eq('status', 'booked')
  .maybeSingle();
```

**OPPURE** (consigliato): Usare la funzione RPC `bookEvent` che gestisce automaticamente tutto:

```typescript
// ✅ CORRETTO: La RPC gestisce automaticamente client_id/user_id
const result = await bookEvent(supabase, {
  eventId: eventId,
});

if (!result.ok && result.reason === 'ALREADY_BOOKED') {
  // L'utente ha già prenotato
}
```

### 3. Display delle Prenotazioni

Quando mostri le prenotazioni, non assumere che abbiano sempre `user_id`. Verifica entrambi i campi:

```typescript
// ✅ CORRETTO: Gestire entrambi i casi nel display
{myBookings.map((booking) => (
  <div key={booking.id}>
    {/* Il booking può avere client_id O user_id, non entrambi */}
    {/* RLS già gestisce l'accesso, quindi se vedi il booking significa che è tuo */}
    <EventCard event={booking.events} />
  </div>
))}
```

## 🔍 Cosa NON Cambia

1. **Le RPC `bookEvent` e `cancelEventBooking`**: Continuano a funzionare esattamente come prima. Non devi modificare il modo in cui le chiami.

2. **RLS Policies**: Le policy RLS gestiscono automaticamente l'accesso basandosi sia su `client_id` che su `user_id`. Non devi modificare nulla.

3. **L'interfaccia utente**: Non cambia nulla per l'utente finale. L'app continua a funzionare come prima.

## ✅ Checklist Verifica

Dopo l'applicazione della migration, verifica:

- [ ] Le prenotazioni eventi continuano a funzionare correttamente
- [ ] Gli utenti con account collegato a un cliente possono prenotare eventi
- [ ] Le prenotazioni vengono visualizzate correttamente nella lista "I Miei Eventi"
- [ ] La cancellazione delle prenotazioni funziona correttamente
- [ ] Non ci sono errori quando si prenota un evento già prenotato
- [ ] Le query per recuperare prenotazioni funzionano correttamente

## 🧪 Test Consigliati

1. **Test Prenotazione Base**:
   - Utente con account collegato a cliente: prenota un evento
   - Verifica che la prenotazione sia visibile nella lista
   - Cancella la prenotazione
   - Verifica che la prenotazione scompaia

2. **Test Ri-prenotazione**:
   - Prenota un evento
   - Cancella la prenotazione
   - Prenota di nuovo lo stesso evento
   - Verifica che funzioni correttamente

3. **Test Visualizzazione**:
   - Verifica che tutte le prenotazioni siano visibili nella sezione "I Miei Eventi"
   - Verifica che i dettagli evento mostrino correttamente lo stato di prenotazione

## 📝 Note Tecniche

1. **Migration Applicata**: La migration `20260106190000_fix_event_bookings_client_id_source_of_truth.sql` è stata applicata al database.

2. **Backward Compatibility**: Le prenotazioni esistenti con `user_id` continuano a funzionare. Le nuove prenotazioni per utenti con `client_id` useranno sempre `client_id`.

3. **RLS**: Le Row Level Security policies gestiscono automaticamente l'accesso. Se vedi una prenotazione nella query, significa che l'utente ha il diritto di vederla.

4. **Non serve modificare le chiamate RPC**: Le funzioni `bookEvent` e `cancelEventBooking` continuano a funzionare esattamente come prima. La logica interna è stata migliorata per usare `client_id` come fonte di verità.

## 🚀 Prossimi Passi

1. **Verifica Funzionalità**: Testa le prenotazioni eventi per assicurarti che tutto funzioni correttamente.

2. **Aggiorna Query (se necessario)**: Se hai query personalizzate che assumono l'uso di `user_id`, aggiornale per gestire anche `client_id`.

3. **Test Completo**: Esegui un test completo del flusso di prenotazione eventi.

