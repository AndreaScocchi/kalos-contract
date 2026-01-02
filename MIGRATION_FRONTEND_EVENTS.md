# Migrazione Frontend: Gestione Eventi con Più Orari

## 📋 Contesto del Cambiamento

Il sistema di gestione eventi è stato modificato per supportare meglio eventi con più date e orari. Invece di gestire un array di date all'interno di un singolo evento, ora **ogni combinazione data+orario viene salvata come un evento separato** nel database.

## 🔄 Cambiamento nella Struttura Dati

### Prima (Vecchia Implementazione)
```typescript
// Ricevevi un evento con array di date
const event = {
  id: "123",
  name: "Decora la tua candela",
  dates: ["2024-01-15", "2024-01-20"],
  // ...
}
```

### Dopo (Nuova Implementazione)
```typescript
// Ricevi eventi separati, ognuno con una singola data/orario
const events = [
  {
    id: "123",
    name: "Decora la tua candela",
    start_date: "2024-01-15T10:00:00",
    end_date: "2024-01-15T11:00:00",
    // ...
  },
  {
    id: "124",
    name: "Decora la tua candela",
    start_date: "2024-01-15T14:00:00",
    end_date: "2024-01-15T15:00:00",
    // ...
  },
  {
    id: "125",
    name: "Decora la tua candela",
    start_date: "2024-01-20T18:00:00",
    end_date: "2024-01-20T19:00:00",
    // ...
  }
]
```

## 🎯 Obiettivo della Migrazione

Adattare il frontend per:
1. ✅ Ricevere eventi separati dalla query `getPublicEvents()`
2. ✅ Gestire eventi multipli con lo stesso nome
3. ✅ Raggruppare eventi opzionalmente per visualizzazione
4. ✅ Mantenere la compatibilità con il codice esistente

## 📝 Task di Migrazione

### 1. Aggiornare le Query degli Eventi

**Prima:**
```typescript
// Se avevi logica per gestire array di date
const event = await getPublicEvents(supabase);
// event.dates.forEach(...)
```

**Dopo:**
```typescript
// Ora ricevi un array di eventi separati
const events = await getPublicEvents(supabase, {
  from: '2024-01-01',
  to: '2024-12-31'
});

// Ogni elemento è un evento completo con una singola data/orario
events.forEach(event => {
  console.log(event.name, event.start_date, event.end_date);
});
```

### 2. Raggruppare Eventi con lo Stesso Nome (Opzionale)

Se vuoi mostrare eventi raggruppati per nome (es. card con tutte le date disponibili):

```typescript
/**
 * Raggruppa eventi con lo stesso nome
 * @param events - Array di eventi separati
 * @returns Oggetto con nome evento come chiave e array di eventi come valore
 */
function groupEventsByName(events: PublicEvent[]) {
  return events.reduce((acc, event) => {
    const key = event.title; // o event.name a seconda della struttura
    if (!acc[key]) {
      acc[key] = [];
    }
    acc[key].push(event);
    // Ordina per data
    acc[key].sort((a, b) => 
      new Date(a.start_date).getTime() - new Date(b.start_date).getTime()
    );
    return acc;
  }, {} as Record<string, PublicEvent[]>);
}

// Utilizzo
const events = await getPublicEvents(supabase);
const grouped = groupEventsByName(events);

// Risultato:
// {
//   "Decora la tua candela": [
//     { id: "123", start_date: "2024-01-15T10:00:00", ... },
//     { id: "124", start_date: "2024-01-15T14:00:00", ... },
//     { id: "125", start_date: "2024-01-20T18:00:00", ... }
//   ]
// }
```

### 3. Visualizzazione Eventi

**Opzione A: Mostra ogni evento separatamente**
```typescript
// Ogni evento appare come una card separata
function EventList({ events }: { events: PublicEvent[] }) {
  return (
    <div>
      {events.map(event => (
        <EventCard 
          key={event.id} 
          event={event}
          // Ogni card mostra un singolo evento con la sua data/orario
        />
      ))}
    </div>
  );
}
```

**Opzione B: Raggruppa eventi con lo stesso nome**
```typescript
// Mostra eventi raggruppati con tutte le date disponibili
function GroupedEventList({ events }: { events: PublicEvent[] }) {
  const grouped = groupEventsByName(events);
  
  return (
    <div>
      {Object.entries(grouped).map(([name, eventGroup]) => (
        <GroupedEventCard 
          key={name}
          name={name}
          events={eventGroup}
          // Mostra tutte le date/orari disponibili per questo evento
        />
      ))}
    </div>
  );
}
```

### 4. Filtri per Data

I filtri per data continuano a funzionare, ma ora ogni evento ha una singola data:

```typescript
// Filtra eventi per una data specifica
function filterEventsByDate(events: PublicEvent[], date: string) {
  return events.filter(event => {
    const eventDate = new Date(event.start_date).toISOString().split('T')[0];
    return eventDate === date;
  });
}

// Filtra eventi futuri
function getFutureEvents(events: PublicEvent[]) {
  const now = new Date();
  return events.filter(event => 
    new Date(event.start_date) > now
  );
}

// Filtra eventi passati
function getPastEvents(events: PublicEvent[]) {
  const now = new Date();
  return events.filter(event => 
    new Date(event.start_date) < now
  );
}
```

### 5. Prenotazioni

**Nessun cambiamento necessario**: Le prenotazioni continuano a funzionare allo stesso modo, ma ora ogni prenotazione è collegata a un evento specifico (data+orario).

```typescript
// Ogni prenotazione è già collegata a un evento specifico
async function bookEvent(eventId: string, userId: string) {
  // eventId è l'ID dell'evento specifico (es. "123" per 15/01/2024 10:00-11:00)
  const { data, error } = await supabase
    .from('event_bookings')
    .insert({
      event_id: eventId,
      user_id: userId,
      status: 'booked'
    });
  
  return { data, error };
}
```

### 6. Helper per Formattare Date/Orari

```typescript
/**
 * Formatta la data di un evento
 */
function formatEventDate(event: PublicEvent): string {
  const date = new Date(event.start_date);
  return date.toLocaleDateString('it-IT', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  });
}

/**
 * Formatta l'orario di un evento
 */
function formatEventTime(event: PublicEvent): string {
  const start = new Date(event.start_date);
  const end = event.end_date ? new Date(event.end_date) : null;
  
  const startTime = start.toLocaleTimeString('it-IT', {
    hour: '2-digit',
    minute: '2-digit'
  });
  
  if (end) {
    const endTime = end.toLocaleTimeString('it-IT', {
      hour: '2-digit',
      minute: '2-digit'
    });
    return `${startTime} - ${endTime}`;
  }
  
  return startTime;
}

/**
 * Verifica se un evento è nello stesso giorno di un altro
 */
function areEventsSameDay(event1: PublicEvent, event2: PublicEvent): boolean {
  const date1 = new Date(event1.start_date).toISOString().split('T')[0];
  const date2 = new Date(event2.start_date).toISOString().split('T')[0];
  return date1 === date2;
}
```

## 🔍 Esempio Completo: Componente Eventi

```typescript
import { getPublicEvents } from '@kalos/contract';
import { useEffect, useState } from 'react';

interface PublicEvent {
  id: string;
  title: string;
  description: string | null;
  start_date: string;
  end_date: string | null;
  registration_url: string;
  image_url: string | null;
  // ... altri campi
}

export function EventsPage() {
  const [events, setEvents] = useState<PublicEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [grouped, setGrouped] = useState(false);

  useEffect(() => {
    async function loadEvents() {
      try {
        const data = await getPublicEvents(supabase, {
          from: new Date().toISOString().split('T')[0] // Solo eventi futuri
        });
        setEvents(data as PublicEvent[]);
      } catch (error) {
        console.error('Errore nel caricamento eventi:', error);
      } finally {
        setLoading(false);
      }
    }
    loadEvents();
  }, []);

  if (loading) return <div>Caricamento...</div>;

  // Opzione 1: Mostra eventi separati
  if (!grouped) {
    return (
      <div>
        <h1>Eventi</h1>
        {events.map(event => (
          <EventCard key={event.id} event={event} />
        ))}
      </div>
    );
  }

  // Opzione 2: Mostra eventi raggruppati
  const groupedEvents = groupEventsByName(events);
  return (
    <div>
      <h1>Eventi</h1>
      {Object.entries(groupedEvents).map(([name, eventGroup]) => (
        <GroupedEventCard 
          key={name}
          name={name}
          events={eventGroup}
        />
      ))}
    </div>
  );
}

function EventCard({ event }: { event: PublicEvent }) {
  return (
    <div className="event-card">
      <h2>{event.title}</h2>
      <p>{formatEventDate(event)}</p>
      <p>{formatEventTime(event)}</p>
      <a href={event.registration_url}>Prenota</a>
    </div>
  );
}

function GroupedEventCard({ 
  name, 
  events 
}: { 
  name: string; 
  events: PublicEvent[] 
}) {
  return (
    <div className="grouped-event-card">
      <h2>{name}</h2>
      <p>Date disponibili:</p>
      <ul>
        {events.map(event => (
          <li key={event.id}>
            {formatEventDate(event)} - {formatEventTime(event)}
            <a href={event.registration_url}>Prenota questo orario</a>
          </li>
        ))}
      </ul>
    </div>
  );
}
```

## ✅ Checklist Migrazione

- [ ] Aggiornare le query degli eventi per gestire array di eventi separati
- [ ] Rimuovere logica che gestiva array di date all'interno di un evento
- [ ] Implementare raggruppamento eventi se necessario (opzionale)
- [ ] Aggiornare componenti di visualizzazione eventi
- [ ] Verificare che i filtri per data funzionino correttamente
- [ ] Testare il processo di prenotazione
- [ ] Aggiornare test se presenti
- [ ] Verificare che le notifiche/email funzionino correttamente

## 🚨 Note Importanti

1. **Backward Compatibility**: Gli eventi esistenti continuano a funzionare (hanno già `start_date` e `end_date`)
2. **API Contract**: La funzione `getPublicEvents()` ora restituisce sempre un array di eventi separati
3. **Performance**: Potrebbero esserci più record da gestire, ma le query rimangono efficienti
4. **Filtri**: I filtri per data funzionano su `start_date` (non più su array di date)

## 📚 Riferimenti

- Contract: `@kalos/contract` - funzione `getPublicEvents()`
- View Database: `public_site_events` - espone `start_date` e `end_date`
- Documentazione: Vedi `MIGRATION_FRONTEND_EVENTS.md` nel repo contract

## ❓ Domande o Problemi?

Se hai domande o riscontri problemi durante la migrazione, contatta il team di sviluppo del management app.

