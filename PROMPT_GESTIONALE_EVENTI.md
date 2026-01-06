# Prompt: Gestione Prenotazione Eventi - Gestionale

## 📋 Obiettivo

Implementare la gestione delle prenotazioni eventi nel gestionale. Lo staff deve poter:
1. Aggiungere prenotazioni di clienti ad eventi (sia clienti con account che senza)
2. Annullare prenotazioni di eventi
3. Visualizzare le prenotazioni di un evento
4. Nel dettaglio cliente, mostrare gli eventi che ha prenotato

## 🎯 Funzionalità Richieste

### 1. Dettaglio Evento - Gestione Prenotazioni

Nel dettaglio evento, aggiungere una sezione "Prenotazioni":

#### 1.1 Lista Prenotazioni
- Tabella/liste delle prenotazioni con:
  - Nome cliente (da `clients.full_name` o `profiles.full_name`)
  - Data prenotazione (`created_at`)
  - Status (`booked`, `canceled`, `attended`, `no_show`)
  - Azioni: Annulla, Modifica status (solo staff)

#### 1.2 Aggiungere Prenotazione
- Pulsante "Aggiungi prenotazione"
- Dialog/form per selezionare:
  - Cliente (dropdown/search con lista clienti)
  - Conferma prenotazione
- Mostra messaggio se evento è pieno prima di permettere l'aggiunta

#### 1.3 Informazioni Evento
- Mostra: "X posti occupati su Y" o "Capacità illimitata"
- Se pieno: evidenzia in rosso
- Mostra se l'evento ha link esterno o prenotazione interna

### 2. Annullamento Prenotazione

Dalla lista prenotazioni o dal dettaglio:
- Pulsante "Annulla" per ogni prenotazione con status `'booked'`
- Mostra conferma prima di annullare
- Dopo annullamento, aggiorna la lista

### 3. Dettaglio Cliente - Eventi Prenotati

Nel dettaglio cliente, aggiungere una sezione "Eventi":

#### 3.1 Lista Eventi Prenotati
- Tabella/liste degli eventi che il cliente ha prenotato:
  - Nome evento
  - Data/ora evento (`starts_at`)
  - Location
  - Status prenotazione (`booked`, `canceled`, `attended`, `no_show`)
  - Link al dettaglio evento

#### 3.2 Filtri
- Filtra per status prenotazione
- Filtra per eventi futuri/passati

## 📚 API e Funzioni da Utilizzare

### Da `@kalos/contract`:

```typescript
import {
  getEventsWithAvailability,
  staffBookEvent,
  staffCancelEventBooking,
  type EventWithAvailability,
} from '@kalos/contract';

// Recupera eventi con disponibilità
const events = await getEventsWithAvailability(supabase, {
  from: new Date().toISOString().split('T')[0],
});

// Aggiunge prenotazione evento per un cliente (staff only)
const result = await staffBookEvent(supabase, {
  eventId: 'uuid-dell-evento',
  clientId: 'uuid-del-cliente',
});

// Cancella una prenotazione evento (staff only)
const cancelResult = await staffCancelEventBooking(supabase, {
  bookingId: 'uuid-della-prenotazione',
});
```

### Query per Prenotazioni di un Evento:

```typescript
// Recupera tutte le prenotazioni di un evento
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
      phone
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

### Query per Eventi di un Cliente:

```typescript
// Recupera eventi prenotati da un cliente
const { data: clientBookings } = await supabase
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
  .eq('client_id', clientId)
  .order('events.starts_at', { ascending: false });

// Se il cliente ha un account (profile_id), recupera anche prenotazioni via user_id
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
  .order('events.starts_at', { ascending: false });

// Combina i risultati
const allBookings = [...clientBookings, ...profileBookings];
```

## 🎨 UI/UX Suggerimenti

1. **Tabella Prenotazioni**:
   - Colonne: Cliente, Data prenotazione, Status, Azioni
   - Badge colorati per status:
     - `booked`: verde
     - `canceled`: grigio
     - `attended`: blu
     - `no_show`: rosso
   - Filtri: per status, data

2. **Form Aggiungi Prenotazione**:
   - Autocomplete/search per selezione cliente
   - Mostra informazioni cliente selezionato (nome, email, telefono)
   - Mostra disponibilità corrente prima di confermare
   - Validazione: non permettere se evento è pieno

3. **Indicatori Disponibilità**:
   - Se `capacity IS NULL`: "Capacità illimitata"
   - Se `capacity IS NOT NULL`: barra progresso o testo "X/Y posti"
   - Se pieno: warning rosso

4. **Gestione Errori**:
   - Mostra toast/notifiche per successo/errore
   - Messaggi chiari in italiano

## ✅ Checklist Implementazione

### Dettaglio Evento
- [ ] Aggiungere sezione "Prenotazioni" nel dettaglio evento
- [ ] Implementare tabella lista prenotazioni con filtri
- [ ] Implementare form/dialog "Aggiungi prenotazione"
- [ ] Implementare logica aggiunta prenotazione con `staffBookEvent`
- [ ] Implementare logica annullamento con `staffCancelEventBooking`
- [ ] Mostrare indicatori disponibilità posti
- [ ] Gestire stati di loading

### Dettaglio Cliente
- [ ] Aggiungere sezione "Eventi" nel dettaglio cliente
- [ ] Implementare query per recuperare eventi prenotati (client_id + user_id se profile_id esiste)
- [ ] Mostrare lista eventi con filtri
- [ ] Link al dettaglio evento da ogni riga

### Generale
- [ ] Testare aggiunta prenotazione per cliente con account
- [ ] Testare aggiunta prenotazione per cliente senza account
- [ ] Testare annullamento prenotazione
- [ ] Testare casi limite: evento pieno, cliente già prenotato
- [ ] Validare che solo staff possa usare queste funzioni

## 🔍 Note Importanti

1. **RLS**: Le RPC `staffBookEvent` e `staffCancelEventBooking` verificano automaticamente che l'utente sia staff. Se non è staff, ritornano `ok: false, reason: 'UNAUTHORIZED'`.

2. **Client_id vs User_id**:
   - Se prenoti per un cliente senza account: usa sempre `client_id`
   - Se prenoti per un cliente con account (ha `profile_id`): puoi usare sia `client_id` che `user_id`, ma `staffBookEvent` usa sempre `client_id`

3. **Query Cliente**: Quando mostri eventi di un cliente, controlla sia:
   - `event_bookings.client_id = client.id` (prenotazioni dirette)
   - `event_bookings.user_id = client.profile_id` (se il cliente ha account)

4. **Status Management**: Lo staff può modificare lo status direttamente nella tabella `event_bookings` se necessario (es. marcare come `attended` o `no_show`).

5. **Capacità**: Verifica sempre la capacità prima di permettere nuove prenotazioni. La RPC `staffBookEvent` gestisce questo, ma è meglio mostrare un warning nella UI.

6. **Sincronizzazione**: Dopo aggiunta/annullamento, ricaricare i dati per mostrare aggiornamenti in tempo reale.

