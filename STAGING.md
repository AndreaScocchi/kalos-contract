# Staging & rilascio sicuro (senza piano Pro)

> Strategia free per evolvere lo schema **senza rompere la prod** (~230 clienti, 3 consumer live).
> Sostituisce branching nativo + PITR (Pro) con: **staging locale + snapshot pre-push + disciplina additiva**.
> Contesto e razionale: `../docs/NEW_APP_PLAN.md` §3 e §3.bis, `../docs/CONTRACT_DISCIPLINE.md`.

## Principio

La prod si tocca **raramente** e solo in modo **additivo**. Ogni feature si sviluppa e si testa in
**locale** su un branch git del contract; la prod riceve la migrazione solo quando la feature è pronta
(gestionale-first), con snapshot e conferma.

## 1. Staging locale (ambiente isolato gratuito)

Ogni "branch di feature" = branch git in `kalos-contract` + DB Supabase **locale**.

```bash
git checkout -b feat/<nome>
# scrivi la migrazione additiva in supabase/migrations/

supabase start                 # avvia lo stack locale (richiede Docker)
supabase db reset              # riapplica TUTTE le migrazioni da zero in locale
npm run codegen                # rigenera tipi TS + modelli Kotlin dallo schema
npm run verify                 # migration-lint + typecheck + build
```

Dati realistici ma anonimi in locale (opzionale):

```bash
SUPABASE_DB_URL=<prod-readonly-url> npm run seed:anon     # genera supabase/seed-anon.sql (gitignored)
psql "$LOCAL_DB_URL" -f supabase/seed-anon.sql            # carica nel DB locale
```

> `seed-anon.sql` contiene dati derivati dalla prod ma anonimizzati (PII sostituite): resta **locale e gitignored**.

## 2. Rilascio in prod (l'unico modo consentito)

**Mai** `supabase db push` a mano. Si usa il wrapper che impone snapshot + conferma:

```bash
supabase link --project-ref tkioedsebdxqblgcctxv   # una tantum
npm run db:push:safe
```

`db:push:safe` esegue in sequenza:
1. **migration-lint** (blocca distruttive non approvate);
2. **snapshot** completo della prod → `backups/<UTC>-full.sql` (gitignored);
3. mostra le migrazioni pendenti e chiede di digitare **`PUSH`** per confermare;
4. `supabase db push`.

Dopo il push: `npm run codegen`, commit dei file generati, **tag** nuova versione, upgrade **opt-in**
dei consumer (vedi CONTRACT_DISCIPLINE.md §3).

## 3. Backup manuale on-demand

```bash
npm run db:snapshot            # snapshot completo (ruoli+schema+dati) → backups/
npm run db:snapshot -- --data-only
```

Conserva lo snapshot finché la migrazione non è verificata in prod. In caso di problemi, ripristina da lì
(è la nostra alternativa al PITR: recovery puntuale, non continuo).

## Cosa NON copriamo (limiti free, accettati)

- **No PITR continuo**: si recupera solo fino all'ultimo snapshot manuale. Mitigato dall'additività
  (una migrazione "sbagliata" è una tabella/colonna nuova inutilizzata, reversibile senza perdita dati).
- **No branch cloud condivisi**: lo staging è locale. Edge Functions/Storage realistici non sono replicati.
- **Trigger per valutare Pro+PITR temporaneo**: backfill massivi su prod o go-live Stripe.
