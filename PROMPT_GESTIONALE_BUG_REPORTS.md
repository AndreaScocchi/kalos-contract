# Prompt: Sistema Gestione Bug Reports - Gestionale

## 📋 Obiettivo

Implementare una sezione nel gestionale per permettere agli admin di visualizzare e gestire tutte le segnalazioni bug (sia da clienti che da operatori). Solo gli admin possono accedere a questa sezione. Gli admin possono visualizzare tutti i bug, vedere i dettagli, e aggiornare lo status.

## 🎯 Funzionalità Richieste

### 1. Sezione Bug Reports (Admin Only)

Aggiungere una nuova sezione nel gestionale accessibile **solo agli admin**:
- Menu principale / Navigazione laterale
- Posizionamento: suggerito nella sezione "Amministrazione" o "Supporto"
- Icona appropriata (es. Bug, Alert, MessageQuestion)
- La sezione deve essere **nascosta** per utenti non admin (operator, user, finance)

#### 1.1 Lista Tutti i Bug

Creare una schermata che mostra **tutti** i bug segnalati:
- Mostrare bug da clienti (con account) e da operatori
- Ordinare per data di creazione (più recenti prima) o per status
- Filtri disponibili:
  - **Status**: Filtro dropdown per status (Tutti, Open, In Progress, Resolved, Closed)
  - **Tipo**: Filtro per tipo di creatore (Tutti, Clienti, Operatori)
  - **Periodo**: Filtro per data (Ultimi 7 giorni, Ultimo mese, Tutti)
- Mostrare per ogni bug:
  - Titolo
  - Status con badge colorato:
    - `open`: rosso/arancione
    - `in_progress`: giallo/blu
    - `resolved`: verde
    - `closed`: grigio
  - Creatore: nome del cliente o operatore
  - Data di creazione
  - Anteprima immagine (se presente)
  - Badge "Nuovo" se creato nelle ultime 24 ore
- Permettere di aprire il dettaglio di un bug
- Paginazione se ci sono molti bug (suggerito 20-50 per pagina)

#### 1.2 Dettaglio Bug

Creare una schermata di dettaglio che mostra tutte le informazioni del bug:

**Informazioni Bug:**
- Titolo completo
- Descrizione completa
- Immagine (se presente) con possibilità di ingrandire
- Status attuale con badge

**Informazioni Creatore:**
- Nome del creatore (cliente o operatore)
- Tipo: "Cliente" o "Operatore"
- Se cliente: link al profilo cliente (se disponibile)
- Se operatore: nome operatore

**Informazioni Temporali:**
- Data di creazione formattata
- Data di ultimo aggiornamento (se diversa dalla creazione)

**Azioni Admin:**
- Dropdown o pulsanti per cambiare status:
  - Open → In Progress
  - In Progress → Resolved
  - Resolved → Closed
  - Closed → Open (per riaprire se necessario)
- Conferma prima di cambiare status (dialog o conferma inline)
- Messaggio di successo dopo l'aggiornamento

#### 1.3 Form Modifica Status

Quando l'admin cambia lo status:
- Mostrare dropdown o pulsanti con tutti gli status disponibili
- Evidenziare lo status corrente
- Conferma prima di salvare (opzionale ma consigliato)
- Salvare l'aggiornamento nel database
- Aggiornare la UI immediatamente dopo il salvataggio
- Mostrare loading state durante il salvataggio

### 2. Integrazione Database

#### 2.1 Query Bug Reports

Utilizzare il contract `@kalos/contract` per interagire con la tabella `bug_reports`:

```typescript
import { createClient } from '@kalos/contract/supabase';

const supabase = createClient();

// Ottenere tutti i bug (solo admin può vedere tutti)
const { data: bugs, error } = await supabase
  .from('bug_reports')
  .select(`
    *,
    created_by_user_id,
    created_by_client_id,
    profiles:created_by_user_id(id, full_name, email),
    clients:created_by_client_id(id, full_name, email)
  `)
  .is('deleted_at', null)
  .order('created_at', { ascending: false });

// Filtrare per status
const { data: openBugs } = await supabase
  .from('bug_reports')
  .select('*')
  .eq('status', 'open')
  .is('deleted_at', null)
  .order('created_at', { ascending: false });

// Aggiornare status di un bug (solo admin)
const { data, error } = await supabase
  .from('bug_reports')
  .update({
    status: 'in_progress',
    updated_at: new Date().toISOString()
  })
  .eq('id', bugId)
  .select()
  .single();
```

#### 2.2 Visualizzazione Immagini Bug Reports

**IMPORTANTE**: Il bucket `bug-reports` è **privato**, quindi non si può usare `getPublicUrl()`. 
Bisogna generare un **signed URL** per visualizzare le immagini.

Il campo `image_url` nel database può contenere:
- Un **path relativo** (es: `{user_id}/{timestamp}.jpg`) - caso più comune
- Un **signed URL completo** (se salvato dall'app) - potrebbe essere scaduto

**Soluzione**: Creare una funzione helper che genera sempre un signed URL valido:

```typescript
/**
 * Ottiene l'URL dell'immagine del bug report.
 * Se image_url è un path relativo, genera un signed URL.
 * Se è già un URL completo, lo restituisce (ma potrebbe essere scaduto).
 */
async function getBugReportImageUrl(
  supabase: SupabaseClient,
  imageUrl: string | null
): Promise<string | null> {
  if (!imageUrl) return null;

  // Se è già un URL completo (contiene http:// o https://), restituiscilo
  // Nota: potrebbe essere scaduto se è un signed URL vecchio
  if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
    return imageUrl;
  }

  // Altrimenti è un path relativo, genera un signed URL
  // Il path è già nel formato corretto: {user_id}/{filename}
  const { data, error } = await supabase.storage
    .from('bug-reports')
    .createSignedUrl(imageUrl, 3600); // 1 ora di validità

  if (error) {
    console.error('Errore generazione signed URL:', error);
    return null;
  }

  return data.signedUrl;
}

// Esempio di utilizzo nel componente:
const BugReportImage = ({ imageUrl }: { imageUrl: string | null }) => {
  const [imageSrc, setImageSrc] = useState<string | null>(null);
  const supabase = useSupabaseClient();

  useEffect(() => {
    if (imageUrl) {
      getBugReportImageUrl(supabase, imageUrl).then(setImageSrc);
    }
  }, [imageUrl, supabase]);

  if (!imageSrc) return null;

  return (
    <img 
      src={imageSrc} 
      alt="Screenshot del bug" 
      className="max-w-full rounded-lg"
    />
  );
};
```

**Alternativa più semplice**: Se preferisci, puoi sempre rigenerare il signed URL quando serve:

```typescript
// Nel componente, quando serve visualizzare l'immagine:
const displayImage = async (imagePath: string | null) => {
  if (!imagePath) return null;
  
  // Se è un URL completo, usalo direttamente
  if (imagePath.startsWith('http')) {
    return imagePath;
  }
  
  // Altrimenti genera signed URL
  const { data } = await supabase.storage
    .from('bug-reports')
    .createSignedUrl(imagePath, 3600);
  
  return data?.signedUrl || null;
};
```

#### 2.3 Verifica Ruolo Admin

Prima di mostrare la sezione, verificare che l'utente sia admin:

```typescript
// Verificare ruolo admin
const { data: profile } = await supabase
  .from('profiles')
  .select('role')
  .eq('id', userId)
  .single();

const isAdmin = profile?.role === 'admin';

// Oppure usare la funzione RPC se disponibile
const { data: isAdmin } = await supabase.rpc('is_admin');
```

### 3. UI/UX Suggerimenti

1. **Navigazione**:
   - Aggiungere voce "Bug Reports" o "Segnalazioni Bug" nel menu admin
   - Mostrare badge con conteggio bug aperti (es. "Bug Reports (5)")
   - Icona appropriata

2. **Lista Bug**:
   - Tabella o lista card con tutte le informazioni
   - Filtri ben visibili in alto
   - Badge colorati per status
   - Badge "Nuovo" per bug recenti
   - Skeleton loading durante il caricamento
   - Empty state quando non ci sono bug: "Nessun bug segnalato"

3. **Dettaglio Bug**:
   - Layout a due colonne (informazioni bug a sinistra, azioni a destra)
   - Immagine cliccabile per fullscreen
   - Formattazione data user-friendly
   - Sezione creatore ben evidenziata
   - Pulsanti azione status ben visibili

4. **Modifica Status**:
   - Dropdown o gruppo di pulsanti per selezionare nuovo status
   - Conferma prima di salvare (dialog)
   - Loading state durante il salvataggio
   - Toast/notifica di successo dopo il salvataggio
   - Aggiornamento immediato della UI

5. **Accessibilità**:
   - Label appropriate per screen reader
   - Contrasto colori adeguato per i badge status
   - Focus states visibili
   - Keyboard navigation

6. **Performance**:
   - Paginazione per liste lunghe
   - Lazy loading delle immagini
   - Debounce sui filtri se necessario

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
  // Joined data
  profiles?: {
    id: string;
    full_name: string | null;
    email: string | null;
  } | null;
  clients?: {
    id: string;
    full_name: string;
    email: string | null;
  } | null;
}
```

### Status Enum

```typescript
type BugStatus = 'open' | 'in_progress' | 'resolved' | 'closed';

const STATUS_LABELS: Record<BugStatus, string> = {
  open: 'Aperto',
  in_progress: 'In Lavorazione',
  resolved: 'Risolto',
  closed: 'Chiuso'
};

const STATUS_COLORS: Record<BugStatus, string> = {
  open: 'red',
  in_progress: 'yellow',
  resolved: 'green',
  closed: 'gray'
};
```

## ✅ Checklist Implementazione

- [ ] Verificare che solo gli admin possano accedere alla sezione
- [ ] Nascondere la sezione per utenti non admin
- [ ] Creare schermata lista tutti i bug
- [ ] Implementare query per ottenere tutti i bug con join a profiles e clients
- [ ] Implementare filtri (status, tipo, periodo)
- [ ] Creare schermata dettaglio bug
- [ ] Implementare form modifica status
- [ ] Aggiungere navigazione alla sezione bug (menu admin)
- [ ] Implementare badge colorati per status
- [ ] Aggiungere badge "Nuovo" per bug recenti
- [ ] Implementare paginazione
- [ ] Aggiungere empty state quando non ci sono bug
- [ ] Aggiungere loading states
- [ ] Implementare conferma prima di cambiare status
- [ ] Testare visualizzazione lista e dettaglio
- [ ] Testare modifica status
- [ ] Verificare che solo gli admin possano vedere tutti i bug
- [ ] Testare filtri e paginazione

## 🔍 Note Importanti

1. **Sicurezza**: Solo gli admin possono vedere tutti i bug. Le RLS policies del database garantiscono già questo, ma è buona pratica verificare anche lato client e nascondere la sezione per utenti non admin.

2. **RLS**: Le RLS policies permettono solo agli admin di vedere tutti i bug. Gli operatori e gli utenti normali non possono vedere bug di altri.

3. **Status Updates**: Solo gli admin possono aggiornare lo status dei bug. Questo è garantito dalle RLS policies.

4. **Creatore Info**: Quando si mostra il creatore, verificare se è `created_by_user_id` (cliente con account) o `created_by_client_id` (cliente senza account o operatore). Mostrare le informazioni appropriate.

5. **Performance**: Se ci sono molti bug, implementare paginazione. Considerare anche la lazy loading delle immagini.

6. **Type Safety**: Utilizzare i tipi da `@kalos/contract` per type safety completo.

7. **Error Handling**: Gestire correttamente gli errori di query e aggiornamento, mostrando messaggi chiari.

8. **Real-time Updates**: Considerare l'uso di Supabase Realtime per aggiornamenti in tempo reale quando un bug viene modificato (opzionale ma utile).

9. **Notifications**: Considerare di mostrare notifiche quando vengono creati nuovi bug (opzionale ma utile per admin).

10. **Export**: Considerare la possibilità di esportare la lista bug in CSV/Excel (opzionale, feature futura).

11. **Storage Policies**: Se gli admin devono caricare immagini per i bug reports (es. per aggiungere screenshot durante la gestione), assicurarsi che le policy di storage siano configurate correttamente. La migration `20260108000003_add_admin_storage_policies.sql` aggiunge le policy necessarie per permettere agli admin di caricare file nel bucket `bug-reports`. Senza queste policy, gli admin riceveranno l'errore "new row violates row-level security policy" quando provano a caricare immagini.

12. **Visualizzazione Immagini**: Il bucket `bug-reports` è **privato**, quindi non si può usare `getPublicUrl()`. Per visualizzare le immagini nel gestionale, bisogna sempre generare un **signed URL** usando `createSignedUrl()`. Il campo `image_url` nel database può contenere un path relativo (es: `{user_id}/{filename}`) o un URL completo. Vedi sezione 2.2 per il codice di esempio.

