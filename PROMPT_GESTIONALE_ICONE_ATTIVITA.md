# Prompt: Gestione Selezione Icone Attività - Gestionale

## 📋 Obiettivo

Aggiungere la possibilità di selezionare l'icona per ogni attività nel dialog di creazione/modifica attività del gestionale. La selezione deve avvenire tramite un campo di testo per inserire il nome esatto dell'icona, un pulsante per aprire il sito iconsax-react, e una preview dell'icona selezionata.

## 🎯 Funzionalità Richieste

### 1. Dialog Creazione/Modifica Attività

Nel dialog di creazione/modifica attività, aggiungere una nuova sezione per la selezione dell'icona:

#### 1.1 Posizionamento
- La sezione icona deve essere posizionata **subito sopra** la sezione di selezione del colore
- Mantenere la stessa struttura e stile delle altre sezioni del form

#### 1.2 Campo Nome Icona
- Campo di testo (input) per inserire il nome esatto dell'icona
- Label: "Nome Icona" o "Icona Attività"
- Placeholder: es. "Activity", "Calendar", "Star" (esempi di nomi icone)
- Validazione: il campo è opzionale (può essere lasciato vuoto)
- Helper text: "Inserisci il nome esatto dell'icona da iconsax-react"

#### 1.3 Pulsante Link Iconsax
- Pulsante/secondary button con testo "Sfoglia icone" o "Apri iconsax-react"
- Icona link esterno (se disponibile)
- Al click, apre il link `https://iconsax-react.pages.dev/` in una nuova tab/finestra
- Posizionato accanto o sotto il campo nome icona

#### 1.4 Preview Icona
- Mostrare una preview dell'icona selezionata quando:
  - Il campo nome icona contiene un valore valido
  - L'icona esiste nella libreria iconsax-react
- Dimensioni preview: suggerito 48x48px o 64x64px
- Colore: utilizzare il colore dell'attività (se definito) o un colore di default
- Se l'icona non esiste o il campo è vuoto: mostrare un placeholder o icona di default
- Posizionato sotto il campo nome icona e il pulsante

### 2. Logica Selezione Icona

#### 2.1 Validazione Nome Icona
- Quando l'utente inserisce un nome icona:
  1. Verificare se l'icona esiste nella libreria `iconsax-react`
  2. Se esiste: mostrare la preview
  3. Se non esiste: mostrare un messaggio di errore/warning (es. "Icona non trovata")
  4. Se campo vuoto: nascondere preview o mostrare placeholder

#### 2.2 Salvataggio
- Salvare il valore del campo `icon_name` nel database quando si salva l'attività
- Se il campo è vuoto, salvare `null`
- Non validare obbligatoriamente l'esistenza dell'icona (permettere di salvare anche se l'icona non esiste, l'app gestirà il fallback)

### 3. Caricamento Dati Esistenti

Quando si modifica un'attività esistente:
- Pre-compilare il campo nome icona con il valore di `activity.icon_name` (se presente)
- Mostrare la preview dell'icona se `icon_name` è presente e valido

## 📚 API e Struttura Dati

### Struttura Attività

```typescript
interface Activity {
  id: string;
  name: string;
  description: string | null;
  discipline: string;
  color: string | null;
  icon_name: string | null; // <-- NUOVO CAMPO
  // ... altri campi
}
```

### Salvataggio Attività

```typescript
// Creazione nuova attività
const newActivity = {
  name: 'Yoga',
  discipline: 'yoga',
  color: '#FF8A65',
  icon_name: 'Activity', // o null se non specificato
  // ... altri campi
};

await supabase
  .from('activities')
  .insert(newActivity);

// Modifica attività esistente
await supabase
  .from('activities')
  .update({
    icon_name: 'Calendar', // o null
    // ... altri campi
  })
  .eq('id', activityId);
```

### Verifica Esistenza Icona

```typescript
import * as IconsaxIcons from 'iconsax-react';

function iconExists(iconName: string): boolean {
  if (!iconName) return false;
  return iconName in IconsaxIcons;
}

function getIconComponent(iconName: string | null) {
  if (!iconName) return null;
  const Icon = IconsaxIcons[iconName as keyof typeof IconsaxIcons];
  return Icon || null;
}
```

## 🎨 UI/UX Suggerimenti

### Layout Sezione Icona

```
┌─────────────────────────────────────┐
│ Icona Attività                      │
├─────────────────────────────────────┤
│ Nome Icona: [____________]         │
│            [Sfoglia icone] →        │
│                                     │
│ Preview:                            │
│  [Icona 48x48px]                    │
│  o "Nessuna icona selezionata"      │
└─────────────────────────────────────┘
```

### Stati del Campo

1. **Vuoto**: Campo vuoto, preview mostra placeholder o icona default
2. **Icona Valida**: Campo con nome valido, preview mostra l'icona
3. **Icona Non Valida**: Campo con nome non valido, mostra warning sotto il campo

### Messaggi

- **Helper text**: "Inserisci il nome esatto dell'icona da iconsax-react. Esempi: Activity, Calendar, Star"
- **Warning icona non valida**: "Icona 'X' non trovata in iconsax-react. Verifica il nome sul sito."
- **Placeholder preview**: "Nessuna icona selezionata" o icona di default

### Stile

- Mantenere coerenza con il resto del form
- Il pulsante "Sfoglia icone" può essere un secondary button o link button
- La preview può essere in un box con bordo leggero o senza bordo
- Usare il colore dell'attività per la preview se disponibile

## ✅ Checklist Implementazione

### Dialog Attività
- [ ] Aggiungere sezione "Icona Attività" sopra la sezione colore
- [ ] Implementare campo input per nome icona
- [ ] Implementare pulsante "Sfoglia icone" che apre https://iconsax-react.pages.dev/
- [ ] Implementare preview icona con rendering dinamico
- [ ] Implementare validazione esistenza icona in tempo reale
- [ ] Mostrare messaggio warning se icona non esiste
- [ ] Gestire stato campo vuoto (preview placeholder)

### Logica Backend
- [ ] Aggiornare form per includere campo `icon_name` nel submit
- [ ] Salvare `icon_name` nel database (o `null` se vuoto)
- [ ] Caricare `icon_name` esistente quando si modifica attività
- [ ] Pre-compilare campo e mostrare preview quando si modifica

### Testing
- [ ] Testare inserimento nome icona valido
- [ ] Testare inserimento nome icona non valido
- [ ] Testare campo vuoto
- [ ] Testare salvataggio con icona valida
- [ ] Testare salvataggio con campo vuoto (null)
- [ ] Testare modifica attività esistente con icona
- [ ] Testare modifica attività esistente senza icona
- [ ] Verificare che il pulsante apra correttamente il link in nuova tab

## 🔍 Note Importanti

1. **Libreria Iconsax**: Le icone devono corrispondere esattamente ai nomi disponibili su https://iconsax-react.pages.dev/. Il nome è case-sensitive.

2. **Campo Opzionale**: Il campo `icon_name` è opzionale. Se non specificato, l'app utilizzerà un'icona di default.

3. **Validazione**: La validazione dell'esistenza dell'icona è solo per feedback all'utente. Non bloccare il salvataggio se l'icona non esiste (l'app gestirà il fallback).

4. **Performance**: La verifica dell'esistenza dell'icona può essere fatta in tempo reale (onChange) o al blur del campo. Considera di debounce la verifica se fatta in tempo reale.

5. **Type Safety**: Se usi TypeScript, considera di creare un tipo per i nomi delle icone valide, oppure usa type casting appropriato.

6. **Database**: Assicurati che il contract sia aggiornato e che il campo `icon_name` sia disponibile nella tabella `activities`. Se necessario, aggiorna `@kalos/contract` alla versione più recente.

7. **Posizionamento**: La sezione icona deve essere **subito sopra** la sezione colore nel form. Verifica l'ordine dei campi nel dialog.

8. **Preview Colore**: La preview dell'icona può utilizzare il colore dell'attività (se già selezionato) o un colore di default. Se il colore non è ancora selezionato, usa un colore neutro.

