# Prompt per Migrazione Frontend Eventi

Copia e incolla questo prompt nel progetto del sito web per avviare la migrazione:

---

## 🎯 Obiettivo

Adattare il frontend per gestire la nuova struttura degli eventi dove **ogni combinazione data+orario è un evento separato** nel database, invece di un array di date all'interno di un singolo evento.

## 📋 Cambiamenti Richiesti

### 1. Query degli Eventi
- La funzione `getPublicEvents()` ora restituisce un **array di eventi separati**
- Ogni evento ha una singola `start_date` e `end_date` (non più array di date)
- Aggiornare il codice che chiama `getPublicEvents()` per gestire array di eventi

### 2. Visualizzazione Eventi
- **Opzione A**: Mostrare ogni evento come card separata (ognuno con la sua data/orario)
- **Opzione B**: Raggruppare eventi con lo stesso nome e mostrare tutte le date disponibili

### 3. Raggruppamento (Opzionale)
Se serve raggruppare eventi con lo stesso nome:
```typescript
function groupEventsByName(events) {
  return events.reduce((acc, event) => {
    const key = event.title;
    if (!acc[key]) acc[key] = [];
    acc[key].push(event);
    acc[key].sort((a, b) => 
      new Date(a.start_date) - new Date(b.start_date)
    );
    return acc;
  }, {});
}
```

### 4. Filtri per Data
I filtri continuano a funzionare, ma ora ogni evento ha una singola data:
```typescript
// Filtra eventi futuri
const futureEvents = events.filter(e => 
  new Date(e.start_date) > new Date()
);
```

### 5. Prenotazioni
Nessun cambiamento: ogni prenotazione è già collegata a un evento specifico (data+orario)

## ✅ Task Checklist

- [ ] Aggiornare query `getPublicEvents()` per gestire array di eventi separati
- [ ] Rimuovere logica che gestiva array di date dentro un evento
- [ ] Implementare raggruppamento eventi se necessario (opzionale)
- [ ] Aggiornare componenti di visualizzazione eventi
- [ ] Verificare filtri per data
- [ ] Testare prenotazioni
- [ ] Aggiornare test se presenti

## 📚 Documentazione Completa

Vedi `MIGRATION_FRONTEND_EVENTS.md` nel repo `@kalos/contract` per:
- Esempi di codice completi
- Helper functions per formattare date/orari
- Componenti React di esempio
- Best practices

## 🔍 Esempio Base

```typescript
// Prima (se avevi logica per array di date)
const event = await getPublicEvents(supabase);
// event.dates.forEach(...)

// Dopo (ora ricevi array di eventi separati)
const events = await getPublicEvents(supabase, {
  from: '2024-01-01'
});

// Ogni elemento è un evento completo con una singola data/orario
events.forEach(event => {
  console.log(event.title, event.start_date, event.end_date);
});
```

---

**Nota**: La struttura del database è già aggiornata. Il contract `@kalos/contract` è stato aggiornato per supportare questa nuova struttura. Basta adattare il frontend per gestire eventi separati invece di array di date.

