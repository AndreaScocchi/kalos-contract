# Fix: Immagine non salvata nel form di segnalazione bug

## 🔍 Problema Identificato

L'immagine caricata nel form di segnalazione bug non viene salvata. Ci sono due problemi principali:

### 1. **Bucket Privato vs URL Pubblico**
Il bucket `bug-reports` è configurato come **privato** (`public = false` nella migration), ma il codice usa `getPublicUrl()` che funziona solo per bucket pubblici.

### 2. **Path del File**
Il path del file deve corrispondere esattamente al formato richiesto dalle policy di storage: `{user_id}/{timestamp}.{ext}` (senza il prefisso `bug-reports/`).

## ✅ Soluzione

### Codice Corretto per l'Upload

```typescript
// 1. Preparare il file e il path
const fileExt = image.name.split('.').pop();
const fileName = `${Date.now()}.${fileExt}`;
// IMPORTANTE: Il path NON include "bug-reports/" perché viene specificato in .from()
const filePath = `${user.id}/${fileName}`;

// 2. Caricare l'immagine su Supabase Storage
const { data: uploadData, error: uploadError } = await supabase.storage
  .from('bug-reports')
  .upload(filePath, image, {
    cacheControl: '3600',
    upsert: false // Non sovrascrivere file esistenti
  });

if (uploadError) {
  console.error('Errore upload immagine:', uploadError);
  throw uploadError;
}

// 3. Ottenere l'URL firmato (signed URL) perché il bucket è privato
// L'URL firmato è valido per un periodo limitato (es. 1 anno)
const { data: signedUrlData, error: signedUrlError } = await supabase.storage
  .from('bug-reports')
  .createSignedUrl(filePath, 31536000); // 1 anno in secondi

if (signedUrlError) {
  console.error('Errore creazione signed URL:', signedUrlError);
  throw signedUrlError;
}

// 4. Usare il signed URL nel campo image_url del bug report
const imageUrl = signedUrlData.signedUrl;

// 5. Creare il bug report con l'URL dell'immagine
const { data: bugReport, error: insertError } = await supabase
  .from('bug_reports')
  .insert({
    title: 'Titolo del bug',
    description: 'Descrizione dettagliata...',
    image_url: imageUrl, // URL firmato
    created_by_user_id: user.id,
    status: 'open'
  })
  .select()
  .single();

if (insertError) {
  console.error('Errore creazione bug report:', insertError);
  throw insertError;
}
```

### Alternativa: Usare Path Relativo

Se preferisci salvare solo il path relativo e generare l'URL quando necessario:

```typescript
// 1. Upload (come sopra)
const filePath = `${user.id}/${Date.now()}.${fileExt}`;
const { data: uploadData, error: uploadError } = await supabase.storage
  .from('bug-reports')
  .upload(filePath, image);

if (uploadError) {
  throw uploadError;
}

// 2. Salvare solo il path relativo nel database
const { data: bugReport, error: insertError } = await supabase
  .from('bug_reports')
  .insert({
    title: 'Titolo del bug',
    description: 'Descrizione dettagliata...',
    image_url: filePath, // Salva solo il path, non l'URL completo
    created_by_user_id: user.id,
    status: 'open'
  })
  .select()
  .single();

// 3. Quando serve visualizzare l'immagine, genera il signed URL:
const getImageUrl = async (imagePath: string | null) => {
  if (!imagePath) return null;
  
  const { data, error } = await supabase.storage
    .from('bug-reports')
    .createSignedUrl(imagePath, 31536000); // 1 anno
  
  if (error) {
    console.error('Errore generazione URL immagine:', error);
    return null;
  }
  
  return data.signedUrl;
};
```

## 🔧 Verifiche da Fare

1. **Verifica che il bucket esista**: Controlla in Supabase Studio → Storage → Buckets che il bucket `bug-reports` esista.

2. **Verifica le policy di storage**: Controlla che le policy siano state applicate correttamente:
   - `bug_reports_users_upload_own_folder` (INSERT)
   - `bug_reports_users_view_own_files` (SELECT)

3. **Verifica il formato del path**: Il path deve essere esattamente `{user_id}/{filename}`, senza il prefisso `bug-reports/`.

4. **Verifica gli errori**: Controlla la console del browser/app per eventuali errori durante l'upload.

## 📝 Note Importanti

- **Signed URL**: Gli URL firmati hanno una scadenza. Se salvi l'URL completo nel database, potrebbe scadere. È meglio salvare il path e rigenerare l'URL quando serve, oppure usare una scadenza molto lunga (es. 1 anno).

- **Path Format**: Il path deve essere `{user_id}/{filename}` perché la policy usa `storage.foldername(name)[1]` per estrarre la prima cartella e verificare che corrisponda a `auth.uid()`.

- **Error Handling**: Gestisci sempre gli errori di upload e mostra messaggi chiari all'utente.

## 🐛 Debug

Se l'immagine ancora non viene salvata, controlla:

1. **Console errors**: Apri la console del browser/app e verifica eventuali errori durante l'upload.

2. **Network tab**: Controlla le richieste di rete per vedere se l'upload viene effettivamente inviato e quale risposta riceve.

3. **Storage policies**: Verifica in Supabase Studio che le policy di storage siano attive e corrette.

4. **User ID**: Assicurati che `user.id` o `auth.uid()` sia disponibile e corretto quando fai l'upload.

5. **File size**: Verifica che il file non superi il limite di 5MB configurato nel bucket.

## 🔧 Problema Specifico: Admin non possono caricare immagini

Se sei un admin e ricevi l'errore **"new row violates row-level security policy"** quando provi a caricare un'immagine, significa che le policy di storage per gli admin non sono state applicate.

### Soluzione

Esegui la migration `20260108000003_add_admin_storage_policies.sql` che aggiunge le policy mancanti:

```sql
-- Policy INSERT per admin
CREATE POLICY "bug_reports_admins_upload_all"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'bug-reports' 
  AND public.is_admin()
);

-- Policy UPDATE per admin
CREATE POLICY "bug_reports_admins_update_all_files"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'bug-reports' 
  AND public.is_admin()
)
WITH CHECK (
  bucket_id = 'bug-reports' 
  AND public.is_admin()
);
```

Oppure applica la migration completa:

```bash
# Se usi Supabase CLI
npx supabase db push

# Oppure applica manualmente la migration
# 20260108000003_add_admin_storage_policies.sql
```

Dopo aver applicato la migration, gli admin potranno caricare immagini nel bucket `bug-reports` senza restrizioni sul path.

