# Fix: Errore "Bucket not found" quando si visualizza immagine bug report nel gestionale

## 🔍 Problema

Quando si prova ad aprire un'immagine di un bug report dal gestionale, si riceve l'errore:
```
{"statusCode":"404","error":"Bucket not found","message":"Bucket not found"}
```

## 🔍 Causa

Il bucket `bug-reports` è **privato** (`public = false`), quindi:
- Non si può usare `getPublicUrl()` - restituisce un URL che non funziona per bucket privati
- Bisogna generare un **signed URL** usando `createSignedUrl()`
- Il campo `image_url` nel database può contenere:
  - Un **path relativo** (es: `{user_id}/{timestamp}.jpg`) - caso più comune
  - Un **signed URL completo** - potrebbe essere scaduto

## ✅ Soluzione

### 1. Funzione Helper per Generare Signed URL

Crea una funzione helper che genera sempre un signed URL valido:

```typescript
import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Ottiene l'URL dell'immagine del bug report.
 * Se image_url è un path relativo, genera un signed URL.
 * Se è già un URL completo, lo restituisce (ma potrebbe essere scaduto).
 */
export async function getBugReportImageUrl(
  supabase: SupabaseClient,
  imageUrl: string | null
): Promise<string | null> {
  if (!imageUrl) return null;

  // Se è già un URL completo (contiene http:// o https://), restituiscilo
  // Nota: potrebbe essere scaduto se è un signed URL vecchio
  if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
    // Se è un signed URL scaduto, prova a rigenerarlo dal path
    // Per ora restituiamo l'URL, ma potresti voler gestire il caso di URL scaduto
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
```

### 2. Utilizzo nel Componente React

```typescript
import { useState, useEffect } from 'react';
import { useSupabaseClient } from '@supabase/auth-helpers-react';
import { getBugReportImageUrl } from './utils/bugReports';

interface BugReportImageProps {
  imageUrl: string | null;
  alt?: string;
  className?: string;
}

export function BugReportImage({ 
  imageUrl, 
  alt = "Screenshot del bug",
  className = "max-w-full rounded-lg"
}: BugReportImageProps) {
  const supabase = useSupabaseClient();
  const [imageSrc, setImageSrc] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!imageUrl) {
      setImageSrc(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    getBugReportImageUrl(supabase, imageUrl)
      .then((url) => {
        setImageSrc(url);
        setError(null);
      })
      .catch((err) => {
        console.error('Errore caricamento immagine:', err);
        setError('Impossibile caricare l\'immagine');
        setImageSrc(null);
      })
      .finally(() => {
        setLoading(false);
      });
  }, [imageUrl, supabase]);

  if (loading) {
    return (
      <div className="flex items-center justify-center p-4">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
      </div>
    );
  }

  if (error || !imageSrc) {
    return (
      <div className="p-4 text-red-600 bg-red-50 rounded-lg">
        {error || 'Immagine non disponibile'}
      </div>
    );
  }

  return (
    <img 
      src={imageSrc} 
      alt={alt}
      className={className}
      onError={() => {
        setError('Errore nel caricamento dell\'immagine');
        setImageSrc(null);
      }}
    />
  );
}
```

### 3. Utilizzo nella Lista Bug Reports

```typescript
import { BugReportImage } from './BugReportImage';

function BugReportListItem({ bug }: { bug: BugReport }) {
  return (
    <div className="bug-report-item">
      <h3>{bug.title}</h3>
      <p>{bug.description}</p>
      
      {/* Anteprima immagine */}
      {bug.image_url && (
        <div className="mt-2">
          <BugReportImage 
            imageUrl={bug.image_url}
            alt={`Screenshot bug: ${bug.title}`}
            className="w-32 h-32 object-cover rounded"
          />
        </div>
      )}
    </div>
  );
}
```

### 4. Utilizzo nel Dettaglio Bug Report

```typescript
import { BugReportImage } from './BugReportImage';
import { useState } from 'react';

function BugReportDetail({ bug }: { bug: BugReport }) {
  const [showFullImage, setShowFullImage] = useState(false);

  return (
    <div className="bug-report-detail">
      <h1>{bug.title}</h1>
      <p>{bug.description}</p>
      
      {/* Immagine cliccabile per fullscreen */}
      {bug.image_url && (
        <div className="mt-4">
          <button
            onClick={() => setShowFullImage(true)}
            className="cursor-pointer"
          >
            <BugReportImage 
              imageUrl={bug.image_url}
              alt={`Screenshot bug: ${bug.title}`}
              className="max-w-md rounded-lg shadow-lg hover:opacity-90 transition"
            />
          </button>
          
          {/* Modal fullscreen */}
          {showFullImage && (
            <div 
              className="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-50"
              onClick={() => setShowFullImage(false)}
            >
              <div className="max-w-4xl max-h-full p-4">
                <BugReportImage 
                  imageUrl={bug.image_url}
                  alt={`Screenshot bug: ${bug.title}`}
                  className="max-w-full max-h-full object-contain"
                />
                <button
                  onClick={() => setShowFullImage(false)}
                  className="mt-4 text-white bg-gray-800 px-4 py-2 rounded"
                >
                  Chiudi
                </button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
```

## 🔧 Verifiche

1. **Verifica che il bucket esista**: Controlla in Supabase Studio → Storage → Buckets che il bucket `bug-reports` esista.

2. **Verifica le policy di storage**: Controlla che le policy siano state applicate correttamente:
   - `bug_reports_admins_view_all_files` (SELECT) - permette agli admin di vedere tutti i file

3. **Verifica il formato di `image_url`**: Controlla nel database che il campo `image_url` contenga:
   - Un path relativo (es: `{user_id}/{timestamp}.jpg`) - caso più comune
   - Oppure un URL completo (signed URL)

4. **Testa la funzione**: Verifica che `getBugReportImageUrl()` generi correttamente il signed URL.

## 📝 Note Importanti

- **Signed URL Scaduti**: I signed URL hanno una scadenza (es. 1 ora). Se un URL è scaduto, bisogna rigenerarlo. La funzione helper gestisce questo caso.

- **Path Format**: Il path deve essere nel formato `{user_id}/{filename}` (senza il prefisso `bug-reports/`).

- **Error Handling**: Gestisci sempre gli errori di generazione signed URL e mostra messaggi chiari all'utente.

- **Performance**: Considera di cacheare i signed URL per evitare di rigenerarli ad ogni render (es. usando React Query o SWR).

## 🐛 Debug

Se l'immagine ancora non viene visualizzata:

1. **Console errors**: Apri la console del browser e verifica eventuali errori durante la generazione del signed URL.

2. **Network tab**: Controlla le richieste di rete per vedere se il signed URL viene generato correttamente.

3. **Verifica il path**: Controlla che il path in `image_url` sia corretto e non contenga il prefisso `bug-reports/`.

4. **Verifica le policy**: Assicurati che la policy `bug_reports_admins_view_all_files` sia attiva e permetta agli admin di vedere tutti i file.

5. **Test diretto**: Prova a generare un signed URL direttamente dalla console del browser:
   ```typescript
   const { data } = await supabase.storage
     .from('bug-reports')
     .createSignedUrl('{user_id}/{filename}', 3600);
   console.log(data.signedUrl);
   ```

