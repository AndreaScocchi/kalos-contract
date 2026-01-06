# Prompt: Gestione Prenotazione Eventi - App Cliente

## 📋 Obiettivo

Implementare la gestione delle prenotazioni eventi nell'app cliente. Quando un evento non ha un link esterno (`link IS NULL`), l'app deve permettere all'utente di prenotare direttamente tramite l'app. L'utente deve anche poter annullare le proprie prenotazioni.

## 🎯 Funzionalità Richieste

### 1. Visualizzazione Eventi con Disponibilità

Nella pagina lista eventi e nel dettaglio evento, mostrare:
- Se l'evento ha un link esterno (`link IS NOT NULL`): mostra un pulsante "Prenota esternamente" che apre il link
- Se l'evento NON ha un link esterno (`link IS NULL`): mostra pulsante "Prenota" se ci sono posti disponibili
- Mostrare sempre il numero di posti disponibili (es. "5 posti disponibili" o "Pieno")
- Se l'evento è pieno (`is_full = true`): disabilitare il pulsante e mostrare "Pieno"

### 2. Dettaglio Evento

Nel dettaglio evento, aggiungere:
- **Pulsante "Prenota"**: visibile solo se:
  - `link IS NULL` (prenotazione interna)
  - `is_full = false` (non pieno)
  - L'utente non ha già prenotato l'evento
- **Pulsante "Annulla prenotazione"**: visibile solo se l'utente ha già prenotato l'evento
- **Informazioni disponibilità**: mostra "X posti disponibili su Y" o "Pieno" o "Capacità illimitata"

### 3. Prenotazione Evento

Quando l'utente clicca "Prenota":
1. Chiama la RPC `bookEvent()` da `@kalos/contract`
2. Gestisci i possibili risultati:
   - `ok: true` → mostra messaggio di successo e aggiorna UI
   - `ok: false, reason: 'ALREADY_BOOKED'` → mostra errore "Hai già prenotato questo evento"
   - `ok: false, reason: 'FULL'` → mostra errore "Evento pieno"
   - `ok: false, reason: 'EVENT_NOT_FOUND'` → mostra errore generico
   - Altri errori → mostra messaggio di errore appropriato

### 4. Annullamento Prenotazione

Quando l'utente clicca "Annulla prenotazione":
1. Mostra conferma (es. "Sei sicuro di voler annullare la prenotazione?")
2. Chiama la RPC `cancelEventBooking()` da `@kalos/contract`
3. Gestisci i possibili risultati:
   - `ok: true` → mostra messaggio di successo e aggiorna UI
   - `ok: false, reason: 'ALREADY_CANCELED'` → mostra errore appropriato
   - `ok: false, reason: 'CANNOT_CANCEL_CONCLUDED'` → mostra errore "Non puoi annullare un evento già concluso"
   - Altri errori → mostra messaggio di errore appropriato

### 5. Lista Eventi Prenotati

In una sezione dedicata (es. "I Miei Eventi"), mostrare:
- Lista degli eventi che l'utente ha prenotato (status = 'booked')
- Per ogni evento: data, nome, possibilità di annullare

## 📚 API e Funzioni da Utilizzare

### Da `@kalos/contract`:

```typescript
import {
  getEventsWithAvailability,
  bookEvent,
  cancelEventBooking,
  type EventWithAvailability,
} from '@kalos/contract';

// Recupera eventi con disponibilità
const events = await getEventsWithAvailability(supabase, {
  from: new Date().toISOString().split('T')[0], // Solo eventi futuri
});

// Prenota un evento
const result = await bookEvent(supabase, {
  eventId: 'uuid-dell-evento',
});

// Cancella una prenotazione
const cancelResult = await cancelEventBooking(supabase, {
  bookingId: 'uuid-della-prenotazione',
});
```

### Query per Eventi Prenotati:

```typescript
// Recupera eventi prenotati dall'utente
const { data: myBookings } = await supabase
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
      image_url
    )
  `)
  .eq('status', 'booked')
  .order('events.starts_at', { ascending: true });
```

## 🎨 UI/UX Suggerimenti

1. **Stati del Pulsante Prenota**:
   - Link esterno: pulsante primario "Prenota esternamente" con icona link
   - Prenotazione interna disponibile: pulsante primario "Prenota"
   - Già prenotato: badge "Prenotato" + pulsante secondario "Annulla"
   - Pieno: pulsante disabilitato "Pieno" con stile grigio

2. **Indicatori Disponibilità**:
   - Se `capacity IS NULL`: mostra "Capacità illimitata"
   - Se `capacity IS NOT NULL`: mostra "X posti disponibili su Y"
   - Se `is_full = true`: mostra "Pieno" in rosso/evidenziato

3. **Feedback Utente**:
   - Durante la prenotazione: mostra spinner/loading
   - Successo: toast/notifica verde
   - Errore: toast/notifica rossa con messaggio chiaro

4. **Gestione Errori**:
   - Mostra messaggi di errore user-friendly in italiano
   - Log degli errori in console per debugging

## ✅ Checklist Implementazione

- [ ] Aggiungere query `getEventsWithAvailability` nella pagina lista eventi
- [ ] Modificare card evento per mostrare disponibilità e pulsante appropriato
- [ ] Implementare pagina dettaglio evento con pulsante prenota/annulla
- [ ] Implementare logica prenotazione con gestione errori
- [ ] Implementare logica annullamento con conferma
- [ ] Aggiungere sezione "I Miei Eventi" con lista prenotazioni
- [ ] Aggiungere indicatori visivi per disponibilità posti
- [ ] Gestire stati di loading durante le operazioni
- [ ] Testare flussi completi: prenota → annulla → ri-prenota
- [ ] Testare casi limite: evento pieno, già prenotato, evento passato

## 🔍 Note Importanti

1. **RLS**: Le RPC functions gestiscono automaticamente l'autenticazione e i permessi. L'utente può prenotare/annullare solo le proprie prenotazioni.

2. **Link NULL**: Solo eventi con `link IS NULL` possono essere prenotati internamente. Eventi con link esterno devono sempre reindirizzare al link.

3. **Capacità**: Se `capacity IS NULL`, l'evento ha capacità illimitata e non può essere "pieno".

4. **Status**: Le prenotazioni hanno status `'booked'`, `'canceled'`, `'attended'`, `'no_show'`. Per la lista prenotazioni, filtrare solo `status = 'booked'`.

5. **Sincronizzazione**: Dopo prenotazione/annullamento, aggiornare la UI e ricaricare i dati per mostrare la disponibilità aggiornata.

