# Fix: client_id come Fonte di Verità - Gestionale

## 🐛 Problema Risolto

Nelle prenotazioni degli eventi, `user_id` e `client_id` non venivano usati propriamente. È stato stabilito che **`client_id` è la fonte di verità** quando disponibile.

### Cosa è cambiato nel database:

1. **Funzione `bookEvent` (per utenti app)**: Ora se l'utente ha un `client_id` associato (ha un account collegato a un cliente CRM), viene **sempre usato `client_id`** (con `user_id = NULL`) invece di `user_id`.

2. **Funzione `cancelEventBooking`**: Ora verifica ownership usando `client_id` come fonte di verità quando disponibile.

3. **Funzione `staffBookEvent`**: Già usava `client_id` correttamente, ma ora è più coerente con il principio che `client_id` è la fonte di verità.

## ✅ Cosa Verificare nel Gestionale

### 1. Query per Recuperare Prenotazioni di un Evento

Assicurati che quando mostri le prenotazioni di un evento, gestisci correttamente entrambi i campi (`client_id` e `user_id`):

```typescript
// ✅ CORRETTO: Query che gestisce entrambi i casi
const { data: bookings } = await supabase
  .from('event_bookings')
  .select(`
    id,
    status,
    created_at,
    client_id,
    user_id,
    clients:client_id (
      id,
      full_name,
      email,
      phone,
      profile_id
    ),
    profiles:user_id (
      id,
      full_name,
      email
    )
  `)
  .eq('event_id', eventId)
  .order('created_at', { ascending: false });
```

**IMPORTANTE**: Per ottenere il nome del cliente:
- Se `client_id IS NOT NULL`: usa `clients.full_name`
- Se `user_id IS NOT NULL` (e `client_id IS NULL`): usa `profiles.full_name`

```typescript
// ✅ CORRETTO: Display del nome cliente
function getClientName(booking: EventBooking) {
  if (booking.client_id && booking.clients) {
    return booking.clients.full_name;
  }
  if (booking.user_id && booking.profiles) {
    return booking.profiles.full_name;
  }
  return 'Cliente sconosciuto';
}
```

### 2. Query per Recuperare Eventi di un Cliente

Quando mostri gli eventi prenotati da un cliente, **devi controllare entrambi `client_id` E `user_id`** se il cliente ha un account:

```typescript
// ✅ CORRETTO: Query che controlla sia client_id che user_id
async function getClientEventBookings(clientId: string, clientProfileId: string | null) {
  let query = supabase
    .from('event_bookings')
    .select(`
      id,
      status,
      created_at,
      events (
        id,
        name,
        description,
        starts_at,
        ends_at,
        location,
        image_url,
        link
      )
    `)
    .eq('client_id', clientId);

  // Se il cliente ha un account (profile_id), cerca anche prenotazioni via user_id
  if (clientProfileId) {
    const { data: profileBookings } = await supabase
      .from('event_bookings')
      .select(`
        id,
        status,
        created_at,
        events (
          id,
          name,
          description,
          starts_at,
          ends_at,
          location,
          image_url,
          link
        )
      `)
      .eq('user_id', clientProfileId)
      .is('client_id', null);

    const { data: clientBookings } = await query;

    // Combina i risultati, rimuovendo duplicati
    const allBookings = [
      ...(clientBookings || []),
      ...(profileBookings || [])
    ];
    
    // Rimuovi duplicati per event_id (nel caso ci siano prenotazioni vecchie con user_id)
    const uniqueBookings = allBookings.filter(
      (booking, index, self) =>
        index === self.findIndex((b) => b.events?.id === booking.events?.id)
    );

    return uniqueBookings;
  } else {
    const { data: clientBookings } = await query;
    return clientBookings || [];
  }
}
```

**NOTA**: Con la nuova logica, le prenotazioni future useranno sempre `client_id`, ma potrebbero esserci prenotazioni vecchie con `user_id` se il cliente ha un account. È importante gestire entrambi i casi per completezza.

### 3. Verifica Duplicati quando si Aggiunge una Prenotazione

La funzione `staffBookEvent` gestisce automaticamente i duplicati, ma nella UI potresti voler verificare prima:

```typescript
// ✅ CORRETTO: Verifica se cliente ha già prenotato (controlla entrambi)
async function checkIfClientAlreadyBooked(eventId: string, clientId: string, clientProfileId: string | null) {
  // Controlla prenotazioni via client_id
  const { data: clientBooking } = await supabase
    .from('event_bookings')
    .select('id')
    .eq('event_id', eventId)
    .eq('client_id', clientId)
    .eq('status', 'booked')
    .maybeSingle();

  if (clientBooking) {
    return true;
  }

  // Se il cliente ha un account, controlla anche user_id
  if (clientProfileId) {
    const { data: userBooking } = await supabase
      .from('event_bookings')
      .select('id')
      .eq('event_id', eventId)
      .eq('user_id', clientProfileId)
      .is('client_id', null)
      .eq('status', 'booked')
      .maybeSingle();

    if (userBooking) {
      return true;
    }
  }

  return false;
}
```

### 4. Visualizzazione Nome Cliente nelle Tabelle

Assicurati che il nome del cliente sia sempre mostrato correttamente:

```typescript
// ✅ CORRETTO: Helper per ottenere informazioni cliente
function getBookingClientInfo(booking: EventBooking) {
  // Priorità: client_id (fonte di verità) poi user_id
  if (booking.client_id && booking.clients) {
    return {
      name: booking.clients.full_name,
      email: booking.clients.email,
      phone: booking.clients.phone,
      hasAccount: booking.clients.profile_id !== null,
    };
  }
  
  if (booking.user_id && booking.profiles) {
    return {
      name: booking.profiles.full_name,
      email: booking.profiles.email,
      phone: null,
      hasAccount: true,
    };
  }

  return {
    name: 'Cliente sconosciuto',
    email: null,
    phone: null,
    hasAccount: false,
  };
}
```

## 🔍 Cosa NON Cambia

1. **La RPC `staffBookEvent`**: Continua a funzionare esattamente come prima. Usa sempre `client_id` (come specificato nel parametro).

2. **La RPC `staffCancelEventBooking`**: Continua a funzionare esattamente come prima.

3. **RLS Policies**: Le policy RLS per lo staff permettono di vedere tutte le prenotazioni. Non cambia nulla.

## ✅ Checklist Verifica

Dopo l'applicazione della migration, verifica:

- [ ] Le prenotazioni eventi vengono visualizzate correttamente nel dettaglio evento
- [ ] Il nome del cliente è mostrato correttamente (sia da `client_id` che da `user_id`)
- [ ] L'aggiunta di una nuova prenotazione per un cliente funziona correttamente
- [ ] La cancellazione delle prenotazioni funziona correttamente
- [ ] Nel dettaglio cliente, vengono mostrati tutti gli eventi prenotati (sia via `client_id` che via `user_id`)
- [ ] Non ci sono duplicati nella visualizzazione degli eventi prenotati da un cliente

## 🧪 Test Consigliati

1. **Test Prenotazione Cliente senza Account**:
   - Aggiungi prenotazione per cliente senza account (solo `client_id`)
   - Verifica che venga visualizzata correttamente
   - Verifica che il nome cliente sia mostrato

2. **Test Prenotazione Cliente con Account**:
   - Aggiungi prenotazione per cliente con account (avrà `client_id`)
   - Verifica che venga visualizzata correttamente
   - Verifica che nel dettaglio cliente compaia l'evento

3. **Test Visualizzazione Eventi Cliente**:
   - Apri dettaglio cliente con account
   - Verifica che vengano mostrati tutti gli eventi (sia quelli con `client_id` che eventuali vecchi con `user_id`)
   - Verifica che non ci siano duplicati

4. **Test Prenotazione Esistente**:
   - Prova ad aggiungere una prenotazione per un cliente che ha già prenotato
   - Verifica che venga mostrato un errore appropriato

## 📝 Note Tecniche

1. **Migration Applicata**: La migration `20260106190000_fix_event_bookings_client_id_source_of_truth.sql` è stata applicata al database.

2. **Backward Compatibility**: Le prenotazioni esistenti con `user_id` continuano a funzionare e vengono visualizzate correttamente. Le nuove prenotazioni per clienti (anche con account) useranno sempre `client_id`.

3. **Principio**: `client_id` è sempre la fonte di verità quando disponibile. Se un cliente ha un account (`profile_id`), le nuove prenotazioni useranno comunque `client_id` invece di `user_id`.

4. **Query Cliente con Account**: Quando mostri eventi di un cliente con account, devi comunque controllare sia `client_id` che `user_id` per essere completo (per gestire eventuali prenotazioni vecchie).

## 🚀 Prossimi Passi

1. **Verifica Query**: Controlla tutte le query che recuperano prenotazioni eventi e assicurati che gestiscano correttamente sia `client_id` che `user_id`.

2. **Aggiorna Display**: Assicurati che il nome del cliente sia sempre mostrato correttamente, indipendentemente da quale campo viene usato.

3. **Test Completo**: Esegui un test completo del flusso di gestione prenotazioni eventi nel gestionale.

4. **Documentazione Interna**: Documenta che `client_id` è la fonte di verità e che le query devono gestire entrambi i casi per completezza.

