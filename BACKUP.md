# Backup notturno e avvisi

Ogni notte una GitHub Action fa una copia **cifrata** di database e Storage e la salva in un bucket
S3 **privato in UE** (Francoforte), dove resta 30 giorni. Un secondo controllo, ogni due ore di
giorno, verifica che la coda delle notifiche venga elaborata e che l'ultimo backup sia recente.
Se qualcosa non va arriva un'email. Deciso nel [piano](../docs/PIANO-APS-E-NUOVA-APP.md) (H3), al
posto di Supabase Pro.

> **Stato: attivo dal 2026-09-23.** Setup completato, prima esecuzione riuscita (76 MB cifrati nel
> bucket `kalos-backup-2026`, 73 tabelle e 64 file dello Storage), controllo della coda verde e
> avvisi email verificati sul campo. Ripristino provato in locale il 2026-09-22 (§4).

## 1. Come funziona

| | |
|---|---|
| **Quando** | ogni notte alle 03:17 in estate e 02:17 in inverno ([`nightly-backup.yml`](.github/workflows/nightly-backup.yml)); anche a mano da *Actions → Backup notturno → Run workflow* |
| **Cosa contiene** | ruoli, schema e dati di `public` e `auth` (utenti e password cifrate comprese); tutti i file dello Storage con i bucket e le loro policy; definizione dei job pg_cron; righe per tabella, per verificare il ripristino |
| **Cosa non contiene** | valori dei secret (Vault, edge function), impostazioni Auth della dashboard: vanno rifatti a mano (§4) |
| **Cifratura** | [age](https://age-encryption.org), a chiave pubblica: GitHub conosce solo la chiave pubblica, che basta per cifrare. Per decifrare serve la chiave privata, che esiste solo da voi |
| **Dove** | bucket S3 privato in `eu-central-1`, prefisso `backups/`, un file `kalos-AAAAMMGGTHHMMSSZ.tar.gz.age` a notte |
| **Per quanto** | 30 giorni (lifecycle rule del bucket) |
| **Quanto pesa** | qualche decina di MB a notte (oggi: DB ~20 MB di dati, Storage ~52 MB) |
| **Avvisi** | email via SES, dallo stesso dominio verificato delle notifiche: se il backup fallisce; se una notifica resta in coda più di 30 minuti; se ne fallisce anche una sola; se l'ultimo backup ha più di 30 ore ([`ops-health.yml`](.github/workflows/ops-health.yml)) |

**Perché S3 e non GitHub.** Il repo `kalos-contract` è **pubblico**: artifact e log delle Actions
li vede chiunque. Per questo il backup va fuori da GitHub, e gli script stampano solo dimensioni e
conteggi. S3 a Francoforte tiene i dati in UE (AWS è già fornitore per le email) e costa pochi
centesimi al mese.

**Perché le credenziali AWS sono "solo scrittura".** L'utente usato da GitHub può caricare i backup
e vedere l'elenco dei file, ma non leggerli né cancellarli. Con il versioning attivo, anche un file
sovrascritto resta recuperabile per 7 giorni.

## 2. Setup una tantum

Circa mezz'ora. Servono l'accesso alla console AWS (lo stesso account di SES), a GitHub e alla
dashboard Supabase. **Le chiavi segrete vanno solo nel password manager e nei secret di GitHub**,
mai in chat o in un file del repo.

### 2.1 Chiave di cifratura (age)

1. Installa age sul tuo computer. Su questo Mac Homebrew oggi rifiuta di installare (Command Line
   Tools vecchi), quindi usa il binario ufficiale: da
   [github.com/FiloSottile/age/releases](https://github.com/FiloSottile/age/releases) scarica
   `age-vX.Y.Z-darwin-arm64.tar.gz`, estrai `age` e `age-keygen`.
2. Genera la coppia di chiavi:
   ```bash
   ./age-keygen -o kalos-backup.key
   ```
   Il comando stampa la **chiave pubblica** (`age1…`). Il file `kalos-backup.key` contiene la
   **chiave privata** (`AGE-SECRET-KEY-1…`).
3. **Metti la chiave privata al sicuro in due posti:** il password manager e una copia offline
   (chiavetta o stampa in un luogo sicuro). Poi cancella il file dal computer.
   ⚠️ **Senza la chiave privata i backup sono illeggibili**, anche per voi.
4. La chiave pubblica va in GitHub come variabile `BACKUP_AGE_RECIPIENT` (§2.5).

### 2.2 Bucket S3

Console AWS, regione **eu-central-1 (Frankfurt)** → **S3 → Create bucket**:
- **Nome:** `kalos-backup-` più un suffisso a scelta, per esempio `kalos-backup-2026`. I nomi sono
  globali, quindi potrebbe servire un altro suffisso.
- **Block all public access:** attivo (è il default).
- **Bucket Versioning:** *Enable*.
- **Default encryption:** SSE-S3 (è il default).

Poi, nel bucket → **Management → Create lifecycle rule** (`scadenza-30-giorni`):
- ambito: prefisso `backups/`;
- *Expire current versions of objects*: **30** giorni;
- *Permanently delete noncurrent versions of objects*: **7** giorni;
- *Delete expired object delete markers*: sì.

### 2.3 Utente IAM per GitHub

**IAM → Users → Create user** `kalos-backup-github`, **senza** accesso alla console. Poi *Add
permissions → Create inline policy → JSON*, sostituendo `NOME-BUCKET`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CaricaBackup",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::NOME-BUCKET/backups/*"
    },
    {
      "Sid": "ElencoPerLaVerifica",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::NOME-BUCKET",
      "Condition": { "StringLike": { "s3:prefix": "backups/*" } }
    },
    {
      "Sid": "EmailDiAvviso",
      "Effect": "Allow",
      "Action": "ses:SendEmail",
      "Resource": "*",
      "Condition": { "StringEquals": { "ses:FromAddress": "avvisi@kalosstudio.it" } }
    }
  ]
}
```

Nome della policy: `kalos-backup-github`. Poi **Security credentials → Create access key →
Other**: copia *Access key* e *Secret access key* (il secret si vede una volta sola).

Il tetto di spesa AWS da 5 $/mese già impostato per SES copre anche questo.

### 2.4 Connessione al database

Dashboard Supabase → **Connect** → *Session pooler* (non "Direct": GitHub non raggiunge IPv6) →
copia l'URI:

```
postgresql://postgres.tkioedsebdxqblgcctxv:[YOUR-PASSWORD]@aws-1-eu-north-1.pooler.supabase.com:5432/postgres
```

Sostituisci `[YOUR-PASSWORD]` con la password del database. Se contiene caratteri speciali
(`@ : / ? # %`), vanno codificati: per esempio `@` diventa `%40`. Se la password non la conosce
nessuno: *Project Settings → Database → Reset database password*. Nel progetto non la usa nient'altro
(CLI, app e edge function usano altre credenziali).

### 2.5 Secret e variabili in GitHub

Repo `kalos-contract` → **Settings → Secrets and variables → Actions**.

| Tipo | Nome | Valore |
|---|---|---|
| Secret | `BACKUP_SUPABASE_DB_URL` | l'URI del §2.4 |
| Secret | `BACKUP_AWS_ACCESS_KEY_ID` | access key del §2.3 |
| Secret | `BACKUP_AWS_SECRET_ACCESS_KEY` | secret access key del §2.3 |
| Secret | `ALERT_EMAIL_TO` | chi riceve gli avvisi (più indirizzi separati da virgola) |
| Secret | `SUPABASE_URL` | *c'è già* (lo usa `notification-cron.yml`) |
| Secret | `SUPABASE_SERVICE_ROLE_KEY` | *c'è già* |
| Variabile | `BACKUP_S3_BUCKET` | nome del bucket del §2.2 |
| Variabile | `BACKUP_AGE_RECIPIENT` | chiave pubblica `age1…` del §2.1 |
| Variabile | `ALERT_EMAIL_FROM` | `Studio Kalòs avvisi <avvisi@kalosstudio.it>` |

### 2.6 Prima esecuzione

1. *Actions → Backup notturno → Run workflow*. Dura qualche minuto; alla fine il log mostra
   "✅ Caricato su S3" con la dimensione.
2. In S3 compare `backups/kalos-….tar.gz.age`.
3. *Actions → Controllo coda notifiche e backup → Run workflow*: deve risultare verde.
4. Per provare l'email: lancia di nuovo il controllo con `BACKUP_S3_BUCKET` temporaneamente
   sbagliato, controlla che l'avviso arrivi, poi rimetti il nome giusto.

## 3. Avvisi

| Controllo | Quando scatta | Frequenza |
|---|---|---|
| Backup non riuscito | qualsiasi errore del backup notturno | una email a notte |
| Coda ferma | una notifica pronta da più di 30 minuti e mai elaborata | a ogni controllo, finché dura |
| Notifiche fallite | almeno una fallita nelle ultime 2 ore (in condizioni normali sono zero) | una volta per ogni gruppo di fallite |
| Backup vecchio | l'ultimo file nel bucket ha più di 30 ore | a ogni controllo, finché dura |

I controlli girano ogni due ore dalle 7 alle 23 circa. Soglie in
[`ops-health.mjs`](scripts/backup/ops-health.mjs).

## 4. Ripristino

Da fare **in un progetto Supabase nuovo**, mai sopra la produzione. Tempo: meno di un'ora.

1. **Progetto nuovo** su Supabase, regione UE (oggi `eu-north-1`).
2. **Scarica il backup** dal bucket S3 con il tuo accesso alla console (l'utente di GitHub non può
   leggerlo, di proposito).
3. **Prerequisiti sul computer:** `age`, `jq`, Node, e `psql` (oppure Docker: vedi sotto).
4. Dalla cartella `kalos-contract`, con `npm ci` fatto:
   ```bash
   TARGET_DB_URL='<URI session pooler del progetto NUOVO>' \
   SUPABASE_URL='https://<ref-nuovo>.supabase.co' \
   SUPABASE_SERVICE_ROLE_KEY='<service_role del progetto NUOVO>' \
   RESTORE_CRON=1 \
   scripts/backup/restore.sh kalos-AAAAMMGGTHHMMSSZ.tar.gz.age /percorso/kalos-backup.key
   ```
   Senza `psql` installato: `PSQL="docker run --rm -i postgres:17-alpine psql"`.
   Lo script decifra, ripristina database e policy dello Storage, ricarica i file e **verifica**
   righe per tabella e checksum di ogni file. Se qualcosa non torna, si ferma con l'elenco delle
   differenze.
5. **A mano, sul progetto nuovo:**
   - Vault: i secret `supabase_url` e `service_role_key`, usati da `call_edge_function` per i cron;
   - edge function: `npx supabase secrets set …` (vedi AWS_SES_SETUP.md §6) e
     `npx supabase functions deploy`;
   - Auth: Site URL, Redirect URLs, provider Google e Apple, template email;
   - storico delle migrazioni: `npx supabase migration repair --status applied <versioni>` sul
     progetto nuovo, così i prossimi `db push` partono dal punto giusto.
6. **Puntare le app al progetto nuovo:** `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` (sito,
   gestionale) ed `EXPO_PUBLIC_…` (webapp) su Netlify, poi redeploy.

### Prova periodica

Una volta ogni tre mesi conviene rifare la prova in locale, come il 2026-09-22: backup del DB
locale, ripristino in un secondo progetto locale vuoto, login con un utente ripristinato. Servono
Docker e lo Storage locale acceso (`[storage] enabled = true` in `supabase/config.toml`, solo per la
prova). I comandi sono gli stessi del §4, con gli URL locali.

## 5. Limiti noti

- **Fino a 24 ore di dati** si possono perdere (backup notturno, niente PITR). Le ricevute partono
  anche via email, quindi esiste una copia fuori dal sistema.
- **GitHub disattiva i workflow programmati** di un repo pubblico dopo 60 giorni senza attività nel
  repo. Contromisura automatica dal 2026-09-23:
  [`keepalive.yml`](.github/workflows/keepalive.yml) scrive un commit sul branch `ops/keepalive` il
  primo di ogni mese, e il conteggio riparte. Se un giorno anche quello venisse spento (per esempio
  dopo due mesi in cui non gira nulla), l'ultimo backup resta comunque nel bucket e basta riaprire
  *Actions* e riattivarlo. Un'ulteriore rete, non necessaria oggi, sarebbe un servizio esterno di
  tipo "dead man's switch" (per esempio healthchecks.io).
- **La password del database è un secret di GitHub.** Secret e variabili non sono visibili ai fork
  né nei log. Solo chi ha accesso in scrittura al repo può usarli.
