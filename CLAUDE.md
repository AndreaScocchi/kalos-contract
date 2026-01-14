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
| `waitlist` | Class waiting list |

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
- `notification_category`: lesson_reminder, subscription_expiry, booking_confirmation, booking_cancellation, waitlist_promotion, welcome, event_reminder, feedback_request, announcement
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

### get_my_client_id()
- Returns current user's client_id
- Auto-creates client if needed

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

## Row-Level Security

### Public Access (anon + authenticated)
- `activities`, `lessons`, `operators`, `events`, `plans`, `promotions`: SELECT

### Authenticated User
- `profiles`: SELECT/UPDATE own
- `bookings`, `subscriptions`, `event_bookings`: SELECT own (via client_id)

### Staff Only (is_staff = true)
- `clients`: Full access
- All transactional data: Full access

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

Current: **v0.1.5**

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

## Important Rules

1. **All schema changes go here** - Never modify database from app/management/website
2. **Forward-only migrations** - Never modify applied migrations
3. **Version before release** - Always tag releases
4. **Verify before push** - Run `npm run verify` before `db:push`
5. **Types must match schema** - Regenerate types after migrations
