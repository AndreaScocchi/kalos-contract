# Supabase DB Context – Studio Kalòs (Single Source of Truth)

This document is the canonical reference for database access (RLS + grants) and RPC usage.
Both projects must follow this file:
- User App (customers)
- Gestionale (100% client-side, staff dashboard)

---

## Identity & Roles

- Authenticated user id: `auth.uid()`
- User roles stored in `public.profiles.role` (enum `user_role`):
  - `user` (customer)
  - `operator` (staff)
  - `admin` (administrator)
- Helper functions:
  - `public.is_staff()` => true for roles: operator, admin
  - `public.is_admin()` => true for role: admin

---

## Core concept: Clients vs Profiles (VERY IMPORTANT)

### `public.profiles` (App Accounts)
- Represents an authenticated account (tied to `auth.users`).
- `profiles.id = auth.uid()`
- Exists only when the person has a login (email/phone/etc).

### `public.clients` (Gestionale CRM / Anagrafica)
- Represents a real-world client/person managed by staff.
- Can exist WITHOUT email and WITHOUT an Auth account (e.g. elderly clients).
- Optional linkage to an app account via:
  - `clients.profile_id -> profiles.id` (nullable)
- `clients` is staff-only (not exposed to user app).

### Ownership model for transactions (bookings/subscriptions)
Some transactional records can be owned by either:
- an app account (`user_id = profiles.id`) OR
- a CRM client (`client_id = clients.id`)
but NOT both.

This is enforced by DB constraints (XOR rule).

---

## High-level access model

### Catalog (public read)
Catalog data is readable by `anon` and `authenticated` (read-only):
- `activities`
- `lessons` (only active rows; typically `deleted_at IS NULL`)
- `operators` (only active operators; typically `is_active IS TRUE`)
- `events` (only active and not deleted; typically `is_active IS TRUE AND deleted_at IS NULL`)
- `plans` (only active and not deleted; typically `is_active IS TRUE AND deleted_at IS NULL`)
- `promotions` (only active + time window)
- `plan_activities`
- Views: `lesson_occupancy`, `subscriptions_with_remaining` (read-only)

### Personal data (authenticated only)
Requires `authenticated` (RLS enforces ownership and/or staff access):
- `profiles`
- `bookings`
- `subscriptions`
- `subscription_usages`
- `waitlist`
- `event_bookings`

### Staff-only (Gestionale only)
- `clients` (CRM/anagrafica, may exist without account)
- Staff RPC functions (see RPC section)

---

## Project-specific rules

### User App (customers)
- Never use `service_role`.
- Must never access `public.clients`.
- Must never create Auth users except normal signup/login flow.
- Must never write directly to `bookings` or `subscription_usages`.
- Booking and cancel flows MUST use RPC:
  - `book_lesson(...)`
  - `cancel_booking(p_booking_id uuid)`
- The app only operates on account-owned records:
  - bookings/subscriptions where `user_id = auth.uid()`
- The app must ignore/never rely on `client_id` owned records.

### Gestionale (100% client-side)
- Never use `service_role` (no backend/Edge Functions).
- The gestionale can only do what RLS allows for logged-in staff (operator/admin).
- The gestionale must NOT create Auth users for clients.
- Create/manage people via `public.clients` (email optional).
- UI must be gated by role:
  - If an action fails with permission/RLS error, treat it as expected and hide/disable that action for that role.
- For transactional flows:
  - For app accounts: staff can view/manage via RLS and/or RPC.
  - For non-digital clients (clients without account): gestionale MUST use staff RPC for booking/cancel to preserve invariants.
- Avoid manual edits that break accounting invariants (especially `subscription_usages`).

---

## RLS summary (behavioral)
Note: exact permissions depend on current DB policies. Summary intent:

### activities
- SELECT: public
- writes: staff-only (via `is_staff()`)

### lessons
- SELECT: public for active rows (usually `deleted_at IS NULL`)
- writes: staff-only

### operators
- SELECT: public for active operators (usually `is_active IS TRUE`)
- writes: typically admin-only OR staff-only (follow current DB policies)

### events / plans / promotions
- SELECT: public for active rows (and time window for promotions)
- writes: staff-only or admin-only depending on policies (follow current DB)

### plan_activities
- SELECT: public
- writes: staff-only

### profiles
- INSERT: created via trigger `handle_new_user()` on signup
- SELECT/UPDATE: own profile or staff

### clients (NEW)
- Staff-only table.
- SELECT/INSERT/UPDATE/DELETE: staff only (`is_staff()`).
- Used to manage people who may not have an app account (email optional).
- Optional linkage to app account: `clients.profile_id`.

### bookings (UPDATED OWNERSHIP MODEL)
- Ownership:
  - Account booking: `user_id = auth.uid()` and `client_id IS NULL`
  - CRM booking: `client_id IS NOT NULL` and `user_id IS NULL`
  - XOR constraint enforced in DB.
- SELECT: own bookings (user_id = auth.uid()) OR staff.
- User App must NOT write directly.
- Writes are primarily via RPC:
  - User App: `book_lesson`, `cancel_booking`
  - Gestionale for CRM clients: `staff_book_lesson`, `staff_cancel_booking` (see RPC)

### subscriptions (UPDATED OWNERSHIP MODEL)
- Ownership:
  - Account subscription: `user_id = auth.uid()` and `client_id IS NULL`
  - CRM subscription: `client_id IS NOT NULL` and `user_id IS NULL`
  - XOR constraint enforced in DB.
- SELECT: own (user_id = auth.uid()) OR staff.
- Writes: staff-only (created/managed in gestionale).
- User App reads only account-owned subscriptions.

### subscription_usages
- Read:
  - staff sees all
  - user sees only via join to their own account-owned subscriptions (user_id = auth.uid()).
- Writes:
  - staff and RPC side effects only.
- For CRM clients, only staff should read/adjust.

### waitlist / event_bookings
- users manage own rows; staff can read/manage depending on policies

---

## RPC Functions (server-enforced business logic)

### book_lesson(...)
- SECURITY DEFINER
- Purpose: books a lesson for the authenticated user (account-owned booking)
- Enforces:
  - booking deadline via `lessons.booking_deadline_minutes`
  - capacity and double-booking prevention
  - subscription validity window
  - entries accounting via `subscription_usages`
  - optional discipline coverage checks (plans.discipline OR plan_activities)
- Returns jsonb: `{ ok: boolean, reason?: string, booking_id?: uuid }`
- IMPORTANT: If multiple signatures exist (overloads), prefer calling with named params and consider removing the legacy overload to avoid ambiguity.

### cancel_booking(p_booking_id uuid)
- SECURITY DEFINER
- Purpose: cancels an authenticated user booking (account-owned)
- Enforces cancel deadline via `lessons.cancel_deadline_minutes`
- Restores entries (+1) when applicable
- Returns jsonb: `{ ok: boolean, reason?: string }`

### staff_book_lesson(p_lesson_id uuid, p_client_id uuid, p_subscription_id uuid DEFAULT NULL)  (NEW)
- SECURITY DEFINER
- Staff-only (must check `is_staff()` inside)
- Purpose: books a lesson for a CRM client without an app account (client-owned booking)
- Enforces:
  - booking deadline and capacity
  - optional subscription validity for the given client
  - entries accounting via `subscription_usages` when subscription is entry-based
- Returns jsonb: `{ ok: boolean, reason?: string, booking_id?: uuid }`

### staff_cancel_booking(p_booking_id uuid) (NEW)
- SECURITY DEFINER
- Staff-only (must check `is_staff()` inside)
- Purpose: cancels a booking that may belong to a CRM client and restores entries if applicable
- Enforces cancel deadline via `lessons.cancel_deadline_minutes`
- Returns jsonb: `{ ok: boolean, reason?: string }`

### create_user_profile(...)
- SECURITY DEFINER
- Staff-only (checked inside the function)
- Creates a profile for an existing auth.user
- NOTE: gestionale should not rely on creating auth users; this function is only for exceptional cases and migration/admin tooling.

### handle_new_user()
- Trigger on `auth.users` insert
- Creates a default `profiles` row with role 'user'

---

## Non-negotiable dev rules
- Never bypass RLS from client.
- Never embed service_role in any client-side app.
- Prefer RPC for booking/cancel flows.
- Gestionale must not create Auth users; it must create `clients`.
- When a query fails: check both RLS policies and GRANTS (anon/authenticated).