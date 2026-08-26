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

## 0. Checklist operativa

> Da seguire in ordine; le sezioni numerate sotto spiegano ogni punto per esteso.
> Circa un'ora di clic più due attese. Esiste anche in versione stampabile:
> [`AWS_SES_CHECKLIST.html`](AWS_SES_CHECKLIST.html).
> **Percorsi e moduli verificati sulla documentazione AWS ad agosto 2026.**

**Prima di sedersi**

- [ ] Carta di credito e documento (AWS verifica l'identità e fa un addebito di prova di ~1 €, poi stornato)
- [ ] **Accesso al pannello DNS di `kalosstudio.it`** con permessi su CNAME, TXT e MX ← è il punto che blocca più spesso
- [ ] Un indirizzo email di prova accessibile (in sandbox si scrive solo a indirizzi verificati)
- [ ] Un password manager per due chiavi segrete — non una chat, non un file nel repo

**I passaggi**

- [ ] **1. Account AWS** — piano **a consumo (Paid)**, *non* il Free: si disattiva dopo 6 mesi e ferma le email. Attivare la MFA sull'utente root. → §1
- [ ] **2. Regione `eu-central-1` (Frankfurt)** e restarci sempre: identità, set, topic, quote e stato sandbox sono per-regione. → §1
- [ ] **3. Dominio + Easy DKIM (RSA_2048)** — `SES → Configuration → Identities → Create identity`, tipo Domain. Restituisce **3 CNAME** da pubblicare (i valori li genera AWS). Attenzione ai pannelli DNS che aggiungono da soli il suffisso del dominio. → §2
- [ ] ⏳ *Attesa: di norma < 30 minuti, ma SES può metterci fino a 72 ore*
- [ ] **4. SPF e DMARC sul dominio** — **mai due record SPF**: se ne esiste già uno, aggiungere `include:amazonses.com` dentro quello, lasciando Resend. DMARC in osservazione (`p=none`) su `_dmarc.kalosstudio.it`. → §2
- [ ] **5. Custom MAIL FROM** `mail.kalosstudio.it` — `Behavior on MX failure` = **Use default MAIL FROM domain** (l'altra opzione fa fallire tutti gli invii). **Un solo MX** su quel sottodominio, e il sottodominio non va usato per altro. Rilevamento fino a 72 h, ma non blocca gli invii. → §2
- [ ] **6. Configuration set `kalos-events`** — open/click tracking, custom redirect domain `track.kalosstudio.it` (senza, i link vengono riscritti su `awstrack.me`), reputation metrics, suppression list a livello account. → §3
- [ ] **7. Topic SNS `kalos-ses-events`** — Standard, **Signature version 2**, event destination con Send/Delivery/Bounce/Complaint/Open/Click/Reject. *La sottoscrizione HTTPS si crea dopo il deploy.* → §3
- [ ] **8. Utente IAM `kalos-ses-sender`** + policy inline. Le chiavi si creano **dopo**, dalla scheda *Security credentials* → *Create access key* → **Other** → *Show* / *Download .csv*. **Il secret si vede una volta sola.** → §4
- [ ] **9. Uscita dalla sandbox** — `Account dashboard → View Get set up page → Request production access`. Campi: Mail type **Transactional**, Website URL, Additional contacts, lingua **English**, Acknowledgement. **Niente campo per il volume**: approvati, la quota è 50.000/giorno. → §5
- [ ] **10. Tetto di spesa** — `Budgets → Create budget → Cost budget`, **$5/mese**, notifica a 80% e 100%. È qui che si mette il limite, non nella quota. → §8
- [ ] ⏳ *Attesa ~24 ore — risposta di AWS. Nel frattempo si può già fare il punto 11.*
- [ ] **11. Passare le due chiavi a Claude** → secret su Supabase, deploy delle 6 function, segreto webhook, poi **insieme** la sottoscrizione SNS e il test di fumo. → §6, §7

**Valori già compilati**

| Cosa | Valore |
|---|---|
| Regione | `eu-central-1` |
| Dominio | `kalosstudio.it` |
| Mittente | `newsletter@kalosstudio.it` |
| Configuration set | `kalos-events` |
| Topic SNS | `kalos-ses-events` |
| Utente IAM | `kalos-ses-sender` |
| TXT · SPF su `kalosstudio.it` | `v=spf1 include:amazonses.com ~all` |
| TXT · DMARC su `_dmarc.kalosstudio.it` | `v=DMARC1; p=none; rua=mailto:dmarc@kalosstudio.it` |
| MX · `mail.kalosstudio.it` | `10 feedback-smtp.eu-central-1.amazonses.com` |
| TXT · `mail.kalosstudio.it` | `v=spf1 include:amazonses.com ~all` |
| CNAME · `track.kalosstudio.it` | `r.eu-central-1.awstrack.me` |

**Se qualcosa non convince:** `_shared/resend.ts` è intatto e i record DNS di Resend restano validi
finché non si rimuovono — i due provider usano selettori DKIM diversi e convivono. Tornare indietro è
cambiare un import e rideployare (§10). Non rimuovere nulla di Resend finché SES non è stabile da
qualche settimana.

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

**IAM → Users → Create user** (`kalos-ses-sender`), **senza** accesso alla console
(serve solo per l'API), con questa policy inline — i due soli permessi necessari:

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

Le chiavi si creano **in un secondo momento**, non più insieme all'utente: il
vecchio flusso con la spunta "accesso programmatico" non esiste più.

Aperto l'utente → scheda **Security credentials** → sezione **Access keys** →
**Create access key** → nella pagina *Access key best practices & alternatives*
scegli **Other** → **Next** → (tag facoltativo) → **Create access key** → **Show**
per rivelare il secret, o **Download .csv**.

Salva subito Access Key ID e Secret: il secret è mostrato **una volta sola**, e se
lo perdi va cancellata la chiave e ricreata.

---

## 5. Uscita dalla sandbox

In sandbox puoi scrivere solo a indirizzi verificati (o al mailbox simulator),
**200 messaggi ogni 24 ore** e **1 al secondo**; anche le azioni bulk sulla
suppression list sono disabilitate.

Percorso: **SES → Account dashboard →** nel riquadro di avviso *"Your Amazon SES
account is in the sandbox"* → **View Get set up page** → **Request production
access**.

Il modulo chiede:

- **Mail type**: **Transactional** (l'uso prevalente sono promemoria e conferme)
- **Website URL**: `https://kalosstudio.it`
- **Additional contacts**: fino a 4 indirizzi, separati da virgola
- **Preferred contact language**: **English** (le uniche opzioni sono inglese e giapponese)
- **Acknowledgement**: spunta di conferma su consenso esplicito dei destinatari e
  gestione di bounce e complaint

L'approvazione arriva in genere entro 24 ore; finché la richiesta è in revisione i
dati non sono modificabili.

> **Correzione 2026-08-24.** La versione precedente di questa guida diceva di
> chiedere un volume giornaliero di 5.000 al posto dei 50.000 di default, e ne
> faceva la protezione principale sui costi. **Quel campo non esiste più nel
> modulo**, e non c'è nemmeno più la descrizione libera del caso d'uso. Approvato
> l'account, la quota è quella predefinita di **50.000 al giorno**, e AWS
> documenta solo come *aumentarla*: non c'è una via self-service per abbassarla.
> Il tetto di spesa va quindi messo con AWS Budgets — vedi §8, livello 3.

Nota: **la quota conta i destinatari, non i messaggi.** Una campagna a 500 persone
pesa 500.

---

## 6. Configurazione Supabase e deploy

```bash
cd kalos-contract

# Credenziali e configurazione SES
npx supabase secrets set SES_ACCESS_KEY_ID=AKIA...
npx supabase secrets set SES_SECRET_ACCESS_KEY=...
npx supabase secrets set SES_REGION=eu-central-1
npx supabase secrets set SES_CONFIGURATION_SET=kalos-events
npx supabase secrets set SES_DAILY_QUOTA=50000   # solo display, vedi nota

# Segreto condiviso per il webhook (genera un valore casuale)
npx supabase secrets set SES_WEBHOOK_SECRET="$(openssl rand -hex 24)"

# Finché sei in sandbox il rate è 1/secondo: rallenta il loop.
# Da rimuovere dopo l'approvazione della produzione.
npx supabase secrets set SES_SEND_DELAY_MS=1100

# Deploy
npx supabase functions deploy ses-webhook   # verify_jwt=false è in config.toml
npx supabase functions deploy send-newsletter
npx supabase functions deploy retry-newsletter
npx supabase functions deploy process-notification-queue
npx supabase functions deploy resend-confirmation-email
npx supabase functions deploy get-email-quota
```

> **`SES_DAILY_QUOTA` non limita nulla.** È solo il numero che il gestionale mostra
> quando l'API SES non risponde: il gate vero legge la quota live da SES prima di
> ogni campagna (§8, livello 2). Tienilo allineato alla quota reale dell'account —
> 200 in sandbox, 50.000 dopo l'approvazione — altrimenti la schermata Newsletter
> mostra un tetto che non esiste.

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

AWS fattura a consumo senza tetto e la quota SES non è abbassabile (§5), quindi
la difesa è a quattro livelli. I primi tre sono nel codice e bloccano **prima**
che l'email parta; il quarto è lato AWS e agisce dopo.

### Livello 1 — tetto giornaliero (codice)

Prima di ogni invio massivo, `send-newsletter`, `retry-newsletter` e
`process-notification-queue` chiedono a SES quante email sono già partite nelle
ultime 24 ore e si fermano se il lotto sforerebbe `MAIL_DAILY_CAP`
(default **1.500**, cioè al massimo **$0,15 al giorno**).

È l'unico blocco in tempo reale contro un bug che invia in loop: AWS Budgets se
ne accorge ore dopo, a soldi già spesi.

```bash
npx supabase secrets set MAIL_DAILY_CAP=1500   # opzionale, questo è il default
```

Il tetto effettivo è sempre il minore tra questo valore e la quota AWS. Se la
verifica non riesce (API SES irraggiungibile) il controllo lascia passare: bloccare
tutte le email per un intoppo momentaneo fermerebbe anche i promemoria delle
lezioni, e nello scenario che questa guardia previene — il loop — l'API funziona.

### Livello 2 — tetto sui destinatari per campagna (codice)

`send-newsletter` rifiuta qualsiasi campagna sopra
`MAIL_MAX_RECIPIENTS_PER_CAMPAIGN` (default **1.000**). Con ~500 clienti reali,
un numero molto più alto significa che la query dei destinatari è andata storta.

```bash
npx supabase secrets set MAIL_MAX_RECIPIENTS_PER_CAMPAIGN=600
```

### Livello 3 — nessun invio parziale (codice)

Se il lotto non entra sotto il tetto, l'invio **non parte affatto** invece di
fermarsi a metà lista. I record restano `pending`, quindi il pulsante **Riprova**
del gestionale riprende la campagna quando la finestra si libera, e le notifiche
in coda vengono ritentate al giro successivo. Nulla va perso.

### Livello 4 — AWS Budgets (console)

**AWS Billing → Budgets → Create budget → Cost budget**, soglia **$5/mese**,
notifica all'80% e al 100%.

Opzionale ma consigliato, e **gratuito**: nello stesso budget aggiungi una
**budget action** che allega una policy IAM di *Deny* all'utente
`kalos-ses-sender` al superamento della soglia. I primi due budget con azione
sono senza costi. È l'unico interruttore che stacca davvero la corrente lato AWS.

Attenzione al limite: i dati di fatturazione AWS si aggiornano poche volte al
giorno, quindi l'azione può scattare **con 8-12 ore di ritardo**. È una rete di
sicurezza, non una guardia in tempo reale — quella è il livello 1.

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
