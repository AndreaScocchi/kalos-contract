# RLS Policies Checklist - Tabella per Tabella

Questa checklist documenta le RLS policies per ogni tabella importante, verificando sicurezza, coerenza con soft delete, e resistenza a race conditions.

## Tabelle Critiche

### 1. `bookings`

**Policies**:
- ✅ `bookings_select_own_or_staff` - SELECT: Solo proprie prenotazioni o staff
- ✅ `bookings update own or staff` - UPDATE: Solo proprie prenotazioni o staff
- ✅ `Clients can create own bookings` - INSERT: Solo proprie prenotazioni o staff

**Verifiche**:
- ✅ Verifica `user_id = auth.uid()` per utenti
- ✅ Verifica `client_id = get_my_client_id()` per clienti
- ✅ Staff può vedere/modificare tutto
- ✅ RPC `book_lesson` e `cancel_booking` gestiscono correttamente i permessi

**Soft Delete**: ❌ Non applicabile (usa `status='canceled'`)

**Race Conditions**: ✅ Gestite in RPC con `FOR UPDATE`

---

### 2. `lessons`

**Policies**:
- ✅ `lessons_select_public_active` - SELECT anon: Solo lezioni non soft-deleted
- ✅ `Clients can view their lessons` - SELECT auth: Pubbliche o individuali assegnate
- ✅ `Only staff can manage lessons` - INSERT/UPDATE/DELETE: Solo staff

**Verifiche**:
- ✅ Anon può vedere solo lezioni pubbliche non soft-deleted
- ✅ Utenti autenticati possono vedere lezioni pubbliche o individuali assegnate
- ✅ Verifica `deleted_at IS NULL` nelle policies
- ✅ Verifica `is_individual` e `assigned_client_id` per lezioni individuali

**Soft Delete**: ✅ Rispettato (`deleted_at IS NULL`)

**Race Conditions**: ✅ Gestite in RPC con `FOR UPDATE`

---

### 3. `subscriptions`

**Policies**:
- ✅ `subscriptions_select_own_or_staff` - SELECT: Solo proprie subscriptions o staff
- ✅ `subscriptions_write_staff` - INSERT/UPDATE/DELETE: Solo staff

**Verifiche**:
- ✅ Verifica `user_id = auth.uid()` per utenti
- ✅ Verifica `client_id` tramite `get_my_client_id()` per clienti
- ✅ Staff può vedere/modificare tutto

**Soft Delete**: ❌ Non applicabile (usa `status`)

**Race Conditions**: ✅ Gestite in RPC (verifica validità, entries rimanenti)

---

### 4. `subscription_usages`

**Policies**:
- ✅ `subscription_usages_select_own_or_staff` - SELECT: Solo proprie usages o staff
- ✅ `subscription_usages_write_staff` - INSERT/UPDATE/DELETE: Solo staff

**Verifiche**:
- ✅ Utenti possono solo LEGGERE le proprie usages
- ✅ Utenti NON possono modificare direttamente (solo tramite RPC)
- ✅ Staff può modificare (per aggiustamenti manuali)

**Soft Delete**: ❌ Non applicabile (record storico)

**Race Conditions**: ✅ Gestite in RPC (verifica esistenza restore, evita duplicati)

---

### 5. `clients`

**Policies**:
- ✅ `clients_select_staff` - SELECT: Staff o proprio client (tramite `profile_id`)
- ✅ `clients_insert_staff` - INSERT: Solo staff
- ✅ `clients_update_staff` - UPDATE: Solo staff
- ✅ `clients_delete_staff` - DELETE: Solo staff

**Verifiche**:
- ✅ Utenti possono vedere solo il proprio client (tramite `profile_id`)
- ✅ Solo staff può modificare/eliminare
- ✅ Verifica `deleted_at IS NULL` nelle query

**Soft Delete**: ✅ Rispettato (`deleted_at IS NULL`)

**Race Conditions**: ✅ Non critiche (modifiche solo da staff)

---

### 6. `profiles`

**Policies**:
- ✅ `profiles_select_own_or_staff` - SELECT: Proprio profilo o staff
- ✅ `profiles_update_own_or_staff` - UPDATE: Proprio profilo o staff
- ✅ `profiles insert staff` - INSERT: Solo staff

**Verifiche**:
- ✅ Utenti possono vedere/modificare solo il proprio profilo
- ✅ Staff può vedere/modificare tutto

**Soft Delete**: ✅ Rispettato (`deleted_at IS NULL`)

**Race Conditions**: ✅ Non critiche

---

### 7. `activities`

**Policies**:
- ✅ `activities_select_public` - SELECT: Pubblico (anon + auth)
- ✅ `activities_write_staff` - INSERT/UPDATE/DELETE: Solo staff

**Verifiche**:
- ✅ Accesso pubblico in lettura
- ✅ Solo staff può modificare
- ✅ Verifica `deleted_at IS NULL` nelle query pubbliche

**Soft Delete**: ✅ Rispettato (`deleted_at IS NULL`)

**Race Conditions**: ✅ Non critiche

---

### 8. `plans`

**Policies**:
- ✅ `plans_select_public_active` - SELECT: Solo piani attivi e non soft-deleted
- ✅ `plans_write_staff` - INSERT/UPDATE/DELETE: Solo staff

**Verifiche**:
- ✅ Anon può vedere solo piani attivi (`is_active = true`) e non soft-deleted
- ✅ Solo staff può modificare
- ✅ Verifica `deleted_at IS NULL` e `is_active = true`

**Soft Delete**: ✅ Rispettato (`deleted_at IS NULL`)

**Race Conditions**: ✅ Non critiche

---

### 9. `events`

**Policies**:
- ✅ `events_select_public_active` - SELECT: Solo eventi attivi e non soft-deleted
- ✅ `events_write_staff` - INSERT/UPDATE/DELETE: Solo staff

**Verifiche**:
- ✅ Anon può vedere solo eventi attivi (`is_active = true`) e non soft-deleted
- ✅ Solo staff può modificare
- ✅ Verifica `deleted_at IS NULL` e `is_active = true`

**Soft Delete**: ✅ Rispettato (`deleted_at IS NULL`)

**Race Conditions**: ✅ Non critiche

---

### 10. `expenses` (Finance)

**Policies**:
- ✅ `expenses_select_finance_admin` - SELECT: Solo finance/admin
- ✅ `expenses_insert_finance_admin` - INSERT: Solo finance/admin
- ✅ `expenses_update_finance_admin` - UPDATE: Solo finance/admin
- ✅ `expenses_delete_admin` - DELETE: Solo admin

**Verifiche**:
- ✅ Solo ruoli `finance` o `admin` possono accedere
- ✅ Funzione helper `can_access_finance()` verifica ruolo

**Soft Delete**: ❌ Non applicabile (record finanziari storici)

**Race Conditions**: ✅ Non critiche

---

### 11. `payouts` (Finance)

**Policies**:
- ✅ `payouts_select_finance_admin` - SELECT: Solo finance/admin
- ✅ `payouts_insert_finance_admin` - INSERT: Solo finance/admin
- ✅ `payouts_update_finance_admin` - UPDATE: Solo finance/admin
- ✅ `payouts_delete_admin` - DELETE: Solo admin

**Verifiche**:
- ✅ Solo ruoli `finance` o `admin` possono accedere
- ✅ Funzione helper `can_access_finance()` verifica ruolo

**Soft Delete**: ❌ Non applicabile (record finanziari storici)

**Race Conditions**: ✅ Non critiche

---

## Views Pubbliche

### `public_site_schedule`
- ✅ Accesso anonimo (`GRANT SELECT TO anon`)
- ✅ Filtra `deleted_at IS NULL` automaticamente
- ✅ Solo lezioni pubbliche (`is_individual = false`)
- ✅ Solo lezioni future

### `public_site_pricing`
- ✅ Accesso anonimo (`GRANT SELECT TO anon`)
- ✅ Filtra `deleted_at IS NULL` e `is_active = true`
- ✅ Solo dati commerciali pubblici

**Nota**: Le views non hanno RLS (solo le tabelle hanno RLS). L'accesso è controllato tramite GRANT.

---

## RPC Functions - Verifica Sicurezza

### `book_lesson`
- ✅ Verifica `auth.uid()` (autenticazione obbligatoria)
- ✅ Verifica `deleted_at` su lezione e attività
- ✅ Usa `FOR UPDATE` per prevenire race conditions
- ✅ Verifica capacità con lock
- ✅ Non espone informazioni sensibili in errori

### `cancel_booking`
- ✅ Verifica `auth.uid()` e ownership del booking
- ✅ Verifica `deleted_at` su lezione e piano
- ✅ Gestisce correttamente subscription usages
- ✅ Previene duplicati (verifica esistenza restore)

### `staff_book_lesson`
- ✅ Verifica `is_staff()` all'inizio
- ✅ Verifica `deleted_at` su lezione e client
- ✅ Usa `FOR UPDATE` per prevenire race conditions
- ✅ Gestisce correttamente subscription usages

### `staff_cancel_booking`
- ✅ Verifica `is_staff()` all'inizio
- ✅ Gestisce correttamente subscription usages
- ✅ Previene duplicati

---

## Checklist Generale

### Sicurezza
- [x] Tutte le tabelle sensibili hanno RLS abilitato
- [x] Policies verificano correttamente ownership
- [x] RPC functions verificano autenticazione/autorizzazione
- [x] Views pubbliche non espongono dati personali

### Soft Delete
- [x] Policies rispettano `deleted_at IS NULL` dove applicabile
- [x] RPC functions verificano soft delete
- [x] Views pubbliche filtrano record soft-deleted

### Race Conditions
- [x] RPC critiche usano `FOR UPDATE`
- [x] Verifica capacità con lock
- [x] Gestione subscription usages atomica

### GDPR
- [x] Views pubbliche minimizzano dati esposti
- [x] Nessun dato personale in views pubbliche
- [x] Accesso controllato tramite GRANT (non RLS su views)

---

## Note per Consumer

### Query Consigliate

**Per sito pubblico**:
- Usa `public_site_schedule` e `public_site_pricing` (views pubbliche)
- Non accedere direttamente alle tabelle

**Per app/gestionale**:
- Usa RPC functions (`book_lesson`, `cancel_booking`) invece di INSERT/UPDATE diretti
- Le RPC gestiscono automaticamente permessi, soft delete, e race conditions

**Per staff**:
- Usa RPC staff (`staff_book_lesson`, `staff_cancel_booking`) per prenotazioni clienti
- Le RPC gestiscono automaticamente permessi e validazioni

### Query da Evitare

- ❌ Non fare INSERT/UPDATE diretti su `subscription_usages` (usa RPC)
- ❌ Non accedere direttamente a tabelle sensibili senza verificare RLS
- ❌ Non bypassare RLS usando service_role key senza motivo

