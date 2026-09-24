# Pagamenti online con Stripe

Quota associativa dal sito ("Diventa sociə") e donazioni con carta, dalla sessione 5 del
[piano](../docs/PIANO-APS-E-NUOVA-APP.md). Gli acquisti in app (abbonamenti, eventi) arrivano con la
sessione 9 sullo stesso webhook.

> **Stato (24/09/2026):** codice, database e function pronti; **l'account Stripe dell'APS non esiste
> ancora**. Finché non c'è, l'interruttore `payments` resta spento: il sito accetta le domande di
> ammissione e dice che la quota si versa in studio; le donazioni con carta non compaiono.

## 1. Come funziona

```
sito ──► stripe-checkout ──► Stripe Checkout (pagina di Stripe) ──► la persona paga
                                                                        │
             registro, quota, ricevuta, email ◄── stripe-webhook ◄──────┘
```

- **Checkout ospitato da Stripe:** i dati della carta non passano mai dal sito, nessuno script di
  Stripe sulle nostre pagine, niente cookie di Stripe sul nostro dominio. Carta, Apple Pay e Google Pay
  (D2): il codice chiede solo `card`, che li comprende tutti e tre e nient'altro. Sempre pagamenti una
  tantum, mai rinnovi.
- **L'importo lo decide il database:** per la quota `prepare_my_fee_payment` legge l'importo
  deliberato; per le donazioni il sito propone 10 · 25 · 50 · 100 € o "altro", da 5 a 1.000 €.
- **Il webhook non si fida dell'ordine degli eventi:** ogni evento fa rileggere da Stripe lo stato
  completo del pagamento (commissione e rimborsi compresi) e lo passa a
  `stripe_apply_payment_state`, l'unico punto che scrive. Doppioni, eventi in parallelo o fuori
  ordine non cambiano il risultato.
- **Cosa nasce da un pagamento riuscito:** l'incasso in `transactions` (metodo `stripe`, fonte `site`),
  la quota segnata come pagata, la ricevuta numerata, l'email con il PDF, e la commissione di Stripe
  come uscita nella categoria "Commissioni" (H5).
- **Stessa quota pagata due volte** (due schede del browser): il secondo incasso si registra (il denaro
  è arrivato) come doppione, **senza ricevuta**, e compare in Incassi → Online da rimborsare.
- **Rimborsi:** mai automatici (D4). Dal gestionale, solo admin e Tesoriere: il denaro torna sulla
  carta e il registro si aggiorna da solo. Anche un rimborso fatto dalla dashboard di Stripe viene
  registrato. Stripe non restituisce la commissione: l'uscita resta.
- **Contestazioni (chargeback):** nessuna scrittura automatica; ops-health manda l'avviso e le si
  gestisce dalla dashboard di Stripe.

### Mai dati di prova nel registro vero

Un pagamento in modalità test scrive incassi, ricevute, email e uscite **solo** dove esiste
l'interruttore `stripe_test_ledger`, che non è in nessuna migrazione: lo crea solo `seed.sql`, cioè
solo il database locale. In produzione un pagamento di prova resta in `stripe_payments` e basta: la
numerazione delle ricevute non ha buchi, e una ricevuta di prova occuperebbe un numero per sempre.

### Interruttori

| Interruttore | Spento | Acceso |
|---|---|---|
| `payments` | Nessun checkout si apre; il sito nasconde il pagamento della quota e le donazioni con carta | Pagamenti online attivi |
| `stripe_live` | Le function accettano solo una chiave di prova | Accettano solo una chiave live |
| `stripe_test_ledger` | (non esiste in produzione) | Solo in locale: i pagamenti di prova scrivono nel registro |

Se la chiave e `stripe_live` non sono coerenti, nessun checkout si apre (`STRIPE_MODE_MISMATCH`): è
il segnale che qualcosa è stato configurato a metà.

## 2. Aprire l'account (lo fa il Presidente)

1. **stripe.com → Registrati** con **info.studiokalos@gmail.com** (G3). Paese Italia.
2. **Tipo di attività:** organizzazione senza scopo di lucro / associazione non riconosciuta.
   Denominazione "Studio Kalòs Associazione di Promozione Sociale", C.F. e P.IVA **01292700315**, sede
   Piazza Furlan 5, 34077 Ronchi dei Legionari (GO), sito https://kalosstudio.it, attività: corsi e
   attività associative di benessere (yoga, meditazione, movimento) riservati ai soci, donazioni.
3. **Rappresentante legale:** Andrea Scocchi, Presidente (documento d'identità).
4. **Conto per gli accrediti:** l'IBAN del conto intestato all'APS.
5. **Descrittore sull'estratto conto:** `STUDIO KALOS APS` (massimo 22 caratteri, senza accenti).
6. **Impostazioni → Metodi di pagamento:** carta, Apple Pay, Google Pay attivi; gli altri spenti
   (il codice li esclude comunque).
7. **Impostazioni → Email ai clienti:** spegnere le ricevute di Stripe per pagamenti riusciti e
   rimborsi. Valgono le nostre ricevute numerate, e due documenti diversi confondono.
8. **Impostazioni → Branding:** logo, colore `#036257`, email di assistenza info.studiokalos@gmail.com.
9. **Radar → Regole:** attivare "Blocca se la verifica del CVC non va a buon fine" e "Blocca se la
   verifica del CAP non va a buon fine". Il modulo delle donazioni è aperto a tutti: è il bersaglio
   tipico di chi prova carte rubate (lato nostro ci sono già minimo 5 € e 10 tentativi l'ora per IP).

⚠️ Lo Stripe CLI installato sul Mac è collegato all'account **"ASD Pallacanestro Bisiaca"**: prima di
usarlo per Kalòs, `stripe login` sull'account dell'APS. Mai chiavi di un altro ente nei secret di
Supabase.

## 3. Webhook e secret

**Endpoint:** `https://tkioedsebdxqblgcctxv.supabase.co/functions/v1/stripe-webhook`

**Versione dell'API:** `2026-08-26.dahlia`, la stessa della libreria (`npm:stripe@22.6.2` in
`_shared/stripe.ts`). Il webhook rilegge comunque tutto dall'API, quindi una versione diversa non
rompe nulla, ma è meglio che coincidano.

**Eventi da inviare** (solo questi):

```
checkout.session.completed
checkout.session.async_payment_succeeded
checkout.session.async_payment_failed
checkout.session.expired
charge.updated
charge.refunded
refund.created
refund.updated
refund.failed
charge.dispute.created
charge.dispute.updated
charge.dispute.closed
```

Dalla dashboard (Sviluppatori → Webhook → Aggiungi destinazione, scegliendo la versione dell'API),
oppure col CLI collegato all'account dell'APS (`--live` crea l'endpoint in modalità live; senza, in
modalità test):

```bash
stripe webhook_endpoints create --live \
  -d url=https://tkioedsebdxqblgcctxv.supabase.co/functions/v1/stripe-webhook \
  -d api_version=2026-08-26.dahlia \
  -d "enabled_events[]=checkout.session.completed" -d "enabled_events[]=checkout.session.expired" \
  -d "enabled_events[]=checkout.session.async_payment_succeeded" -d "enabled_events[]=checkout.session.async_payment_failed" \
  -d "enabled_events[]=charge.updated" -d "enabled_events[]=charge.refunded" \
  -d "enabled_events[]=refund.created" -d "enabled_events[]=refund.updated" -d "enabled_events[]=refund.failed" \
  -d "enabled_events[]=charge.dispute.created" -d "enabled_events[]=charge.dispute.updated" -d "enabled_events[]=charge.dispute.closed"
```

**Secret** (li imposta chi ha accesso a Supabase):

```bash
npx supabase secrets set \
  STRIPE_SECRET_KEY=sk_live_… \
  STRIPE_WEBHOOK_SECRET=whsec_… \
  CHECKOUT_ALLOWED_ORIGINS=https://kalosstudio.it,https://www.kalosstudio.it
```

- `STRIPE_WEBHOOK_SECRET` accetta più segreti separati da virgola: serve durante una rotazione.
- `CHECKOUT_ALLOWED_ORIGINS`: dove si torna dopo il pagamento. Il primo è quello di ripiego.
- `STRIPE_API_BASE` **non va mai impostato in produzione** (serve solo al finto Stripe locale, e
  fuori dal locale viene ignorato comunque).

**Deploy delle function:**

```bash
npx supabase functions deploy stripe-checkout stripe-webhook stripe-refund send-receipt member-application receipt-pdf
```

`stripe-webhook` gira senza JWT (`config.toml`): Stripe non ne manda uno, la sicurezza è la firma.

## 4. Andare live

1. Account Stripe verificato, IBAN collegato, impostazioni del §2 fatte.
2. Endpoint del webhook creato **in modalità live** (§3); segreto copiato.
3. `supabase secrets set` con la chiave **live** e il segreto live.
4. Nel database, insieme:
   ```sql
   update feature_flags set enabled = true where key in ('stripe_live', 'payments');
   ```
5. Sul sito, Stripe passa da "fornitori previsti" a "fornitori" in
   `kalos-website/kalos-react/src/config/associazione.json` (privacy), con `legaliAggiornatiAl`.
6. **Primo pagamento vero fatto dallo staff** (per esempio una donazione piccola): controllare
   incasso, ricevuta, email ricevuta, commissione tra le uscite. Niente pagamenti "di prova" con
   carte vere da rimborsare: ogni ricevuta occupa un numero per sempre.
7. Guardare `stripe_events` per qualche giorno: nessun `error_message`, nessun evento con
   `processed_at` vuoto (lo controlla anche ops-health ogni due ore).

**Prova in modalità test prima del live** (facoltativa): in locale con le chiavi di prova dell'APS e
`stripe listen --forward-to http://127.0.0.1:54321/functions/v1/stripe-webhook` (il CLI stampa il
`whsec_` da mettere nel file di env delle function). In produzione una prova con chiavi di test è
innocua per il registro, ma il pulsante di pagamento sarebbe visibile a tutti per quel tempo.

## 5. Spegnimento d'emergenza

```sql
update feature_flags set enabled = false where key = 'payments';
```

Nessun checkout nuovo si apre; il sito torna a "la quota si versa in studio". Il webhook continua a
registrare i pagamenti già in corso e i rimborsi. Per riaccendere, lo stesso comando con `true`.

## 6. Prove in locale senza account Stripe

`scripts/stripe-local/`: un finto server Stripe in memoria e un driver che fa il giro completo
(domanda dal sito, checkout, pagamento, eventi firmati come li firma Stripe, doppioni e parallelo,
commissione in ritardo, rimborsi dal gestionale e "dalla dashboard", rimborso fallito, pagamento di
prova dove il registro non è ammesso, limiti).

```bash
npx supabase start && npx supabase db reset
node scripts/stripe-local/fake-stripe.mjs &
node scripts/stripe-local/run-scenarios.mjs          # la prima volta scrive l'env delle function ed esce
npx supabase functions serve --env-file scripts/stripe-local/.env.functions.local &
node scripts/stripe-local/run-scenarios.mjs          # 43 controlli
```

Più i test del database (`npm run test:db`, file `online_payments.test.sql`) e quelli delle email
(`cd supabase/functions && deno test --allow-env --allow-write --allow-read --node-modules-dir=none tests/email_test.ts`,
con `EML_OUT=<cartella>` per avere i `.eml` e i PDF da aprire).
