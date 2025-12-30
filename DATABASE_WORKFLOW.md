# Database Workflow - Single Source of Truth

Questo repository (`kalos-contract`) è l'**unico punto** dove vengono fatte modifiche al database Supabase. Tutti i cambiamenti devono passare attraverso migrations canoniche qui contenute.

## Principi Fondamentali

1. **Single Source of Truth**: Questo repo contiene le migrations canoniche
2. **Forward-only**: Non modificare mai migrations già applicate in produzione
3. **Atomic**: Ogni migration deve essere completa e applicabile in modo atomico
4. **Testato**: Sempre testare in locale prima di applicare a produzione

## Workflow Completo

### 1. Sviluppo Locale

```bash
# Avvia Supabase locale
npm run db:start

# Applica tutte le migrations
supabase db reset

# Oppure applica solo nuove migrations
supabase migration up
```

### 2. Creare una Nuova Migration

```bash
# Opzione A: Genera automaticamente da modifiche locali
npm run db:diff
# Questo crea una nuova migration in supabase/migrations/

# Opzione B: Crea manualmente
# Crea file: supabase/migrations/YYYYMMDDHHMMSS_description.sql
# Formato: timestamp (14 cifre) + underscore + descrizione
```

### 3. Verifica Pre-Commit

**OBBLIGATORIO**: Prima di committare, esegui:

```bash
npm run verify
```

Questo script verifica:
- ✅ Types TypeScript compilano correttamente
- ✅ Build funziona
- ✅ Migrations sono in ordine e non duplicate
- ✅ Sintassi SQL base è corretta

**NON committare se `npm run verify` fallisce!**

### 4. Test Locale Completo

```bash
# Reset completo del DB locale
supabase db reset

# Verifica che tutto funzioni
npm run verify

# Testa le tue query/views/RPC manualmente
```

### 5. Applicare a Staging/Produzione

```bash
# Assicurati di essere collegato al progetto corretto
npm run db:link

# Verifica le migrations da applicare
supabase migration list

# Applica migrations
npm run db:push
```

### 6. Rigenerare Types

**DOPO** aver applicato le migrations a produzione/staging:

```bash
# Rigenera types dal database remoto
supabase gen types typescript --project-id <your-project-id> > src/types/database.ts

# Oppure da locale (se hai applicato solo localmente)
supabase gen types typescript --local > src/types/database.ts

# Verifica che compili
npm run typecheck
npm run build
```

### 7. Bump Versione e Release

```bash
# Bump versione in package.json
# (es. 0.1.0 → 0.1.1)

# Commit
git add .
git commit -m "feat: add migration X and update types"

# Tag
git tag v0.1.1

# Push
git push origin main --tags
```

## Convenzioni Migrations

### Naming

- Formato: `YYYYMMDDHHMMSS_description.sql`
- Esempio: `20240115143000_add_soft_delete_to_subscriptions.sql`
- Descrizione: breve, in inglese, snake_case

### Struttura

Ogni migration dovrebbe:

1. **Essere atomica**: Completa e applicabile in una transazione
2. **Essere idempotente** (quando possibile): Usa `IF NOT EXISTS`, `CREATE OR REPLACE`, ecc.
3. **Non modificare migrations precedenti**: Solo aggiungere nuove
4. **Includere commenti**: Spiega cosa fa e perché

### Esempio Template

```sql
-- Migration YYYYMMDDHHMMSS: Brief description
--
-- Obiettivo: Descrizione dettagliata di cosa fa questa migration
-- e perché è necessaria.
--
-- Compatibilità retroattiva: Note su compatibilità

-- 1. Sezione 1: Cosa fa
CREATE INDEX IF NOT EXISTS idx_example ON public.table(column);

-- 2. Sezione 2: Altri cambiamenti
ALTER TABLE public.table ADD COLUMN IF NOT EXISTS new_column text;

-- 3. Commenti
COMMENT ON COLUMN public.table.new_column IS 'Descrizione colonna';
```

## Verifica Pre-Push (Opzionale ma Consigliato)

Puoi configurare un pre-push hook Git per eseguire automaticamente `npm run verify`:

```bash
# Crea .git/hooks/pre-push
cat > .git/hooks/pre-push << 'EOF'
#!/bin/sh
npm run verify
EOF

chmod +x .git/hooks/pre-push
```

## Sincronizzazione Consumer

Quando pubblichi una nuova versione del contract:

1. **Consumer devono aggiornare la dependency**:
   ```json
   {
     "dependencies": {
       "@kalos/contract": "github:ORG/kalos-contract#v0.1.1"
     }
   }
   ```

2. **Eseguire**:
   ```bash
   npm install
   # o
   yarn install
   # o
   pnpm install
   ```

3. **Verificare breaking changes**:
   - Controlla il CHANGELOG (se presente)
   - Verifica che i types siano compatibili
   - Testa le funzionalità usate

## Troubleshooting

### Migration già applicata in produzione

**NON modificare la migration esistente!** Crea una nuova migration che corregge il problema.

### Types non aggiornati

Se i types non corrispondono al database:

1. Rigenera: `supabase gen types typescript --project-id <id> > src/types/database.ts`
2. Verifica: `npm run typecheck`
3. Commit e tag nuova versione

### Conflict tra local e remote

Se c'è un mismatch nella migration history:

1. **NON usare** `db:repair:history` senza capire il problema
2. Verifica manualmente: `supabase migration list`
3. Se necessario, sincronizza manualmente le migrations

## Checklist Pre-Release

Prima di pubblicare una nuova versione:

- [ ] Tutte le migrations sono testate in locale (`supabase db reset`)
- [ ] `npm run verify` passa senza errori
- [ ] Types sono aggiornati e compilano
- [ ] Build funziona (`npm run build`)
- [ ] Migrations applicate a staging (se disponibile)
- [ ] Types rigenerati da staging/produzione
- [ ] Versione bumpata in `package.json`
- [ ] Commit e tag creati
- [ ] Documentazione aggiornata (se necessario)

## Supporto

Per domande o problemi:
1. Controlla questo documento
2. Verifica le migrations esistenti come riferimento
3. Consulta la documentazione Supabase: https://supabase.com/docs/guides/cli

