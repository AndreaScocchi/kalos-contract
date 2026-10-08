# Kalos Contract

Shared TypeScript library providing database types, RPC wrappers, and Supabase client factories. **Source of truth for all schema changes.**

## Tech Stack

- **Language**: TypeScript 5.3
- **Build**: tsup 8.0
- **Database**: Supabase PostgreSQL
- **Package**: GitHub-hosted npm package

## Project Structure

```
kalos-contract/
├── src/
│   ├── index.ts                # Main exports
│   ├── types/
│   │   ├── database.ts         # Generated Supabase types
│   │   └── helpers.ts          # Type utilities
│   ├── supabase/
│   │   └── client.ts           # Client factories
│   ├── rpc/
│   │   └── index.ts            # RPC wrappers
│   └── queries/
│       └── public.ts           # Public query helpers
├── supabase/
│   ├── migrations/             # 76 canonical migrations
│   │   ├── 20240101000000_migration_0000.sql
│   │   ├── 20240101000001_migration_0001.sql
│   │   └── ...
│   ├── functions/              # Edge functions
│   ├── seed.sql                # Dev seed data
│   └── config.toml             # Supabase CLI config
├── scripts/                    # Migration utilities
├── package.json
├── tsup.config.ts
└── DATABASE_WORKFLOW.md
```

## Exports

### Client Factories

```typescript
// Browser (Vite, Next.js)
createSupabaseBrowserClient({
  url: string,
  anonKey: string,
  storageKey?: string,
  enableTimeoutMs?: number,      // Default: 30s
})

// Expo (React Native + PWA)
createSupabaseExpoClient({
  url: string,
  anonKey: string,
  storage: Storage,              // Required
  storageKey?: string,           // Default 'sb-auth-token' (la webapp e la nuova app la condividono)
  detectSessionInUrl?: boolean,  // true solo sul web (token di reset nell'hash)
  lock?: LockFunc,               // Da iOS/Android: processLock di supabase-js (v0.3.5)
})

// Validation
assertSupabaseConfig(url, anonKey)
```

### Type Exports

```typescript
type Database        // Full schema type
type Tables<T>       // Table row type
type TablesInsert<T> // Insert type
type TablesUpdate<T> // Update type
type Enums           // Enum types
type Views           // View types

// Usage:
type Lesson = Tables<'lessons'>
type NewBooking = TablesInsert<'bookings'>
```

### RPC Wrappers

```typescript
// User booking
bookLesson(client, {lessonId, subscriptionId?})
cancelBooking(client, {bookingId})
bookEvent(client, {eventId})
cancelEventBooking(client, {bookingId})

// Staff booking
staffBookLesson(client, {lessonId, clientId, subscriptionId?})
staffCancelBooking(client, {bookingId})
staffBookEvent(client, {eventId, clientId})
staffCancelEventBooking(client, {bookingId})
```

### Public Query Helpers

```typescript
getPublicSchedule(client, {from?, to?})
getPublicPricing(client)
getPublicActivities(client)
getPublicOperators(client)
getPublicEvents(client, {from?, to?})
fromPublic(client, viewName)  // Generic view access
```

## Commands

```bash
npm install          # Install dependencies
npm run build        # Compile with tsup
npm run typecheck    # Type check only
npm run clean        # Remove dist/
npm run verify       # Full verification

# Database
npm run db:start     # Start local Supabase
npm run db:stop      # Stop local Supabase
npm run db:link      # Connect to remote
npm run db:push      # Apply migrations to remote
npm run db:diff      # Generate migration from changes
npm run db:migrations:list  # Show migration history
npm run verify:migrations   # Check migration integrity
```

## Database Schema

### Core Tables

| Table | Purpose |
|-------|---------|
| `profiles` | User accounts (1:1 with auth.users) |
| `clients` | CRM records (staff-managed) |
| `activities` | Class types/disciplines |
| `operators` | Instructors/staff |
| `lessons` | Scheduled classes |
| `bookings` | Lesson reservations |
| `plans` | Subscription packages |
| `subscriptions` | Active subscriptions |
| `subscription_usages` | Credit tracking |
| `events` | Special events |
| `event_bookings` | Event registrations |
| `promotions` | Discount codes |
| `waitlist` | Lista d'attesa delle lezioni piene (usata dalla sessione 3 in poi) |

### Associazione, incassi e Finanze (dal 2026-09-23, contract v0.3.0)

| Tabella | A cosa serve |
|---|---|
| `association_settings` | Dati dell'associazione, riga unica: da qui escono le ricevute |
| `association_years` | Quota per anno solare: importo e data di decadenza, decisi dal Consiglio Direttivo |
| `member_applications` | Domande di ammissione (art. 4), con le accettazioni registrate |
| `members` | Libro soci (art. 22): numero, ammissione, cessazione |
| `member_fees` | Quota dovuta o pagata, una riga per persona e anno |
| `volunteers`, `volunteer_reimbursements` | Registro dei volontari e rimborsi con allegato obbligatorio |
| `transactions` | Registro degli incassi; i rimborsi sono righe negative |
| `receipts`, `receipt_sequences` | Ricevute numerate per anno, senza buchi |
| `expense_categories`, `recurring_expenses` | Categorie modificabili e spese ricorrenti da confermare |
| `compensation_models`, `compensation_components`, `compensation_tiers`, `compensation_assignments`, `compensation_entries` | Compensi a mattoni (dalla v0.3.14 con le spese della lezione e il tetto a lezione), congelati quando il mese si chiude |
| `event_operators` | Chi tiene un evento, per calcolarne il compenso |
| `activity_groups`, `locations` | Gruppi di attività e luoghi (sito e app) |
| `trials` | Lezioni di prova: una per attività, sempre gratuite; «convertita» = ha comprato dopo la prova (dalla v0.3.13 non scala ingressi) |
| `site_rebuild_state` | Riga unica: quando il sito va ricostruito e com'è andata l'ultima build (sessione 6) |
| `stripe_events`, `stripe_payments`, `stripe_refunds` | Pagamenti online: memoria del webhook, pagamenti (con `source`, `metadata`, `is_duplicate`), rimborsi |
| `stripe_checkout_attempts` | Limite orario dei checkout delle donazioni per impronta dell'IP (interna) |
| `rendiconto_voci`, `account_transfers`, `operator_compensation_settings`, `compensation_payments` | Finanze (sessione 7): voci del Modello D, giroconti, ritenuta per persona, pagamenti dei compensi |

### Communication Tables

| Table | Purpose |
|-------|---------|
| `notification_queue` | Pending notifications to send |
| `notification_logs` | Sent notification history |
| `notification_preferences` | User channel preferences |
| `notification_reads` | Read status tracking |
| `device_tokens` | Push notification tokens |
| `announcements` | Broadcast messages |
| `newsletter_campaigns` | Email campaigns |
| `newsletter_sends` | Campaign send history |

### Enums

- `booking_status`: booked, canceled, attended, no_show
- `subscription_status`: active, completed, expired, canceled
- `notification_category`: lesson_reminder, subscription_expiry, entries_low, re_engagement, first_lesson, milestone, birthday, new_event, announcement, practice_reminder, practice_resume, journal_reminder, feedback_request, waitlist_promotion, member_application_decided, membership_fee_due, trial_followup, trial_booked, trial_booked_staff
- `feedback_kind`: practice, lesson, onboarding, event, trial
- `notification_channel`: push, email
- `notification_status`: pending, sent, failed, skipped

### Public Views

- `public_site_schedule` - Lesson calendar
- `public_site_pricing` - Subscription plans
- `public_site_activities` - Activities
- `public_site_operators` - Instructors
- `public_site_events` - Events

## RPC Functions (PostgreSQL)

### book_lesson(p_lesson_id, p_subscription_id)
- Validates: deadline, capacity, subscription (obbligatorio dalla v0.3.6: `SUBSCRIPTION_REQUIRED`)
- Creates booking
- Deducts subscription credits
- Returns: `{ok, reason?, booking_id?}`

### cancel_booking(p_booking_id)
- Validates: ownership, cancellation deadline
- Marks booking canceled
- Restores subscription credits
- Returns: `{ok, reason?}`

### book_event(p_event_id)
- Validates: capacity, no double-booking
- Creates event booking
- Returns: `{ok, reason?, booking_id?}`

### cancel_event_booking(p_booking_id)
- Validates: ownership
- Marks booking canceled
- Returns: `{ok, reason?}`

### Soci e incassi dal gestionale (v0.3.1, sessione 4)

| Funzione | Cosa fa |
|---|---|
| `staff_settle_transaction(p_transaction_id, p_method?, p_occurred_on?, p_issue_receipt?, p_causale?)` | Salda un incasso "da saldare": `pending` → `paid` con metodo e data veri, più la ricevuta. Tutto lo staff |
| `staff_pay_member_fee(p_client_id, p_year, p_amount_cents?, p_method?, p_occurred_on?, p_issue_receipt?, p_note?)` | Quota di un anno in un gesto: crea la riga se manca, rifiuta il doppio pagamento, incasso e ricevuta |
| `staff_get_member_statuses(p_client_ids[])` | `{ members_only, statuses: { client_id: stato } }` con gli stati di `internal.member_booking_status` |
| `issue_receipt` (corretta) | Codice fiscale e indirizzo presi anche dalla domanda ancora in attesa: la quota si paga prima della delibera |

**Edge function `receipt-pdf`:** `POST { receipt_id }` con il token dell'utente → PDF della ricevuta,
ridisegnato dalla riga di `receipts` (dati congelati all'emissione) con `_shared/receiptPdf.ts`, lo
stesso disegno che useranno email, Stripe e app. Nessun file salvato.

### Pagamenti online con Stripe (v0.3.2, sessione 5)

Tutto in **[STRIPE_SETUP.md](STRIPE_SETUP.md)**: come funziona, account, webhook, secret, go-live,
spegnimento d'emergenza, prove in locale senza account (`scripts/stripe-local/`).

| Funzione | Chi | Cosa fa |
|---|---|---|
| `prepare_my_fee_payment(p_year?)` | cliente | Si può pagare online la propria quota? Importo deciso dal DB; crea la riga della quota se manca |
| `staff_prepare_stripe_refund(p_transaction_id, p_amount_cents)` | Finanze | Controlli prima del rimborso sulla carta |
| `stripe_apply_payment_state(p_payload)` | solo service_role | **L'unico punto che scrive un pagamento**: incasso, quota, ricevuta, commissione, rimborsi. Idempotente, serializzato sulla riga |
| `stripe_checkout_expired`, `stripe_event_received`, `stripe_event_done`, `stripe_register_checkout_attempt`, `receipt_claim_send`, `receipt_mark_sent` | solo service_role | Servizio del webhook e dell'invio delle ricevute |
| `issue_receipt`, `staff_refund_transaction` | staff / Finanze | Stessa firma; il corpo sta in `internal.issue_receipt_core` e `internal.refund_transaction_core`. `staff_refund_transaction` rifiuta gli incassi online (`USE_STRIPE_REFUND`) |

**Mai dati di prova nel registro:** un pagamento `livemode = false` scrive incassi, ricevute e uscite
solo con l'interruttore `stripe_test_ledger`, che esiste solo nel seed locale.

**Edge function:** `stripe-checkout` (quota col token, donazioni anche anonime), `stripe-webhook`
(senza JWT, firma di Stripe; ogni evento rilegge il pagamento dall'API e chiama
`stripe_apply_payment_state`), `stripe-refund` (Finanze), `send-receipt` (staff: invia o reinvia la
ricevuta con il PDF), `member-application` (domanda dal sito con IP e dispositivo presi dal server,
email con il PDF della domanda). Condivise: `_shared/stripe.ts`, `receiptEmail.ts`,
`applicationPdf.ts`, `receiptData.ts`, `http.ts`, e `ses.ts` con `sendRawEmail` (allegati via
`Content.Raw`). Test delle email: `supabase/functions/tests/email_test.ts`.

**Storage:** i bucket si creano in produzione con gli script di `supabase/storage/`
(`npx supabase db query --linked -f supabase/storage/<bucket>.sql`), non da migrazione.

### Gruppi, luoghi, prove e lista d'attesa (v0.3.3, sessione 6)

| Funzione | Chi | Cosa fa |
|---|---|---|
| `staff_add_to_waitlist(p_lesson_id, p_client_id)` | staff | Mette in fila per una lezione piena (anche chi non ha l'app: `waitlist.user_id` ora può essere NULL) |
| `staff_remove_from_waitlist(p_waitlist_id)` | staff | Toglie dalla fila; se aveva un posto offerto, passa al successivo |
| `submit_trial_feedback(p_trial_id, p_rating, p_answers?, p_comment?)` | cliente | Questionario dopo la prova (feedback `kind = 'trial'`, risposte in `metadata.answers`). Domande in `src/labels.ts` (`TRIAL_FEEDBACK_QUESTIONS`) |
| `staff_book_trial`, `staff_create_client_and_book_trial` | staff | Come prima, più la conferma `trial_booked` con l'invito all'app; la scheda creata al volo si toglie se la prova non va |
| `book_lesson`, `staff_book_lesson`, `join_waitlist` | — | Stessa firma: **un posto offerto a chi è in fila conta come occupato** (risposta `FULL` con `waitlist_offer: true`) |

- **Prove:** una prova disdetta si riprenota (la riga si riusa); lo stato segue la prenotazione
  (trigger `bookings_sync_trial_status`), tranne quando è già `converted`.
- **Lista d'attesa:** offerte su disdetta, aumento dei posti e dal job `internal.cron_waitlist`
  (pg_cron ogni 5 minuti, solo in produzione); chi prenota esce dalla fila da solə.
- **Promemoria** (`queue_lesson_reminders`): luogo e orario nel testo, testo dedicato alle prove, e
  niente invio a chi ha spento push ed email per i promemoria.
- **Ricostruzione del sito:** trigger su `locations`, `activity_groups`, `activities`, `events` (e
  l'interruttore `cinque_per_mille`) → `site_rebuild_state.requested_at`; il job
  `internal.cron_site_rebuild` (pg_cron ogni 5 minuti, solo in produzione) dopo 3 minuti di quiete
  chiama l'edge function **`site-rebuild`**, che chiama il build hook di Netlify (secret
  `NETLIFY_BUILD_HOOK_URL`) e scrive l'esito; ops-health avvisa se fallisce.
- **Interruttore `cinque_per_mille`**, spento: sito e app mostrano il 5x1000 solo acceso.
- **View del sito:** `public_site_events` nasconde gli eventi non pubblicati e aggiunge indirizzo del
  luogo e contributo; `public_site_activities` aggiunge nome del luogo predefinito e `trial_enabled`.
- **Etichette condivise** (`src/labels.ts`): `EVENT_TYPE_LABELS`, `EVENT_TYPE_LABELS_PLURAL`.

### Finanze (v0.3.4, sessione 7)

Contabilità per cassa dell'associazione, dal 19/08/2026, con il rendiconto nello schema del
**Modello D** degli enti del Terzo Settore (DM 5 marzo 2020). Tutto solo Finanze
(`can_access_finance()`: admin e Tesoriere).

| Oggetto | Cosa fa |
|---|---|
| `rendiconto_voci` | Le 58 voci del Modello D (entrate e uscite A–E, imposte, investimenti e disinvestimenti). Sola lettura: le categorie di uscita (`expense_categories.rendiconto_bucket`) e le righe (`expenses.rendiconto_voce`, `transactions.rendiconto_voce`) ci puntano; un trigger rifiuta una voce di entrata su un'uscita e viceversa |
| `account_transfers` | Giroconti fra i conti (enum `cash_account`: cassa, banca e, dalla v0.3.15, Stripe); gli accrediti di Stripe hanno `stripe_payout_id` |
| `association_settings.opening_cash_cents` / `opening_bank_cents` | Saldi al 19/08/2026; si impostano con `finance_set_opening_balances` |
| `expenses.payment_method` | Conto dell'uscita (contanti = cassa, il resto banca). Trigger `internal.expenses_before_write`: allinea `category` da `category_id`, conferma le uscite a mano, e dall'API impedisce di inserire, cambiare o cancellare le uscite automatiche (`payout`, `stripe_fee`, `volunteer`) |
| `operator_compensation_settings` | Ritenuta d'acconto per persona (tabella a parte: `operators` è leggibile dal sito) |
| `compensation_payments` | Un pagamento per persona e mese: lordo, ritenuta, netto, uscite collegate. `compensation_entries.payment_id`. I compensi congelati ora si scrivono solo con le funzioni |

| Funzione | Cosa fa |
|---|---|
| `finance_income_lines(p_from, p_to)` | Entrate del periodo, riga per riga (rimborsi in negativo): conto, voce del rendiconto (`internal.income_voce`: A1 quote, A4 donazioni, A3/A7 contributi da associatə/terzi secondo `internal.client_is_member_on`, B per le commerciali), ricevuta, abbonamento, evento |
| `finance_income_allocations(p_from, p_to)` | Entrate per attività ed evento: un abbonamento si divide in proporzione alle lezioni prenotate con esso (resto dei centesimi alle quote più grandi); `unused` = abbonamento senza prenotazioni, `unlinked` = incasso non collegato |
| `finance_account_balances(p_at)` | Saldi di cassa, banca e (v0.3.15) Stripe a fine giornata |
| `finance_set_opening_balances(p_cash_cents, p_bank_cents)` | Saldi iniziali |
| `staff_register_payment` | Stessa firma: accetta `rendiconto_voce` nel payload, solo dalle Finanze |
| `generate_recurring_expenses(p_month?)` | Recupera i mesi mancanti fino a quello in corso (mai oltre); una ricorrenza riattivata riparte dal mese in corso |
| `confirm_expense(p_expense_id, p_amount_cents?, p_expense_date?, p_payment_method?)` | Conferma con importo, data e metodo veri; l'importo della ritenuta non si cambia (`AMOUNT_LOCKED`) |
| `staff_pay_volunteer_reimbursement(p_reimbursement_id, p_paid_on?, p_method?)` | L'uscita è del giorno del pagamento |
| `calculate_compensation_v2` | Mese in ora italiana, durata vera della lezione, operatrici archiviate incluse; in più `activity_id` |
| `staff_freeze_compensation` | Congela solo quello che è già avvenuto; risponde anche `future` e `no_model` |
| `staff_unfreeze_compensation(p_month_start, p_operator_id?)` | Riapre i congelati non pagati |
| `staff_pay_compensation(p_operator_id, p_month_start, p_paid_on?, p_method?, p_withholding_percent?, p_gross_cents?, p_note?)` | Paga una persona per un mese: netto come uscita del giorno, ritenuta come uscita da confermare con scadenza il 16 del mese dopo (F24). Sostituisce `staff_mark_compensation_paid` |
| `staff_undo_compensation_payment(p_payment_id)` | Annulla un pagamento sbagliato |
| `staff_save_compensation_model(p_payload)` | Modello, spese, mattoni, scaglioni e tetti in un colpo solo (`INVALID_MODEL` e niente di scritto se un mattone è sbagliato) |
| `preview_compensation(p_model_id, p_duration_minutes, p_participants, p_revenue_cents)` | Prova di un modello |

Test: `supabase/tests/finanze.test.sql` (66).

### v0.3.5 (sessione 8)

- La **lista d'attesa si scrive solo con le funzioni**: tolte due policy del 2024 rimaste attive
  (migrazione `20260924200000`). `access_model.test.sql` ora elenca anche le scritture dirette
  concesse ai clienti.
- `createSupabaseExpoClient` accetta `lock` (additivo): la nuova app Expo (`kalos-app`) passa
  `processLock` su iOS e Android.

### v0.3.6 (dopo la sessione 8)

- **`book_lesson` vuole sempre un abbonamento** (migrazione `20260928090000`): con
  `p_subscription_id` NULL risponde `SUBSCRIPTION_REQUIRED` e non prenota. Prima il controllo stava
  solo nell'interfaccia della webapp. Senza abbonamento prenota solo lo staff (`staff_book_lesson`,
  con l'incasso da saldare); le prove passano da `book_trial_lesson`. La regola "solo soci" viene
  prima, quindi `NOT_A_MEMBER` e `MEMBERSHIP_FEE_DUE` restano le risposte di chi non è in regola.

### v0.3.7 (sessione 9: acquisti dall'app)

Migrazioni `20260928120000` (valore enum `trial_booked_staff`), `…120100` (abbonamenti che partono
dal primo ingresso) e `…120200` (pagamenti dall'app, eventi, avviso della prova).

- **`plans.sold_in_app`**: il piano si compra dall'app (interruttore del gestionale, spento di partenza).
- **D5, abbonamento che parte dal primo ingresso** (`subscriptions.starts_on_first_entry`,
  `activation_deadline`, `first_entry_on`): nato da un acquisto in app, `started_at` resta il giorno
  del pagamento e non si sposta mai; `expires_at` è provvisoria (acquisto + 60 + validità) finché non
  c'è un ingresso, poi primo ingresso (o scadenza di attivazione, se viene prima) + validità.
  Ingresso = prenotazione con l'abbonamento, non di prova, prenotata / partecipata / assente, su
  lezione non cancellata; ricalcolo con i trigger su `bookings` e `lessons`
  (`internal.recompute_first_entry`). Lo staff che cambia le date a mano spegne il primo ingresso.
  `book_lesson` e `staff_book_lesson` rispondono `OUTSIDE_SUBSCRIPTION_WINDOW` (con `valid_until`)
  se una lezione più vicina lascerebbe fuori una prenotazione già fatta.
- **`book_lesson` non risponde più `PLAN_NOT_FOUND` per un piano archiviato**: gli abbonamenti già
  venduti restano validi (i clienti leggono il piano con `plans_select_own_subscription`).
- **Acquisti dall'app:** `prepare_my_plan_purchase`, `prepare_my_event_payment`,
  `prepare_my_settlement`, `get_my_open_payments`, `get_my_payment_status` (cliente, solo le proprie
  righe). `stripe-checkout` con gli scopi `subscription`, `event`, `settlement` e `client: 'app'`;
  `stripe_apply_payment_state` passa l'incasso a `internal.stripe_record_income` (quota e donazioni
  come prima). Dettagli in [STRIPE_SETUP.md](STRIPE_SETUP.md) §1bis.
- **Eventi:** `book_event` controlla la capienza anche riattivando un'iscrizione disdetta e risponde
  `EVENT_CONCLUDED` a evento finito; `cancel_event_booking` risponde `PAID_CONTACT_STUDIO` a chi
  disdice (non staff) un'iscrizione già pagata.
- **Avviso allo staff per le prove dall'app** (`internal.queue_trial_booked_staff`, categoria
  `trial_booked_staff`): admin e operatrice della lezione, push web se c'è, altrimenti email.
- Wrapper TS: `prepareMyPlanPurchase`, `prepareMyEventPayment`, `prepareMySettlement`,
  `getMyOpenPayments`, `getMyPaymentStatus` e i loro tipi.
- Un "da saldare" superato (quota versata per un'altra strada, iscrizione disdetta o già pagata,
  abbonamento cancellato) non si paga più: `NO_LONGER_DUE`, e un pagamento già partito diventa un
  doppione (`internal.pending_still_payable`). I contributi si chiedono solo per gli eventi dal
  19/08/2026 (`association_settings.ledger_start_date`).
- Test: `supabase/tests/sessione9.test.sql` (65), `verify-access` (+11), scenari
  `scripts/stripe-local/run-scenarios-app.mjs` (31).

### v0.3.8 (sessione 10: profilo e contenuti dell'app)

Migrazione `20260928160000`.

- **La Bussola è dei soci (D6):** `request_bussola` non chiede più il Community Pass (spento dalla
  sessione 3) ma di essere sociə in regola, cioè poter partecipare (`internal.member_booking_status`
  in `ok` o `fee_due_grace`), anche con "solo soci" spenta. Risposte: `NOT_A_MEMBER`,
  `PENDING_ADMISSION`, `MEMBERSHIP_FEE_DUE`, `NOTE_TOO_LONG` (oltre 1000 caratteri), `ALREADY_OPEN`.
  `cancel_bussola_request`: il cliente ritira solo una richiesta ancora da fissare
  (`ALREADY_SCHEDULED`), quella di un'altra persona risponde `NOT_FOUND`.
- **Le proprie ricevute:** `get_my_receipts()` (elenco, con metodo, tipo e stato dell'incasso) e
  `get_my_receipt(p_receipt_id)` (i campi del PDF). `receipt-pdf` le usa per chi non è staff, sempre col
  token di chi chiede (`_shared/receiptData.ts` → `loadMyReceiptPdfData`).
- **Interruttore `home_practice`**, spento: la Pratica a casa nell'app la vede solo lo staff finché
  non ci sono pratiche vere.
- Wrapper TS: `getMyReceipts`, `getJourneySummary`, `getJourneyTimeline` e i loro tipi.
- Test: `supabase/tests/sessione10.test.sql` (24), `verify-access` (+7).

### v0.3.9 (sessione 11: notifiche, impostazioni e account nell'app)

Migrazione `20260929120000`.

- **Dove porta una notifica:** `internal.notification_path(categoria, data)` dà il percorso dell'app
  (`/lesson/<id>`, `/subscriptions`, `/announcement/<id>`, `/journal`, `/feedback/trial/<id>`…); il
  trigger `notification_queue_set_url` lo scrive in `data.url` di ogni riga nuova (un `url` già
  presente vince solo se è un percorso dell'app). Lo usano il service worker dell'app, le push Expo e
  il pulsante delle email; `get_my_notifications` ha in più `path` (anche per i log di prima).
- **Messaggio dopo la prova (F6):** trigger `bookings_trial_followup` → `internal.queue_trial_followup`
  quando una prova diventa «partecipata»: `trial_followup` con il questionario, un'ora dopo la fine
  della lezione e mai fra le 21 e le 9 (ora italiana), una volta sola per prova, niente a chi ha già
  risposto. Dietro l'interruttore **`trial_followup`**, spento fino al lancio della nuova app.
- **Eliminazione dell'account:** `delete_account_data(p_user_id)`, solo `service_role`, in una
  transazione (vedi ACCESS_MODEL.md). `internal.handle_new_user` riattiva la scheda di chi si
  registra di nuovo con la stessa email (prima la registrazione falliva sull'indice unico).
- **I propri dati:** `update_my_profile(p_full_name, p_phone, p_birthday)` (profilo e scheda
  insieme; `INVALID_NAME`, `INVALID_PHONE`, `INVALID_BIRTHDAY`), `accept_my_legal_documents()`.
- **Interruttore `app_version_gate`**, spento: `payload` con `ios` e `android` (`min`, `latest`,
  `store_url`) e `message`.
- **Edge function:** `delete-account` riscritta sopra `delete_account_data` (risposte `UNAUTHORIZED`,
  `STAFF_ACCOUNT` 403, `DATA_DELETE_FAILED`, `AUTH_DELETE_FAILED`); `process-notification-queue`
  manda le push Expo (`DeviceNotRegistered` disattiva il token, ticket in `expo_receipt_id`,
  `EXPO_ACCESS_TOKEN` facoltativo) e mette `data.url` nel pulsante delle email.
- **Storage:** `supabase/storage/bug-reports.sql`, il bucket delle segnalazioni com'è in produzione.
- Wrapper TS: `getMyNotifications`, `updateMyProfile`, `acceptMyLegalDocuments` e i loro tipi.
- Test: `supabase/tests/sessione11.test.sql` (50), `verify-access` (+9).

### Dopo la v0.3.9: cosa copre un piano (solo dati, nessun tag)

Migrazione `20260929180000`. Un piano vale per le attività di `plan_activities`; **senza attività
vale per tutte** (`book_lesson`, `staff_book_lesson`, nuova app). `plans.discipline` è solo
un'etichetta. I piani in listino che avevano solo la disciplina ricevono le attività non eliminate
della stessa disciplina; il modulo del gestionale ora ne chiede sempre almeno una.

### v0.3.10 (verifica generale del 30/09/2026)

Migrazioni `20260930100000`…`100700` (più `20260929180000`, i piani «a disciplina»). Dettagli e motivi
in `docs/ISSUES.md` del repo dei documenti.

- **Notifiche:** `internal.get_notification_channel` dà un canale solo se si può usare (push accesa e
  un dispositivo, oppure email accesa con un indirizzo che non rimbalza); NULL = non accodare, in tutte
  le code (niente più `COALESCE(…, 'email')`). `internal.notification_exists` guarda coda (qualsiasi
  stato) e log: una notifica saltata non si riaccoda. «Ci manchi!» al massimo ogni 30 giorni
  finché la persona non torna (v0.3.11, decisione dell'utente: nella v0.3.10 era una volta per
  assenza, fino a 60 giorni). Promemoria della sera alle 20:00 italiane (prima a mezzanotte) e ritirati se la prenotazione
  non è più attiva o la lezione cambia orario o si archivia (trigger). `queue_new_event` solo per
  eventi pubblicati, una volta per evento e canale, email solo a chi riceve la newsletter. Annunci:
  push con le preferenze, ritirate o rimesse se l'annuncio cambia, ricorrenti in ora italiana.
  `queue_feedback_request` solo service_role. Categoria nuova `lesson_canceled`.
  `internal.rome_today()` è «oggi in Italia».
- **Soci:** quota senza importo deliberato mai scaduta; decadenza 2026 al 31/12/2026 (decisione del
  30/09); chi era cessatə e rifà domanda segue la domanda. `staff_set_member_fee`: esonero, pagata
  senza incasso e rimborso solo Finanze (`FINANCE_ONLY`). `submit_member_application` accetta canale,
  IP e dispositivo solo da service_role (con `user_id` nel payload). `staff_create_member_application`
  con `p_client_id` NULL crea la scheda (`CLIENT_EMAIL_EXISTS`).
- **Note dello staff** in `client_staff_notes` (solo staff); `clients.notes` resta vuota (trigger),
  il profilo non copia più le note. `internal.append_client_staff_note` per i messaggi automatici.
- **Registrazione** (`internal.handle_new_user`): email senza maiuscole, `accepted_privacy_at` e
  `accepted_terms_at` nei metadata registrati con l'ora del server, `newsletter_opt_out` rispettato.
  `set_my_newsletter_subscription(p_subscribed)` per l'app.
- **Prenotazioni:** abbonamenti eliminati mai usabili; finestra sul giorno italiano; schede archiviate
  non prenotano dall'app (`CLIENT_NOT_FOUND`); lezioni individuali che spostano l'ingresso invece di
  regalarlo; lista d'attesa solo per chi potrebbe prenotare (`internal.lesson_booking_obstacle`);
  `staff_update_booking_status` rifiuta di «riattivare» una disdetta (`BOOKING_CANCELED`); evento
  iniziato non disdicibile dall'app; una prova `no_show` non si converte.
- **Ricevute:** una annullata si sostituisce (`receipts.replaced_transaction_id`, senza chiave esterna
  di proposito); `staff_undo_compensation_payment` rifiuta con la ritenuta già confermata.
- **Gestionale:** `staff_save_plan`, `staff_archive_lessons`.
- **Permessi e pulizia:** `search_path` fisso su tutte le SECURITY DEFINER; anon legge di `operators`
  solo le colonne pubbliche; `social_connections.access_token` non leggibile dall'API; tolte 8
  funzioni senza chiamanti e due indici doppi.
- **Edge function:** `unsubscribe-newsletter` senza JWT (prima nessunə riusciva a disiscriversi);
  token dei link in `_shared/unsubscribe.ts`, senza segreto di ripiego; `send-newsletter` e
  `retry-newsletter` con una sola esecuzione per campagna, un invio per indirizzo, mai a disiscrittə
  o rimbalzati, prova prima dell'invio a chi invia (o `NEWSLETTER_TEST_EMAIL`/`_CLIENT_ID`);
  `process-notification-queue` con HTML sempre in escape, niente email a indirizzi rimbalzati, niente
  promemoria di lezioni già iniziate, code push ed email separate, link «Scegli quali messaggi
  ricevere»; `ses-webhook` segna rimbalzi e segnalazioni di spam anche per le email di servizio;
  `execute-scheduled-campaigns` con i passi del wizard giusti e una sola esecuzione; `meta-publish-post`
  accetta la chiave di sistema; `member-application` registra la domanda con la chiave di sistema.
  Tolte: `resend-webhook` e `_shared/resend.ts` (SES stabile da un mese), `send-push` e
  `recalculate-stats` (mai pubblicate), `schedule-notifications` (nessun chiamante) e il workflow
  `notification-cron.yml`.
- **Pulizie programmate** (`20260930100700`): `internal.purge_rejected_applications()` (domande
  respinte cancellate dopo 12 mesi, come dice la privacy) e `internal.cleanup_job_history()` (storico
  di pg_cron a 30 giorni); i due job si creano a mano in produzione (comandi nella migrazione).
- **TS:** `RpcError` (errore con `code`, `details`, `hint`; stesso messaggio di prima),
  `setMyNewsletterSubscription`, `staffSavePlan`, `staffArchiveLessons`.
- **Test:** `supabase/tests/verifica_30_09.test.sql` (69), `verify-access` 221.

### v0.3.12 (05/10/2026: ingressi rimasti leggibili)

Migrazione `20261005100000`. `subscriptions_with_remaining` non aveva mai avuto un GRANT esplicito e la
leggeva solo service_role: dal 30/09 il gestionale la legge in blocco (Dashboard, Abbonamenti,
Clienti, prenotazioni di lezioni ed eventi) e quelle pagine ricevevano `permission denied` (42501).
Ora `GRANT SELECT ... TO authenticated`; è `security_invoker`, quindi lo staff vede tuttə e ciascun
cliente solo i propri abbonamenti. `access_model.test.sql` elenca ora anche le relazioni **chiuse ad
authenticated** per scelta: una tabella o view nuova che serve alle app e nasce senza GRANT fa
fallire il test. Test: `supabase/tests/ingressi_rimasti.test.sql` (7).

### v0.3.13 (05/10/2026: la prova è sempre gratuita)

Migrazione `20261005110000`, decisione dell'utente del 05/10 che sostituisce F1/F2: **la lezione di
prova non scala mai un ingresso** dagli abbonamenti comprati dopo (prima diventava il primo ingresso,
e un pacchetto da un ingresso comprato dopo la prova nasceva «completato»).
`internal.convert_trial_on_new_subscription` segna ancora la prova `converted` (= ha comprato dopo la
prova, per la pagina Prove) ma non scrive più la riga `TRIAL` in `subscription_usages`; il messaggio
`trial_followup` invita agli abbonamenti senza parlare di primo ingresso. Le righe `TRIAL` esistenti
sono state tolte e il trigger sulla cancellazione ha ricalcolato lo stato degli abbonamenti.
Test: `supabase/tests/prove_gratuite.test.sql` (8); aggiornati `trials`, `sessione9`, `sessione11`.

### v0.3.14 (07/10/2026: spese della lezione nei modelli di compenso)

Migrazioni `20261007100000` (valori dell'enum) e `…100100`. Richiesta della tesoreria per Yoga e
Meditazione: dagli incassi della lezione si tolgono le spese fisse, quello che resta va all'insegnante
fino a un tetto e il resto allo Studio. Il calcolo (`internal.compute_compensation`) ora è:

```
incassi − spese (mattoni cost_*) = quello che resta
compenso = altri mattoni + scaglione → tetti (a lezione e orario: vale il più basso) → minimo → mai < 0
allo Studio = quello che resta − compenso   (può essere negativo)
```

- **Spese della lezione**, nuovi valori di `compensation_component_kind`: `cost_per_lesson`,
  `cost_per_hour`, `cost_per_participant` e `cost_percent_of_revenue` (era `room_fee_percent`,
  rinominato). Il nome della spesa sta in `compensation_components.note`. **Servono solo al calcolo:
  non diventano uscite** (l'affitto vero si registra in Uscite).
- **`percent_of_margin`**: percentuale di quello che resta dopo le spese (zero se le spese superano
  gli incassi, senza mangiare gli altri mattoni). `percent_of_revenue` resta sugli incassi lordi.
- **`compensation_models.max_per_lesson_cents`**: tetto a lezione, salvato da `staff_save_compensation_model`.
- **Cambia il significato della «Trattenuta sala»**: prima si sottraeva dal compenso, ora dagli
  incassi. «100% degli incassi − 15% di sala» si scrive «spesa 15% sugli incassi + 100% di quello che
  resta». In produzione al 07/10 non c'era nessun modello né compenso congelato.
- Il dettaglio del calcolo (`breakdown`, anche in `preview_compensation` e `calculate_compensation_v2`)
  ha in più `costs` (`kind`, `note`, `amount_cents`), `costs_cents`, `margin_cents`, `studio_cents`;
  fra i `components` c'è il nuovo `max_lesson_cap`.
- Test: `supabase/tests/compensation.test.sql` (27, con la ricetta di Yoga e Meditazione).

### v0.3.15 (07/10/2026: Stripe è un conto)

Migrazioni `20261007120000` (valore `stripe` dell'enum `cash_account`) e `…120100`. Prima un
pagamento con carta contava «in banca» dal giorno del pagamento, ma i soldi restano su Stripe finché
Stripe non li accredita sul conto: «In banca» del gestionale non tornava con l'estratto conto.

- **Tre conti:** `internal.cash_account_for` manda il metodo `stripe` sul conto **Stripe** (pagamenti
  con carta e commissioni, che hanno già `payment_method = 'stripe'`); `finance_account_balances`
  restituisce anche `stripe_cents`, e `total_cents` lo comprende. `bank_cents` ora è solo il conto
  corrente. `finance_income_lines` dà `account = 'stripe'` ai pagamenti con carta.
- **Accrediti = giroconti Stripe → banca** nel giorno di arrivo (`account_transfers.stripe_payout_id`,
  unico; vincolo: un giroconto tocca Stripe solo se è un accredito). Li scrive solo
  **`stripe_apply_payout_state(p_payout)`** (solo service_role, idempotente: `recorded`, `updated`,
  `unchanged`, `removed` se l'accredito fallisce o si annulla, `waiting` finché è in viaggio,
  `ignored` se di prova senza `stripe_test_ledger`). Dall'API niente giroconti che toccano Stripe e
  niente modifiche agli accrediti, tranne la nota (`internal.account_transfers_before_write`,
  `AUTOMATIC_TRANSFER`).
- **Edge function:** `stripe-webhook` gestisce `payout.paid`, `payout.failed`, `payout.canceled`,
  `payout.updated` (`reconcilePayout` in `_shared/stripe.ts`); **`stripe-reconcile`** (solo Finanze,
  la chiama il gestionale aprendo le Finanze) rilegge gli accrediti dall'inizio della contabilità e
  confronta il conto Stripe del registro con il saldo vero (disponibile + in arrivo + accrediti in
  viaggio), più `payouts_enabled` e il calendario degli accrediti. `scripts/stripe-setup.mjs` ha gli
  eventi `payout.*` e `--update-events` per aggiungerli all'endpoint esistente senza cambiarne il
  segreto. Dettagli in [STRIPE_SETUP.md](STRIPE_SETUP.md).
- **Rendiconto:** invariato; il saldo di Stripe a fine anno sta nei «Depositi bancari e postali»
  (lo somma il gestionale).
- Test: `supabase/tests/stripe_conto.test.sql` (32), `finanze.test.sql` aggiornato (carta su Stripe),
  `verify-access` (+3), scenari `scripts/stripe-local/run-scenarios-payouts.mjs` (21).

### v0.3.17 (08/10/2026: il modello di compenso predefinito)

Migrazione `20261008110000`. Richiesta dell'utente: una ricetta che valga di base senza assegnarla a
ogni persona («dagli incassi della lezione si tolgono affitto sala, usura dei materiali e accoglienza;
quello che resta va all'insegnante fino a 40 € a lezione, il resto rimane all'Associazione»).

- **`compensation_models.is_default`**: al massimo un modello (indice unico parziale), sempre attivo
  (vincolo `compensation_models_default_is_active`).
- **`internal.resolve_compensation_model`**: prima l'assegnazione per l'attività, poi quella generale,
  poi il **predefinito**. Il modello scelto per un evento (`event_operators.model_id`) vince ancora.
  Senza predefinito il calcolo è quello di prima (`NO_MODEL`); i volontari restano esclusi.
- **`staff_set_default_compensation_model(p_model_id)`** (Finanze): `SAVED`, `MODEL_NOT_FOUND`,
  `MODEL_INACTIVE`, `NOT_FINANCE`; toglie il segno al predefinito di prima.
- **`staff_save_compensation_model`**: stessa firma; disattivare il predefinito risponde
  `DEFAULT_MODEL_ACTIVE`.
- La migrazione non crea modelli: in produzione il modello della richiesta («Compenso Standard») era
  già stato creato dal gestionale l'08/10, e il predefinito si sceglie da lì.
- Test: `supabase/tests/compenso_predefinito.test.sql` (26), `verify-access` (+3).

### get_my_client_id()
- Returns current user's client_id
- **Non crea la scheda cliente**: restituisce NULL se non c'è. La scheda nasce dal trigger su
  `auth.users` alla registrazione, oppure da `submit_member_application` se manca.

### Notification RPCs

| Function | Purpose |
|----------|---------|
| `get_my_notifications(p_limit, p_offset)` | Centro notifiche: log degli ultimi 30 giorni e annunci in corso, con `path` (v0.3.9) |
| `get_unread_notifications_count()` | Quante da leggere |
| `mark_notification_read(p_notification_log_id, p_announcement_id)` | Segna letta (uno dei due) |
| `mark_all_notifications_read()` | Segna tutte lette |
| `deactivate_device_token(p_token)` | Il dispositivo smette di ricevere (all'uscita dall'app) |
| `internal.get_notification_channel(p_client_id, p_category)` | Push se accesa e c'è un dispositivo attivo, altrimenti email se accesa |
| `internal.queue_*` | Le code (promemoria, scadenze, annunci, prove…): non raggiungibili dall'API |

La registrazione dei dispositivi passa dall'edge function `register-push-token` (push web: il testo
JSON dell'iscrizione; app: `ExponentPushToken[…]`).

## Foto nello storage (07/10/2026, nessun tag)

Le foto si comprimono nel gestionale, nel browser di chi le carica. Accanto a ogni originale, che è al
massimo 2400×3600 px, il gestionale salva le versioni ridotte in `varianti/<percorso>/w480|w960|w1600|w2400`
(WebP) e `jpeg1200`. Sito, app e newsletter leggono queste versioni; se una manca, ripiegano
sull'originale. Regole, qualità e motivi in **[supabase/storage/FOTO.md](supabase/storage/FOTO.md)**.

- **Non usare il ridimensionamento di Supabase (`render/image`):** il piano gratuito non lo include.
- **Newsletter:** `send-newsletter` e `retry-newsletter` mettono nell'email la versione `jpeg1200`
  (`_shared/fotoEmail.ts`, che controlla con HEAD che esista).

## Row-Level Security e permessi

Modello completo e regole per funzioni, tabelle e view nuove: **[ACCESS_MODEL.md](ACCESS_MODEL.md)**.
In breve: "tutto chiuso" — anon e authenticated eseguono solo le funzioni elencate in
`supabase/tests/access_model.test.sql` (le funzioni nuove nascono chiuse), anon legge solo i dati
pubblici del sito e non scrive nulla. Verifiche: `npm run test:db` e `npm run verify:access`.

## Migration Workflow

1. **Create migration:**
   ```bash
   npm run db:diff   # Or manually create in supabase/migrations/
   ```

2. **Test locally:**
   ```bash
   npm run db:start
   supabase db reset
   npm run verify
   npm run test:db        # modello di accesso (pgTAP)
   npm run verify:access  # ruoli simulati via API
   ```

3. **Apply to production:**
   ```bash
   npm run db:link
   npm run db:push
   ```

4. **Regenerate types:**
   ```bash
   supabase gen types typescript --project-id tkioedsebdxqblgcctxv > src/types/database.ts
   ```

5. **Release:**
   ```bash
   # Update version in package.json
   git commit -am "feat: description"
   git tag v0.1.X
   git push origin main --tags
   ```

6. **Update consumers:**
   ```json
   {"@kalos/contract": "https://github.com/AndreaScocchi/kalos-contract.git#v0.1.X"}
   ```

## Versioning

Current: **v0.3.15**

Consumers reference via git tag:
```json
{
  "@kalos/contract": "https://github.com/AndreaScocchi/kalos-contract.git#v0.1.5"
}
```

## Build Output

```
dist/
├── index.js      # CommonJS
├── index.mjs     # ES Modules
├── index.d.ts    # TypeScript definitions
└── sourcemaps
```

## Key Files to Know

- [src/index.ts](src/index.ts) - All exports
- [src/types/database.ts](src/types/database.ts) - Generated types
- [src/supabase/client.ts](src/supabase/client.ts) - Client factories
- [src/rpc/index.ts](src/rpc/index.ts) - RPC wrappers
- [supabase/migrations/](supabase/migrations/) - Schema source of truth
- [DATABASE_WORKFLOW.md](DATABASE_WORKFLOW.md) - Detailed migration guide
- [ACCESS_MODEL.md](ACCESS_MODEL.md) - Chi può leggere, scrivere ed eseguire cosa; regole per funzioni/tabelle/view nuove
- [BACKUP.md](BACKUP.md) - Backup notturno cifrato su S3 (UE), avvisi email, procedura di ripristino
- [STRIPE_SETUP.md](STRIPE_SETUP.md) - Pagamenti online: account, webhook, secret, go-live, prove in locale
- [supabase/storage/FOTO.md](supabase/storage/FOTO.md) - Foto: compressione nel gestionale, versioni ridotte, chi le legge

## Important Rules

1. **All schema changes go here** - Never modify database from app/management/website
2. **Forward-only migrations** - Never modify applied migrations
3. **Version before release** - Always tag releases
4. **Verify before push** - Run `npm run verify` before `db:push`
5. **Types must match schema** - Regenerate types after migrations
