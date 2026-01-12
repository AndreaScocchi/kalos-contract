/**
 * @kalos/contract
 * 
 * Shared contract library for Kalos projects.
 * Provides types, Supabase client factories, RPC wrappers, and public queries.
 */

// Types
export type { Database } from './types/database';
export type {
  Tables,
  TablesInsert,
  TablesUpdate,
  Enums,
  Views,
} from './types/helpers';

// Supabase client factories
export {
  createSupabaseBrowserClient,
  createSupabaseExpoClient,
  assertSupabaseConfig,
} from './supabase/client';
export type {
  SupabaseBrowserClientConfig,
  SupabaseExpoClientConfig,
} from './supabase/client';

// RPC wrappers
export {
  bookLesson,
  cancelBooking,
  bookEvent,
  cancelEventBooking,
  staffBookEvent,
  staffCancelEventBooking,
} from './rpc';
export type {
  BookLessonResult,
  CancelBookingResult,
  BookLessonParams,
  CancelBookingParams,
  BookEventResult,
  CancelEventBookingResult,
  BookEventParams,
  CancelEventBookingParams,
  StaffBookEventParams,
  StaffCancelEventBookingParams,
} from './rpc';

// Public queries
export {
  fromPublic,
  getPublicSchedule,
  getPublicPricing,
  getPublicActivities,
  getPublicOperators,
  getPublicEvents,
  getEventsWithAvailability,
} from './queries/public';
export type {
  PublicViewName,
  GetPublicScheduleParams,
  GetPublicEventsParams,
  EventWithAvailability,
  GetEventsWithAvailabilityParams,
} from './queries/public';

// Force rebuild Mon Jan 12 15:53:34 CET 2026
