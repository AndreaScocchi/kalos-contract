# Checklist Verifica - 15 Minuti

Questa checklist ti permette di verificare rapidamente che tutto funzioni correttamente dopo modifiche al database o al contract.

## Verifica Locale (5 minuti)

### 1. Types e Build

```bash
npm run verify
```

✅ **Atteso**: Nessun errore, build completato

### 2. Migrations Order e Syntax

```bash
npm run verify:migrations
```

✅ **Atteso**: 
- Migrations in ordine cronologico
- Nessun timestamp duplicato
- Sintassi SQL base corretta

### 3. Test Database Locale

```bash
# Avvia Supabase locale
npm run db:start

# Reset completo (applica tutte le migrations)
supabase db reset
```

✅ **Atteso**: 
- Nessun errore durante l'applicazione delle migrations
- Database locale funzionante

### 4. Verifica Views Pubbliche (se create/modificate)

```bash
# Connettiti al DB locale e testa
psql postgresql://postgres:postgres@localhost:54322/postgres -c "SELECT * FROM public_site_schedule LIMIT 1;"
psql postgresql://postgres:postgres@localhost:54322/postgres -c "SELECT * FROM public_site_pricing LIMIT 1;"
```

✅ **Atteso**: 
- Views restituiscono dati (o risultato vuoto se non ci sono dati)
- Nessun errore di permessi

### 5. Verifica RPC (se modificate)

```bash
# Testa book_lesson e cancel_booking manualmente
# (richiede autenticazione, testa tramite app/gestionale)
```

✅ **Atteso**: 
- RPC funzionano correttamente
- Nessun errore di permessi
- Soft delete rispettato

## Verifica Staging/Remote (10 minuti)

### 1. Applica Migrations a Staging

```bash
npm run db:link  # Verifica di essere collegato al progetto corretto
npm run db:push
```

✅ **Atteso**: 
- Migrations applicate senza errori
- Nessun rollback

### 2. Rigenera Types da Remote

```bash
supabase gen types typescript --project-id <your-project-id> > src/types/database.ts
npm run typecheck
npm run build
```

✅ **Atteso**: 
- Types generati correttamente
- Typecheck passa
- Build funziona

### 3. Verifica Views Pubbliche su Remote

Testa le views pubbliche tramite:
- Dashboard Supabase (SQL Editor)
- App/Sito che usa le views

✅ **Atteso**: 
- Views accessibili con anon key
- Dati corretti (rispettano soft delete, minimizzazione GDPR)

### 4. Verifica RLS Policies

Testa manualmente:
- Accesso anonimo a views pubbliche
- Accesso autenticato a dati personali
- Staff può accedere a tutto

✅ **Atteso**: 
- Permessi corretti
- Nessun accesso non autorizzato

## Checklist Pre-Release

Prima di pubblicare una nuova versione:

- [ ] ✅ `npm run verify` passa
- [ ] ✅ `npm run verify:migrations` passa
- [ ] ✅ Test locale: `supabase db reset` funziona
- [ ] ✅ Migrations applicate a staging (se disponibile)
- [ ] ✅ Types rigenerati da staging/produzione
- [ ] ✅ Views pubbliche testate (se modificate)
- [ ] ✅ RPC testate (se modificate)
- [ ] ✅ RLS policies verificate
- [ ] ✅ Versione bumpata in `package.json`
- [ ] ✅ README aggiornato (se necessario)
- [ ] ✅ Commit e tag creati
- [ ] ✅ Documentazione aggiornata

## Troubleshooting Rapido

### `npm run verify` fallisce

1. **Typecheck fallisce**: Rigenera types da database
2. **Build fallisce**: Verifica errori di sintassi TypeScript
3. **Migrations falliscono**: Verifica ordine e sintassi SQL

### Migrations non si applicano

1. **Timestamp duplicato**: Rinomina migration con timestamp univoco
2. **Sintassi SQL errata**: Verifica con `psql` o Supabase Dashboard
3. **Dipendenza mancante**: Verifica che migrations precedenti siano applicate

### Types non corrispondono al database

1. Rigenera: `supabase gen types typescript --project-id <id> > src/types/database.ts`
2. Verifica: `npm run typecheck`
3. Se ancora non corrisponde, verifica che migrations siano applicate

### Views pubbliche non accessibili

1. Verifica grants: `GRANT SELECT ON view TO anon;`
2. Verifica RLS: views non hanno RLS (solo tabelle)
3. Testa con anon key direttamente

## Note Importanti

- ⚠️ **NON modificare migrations già applicate in produzione**
- ⚠️ **Sempre testare in locale prima di applicare a produzione**
- ⚠️ **Sempre rigenerare types dopo modifiche al database**
- ⚠️ **Sempre eseguire `npm run verify` prima di commit**

