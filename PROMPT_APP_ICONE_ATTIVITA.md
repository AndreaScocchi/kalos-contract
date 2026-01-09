# Prompt: Gestione Automatica Icone Attività - App Cliente

## 📋 Obiettivo

Eliminare il mapping statico delle icone alle attività nell'app e utilizzare invece il campo `icon_name` presente direttamente nelle informazioni dell'attività dal database. Questo permette di gestire le icone senza dover modificare il codice dell'app ogni volta che viene aggiunta una nuova attività.

## 🎯 Funzionalità Richieste

### 1. Rimozione Mapping Statico

Eliminare qualsiasi mapping statico o hardcoded che associa icone alle attività. Questo include:
- File di configurazione con mapping `activityId -> iconName` o `slug -> iconName`
- Switch/case statements che mappano attività a icone
- Oggetti/array che definiscono icone per attività specifiche (es. mapping basato su `discipline` o `slug`)
- Qualsiasi logica che determina l'icona basandosi su `activity.id`, `activity.name`, `activity.discipline`, o `activity.slug`

**IMPORTANTE**: Rimuovere il mapping esistente che associa slug/ discipline a icone come:
- `yogavinyasa -> Sun1`
- `yogagravidanza -> Star1`
- `yogapostparto -> HeartAdd`
- `mamamoves -> Wind`
- `arteterapia -> Brush`
- `scritturaintrospettiva -> Magicpen`
- `bussolainteriore -> Location`
- `meditazione -> Moon`
- `meditazionemindfulness -> Moon`
- `radicifemminili -> Woman`
- `semimaternita -> Woman`
- `semidimaternita -> Woman`
- `kalosmomcafe -> Coffee`
- `kalosseniorcafe -> Coffee`
- `laboratori -> Brush`

Questo mapping è stato migrato nel database e le icone sono ora disponibili direttamente nel campo `icon_name` di ogni attività.

### 2. Utilizzo Campo `icon_name` dal Database

Utilizzare direttamente il campo `icon_name` presente nell'oggetto attività:
- Il campo `icon_name` contiene il nome esatto dell'icona della libreria `iconsax-react`
- Se `icon_name` è presente (`icon_name IS NOT NULL`), utilizzarlo direttamente
- Se `icon_name` è `null` o `undefined`, utilizzare un'icona di default (es. "Activity" o "Calendar")

### 3. Rendering Icone

Implementare il rendering dinamico delle icone:
- Importare dinamicamente l'icona da `iconsax-react` basandosi su `icon_name`
- Gestire il caso in cui il nome dell'icona non esista nella libreria (fallback a icona default)
- Mantenere la stessa dimensione e stile delle icone esistenti

## 📚 API e Struttura Dati

### Query Attività

Le attività ora includono il campo `icon_name`:

```typescript
import { getActivities } from '@kalos/contract';

// Le attività includono ora icon_name
const activities = await getActivities(supabase);

// Struttura attività:
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

### Utilizzo Icona

```typescript
import * as IconsaxIcons from 'iconsax-react';

// Funzione helper per ottenere l'icona
function getActivityIcon(iconName: string | null) {
  if (!iconName) {
    return IconsaxIcons.Activity; // o un'altra icona di default
  }
  
  // Cerca l'icona nella libreria iconsax-react
  const IconComponent = IconsaxIcons[iconName as keyof typeof IconsaxIcons];
  
  if (!IconComponent) {
    console.warn(`Icona "${iconName}" non trovata in iconsax-react, uso default`);
    return IconsaxIcons.Activity; // fallback
  }
  
  return IconComponent;
}

// Utilizzo nel componente
function ActivityCard({ activity }: { activity: Activity }) {
  const Icon = getActivityIcon(activity.icon_name);
  
  return (
    <div>
      <Icon size={24} color={activity.color || '#000'} />
      <h3>{activity.name}</h3>
    </div>
  );
}
```

### Query con icon_name

Se stai usando query dirette a Supabase:

```typescript
const { data: activities } = await supabase
  .from('activities')
  .select('id, name, description, color, icon_name, ...')
  .is('deleted_at', null);
```

Oppure usa la view pubblica:

```typescript
const { data: activities } = await supabase
  .from('public_site_activities')
  .select('*')
  .eq('is_active', true);
```

## 🎨 UI/UX Suggerimenti

1. **Icona Default**: Scegli un'icona di default appropriata (es. "Activity", "Calendar", "Star") da mostrare quando `icon_name` è `null`

2. **Gestione Errori**: Se un'icona non esiste nella libreria, mostra l'icona di default e logga un warning in console per debugging

3. **Performance**: Considera di pre-caricare le icone più comuni se necessario, ma generalmente il rendering dinamico dovrebbe essere sufficiente

4. **Stile Consistente**: Mantieni lo stesso stile (dimensione, colore, variante) delle icone esistenti

## ✅ Checklist Implementazione

- [ ] Identificare tutti i punti nel codice dove viene fatto mapping statico attività -> icona
- [ ] Rimuovere file/oggetti/array di configurazione con mapping statico
- [ ] Rimuovere switch/case o if/else che mappano attività a icone
- [ ] Creare funzione helper `getActivityIcon(iconName: string | null)`
- [ ] Aggiornare tutti i componenti che mostrano icone attività per usare `activity.icon_name`
- [ ] Implementare fallback a icona default quando `icon_name` è `null`
- [ ] Gestire caso in cui nome icona non esiste nella libreria
- [ ] Testare con attività che hanno `icon_name` definito
- [ ] Testare con attività che hanno `icon_name = null`
- [ ] Verificare che tutte le schermate mostrino correttamente le icone
- [ ] Rimuovere codice non utilizzato relativo al vecchio mapping

## 🔍 Note Importanti

1. **Libreria Iconsax**: Le icone devono corrispondere esattamente ai nomi disponibili su https://iconsax-react.pages.dev/. Il nome è case-sensitive.

2. **Backward Compatibility**: Le attività esistenti potrebbero non avere `icon_name` definito. Assicurati di gestire questo caso con un'icona di default.

3. **Type Safety**: Se usi TypeScript, considera di creare un tipo per i nomi delle icone valide, oppure usa `as keyof typeof IconsaxIcons` per il type casting.

4. **Performance**: Il rendering dinamico delle icone non dovrebbe avere impatto significativo sulle performance. Se noti problemi, considera un sistema di cache delle icone.

5. **Testing**: Testa con diverse attività:
   - Attività con `icon_name` valido
   - Attività con `icon_name = null`
   - Attività con `icon_name` non esistente nella libreria

6. **Database**: Assicurati che il contract sia aggiornato e che le query includano il campo `icon_name`. Se necessario, aggiorna `@kalos/contract` alla versione più recente.

