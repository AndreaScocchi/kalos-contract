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
  submitFeedback,
  queueFeedbackRequest,
  getMyMembership,
  assignMembership,
  cancelMembership,
  requestBussola,
  cancelBussolaRequest,
  submitMemberApplication,
  getMyMembershipStatus,
  getMyMemberCard,
  prepareMyFeePayment,
  bookTrialLesson,
  joinWaitlist,
  leaveWaitlist,
  submitTrialFeedback,
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
  FeedbackKind,
  SubmitFeedbackParams,
  SubmitFeedbackResult,
  QueueFeedbackRequestParams,
  QueueFeedbackRequestResult,
  PassBenefitType,
  MembershipBenefit,
  GetMyMembershipResult,
  AssignMembershipParams,
  AssignMembershipResult,
  PassActionResult,
  RequestBussolaParams,
  RequestBussolaResult,
  MembershipStatus,
  MemberFeeStatus,
  SubmitMemberApplicationParams,
  SubmitMemberApplicationResult,
  GetMyMembershipStatusResult,
  GetMyMemberCardResult,
  PrepareMyFeePaymentReason,
  PrepareMyFeePaymentResult,
  TrialBookingResult,
  WaitlistResult,
  TrialFeedbackAnswers,
  SubmitTrialFeedbackParams,
  SubmitTrialFeedbackResult,
} from './rpc';

// Etichette e domande condivise fra sito, gestionale e app
export {
  EVENT_TYPE_LABELS,
  EVENT_TYPE_LABELS_PLURAL,
  TRIAL_FEEDBACK_QUESTIONS,
  TRIAL_FEEDBACK_RATING_QUESTION,
  TRIAL_FEEDBACK_COMMENT_QUESTION,
} from './labels';
export type { TrialFeedbackQuestion } from './labels';

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
