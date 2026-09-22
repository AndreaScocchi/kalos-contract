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
- **Tabelle.** RLS è attivo su tutte. `anon` legge solo i dati pubblici del sito e non scrive
  nulla. Nessuno ha TRUNCATE, REFERENCES, TRIGGER o MAINTAIN tramite l'API. `service_role` legge e
  scrive tutte le tabelle (le edge function ne hanno bisogno: fino al 2026-09-22 non poteva, e
  disiscrizioni, bounce ed eliminazione account fallivano). Anche le tabelle future nascono così.

### Cosa è aperto ad `anon`

- **Lettura:** `activities`, `lessons` (solo di gruppo), `operators` attive, `plans`, `plan_activities`,
  `promotions` in corso, `events`, `feature_flags`, `pass_tiers`, `pass_tier_benefits`, le view
  `public_site_*` e `lesson_occupancy` (solo conteggi).
- **Funzioni:** gli helper delle policy (per anon restituiscono false o null) e i conteggi pubblici
  degli eventi (`get_event_booking_count`, `get_events_booking_counts`).

### Cosa è aperto ad `authenticated`

Solo RPC che controllano login e ruolo **al loro interno**:
- **cliente:** prenotazioni (`book_*`, `cancel_*`), percorso e pratica, notifiche, token push,
  Bussola, feedback;
- **staff:** `staff_*`, tessere, campagne, `promote_profile_to_operator` (solo admin),
  `queue_new_event`;
- **Finanze:** `calculate_operator_compensation`, `get_monthly_revenue_by_*`, `get_financial_kpis`,
  `get_revenue_breakdown` (tutte con `can_access_finance()`);
- due funzioni pure chiamate dai trigger `SECURITY INVOKER` su `announcements` e `activities`.

Tutto il resto è interno: code delle notifiche (`queue_*`), `cron_*`, `call_edge_function`,
manutenzione, helper dei trigger. Lo chiamano cron, trigger e edge function, mai le app.

### Scritture dirette dalle app

| Tabella | Chi scrive direttamente | Note |
|---|---|---|
| `profiles` | l'utente sul proprio profilo, lo staff su tutti | Il trigger `guard_profile_privileged_columns` blocca il cambio di `role` (solo admin) e di `email` (solo staff). L'email del profilo collega la scheda cliente. |
| `bookings`, `event_bookings` | solo staff | I clienti passano da `book_lesson`, `cancel_booking`, `book_event` e `cancel_event_booking`, che applicano capienza e scadenze (in futuro anche la regola "solo soci"). |
| `clients`, `subscriptions`, `lessons`, … | solo staff | via policy `is_staff()` |
| dati personali del cliente (notifiche, preferenze, diario, pratica) | il cliente, solo le proprie righe | policy su `get_my_client_id()` |

## Regole per chi modifica lo schema

**Nuova funzione**
1. Nasce chiusa. Se un'app la deve chiamare, aggiungi il `GRANT EXECUTE ... TO authenticated` (o
   `anon`, solo per dati davvero pubblici) nella stessa migrazione.
2. Se è `SECURITY DEFINER`: controlla login e ruolo **in testa**, prima di leggere o scrivere, e
   imposta `SET search_path TO 'public'`.
3. Non considerare `auth.uid() IS NULL` una prova di "chiamata di sistema": anche anon non ha uid.
   Le funzioni di sistema semplicemente non vanno aperte ad anon.
4. Aggiorna l'elenco in `access_model.test.sql` e, se serve, questa pagina.

**Nuova tabella**
1. `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` e policy `TO authenticated`.
2. Niente policy `TO anon` o senza `TO` (cioè `public`), salvo dati pubblici del sito.
3. I grant ad `anon`/`authenticated` vanno scritti esplicitamente (per esempio
   `GRANT SELECT, INSERT, UPDATE, DELETE ON ... TO authenticated`); `service_role` e l'assenza di
   TRUNCATE/REFERENCES/TRIGGER/MAINTAIN arrivano dai default privileges.

**Nuova view**
- `WITH (security_invoker = true)`, così valgono le RLS delle tabelle sotto.
- Le view pubbliche senza `security_invoker` sono ammesse solo se espongono esclusivamente colonne
  pubbliche (come `public_site_activities`).

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

- **Riordino strutturale** (sessione 3): funzioni interne in uno schema non esposto all'API, policy
  doppie accorpate (es. su `lessons`), `search_path` fisso su tutte le `SECURITY DEFINER`.
- **Storage:** le policy di `storage.objects` esistono solo in produzione (create fuori dalle
  migrazioni) e in locale lo Storage è spento.
