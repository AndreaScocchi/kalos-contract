# Fix: Cancellazione Prenotazioni Eventi - Gestionale

## 🐛 Problema Risolto

Quando si tentava di cancellare una prenotazione evento dal gestionale, si verificava il seguente errore:

```
Error canceling booking: 
{
  code: '42703', 
  message: 'record "new" has no field "updated_at"'
}
```

**Causa**: La tabella `event_bookings` aveva un trigger che aggiornava automaticamente il campo `updated_at` durante gli UPDATE, ma la tabella non aveva questo campo definito.

## ✅ Soluzione Applicata

È stata creata una migration che aggiunge il campo `updated_at` alla tabella `event_bookings`:

- **Migration**: `20260106180000_add_updated_at_to_event_bookings.sql`
- **Modifica**: Aggiunta colonna `updated_at timestamp with time zone DEFAULT now() NOT NULL`
- **Comportamento**: Il campo viene aggiornato automaticamente dal trigger `update_event_bookings_updated_at` ad ogni UPDATE

## 🔄 Cosa Cambia per il Gestionale

### Usare la RPC `staffCancelEventBooking` (Consigliato)

Per maggiore sicurezza e coerenza, è consigliato usare la funzione RPC dedicata:

```typescript
import { staffCancelEventBooking } from '@kalos/contract';

// Cancellazione tramite RPC (consigliato)
const result = await staffCancelEventBooking(supabase, {
  bookingId: bookingId,
});

if (result.ok) {
  console.log('Prenotazione cancellata con successo');
} else {
  console.error('Errore:', result.reason);
  // Possibili reason: 'UNAUTHORIZED', 'BOOKING_NOT_FOUND', 'ALREADY_CANCELED'
}
```

**Vantaggi della RPC**:
- Verifica automatica che l'utente sia staff
- Validazione dello stato della prenotazione
- Gestione degli errori più chiara
- Coerenza con il resto del sistema

## 📋 Checklist Verifica

Dopo che la migration è stata applicata al database, verificare:

- [ ] La cancellazione di una prenotazione evento funziona senza errori
- [ ] Il campo `updated_at` viene aggiornato automaticamente quando si modifica lo status
- [ ] Non ci sono più errori `42703` nella console del browser
- [ ] Le prenotazioni cancellate mostrano lo status corretto (`canceled`)

## 🧪 Test Consigliati

1. **Test Cancellazione Base**:
   - Aprire il dettaglio di un evento con prenotazioni
   - Cliccare "Annulla" su una prenotazione con status `booked`
   - Verificare che la cancellazione avvenga senza errori
   - Verificare che lo status cambi a `canceled`

2. **Test Aggiornamento Status**:
   - Modificare lo status di una prenotazione (es. da `booked` a `attended`)
   - Verificare che `updated_at` venga aggiornato automaticamente

3. **Test Errori**:
   - Verificare che vengano mostrati messaggi di errore appropriati se:
     - La prenotazione non esiste
     - L'utente non è autorizzato
     - La prenotazione è già cancellata

## 🔍 Verifica Migration Applicata

Per verificare che la migration sia stata applicata correttamente, eseguire questa query:

```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'event_bookings'
  AND column_name = 'updated_at';
```

Dovrebbe restituire:
- `column_name`: `updated_at`
- `data_type`: `timestamp with time zone`
- `is_nullable`: `NO`
- `column_default`: `now()`

## 📝 Note Tecniche

1. **Trigger Automatico**: Il trigger `update_event_bookings_updated_at` aggiorna automaticamente `updated_at` ad ogni UPDATE sulla tabella. Non è necessario includere questo campo manualmente nelle query UPDATE.

2. **Compatibilità**: Se state usando PATCH diretto, continuerà a funzionare. Se preferite, potete migrare all'uso della RPC `staffCancelEventBooking` per maggiore sicurezza.

3. **Tipi TypeScript**: Dopo l'applicazione della migration, i tipi TypeScript verranno aggiornati automaticamente quando rigenerate i tipi da Supabase. Il campo `updated_at` sarà disponibile nel tipo `event_bookings`.

4. **Query Esistenti**: Le query esistenti che selezionano da `event_bookings` possono includere `updated_at` se necessario, ma non è obbligatorio.

## 🚀 Prossimi Passi

1. **Applicare la Migration**: Assicurarsi che la migration `20260106180000_add_updated_at_to_event_bookings.sql` sia stata applicata al database di produzione/staging.

2. **Testare**: Eseguire i test sopra descritti per verificare che tutto funzioni correttamente.

3. **Opzionale - Migrare a RPC**: Se attualmente usate PATCH diretto, considerare di migrare all'uso della RPC `staffCancelEventBooking` per maggiore sicurezza e coerenza.

4. **Aggiornare Tipi**: Se necessario, rigenerare i tipi TypeScript da Supabase per includere il nuovo campo `updated_at`.

## ❓ Domande Frequenti

**Q: Devo modificare il mio codice esistente?**  
A: No, se usate PATCH diretto continuerà a funzionare. Il campo `updated_at` viene gestito automaticamente dal trigger.

**Q: Posso continuare a usare PATCH diretto?**  
A: Sì, funziona correttamente. Tuttavia, è consigliato usare la RPC `staffCancelEventBooking` per maggiore sicurezza.

**Q: Il campo `updated_at` è obbligatorio nelle query SELECT?**  
A: No, è opzionale. Potete includerlo se necessario per mostrare quando è stata modificata l'ultima volta la prenotazione.

**Q: Cosa succede se la migration non è ancora applicata?**  
A: Continuerete a vedere l'errore `42703`. Assicuratevi che la migration sia stata applicata al database.

