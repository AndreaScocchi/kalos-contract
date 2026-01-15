# Prompt: Sistema Segnalazione Bug - App Cliente

## 📋 Obiettivo

Implementare una sezione nell'app clienti per permettere agli utenti di segnalare bug. Gli utenti possono creare segnalazioni con titolo, descrizione e opzionalmente un'immagine/screenshot. Le segnalazioni sono visibili solo all'utente che le ha create (non possono vedere quelle di altri utenti).

## 🎯 Funzionalità Richieste

### 1. Sezione Segnalazione Bug

Aggiungere una nuova sezione nell'app per la segnalazione bug. La sezione può essere accessibile da:
- Menu principale / Impostazioni
- Profilo utente
- Menu laterale / Drawer

#### 1.1 Lista Bug Segnalati

Creare una schermata che mostra la lista dei bug segnalati dall'utente corrente:
- Mostrare solo i bug creati dall'utente autenticato
- Ordinare per data di creazione (più recenti prima)
- Mostrare per ogni bug:
  - Titolo
  - Status (open, in_progress, resolved, closed) con badge colorato
  - Data di creazione
  - Anteprima immagine (se presente)
- Permettere di aprire il dettaglio di un bug per vedere tutte le informazioni

#### 1.2 Form Creazione Bug

Creare un form per segnalare un nuovo bug con i seguenti campi:

**Campi Obbligatori:**
- **Titolo**: Campo di testo (input) con label "Titolo" o "Titolo del bug"
  - Placeholder: es. "Errore durante la prenotazione"
  - Validazione: campo obbligatorio, minimo 3 caratteri

- **Descrizione**: Campo di testo multilinea (textarea) con label "Descrizione"
  - Placeholder: es. "Descrivi il problema in dettaglio..."
  - Validazione: campo obbligatorio, minimo 10 caratteri
  - Suggerimento: "Più dettagli fornisci, più facile sarà risolvere il problema"

**Campi Opzionali:**
- **Immagine/Screenshot**: Upload immagine opzionale ma consigliato
  - Pulsante "Aggiungi screenshot" o "Carica immagine"
  - Supporto per selezione da galleria o scatto foto
  - Preview dell'immagine selezionata
  - Possibilità di rimuovere l'immagine prima dell'invio
  - Messaggio: "Aggiungere uno screenshot è molto utile per capire il problema"
  - Formati supportati: JPG, PNG
  - Dimensione massima: suggerito 5MB

#### 1.3 Dettaglio Bug

Creare una schermata di dettaglio che mostra:
- Titolo completo
- Descrizione completa
- Status con badge colorato:
  - `open`: rosso/arancione
  - `in_progress`: giallo/blu
  - `resolved`: verde
  - `closed`: grigio
- Immagine (se presente) con possibilità di ingrandire
- Data di creazione formattata
- Data di ultimo aggiornamento (se diversa dalla creazione)

### 2. Integrazione Database

#### 2.1 Query Bug Reports

Utilizzare il contract `@kalos/contract` per interagire con la tabella `bug_reports`:

```typescript
import { createClient } from '@kalos/contract/supabase';

const supabase = createClient();

// Creare un nuovo bug report
const { data, error } = await supabase
  .from('bug_reports')
  .insert({
    title: 'Titolo del bug',
    description: 'Descrizione dettagliata...',
    image_url: 'https://...', // URL dell'immagine caricata su Supabase Storage
    created_by_user_id: user.id, // L'utente corrente (auth.uid())
    status: 'open'
  })
  .select()
  .single();

// Ottenere i bug dell'utente corrente
const { data: bugs, error } = await supabase
  .from('bug_reports')
  .select('*')
  .eq('created_by_user_id', user.id)
  .is('deleted_at', null)
  .order('created_at', { ascending: false });
```

#### 2.2 Upload Immagine

Per caricare l'immagine su Supabase Storage:

**IMPORTANTE**: Il bucket `bug-reports` è **privato**, quindi bisogna usare `createSignedUrl()` invece di `getPublicUrl()`.

```typescript
// 1. Preparare il file e il path
// Il path NON include "bug-reports/" perché viene specificato in .from()
const fileExt = image.name.split('.').pop();
const fileName = `${Date.now()}.${fileExt}`;
const filePath = `${user.id}/${fileName}`; // Formato: {user_id}/{filename}

// 2. Caricare l'immagine su Supabase Storage
const { data: uploadData, error: uploadError } = await supabase.storage
  .from('bug-reports') // Bucket da creare in Supabase Storage
  .upload(filePath, image, {
    cacheControl: '3600',
    upsert: false
  });

if (uploadError) {
  console.error('Errore upload immagine:', uploadError);
  throw uploadError;
}

// 3. Ottenere l'URL firmato (signed URL) perché il bucket è privato
// L'URL firmato è valido per un periodo limitato (es. 1 anno = 31536000 secondi)
const { data: signedUrlData, error: signedUrlError } = await supabase.storage
  .from('bug-reports')
  .createSignedUrl(filePath, 31536000); // 1 anno in secondi

if (signedUrlError) {
  console.error('Errore creazione signed URL:', signedUrlError);
  throw signedUrlError;
}

// 4. Usare il signed URL nel campo image_url del bug report
const imageUrl = signedUrlData.signedUrl;
```

**Alternativa**: Salvare solo il path relativo e generare l'URL quando serve:

```typescript
// Dopo l'upload, salva solo il path nel database
image_url: filePath, // Es: "user-id/1234567890.jpg"

// Quando serve visualizzare l'immagine, genera il signed URL:
const getImageUrl = async (imagePath: string | null) => {
  if (!imagePath) return null;
  
  const { data, error } = await supabase.storage
    .from('bug-reports')
    .createSignedUrl(imagePath, 31536000);
  
  return error ? null : data.signedUrl;
};
```

**Nota Importante**: 
- Il bucket `bug-reports` è **privato** (non pubblico), quindi bisogna usare `createSignedUrl()` invece di `getPublicUrl()`.
- Assicurarsi che il bucket esista in Supabase Storage con le policy corrette:
  - INSERT: autenticati possono caricare solo nella propria cartella (`${user.id}/*`)
  - SELECT: autenticati possono leggere solo dalla propria cartella
- Il path del file deve essere esattamente `{user_id}/{filename}` (senza il prefisso `bug-reports/`).

### 3. UI/UX Suggerimenti

1. **Navigazione**:
   - Aggiungere voce "Segnala anomalia" o "Supporto" nel menu principale
   - Icona appropriata (es. Bug, Alert, MessageQuestion)

2. **Form Creazione**:
   - Validazione in tempo reale dei campi
   - Messaggi di errore chiari
   - Loading state durante il salvataggio
   - Messaggio di successo dopo la creazione
   - Redirect alla lista bug dopo il salvataggio

3. **Lista Bug**:
   - Empty state quando non ci sono bug: "Nessun bug segnalato"
   - Pull-to-refresh per aggiornare la lista
   - Badge colorati per lo status
   - Skeleton loading durante il caricamento

4. **Dettaglio Bug**:
   - Immagine cliccabile per fullscreen
   - Formattazione data user-friendly (es. "2 giorni fa")
   - Badge status ben visibile

5. **Accessibilità**:
   - Label appropriate per screen reader
   - Contrasto colori adeguato per i badge status
   - Focus states visibili

## 📚 Struttura Dati

### Bug Report Type

```typescript
interface BugReport {
  id: string;
  title: string;
  description: string;
  image_url: string | null;
  created_by_user_id: string | null;
  created_by_client_id: string | null;
  status: 'open' | 'in_progress' | 'resolved' | 'closed';
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}
```

### Status Enum

```typescript
type BugStatus = 'open' | 'in_progress' | 'resolved' | 'closed';
```

## ✅ Checklist Implementazione

- [ ] Creare schermata lista bug segnalati
- [ ] Implementare query per ottenere bug dell'utente corrente
- [ ] Creare form creazione bug con validazione
- [ ] Implementare upload immagine su Supabase Storage
- [ ] Creare bucket `bug-reports` in Supabase Storage con policy corrette
- [ ] Implementare schermata dettaglio bug
- [ ] Aggiungere navigazione alla sezione bug (menu/drawer)
- [ ] Implementare badge colorati per status
- [ ] Aggiungere empty state quando non ci sono bug
- [ ] Implementare pull-to-refresh
- [ ] Aggiungere loading states
- [ ] Testare creazione bug con e senza immagine
- [ ] Testare visualizzazione lista e dettaglio
- [ ] Verificare che gli utenti vedano solo i propri bug

## 🔍 Note Importanti

1. **Privacy**: Gli utenti possono vedere SOLO i propri bug. Non devono mai vedere bug di altri utenti.

2. **Storage**: Assicurarsi che il bucket `bug-reports` in Supabase Storage abbia le policy corrette per limitare l'accesso alle proprie immagini.

3. **RLS**: Le RLS policies del database garantiscono già che gli utenti vedano solo i propri bug. Non è necessario filtrare ulteriormente lato client, ma è buona pratica farlo comunque.

4. **Status**: Gli utenti possono solo CREARE bug con status `open`. Solo gli admin possono cambiare lo status (lato gestionale).

5. **Immagine Opzionale**: Anche se l'immagine è opzionale, è fortemente consigliata. Mostrare un messaggio che incoraggia l'utente ad aggiungere uno screenshot.

6. **Type Safety**: Utilizzare i tipi da `@kalos/contract` per type safety completo.

7. **Error Handling**: Gestire correttamente gli errori di upload immagine e creazione bug, mostrando messaggi chiari all'utente.

8. **Performance**: Considerare la paginazione se ci sono molti bug (attualmente non necessaria, ma buona pratica per il futuro).

