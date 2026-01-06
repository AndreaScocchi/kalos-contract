# Prompt: Visualizzazione Eventi - Sito Web

## 📋 Obiettivo

Aggiornare il sito web per mostrare correttamente gli eventi e distinguere tra eventi con link esterno e eventi con prenotazione interna. Il sito web è pubblico (non autenticato), quindi NON gestisce prenotazioni, ma deve mostrare chiaramente come prenotare.

## 🎯 Funzionalità Richieste

### 1. Lista Eventi

Nella pagina lista eventi:

#### 1.1 Visualizzazione Eventi
- Mostra tutti gli eventi attivi e non soft-deleted
- Per ogni evento mostra:
  - Immagine evento
  - Nome evento
  - Data/ora (`starts_at`, `ends_at`)
  - Location
  - Descrizione
  - **Link esterno** o **"Prenota tramite app"**

#### 1.2 Pulsante Prenotazione
- **Se `link IS NOT NULL`**: 
  - Pulsante "Prenota" che apre il link esterno in nuova tab
  - Icona link esterno
  
- **Se `link IS NULL`**:
  - Testo "Prenota tramite app Kalos" o badge "Disponibile sull'app"
  - Link/button che porta alla pagina download app o alla pagina login app
  - NON permettere prenotazione diretta dal sito (solo app)

### 2. Dettaglio Evento

Nella pagina dettaglio evento:

#### 2.1 Informazioni Evento
- Mostra tutte le informazioni dell'evento
- Mostra disponibilità posti (se disponibile tramite query)
- Distingui chiaramente:
  - **Eventi con link esterno**: "Prenota su [piattaforma esterna]"
  - **Eventi con prenotazione interna**: "Prenota tramite l'app Kalos"

#### 2.2 Call-to-Action
- **Se `link IS NOT NULL`**: 
  - Pulsante primario grande "Prenota Ora" che apre link
  - Mostra eventualmente badge con nome piattaforma (es. "Eventbrite")
  
- **Se `link IS NULL`**:
  - Pulsante "Scarica l'app per prenotare" o "Accedi all'app"
  - Sezione informativa: "Le prenotazioni per questo evento sono gestite tramite l'app Kalos. Scarica l'app o accedi per prenotare."

### 3. Disponibilità Posti (Opzionale)

Se vuoi mostrare disponibilità posti sul sito:
- Mostra solo se `capacity IS NOT NULL`
- Mostra "X posti disponibili" o "Pochi posti rimasti" o "Pieno"
- **NOTA**: Questo richiede query autenticate o view pubblica con conteggio. Verifica se esiste una view pubblica o implementa una query server-side.

## 📚 API e Funzioni da Utilizzare

### Da `@kalos/contract`:

```typescript
import {
  getPublicEvents,
  type GetPublicEventsParams,
} from '@kalos/contract';

// Recupera eventi pubblici
const events = await getPublicEvents(supabase, {
  from: new Date().toISOString().split('T')[0], // Solo eventi futuri
  to: '2024-12-31', // Opzionale
});
```

### Struttura Evento Pubblico:

La funzione `getPublicEvents` ritorna eventi dalla view `public_site_events` che contiene:
- `id`: ID evento
- `title`: Nome evento (alias di `name`)
- `description`: Descrizione
- `start_date`: Data/ora inizio
- `end_date`: Data/ora fine (nullable)
- `location`: Location
- `image_url`: URL immagine
- `registration_url`: URL registrazione (alias di `link`)
- `capacity`: Capacità (nullable)
- `price`: Prezzo in centesimi
- `currency`: Valuta
- `is_active`: Se attivo

### Query per Evento Specifico:

```typescript
// Recupera un evento specifico
const { data: event } = await supabase
  .from('events')
  .select('*')
  .eq('id', eventId)
  .eq('is_active', true)
  .is('deleted_at', null)
  .single();
```

## 🎨 UI/UX Suggerimenti

1. **Distinzione Visiva**:
   - Eventi con link esterno: badge "Prenota esternamente" o icona link
   - Eventi con prenotazione app: badge "Prenota sull'app" o icona app

2. **Pulsanti CTA**:
   - Link esterno: pulsante primario colorato con icona link esterno
   - App: pulsante secondario/outline con icona app/smartphone

3. **Messaggi Informativi**:
   - Per eventi app: "Le prenotazioni per questo evento sono disponibili solo tramite l'app Kalos. Scarica l'app o accedi se sei già registrato."
   - Per eventi esterni: "Prenota direttamente su [piattaforma] cliccando il pulsante qui sotto."

4. **Layout**:
   - Card eventi chiare con immagine prominente
   - CTA ben visibile e accessibile
   - Informazioni data/ora/location ben formattate

## ✅ Checklist Implementazione

- [ ] Aggiornare pagina lista eventi per distinguere link esterno vs app
- [ ] Aggiornare pagina dettaglio evento con CTA appropriato
- [ ] Aggiungere badge/icone per distinguere tipi di prenotazione
- [ ] Implementare link esterno che apre in nuova tab
- [ ] Implementare link/pulsante "Prenota sull'app" che porta a download/login
- [ ] Aggiungere messaggi informativi chiari
- [ ] Testare visualizzazione su mobile e desktop
- [ ] Verificare che tutti gli eventi siano visualizzati correttamente
- [ ] Testare link esterni (verifica che siano validi)

## 🔍 Note Importanti

1. **Nessuna Prenotazione Diretta**: Il sito web NON deve gestire prenotazioni direttamente. Solo mostrare link esterni o reindirizzare all'app.

2. **Link NULL**: Se `link IS NULL`, significa che la prenotazione è gestita internamente. Sul sito, mostra solo informazioni e reindirizza all'app.

3. **Query Pubbliche**: Usa sempre `getPublicEvents` che accede alla view pubblica `public_site_events`. Non fare query dirette sulla tabella `events` (richiede autenticazione per RLS).

4. **Disponibilità Posti**: Se vuoi mostrare disponibilità posti sul sito pubblico, hai due opzioni:
   - **Opzione A**: Non mostrare (più semplice)
   - **Opzione B**: Creare una view pubblica con conteggio (richiede migration)

5. **SEO**: Assicurati che gli eventi siano indicizzati correttamente e che i link esterni siano accessibili.

6. **Accessibilità**: I pulsanti e link devono essere accessibili (WCAG compliance), con testi alternativi e focus states.

7. **Performance**: Considera paginazione o lazy loading se ci sono molti eventi.

