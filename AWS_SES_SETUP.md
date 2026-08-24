# Migrazione email: Resend → Amazon SES

Guida operativa per portare l'invio email di Studio Kalòs su Amazon SES.
Il codice è già pronto (vedi [Stato del codice](#stato-del-codice)); questa
guida copre la parte da fare in console AWS e il cutover.

**Perché:** il piano free di Resend è limitato a 100 email/giorno, il che rende
impossibile inviare una newsletter a ~500 clienti in un colpo solo. SES non ha
tetto giornaliero utile (50.000/giorno di default dopo l'uscita dalla sandbox) e
costa $0,10 ogni 1.000 email — sui volumi reali di Studio Kalòs (~490 email/mese)
significa **circa $0,60 all'anno**.

---

## 1. Account e regione

1. Crea l'account AWS scegliendo il piano **Paid** (pay-as-you-go), non il piano
   Free: quest'ultimo si disattiva dopo 6 mesi e fermerebbe l'invio email.
2. Regione: **`eu-central-1` (Francoforte)**.
   - Dati in UE, nessuna attivazione opt-in richiesta, supporto completo incluso SMTP.
   - `eu-south-1` (Milano) sarebbe più vicina ma **non ha endpoint SMTP** ed è una
     regione opt-in: nessun vantaggio reale a questi volumi.
3. Lavora sempre nella stessa regione: identità, configuration set, topic SNS e
   credenziali IAM sono per-regione.

---

## 2. Verifica del dominio e DKIM

In **SES → Identities → Create identity → Domain**, inserisci `kalosstudio.it`.

1. Attiva **Easy DKIM** (RSA 2048).
2. SES genera 3 record CNAME: aggiungili al DNS di `kalosstudio.it`.
3. Attendi la verifica (di solito < 30 minuti).

> I record DKIM di Resend usano selettori diversi e **possono restare attivi**:
> i due provider convivono senza conflitti. Questo permette il cutover graduale
> e il rollback immediato descritti al punto 10.

### SPF e DMARC

- **SPF**: se il TXT esistente contiene già `include:amazonses.com` sei a posto,
  altrimenti aggiungilo mantenendo quello di Resend durante la transizione.
- **DMARC**: se non esiste, parti in modalità osservazione —
  `v=DMARC1; p=none; rua=mailto:dmarc@kalosstudio.it` — e irrigidisci solo dopo
  aver verificato l'allineamento per qualche settimana.

### Custom MAIL FROM (consigliato)

In **SES → Identities → kalosstudio.it → Custom MAIL FROM**, imposta
`mail.kalosstudio.it`. Serve per allineare il `Return-Path` al dominio e
migliorare DMARC. Richiede due record DNS:

| Tipo | Nome | Valore |
|---|---|---|
| MX | `mail.kalosstudio.it` | `10 feedback-smtp.eu-central-1.amazonses.com` |
| TXT | `mail.kalosstudio.it` | `v=spf1 include:amazonses.com ~all` |

---

## 3. Configuration set ed eventi

Il configuration set è ciò che collega gli invii al tracciamento aperture/click
e al webhook.

1. **SES → Configuration sets → Create set**, nome: `kalos-events`.
2. Attiva **Open and click tracking**.
3. Imposta un **custom redirect domain** (es. `track.kalosstudio.it`, un CNAME
   verso `r.eu-central-1.awstrack.me`). Senza, i link nelle email vengono
   riscritti su `awstrack.me`, visibile e poco professionale.
4. Attiva **Reputation metrics** e la **account-level suppression list**
   (bounce + complaint): SES smette da solo di riscrivere a indirizzi morti.

### Event destination → SNS

1. **SNS → Create topic** (Standard), nome: `kalos-ses-events`.
2. Nel topic, **Edit → Delivery policy**, e imposta la firma a
   **Signature version 2** (SHA-256). Il webhook accetta anche la v1, ma la v2
   è quella raccomandata.
3. Torna sul configuration set → **Event destinations → Add destination**:
   - Tipo: **Amazon SNS**, topic: `kalos-ses-events`
   - Eventi: `Send`, `Delivery`, `Bounce`, `Complaint`, `Open`, `Click`, `Reject`
4. **SNS → topic → Create subscription**:
   - Protocol: **HTTPS**
   - Endpoint:
     `https://tkioedsebdxqblgcctxv.supabase.co/functions/v1/ses-webhook?token=<SES_WEBHOOK_SECRET>`
   - Lascia **Raw message delivery disattivato** (il webhook si aspetta la busta SNS).

La sottoscrizione resta *Pending confirmation* finché la function non è
deployata: SNS invia un messaggio `SubscriptionConfirmation`, che il webhook
conferma da solo chiamando la `SubscribeURL`. Deploya prima (punto 6), poi
crea la sottoscrizione — o usa **Request confirmation** per rimandarla.

---

## 4. Utente IAM

**IAM → Users → Create user** (`kalos-ses-sender`), accesso programmatico, con
questa policy inline — solo i due permessi che servono:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SendEmail",
      "Effect": "Allow",
      "Action": ["ses:SendEmail", "ses:SendRawEmail"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ses:FromAddress": "newsletter@kalosstudio.it"
        }
      }
    },
    {
      "Sid": "ReadQuota",
      "Effect": "Allow",
      "Action": ["ses:GetAccount"],
      "Resource": "*"
    }
  ]
}
```

`ses:GetAccount` serve alla schermata Newsletter del gestionale per mostrare la
quota reale invece di un numero fisso. La condizione su `ses:FromAddress` limita
il danno se la chiave venisse esfiltrata: può inviare solo da quell'indirizzo.

Salva Access Key ID e Secret: il secret è mostrato una volta sola.

---

## 5. Uscita dalla sandbox

In sandbox puoi scrivere solo a indirizzi verificati, max 200/giorno a 1/secondo.

**SES → Account dashboard → Request production access**:

- Tipo di mail: **Transactional** (l'uso prevalente sono promemoria e conferme)
- Sito web: `https://kalosstudio.it`
- Descrizione: spiega che si tratta di comunicazioni a clienti iscritti di un
  centro benessere, con doppio opt-in, unsubscribe one-click e gestione
  automatica dei bounce.
- **Volume giornaliero richiesto: 5.000** — non i 50.000 di default.

L'ultimo punto è una protezione concreta: la quota giornaliera è un tetto
rigido, quindi anche in caso di bug con invio in loop il danno massimo è
5.000 × $0,0001 = **$0,50 al giorno**.

L'approvazione arriva in genere entro 24 ore.

---

## 6. Configurazione Supabase e deploy

```bash
cd kalos-contract

# Credenziali e configurazione SES
npx supabase secrets set SES_ACCESS_KEY_ID=AKIA...
npx supabase secrets set SES_SECRET_ACCESS_KEY=...
npx supabase secrets set SES_REGION=eu-central-1
npx supabase secrets set SES_CONFIGURATION_SET=kalos-events
npx supabase secrets set SES_DAILY_QUOTA=5000

# Segreto condiviso per il webhook (genera un valore casuale)
npx supabase secrets set SES_WEBHOOK_SECRET="$(openssl rand -hex 24)"

# Finché sei in sandbox il rate è 1/secondo: rallenta il loop.
# Da rimuovere dopo l'approvazione della produzione.
npx supabase secrets set SES_SEND_DELAY_MS=1100

# Deploy
npx supabase functions deploy ses-webhook --no-verify-jwt
npx supabase functions deploy send-newsletter
npx supabase functions deploy retry-newsletter
npx supabase functions deploy process-notification-queue
npx supabase functions deploy resend-confirmation-email
npx supabase functions deploy get-email-quota
```

I secret `MAIL_FROM_EMAIL`, `MAIL_REPLY_TO` e `MAIL_UNSUBSCRIBE_MAILTO` sono
opzionali: se assenti il codice ricade sui vecchi `RESEND_*` già configurati,
quindi non c'è niente da toccare durante la transizione.

**Nessuna migrazione database.** Il MessageId di SES viene salvato nelle colonne
`resend_id` esistenti, quindi non serve né una release del contract né un
aggiornamento dei consumer.

---

## 7. Test di fumo

Ancora in sandbox, verifica l'indirizzo di test in **SES → Identities**, poi:

1. Manda una newsletter di prova a quel solo indirizzo dal gestionale.
2. Controlla che arrivi con il mittente corretto: **`Studio Kalòs`**, con la
   `ò` intatta. SES rifiuta i display name non-ASCII non codificati, e il
   modulo li incapsula in MIME encoded-word — questo test lo conferma.
3. Apri l'email e clicca un link.
4. Verifica in `newsletter_tracking_events` che compaiano `delivered`, `opened`,
   `clicked`. Se non arrivano, il problema è nella catena SNS: controlla i log
   con `npx supabase functions logs ses-webhook`.
5. Controlla che `newsletter_emails.resend_id` contenga il MessageId di SES.

---

## 8. Protezioni contro un invio impazzito

AWS fattura a consumo senza tetto, quindi la difesa è a tre livelli
indipendenti. I primi due sono già nel codice, il terzo lo configuri tu.

### Livello 1 — tetto sui destinatari (codice)

`send-newsletter` rifiuta qualsiasi campagna sopra
`MAIL_MAX_RECIPIENTS_PER_CAMPAIGN` (default **1.000**). Con ~500 clienti reali,
un numero molto più alto significa che la query dei destinatari è andata storta:
meglio bloccare che far partire l'invio.

```bash
npx supabase secrets set MAIL_MAX_RECIPIENTS_PER_CAMPAIGN=1000   # opzionale
```

### Livello 2 — gate sulla quota (codice)

Prima di iniziare, `send-newsletter` e `retry-newsletter` chiedono a SES quanta
quota resta nella finestra mobile di 24 ore. Se non basta per l'intera
campagna, l'invio **non parte affatto** e risponde `SES_QUOTA_INSUFFICIENT`.

Questo evita lo scenario peggiore: sforare a metà lista, con una parte dei
clienti che riceve la newsletter e l'altra no, e la campagna in stato
incoerente. I record restano `pending`, quindi il pulsante **Riprova** del
gestionale riprende la campagna quando la finestra si libera.

### Livello 3 — tetto AWS (console)

1. **Quota giornaliera a 5.000** (richiesta al punto 5): è un limite rigido lato
   AWS, quindi il danno massimo teorico è 5.000 × $0,0001 = **$0,50 al giorno**.
2. **AWS Budgets → Create budget → Cost budget**, soglia **$5/mese**, notifica
   via email all'80% e al 100%.

Il livello 3 è quello che conta davvero, perché è l'unico che regge anche se il
codice ha un bug: gli altri due si limitano a far fallire l'invio prima e con un
messaggio comprensibile.

---

## 9. Dopo l'approvazione della produzione

```bash
npx supabase secrets unset SES_SEND_DELAY_MS   # torna al default 100ms (10/sec)
```

Una campagna da 500 destinatari passa così da ~8 minuti a **~50 secondi**.
`sendEmail()` gestisce comunque il throttling con retry e backoff esponenziale,
quindi un rate leggermente troppo aggressivo rallenta ma non perde email.

---

## 10. Rollback

`_shared/resend.ts` è rimasto al suo posto, intatto. Per tornare indietro:

```bash
cd kalos-contract/supabase/functions
sed -i '' "s|from '../_shared/ses.ts'|from '../_shared/resend.ts'|" \
  send-newsletter/index.ts retry-newsletter/index.ts \
  process-notification-queue/index.ts resend-confirmation-email/index.ts
```

Poi rimuovi `SEND_DELAY_MS` dagli import di `send-newsletter` e
`retry-newsletter` e rimetti `const EMAIL_DELAY_MS = 1000`, e rideploya.
I record DKIM di Resend, se non li hai rimossi, sono ancora validi.

Da fare solo **dopo** che SES è stabile da qualche settimana: rimuovere
`_shared/resend.ts`, la function `resend-webhook`, i secret `RESEND_*` e i
record DNS di Resend.

---

## Stato del codice

| File | Stato |
|---|---|
| `supabase/functions/_shared/ses.ts` | **nuovo** — transport SES v2, firma SigV4 via `aws4fetch`, retry su throttling, encoding RFC 2047 del display name, lettura quota live |
| `supabase/functions/ses-webhook/index.ts` | **nuovo** — eventi SNS con verifica della firma, conferma automatica della sottoscrizione |
| `supabase/functions/send-newsletter/index.ts` | import aggiornato, rate limit da `SEND_DELAY_MS`, tetto destinatari, gate sulla quota |
| `supabase/functions/retry-newsletter/index.ts` | idem, con gate sulla quota |
| `supabase/functions/process-notification-queue/index.ts` | import aggiornato |
| `supabase/functions/resend-confirmation-email/index.ts` | import aggiornato |
| `supabase/functions/get-email-quota/index.ts` | quota reale da SES invece dei limiti fissi di Resend |
| `supabase/functions/_shared/resend.ts` | **invariato** — percorso di rollback |
| `supabase/functions/resend-webhook/index.ts` | **invariato** — da rimuovere a migrazione consolidata |

### Differenze di comportamento rispetto a Resend

- **Bounce transitori**: Resend riportava un unico evento `bounced`. SES
  distingue `Permanent` da `Transient`, e il webhook marca
  `clients.email_bounced` **solo sui permanenti**. Una casella piena non
  disabilita più le email di un cliente.
- **Quota giornaliera**: la schermata Newsletter mostra ora la finestra mobile
  di 24 ore riportata da SES, non il conteggio per giorno solare del database.
  È il numero che determina davvero se un invio passa.
