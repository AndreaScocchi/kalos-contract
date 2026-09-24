# Modello di accesso al database

Chi può leggere, scrivere ed eseguire cosa, e le regole per non riaprire i buchi chiusi nella
sessione 1 del 2026-09-22 ([piano](../docs/PIANO-APS-E-NUOVA-APP.md) §0).

**La fonte di verità sono i test:** [supabase/tests/access_model.test.sql](supabase/tests/access_model.test.sql)
contiene l'elenco esatto di funzioni e tabelle aperte ad anon e authenticated, e fallisce se una
migrazione ne apre altre. Questa pagina spiega il perché.

## Ruoli

| Ruolo Postgres | Chi è | Come si riconosce |
|---|---|---|
| `anon` | Chiunque abbia la chiave pubblica (è nel codice del sito) | nessun login |
| `authenticated` | Clienti, operatrici, admin, Tesoriere | login; il ruolo applicativo è `profiles.role` (`user`, `operator`, `admin`, `finance`) |
| `service_role` | Edge function e automazioni | chiave segreta, mai nei client |
| `postgres` | Cron (`pg_cron`), trigger e RPC `SECURITY DEFINER` | proprietario degli oggetti |

Helper usati da policy e RPC: `is_staff()` (operator, admin, finance), `is_admin()`,
`can_access_finance()` (admin, finance), `get_my_client_id()`.

## Regola base: tutto chiuso

- **Funzioni.** Una funzione in `public` non è eseguibile da `anon` né da `authenticated` finché
  non riceve un `GRANT EXECUTE` esplicito. Vale anche per quelle future: dal 2026-09-22 i default
  privileges di `postgres` non danno più EXECUTE a PUBLIC. `service_role` le esegue tutte.
- **Schema `internal`.** Dal 2026-09-23 le funzioni interne non stanno più in `public` ma in uno
  schema che **PostgREST non espone** (`config.toml` elenca solo `public` e `graphql_public`), e su
  cui `anon` e `authenticated` non hanno `USAGE`. Dall'API non sono "vietate": non esistono
  proprio, e nessun `GRANT` distratto in una migrazione futura può riaprirle. Ci arrivano solo i
  trigger, le altre funzioni e `service_role`.
- **Tabelle.** RLS è attivo su tutte. `anon` legge solo i dati pubblici del sito e non scrive
  nulla. Nessuno ha TRUNCATE, REFERENCES, TRIGGER o MAINTAIN tramite l'API. `service_role` legge e
  scrive tutte le tabelle (le edge function ne hanno bisogno: fino al 2026-09-22 non poteva, e
  disiscrizioni, bounce ed eliminazione account fallivano). Anche le tabelle future nascono così.

### Cosa è aperto ad `anon`

- **Lettura:** `activities`, `lessons` (solo di gruppo), `operators` attive, `plans`, `plan_activities`,
  `promotions` in corso, `events` attivi, `feature_flags`, `pass_tiers`, `pass_tier_benefits`,
  `activity_groups` e `locations` (i luoghi con `show_on_site`), le view `public_site_*` e
  `lesson_occupancy` (solo conteggi).
- **Funzioni:** gli helper delle policy (per anon restituiscono false o null) e i conteggi pubblici
  degli eventi (`get_event_booking_count`, `get_events_booking_counts`).

### Cosa è aperto ad `authenticated`

Solo RPC che controllano login e ruolo **al loro interno**:
- **cliente:** prenotazioni (`book_*`, `cancel_*`), percorso e pratica, notifiche, token push,
  Bussola, feedback;
- **staff:** `staff_*`, tessere, campagne, `promote_profile_to_operator` (solo admin),
  `queue_new_event`;
- **soci:** `submit_member_application`, `get_my_membership_status`, `get_my_member_card`;
- **prove e lista d'attesa:** `book_trial_lesson`, `join_waitlist`, `leave_waitlist`;
- **incassi (staff):** `staff_register_payment`, `issue_receipt`, `void_receipt`,
  `staff_refund_transaction`, `staff_set_member_fee`, `staff_create_member_application`,
  `staff_decide_member_applications`, `staff_book_trial`, `staff_create_client_and_book_trial`,
  `staff_unconvert_trial`; dalla sessione 4 `staff_settle_transaction` (salda un "da saldare":
  le operatrici registrano e saldano, ma correggere o annullare resta alle Finanze),
  `staff_pay_member_fee` (quota dell'anno in una transazione sola) e `staff_get_member_statuses`
  (espone allo staff la regola "solo soci" di `internal.member_booking_status`). `void_receipt` e
  `staff_refund_transaction` controllano `can_access_finance()`;
- **pagamenti online (sessione 5):** `prepare_my_fee_payment` (il cliente chiede se può pagare la
  propria quota; l'importo lo decide il database) e `staff_prepare_stripe_refund` (solo Finanze).
  Dalla sessione 5 `staff_refund_transaction` rifiuta gli incassi online (`USE_STRIPE_REFUND`): si
  rimborsano sulla carta, dall'edge function `stripe-refund`;
- **lista d'attesa e prove (sessione 6):** `staff_add_to_waitlist` e `staff_remove_from_waitlist`
  (staff), `submit_trial_feedback` (cliente, solo per una propria prova fatta);
- **Finanze:** `calculate_operator_compensation`, `calculate_compensation_v2`,
  `get_monthly_revenue_by_*`, `get_financial_kpis`, `get_revenue_breakdown`,
  `staff_freeze_compensation`, `staff_mark_compensation_paid`, `generate_recurring_expenses`,
  `confirm_expense`, `staff_pay_volunteer_reimbursement` (tutte con `can_access_finance()`);
- due funzioni pure chiamate dai trigger `SECURITY INVOKER` su `announcements` e `activities`.

Tutto il resto è interno e vive nello schema `internal`: code delle notifiche (`queue_*`),
`cron_*`, `call_edge_function`, manutenzione, helper dei trigger, il motore dei compensi
(`compute_compensation`), la numerazione (`next_receipt_number`, `next_member_number`), la regola
"solo soci" (`member_booking_status`). Lo chiamano cron, trigger e edge function, mai le app.

**Restano in `public` per necessità, pur essendo chiuse ad anon e authenticated:**
`queue_lesson_reminders`, `queue_subscription_expiry`, `queue_entries_low`, `queue_re_engagement`
e `queue_birthday`, perché l'edge function `schedule-notifications` le chiama **attraverso
PostgREST** con la chiave di servizio, e `process_recurring_announcements`. Se un giorno quella
edge function cambiasse modo di chiamarle, potrebbero seguire le altre.

**`site_rebuild_state`** (sessione 6) sta in `public` con RLS attivo, nessuna policy e nessun grant ad
anon e authenticated: la scrive il job `internal.cron_site_rebuild`, la aggiorna l'edge function
`site-rebuild` (service_role) con l'esito del build hook di Netlify, e ops-health la legge.

Per lo stesso motivo stanno in `public`, **solo per service_role**, le funzioni dei pagamenti online
che chiamano le edge function (sessione 5): `stripe_apply_payment_state` (l'unico punto che scrive un
pagamento nel registro), `stripe_checkout_expired`, `stripe_event_received`, `stripe_event_done`,
`stripe_register_checkout_attempt`, `receipt_claim_send` e `receipt_mark_sent`. Nessun `GRANT` ad
anon o authenticated: il test pgTAP e `verify-access` controllano che restino chiuse.

### Scritture dirette dalle app

| Tabella | Chi scrive direttamente | Note |
|---|---|---|
| `profiles` | l'utente sul proprio profilo, lo staff su tutti | Il trigger `guard_profile_privileged_columns` blocca il cambio di `role` (solo admin) e di `email` (solo staff). L'email del profilo collega la scheda cliente. |
| `bookings`, `event_bookings` | solo staff | I clienti passano da `book_lesson`, `cancel_booking`, `book_event` e `cancel_event_booking`, che applicano capienza, scadenze e la regola "solo soci" (interruttore `members_only`). |
| `clients`, `subscriptions`, `lessons`, … | solo staff | via policy `is_staff()` |
| dati personali del cliente (notifiche, preferenze, diario, pratica) | il cliente, solo le proprie righe | policy su `get_my_client_id()` |

## Regole per chi modifica lo schema

**Nuova funzione**
0. Decidi dove vive. Se la chiamano solo trigger, cron o altre funzioni, creala in **`internal`**.
   In `public` vanno solo quelle che un'app o un'edge function chiama attraverso l'API.
1. Nasce chiusa. Se un'app la deve chiamare, aggiungi il `GRANT EXECUTE ... TO authenticated` (o
   `anon`, solo per dati davvero pubblici) nella stessa migrazione.
2. Se è `SECURITY DEFINER`: controlla login e ruolo **in testa**, prima di leggere o scrivere, e
   imposta `SET search_path TO 'public'`.
3. Non considerare `auth.uid() IS NULL` una prova di "chiamata di sistema": anche anon non ha uid.
   Le funzioni di sistema semplicemente non vanno aperte ad anon.
4. Aggiorna l'elenco in `access_model.test.sql` e, se serve, questa pagina.

**Nuova tabella**
0. Il trigger di `updated_at` ora si scrive `EXECUTE FUNCTION "internal"."update_updated_at_column"()`.
1. `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` e policy `TO authenticated`. **Sempre con `TO`:** una
   policy senza `TO` vale per il ruolo `public`, che comprende anon.
2. Niente policy `TO anon` o senza `TO` (cioè `public`), salvo dati pubblici del sito.
3. I grant ad `anon`/`authenticated` vanno scritti esplicitamente (per esempio
   `GRANT SELECT, INSERT, UPDATE, DELETE ON ... TO authenticated`); `service_role` e l'assenza di
   TRUNCATE/REFERENCES/TRIGGER/MAINTAIN arrivano dai default privileges.

**Nuova view**
- `WITH (security_invoker = true)`, così valgono le RLS delle tabelle sotto.
- Le view pubbliche senza `security_invoker` sono ammesse solo se espongono esclusivamente colonne
  pubbliche (come `public_site_activities`).

### Edge function e Storage

- **`receipt-pdf`** (sessione 4) ridisegna il PDF di una ricevuta leggendo `receipts` **con il token
  di chi chiede**, non con la chiave di servizio: decidono le RLS (oggi solo lo staff). Quando l'app
  mostrerà le ricevute al socio basterà una policy sul proprio `client_id`.
- **Pagamenti online (sessione 5, [STRIPE_SETUP.md](STRIPE_SETUP.md)):**
  - `stripe-webhook` gira **senza JWT** (`config.toml`): la sicurezza è la firma di Stripe,
    verificata sul corpo grezzo. Scrive solo attraverso `stripe_apply_payment_state`, dopo aver
    riletto il pagamento dall'API di Stripe: un evento inventato non basta a creare un incasso;
  - `stripe-checkout`: la quota con il token di chi è loggato (`prepare_my_fee_payment` decide
    importo e permesso), le donazioni anche con la sola chiave anon, con un limite orario per
    impronta dell'IP;
  - `stripe-refund`: col token di chi chiede, passa da `staff_prepare_stripe_refund` (solo Finanze);
  - `member-application`: la domanda la registra `submit_member_application` col token della
    persona; la function aggiunge IP e dispositivo presi dalla richiesta e manda il PDF;
  - `send-receipt`: staff, e solo per ricevute che può leggere col proprio token.
- **`site-rebuild`** (sessione 6): accetta solo la chiave di servizio (la chiama il job
  `internal.cron_site_rebuild` via `call_edge_function`) e chiama il build hook di Netlify del sito,
  il cui indirizzo sta nel secret `NETLIFY_BUILD_HOOK_URL`, mai nel database né nel repo.
- **Bucket privati** (creati in produzione con gli script in `supabase/storage/`, non da
  migrazione: vedi sotto): `documenti-spese` per i documenti dei rimborsi ai volontari e delle
  uscite, leggibile e scrivibile solo con `can_access_finance()`. Il bucket `newsletter` (immagini,
  lettura pubblica, scrittura staff) è stato creato a mano prima di questo modello.

## Come si verifica

```bash
npm run db:start && npx supabase db reset   # DB locale dalle migrazioni
npm run test:db                              # pgTAP: elenco esplicito + comportamenti critici
npm run verify:access                        # via API: anon, cliente, operatrice, admin, service_role

# Produzione: solo chiave anon, nessun dato personale letto, nessun invio
SUPABASE_URL=https://tkioedsebdxqblgcctxv.supabase.co SUPABASE_ANON_KEY=<chiave anon> \
  node scripts/verify-access.mjs --prod
```

## Cose note, rimandate

- **Storage:** le policy di `storage.objects` esistono solo in produzione (create fuori dalle
  migrazioni) e in locale il servizio Storage è spento, anche se lo schema `storage` c'è. I bucket
  si creano in produzione con gli script idempotenti di `supabase/storage/` (un solo blocco `DO`,
  perché `supabase db query` esegue un'istruzione per volta), che si possono provare anche in locale
  con `--local`. Le ricevute non hanno bisogno di un bucket: il PDF si genera al momento.
- **`cron_*` in `internal`:** i job di pg_cron esistono solo in produzione, quindi la migrazione che
  li sposta riscrive i comandi dei job e fallisce se non ci riesce. Dopo ogni push che le tocca vanno
  guardati `cron.job` e `cron.job_run_details`.

## Chiuso il 2026-09-23 (sessione 3)

Il riordino strutturale che questa pagina elencava come rimandato è stato fatto: funzioni interne
nello schema `internal`, policy doppie di `lessons` accorpate (da quattro a tre), tutte le policy
scritte senza `TO` ora dichiarano il proprio ruolo, e `search_path` fisso su tutte le nuove
`SECURITY DEFINER`. Il test pgTAP verifica che `internal` resti irraggiungibile.
