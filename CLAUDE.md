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
| `compensation_models`, `compensation_components`, `compensation_tiers`, `compensation_assignments`, `compensation_entries` | Compensi a mattoni, congelati quando il mese si chiude |
| `event_operators` | Chi tiene un evento, per calcolarne il compenso |
| `activity_groups`, `locations` | Gruppi di attività e luoghi (sito e app) |
| `trials` | Lezioni di prova: una per attività, con la conversione in primo ingresso |
| `site_rebuild_state` | Riga unica: quando il sito va ricostruito e com'è andata l'ultima build (sessione 6) |
| `stripe_events`, `stripe_payments`, `stripe_refunds` | Pagamenti online: memoria del webhook, pagamenti (con `source`, `metadata`, `is_duplicate`), rimborsi |
| `stripe_checkout_attempts` | Limite orario dei checkout delle donazioni per impronta dell'IP (interna) |

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
- `notification_category`: lesson_reminder, subscription_expiry, entries_low, re_engagement, first_lesson, milestone, birthday, new_event, announcement, practice_reminder, practice_resume, journal_reminder, feedback_request, waitlist_promotion, member_application_decided, membership_fee_due, trial_followup, trial_booked
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

### book_lesson(p_lesson_id, p_subscription_id?)
- Validates: deadline, capacity, subscription
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

### get_my_client_id()
- Returns current user's client_id
- **Non crea la scheda cliente**: restituisce NULL se non c'è. La scheda nasce dal trigger su
  `auth.users` alla registrazione, oppure da `submit_member_application` se manca.

### Notification RPCs

| Function | Purpose |
|----------|---------|
| `queue_lesson_reminder(p_lesson_id)` | Queue reminder 1h before lesson |
| `queue_subscription_expiry(p_subscription_id, p_days_until)` | Queue expiry warning |
| `queue_announcement(p_announcement_id, p_title, p_body)` | Queue push to all clients with active tokens |
| `get_notification_channel(p_client_id, p_category)` | Get preferred channel |
| `mark_notification_read(p_notification_log_id, p_announcement_id)` | Mark as read |
| `mark_all_notifications_read()` | Mark all as read |
| `get_unread_notifications_count()` | Count unread |

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

Current: **v0.3.3**

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

## Important Rules

1. **All schema changes go here** - Never modify database from app/management/website
2. **Forward-only migrations** - Never modify applied migrations
3. **Version before release** - Always tag releases
4. **Verify before push** - Run `npm run verify` before `db:push`
5. **Types must match schema** - Regenerate types after migrations
