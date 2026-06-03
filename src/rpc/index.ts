import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';

/**
 * Risultato della chiamata RPC book_lesson
 */
export type BookLessonResult = {
  ok: boolean;
  reason?: string;
  booking_id?: string | number;
};

/**
 * Risultato della chiamata RPC cancel_booking
 */
export type CancelBookingResult = {
  ok: boolean;
  reason?: string;
};

/**
 * Parametri per bookLesson
 */
export type BookLessonParams = {
  lessonId: string;
  subscriptionId?: string;
};

/**
 * Parametri per cancelBooking
 */
export type CancelBookingParams = {
  bookingId: string;
};

/**
 * Risultato della chiamata RPC book_event
 */
export type BookEventResult = {
  ok: boolean;
  reason?: string;
  booking_id?: string | number;
};

/**
 * Risultato della chiamata RPC cancel_event_booking
 */
export type CancelEventBookingResult = {
  ok: boolean;
  reason?: string;
};

/**
 * Parametri per bookEvent
 */
export type BookEventParams = {
  eventId: string;
};

/**
 * Parametri per cancelEventBooking
 */
export type CancelEventBookingParams = {
  bookingId: string;
};

/**
 * Parametri per staffBookEvent
 */
export type StaffBookEventParams = {
  eventId: string;
  clientId: string;
};

/**
 * Parametri per staffCancelEventBooking
 */
export type StaffCancelEventBookingParams = {
  bookingId: string;
};

/**
 * Helper per gestire errori dalle chiamate RPC
 */
function handleRpcError(error: any, rpcName: string): never {
  if (error?.message) {
    throw new Error(`RPC ${rpcName} failed: ${error.message}`);
  }
  if (error?.details) {
    throw new Error(`RPC ${rpcName} failed: ${error.details}`);
  }
  if (error?.hint) {
    throw new Error(`RPC ${rpcName} failed: ${error.hint}`);
  }
  throw new Error(`RPC ${rpcName} failed with unknown error: ${JSON.stringify(error)}`);
}

/**
 * Wrapper tipizzato per la RPC book_lesson.
 * Prenota una lezione usando l'ID della lezione e opzionalmente l'ID della subscription.
 * 
 * @param client - Il client Supabase autenticato
 * @param params - Parametri per la prenotazione
 * @returns Promise<BookLessonResult> con ok, reason opzionale, e booking_id se successo
 * @throws Error se la chiamata RPC fallisce
 */
export async function bookLesson(
  client: SupabaseClient<Database>,
  params: BookLessonParams
): Promise<BookLessonResult> {
  const { lessonId, subscriptionId } = params;

  const { data, error } = await client.rpc('book_lesson', {
    p_lesson_id: lessonId,
    p_subscription_id: subscriptionId,
  });

  if (error) {
    handleRpcError(error, 'book_lesson');
  }

  // Assumiamo che la RPC ritorni un oggetto con ok, reason?, booking_id?
  // Se ritorna un array o altro formato, il consumer dovrà adattare i types
  return data as BookLessonResult;
}

/**
 * Wrapper tipizzato per la RPC cancel_booking.
 * Cancella una prenotazione usando l'ID della prenotazione.
 * 
 * @param client - Il client Supabase autenticato
 * @param params - Parametri per la cancellazione
 * @returns Promise<CancelBookingResult> con ok e reason opzionale
 * @throws Error se la chiamata RPC fallisce
 */
export async function cancelBooking(
  client: SupabaseClient<Database>,
  params: CancelBookingParams
): Promise<CancelBookingResult> {
  const { bookingId } = params;

  // Validazione: assicuriamoci che bookingId sia una stringa non vuota
  if (!bookingId || typeof bookingId !== 'string') {
    throw new Error('cancelBooking: bookingId must be a non-empty string');
  }

  // Chiamata RPC con tipo esplicito dal Database
  const { data, error } = await client.rpc('cancel_booking', {
    p_booking_id: bookingId,
  } as Database['public']['Functions']['cancel_booking']['Args']);

  if (error) {
    handleRpcError(error, 'cancel_booking');
  }

  // Assumiamo che la RPC ritorni un oggetto con ok, reason?
  return data as CancelBookingResult;
}

/**
 * Wrapper tipizzato per la RPC book_event.
 * Prenota un evento usando l'ID dell'evento.
 * 
 * @param client - Il client Supabase autenticato
 * @param params - Parametri per la prenotazione
 * @returns Promise<BookEventResult> con ok, reason opzionale, e booking_id se successo
 * @throws Error se la chiamata RPC fallisce
 */
export async function bookEvent(
  client: SupabaseClient<Database>,
  params: BookEventParams
): Promise<BookEventResult> {
  const { eventId } = params;

  const { data, error } = await client.rpc('book_event', {
    p_event_id: eventId,
  });

  if (error) {
    handleRpcError(error, 'book_event');
  }

  return data as BookEventResult;
}

/**
 * Wrapper tipizzato per la RPC cancel_event_booking.
 * Cancella una prenotazione evento usando l'ID della prenotazione.
 * 
 * @param client - Il client Supabase autenticato
 * @param params - Parametri per la cancellazione
 * @returns Promise<CancelEventBookingResult> con ok e reason opzionale
 * @throws Error se la chiamata RPC fallisce
 */
export async function cancelEventBooking(
  client: SupabaseClient<Database>,
  params: CancelEventBookingParams
): Promise<CancelEventBookingResult> {
  const { bookingId } = params;

  if (!bookingId || typeof bookingId !== 'string') {
    throw new Error('cancelEventBooking: bookingId must be a non-empty string');
  }

  const { data, error } = await client.rpc('cancel_event_booking', {
    p_booking_id: bookingId,
  } as Database['public']['Functions']['cancel_event_booking']['Args']);

  if (error) {
    handleRpcError(error, 'cancel_event_booking');
  }

  return data as CancelEventBookingResult;
}

/**
 * Wrapper tipizzato per la RPC staff_book_event.
 * Prenota un evento per un cliente (staff only).
 * 
 * @param client - Il client Supabase autenticato (deve essere staff)
 * @param params - Parametri per la prenotazione
 * @returns Promise<BookEventResult> con ok, reason opzionale, e booking_id se successo
 * @throws Error se la chiamata RPC fallisce
 */
export async function staffBookEvent(
  client: SupabaseClient<Database>,
  params: StaffBookEventParams
): Promise<BookEventResult> {
  const { eventId, clientId } = params;

  const { data, error } = await client.rpc('staff_book_event', {
    p_event_id: eventId,
    p_client_id: clientId,
  });

  if (error) {
    handleRpcError(error, 'staff_book_event');
  }

  return data as BookEventResult;
}

/**
 * Wrapper tipizzato per la RPC staff_cancel_event_booking.
 * Cancella una prenotazione evento (staff only).
 * 
 * @param client - Il client Supabase autenticato (deve essere staff)
 * @param params - Parametri per la cancellazione
 * @returns Promise<CancelEventBookingResult> con ok e reason opzionale
 * @throws Error se la chiamata RPC fallisce
 */
export async function staffCancelEventBooking(
  client: SupabaseClient<Database>,
  params: StaffCancelEventBookingParams
): Promise<CancelEventBookingResult> {
  const { bookingId } = params;

  if (!bookingId || typeof bookingId !== 'string') {
    throw new Error('staffCancelEventBooking: bookingId must be a non-empty string');
  }

  const { data, error } = await client.rpc('staff_cancel_event_booking', {
    p_booking_id: bookingId,
  } as Database['public']['Functions']['staff_cancel_event_booking']['Args']);

  if (error) {
    handleRpcError(error, 'staff_cancel_event_booking');
  }

  return data as CancelEventBookingResult;
}

/**
 * Tipo di feedback (Fase 5 nuova app): momento/oggetto a cui si riferisce.
 */
export type FeedbackKind = 'practice' | 'lesson' | 'onboarding' | 'event';

/**
 * Parametri per submitFeedback.
 * `targetId` è obbligatorio per tutti i kind tranne `onboarding`.
 */
export type SubmitFeedbackParams = {
  kind: FeedbackKind;
  targetId?: string;
  rating?: number;
  comment?: string;
};

/**
 * Risultato della RPC submit_feedback.
 */
export type SubmitFeedbackResult = {
  ok: boolean;
  reason?: string;
  feedback_id?: string;
};

/**
 * Parametri per queueFeedbackRequest (raccolta automatica).
 */
export type QueueFeedbackRequestParams = {
  clientId: string;
  kind: FeedbackKind;
  targetId?: string;
  scheduledFor?: string;
};

/**
 * Risultato della RPC queue_feedback_request.
 */
export type QueueFeedbackRequestResult = {
  ok: boolean;
  reason?: string;
  notification_id?: string;
};

/**
 * Wrapper tipizzato per la RPC submit_feedback.
 * Invia (o aggiorna) un feedback dell'utente autenticato: voto 1–5 e/o commento.
 * Valida lato DB che l'azione su cui si dà feedback sia avvenuta (pratica completata,
 * lezione attended, evento prenotato). Upsert: un feedback per target.
 *
 * @param client - Il client Supabase autenticato
 * @param params - kind, targetId (tranne onboarding), rating?, comment?
 * @returns Promise<SubmitFeedbackResult> con ok, reason opzionale, feedback_id se successo
 * @throws Error se la chiamata RPC fallisce
 */
export async function submitFeedback(
  client: SupabaseClient<Database>,
  params: SubmitFeedbackParams
): Promise<SubmitFeedbackResult> {
  const { kind, targetId, rating, comment } = params;

  const { data, error } = await client.rpc('submit_feedback', {
    p_kind: kind,
    p_target_id: targetId,
    p_rating: rating,
    p_comment: comment,
  });

  if (error) {
    handleRpcError(error, 'submit_feedback');
  }

  return data as SubmitFeedbackResult;
}

/**
 * Wrapper tipizzato per la RPC queue_feedback_request.
 * Accoda una richiesta di feedback (notifica `feedback_request`) per un cliente.
 * Pensata per automazioni e staff; rispetta le preferenze di canale.
 *
 * @param client - Il client Supabase autenticato (staff/service o il cliente stesso)
 * @param params - clientId, kind, targetId?, scheduledFor?
 * @returns Promise<QueueFeedbackRequestResult> con ok, reason opzionale, notification_id se successo
 * @throws Error se la chiamata RPC fallisce
 */
export async function queueFeedbackRequest(
  client: SupabaseClient<Database>,
  params: QueueFeedbackRequestParams
): Promise<QueueFeedbackRequestResult> {
  const { clientId, kind, targetId, scheduledFor } = params;

  const { data, error } = await client.rpc('queue_feedback_request', {
    p_client_id: clientId,
    p_kind: kind,
    p_target_id: targetId,
    p_scheduled_for: scheduledFor,
  });

  if (error) {
    handleRpcError(error, 'queue_feedback_request');
  }

  return data as QueueFeedbackRequestResult;
}

// ─────────────────────────────────────────────────────────────────────────────
// Kalòs Community Pass (tesseramento) + Bussola — Fase 6 (item B / F)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Tipo di vantaggio del Pass (allineato all'enum DB pass_benefit_type).
 */
export type PassBenefitType =
  | 'subscription_discount'
  | 'event_discount'
  | 'bussola'
  | 'community_access'
  | 'priority_booking'
  | 'other';

/**
 * Vantaggio del Pass come restituito da get_my_membership.
 */
export type MembershipBenefit = {
  benefit_type: PassBenefitType;
  value_percent: number | null;
  value_int: number | null;
  label: string | null;
  description: string | null;
};

/**
 * Risultato della RPC get_my_membership: stato del Pass dell'utente autenticato.
 * `has_pass` è true solo se la membership è attiva e non scaduta.
 */
export type GetMyMembershipResult = {
  ok: boolean;
  reason?: string;
  has_pass?: boolean;
  membership?: {
    id: string;
    status: 'active' | 'expired' | 'cancelled';
    started_at: string;
    expires_at: string;
  };
  tier?: {
    id: string;
    name: string;
    description: string | null;
    price_cents: number;
    currency: string;
    validity_days: number;
  };
  benefits?: MembershipBenefit[];
};

/**
 * Parametri per assignMembership (staff).
 */
export type AssignMembershipParams = {
  clientId: string;
  tierId: string;
  /** Data di attivazione (default: oggi lato DB). */
  startedAt?: string;
  /** Prezzo effettivamente pagato in centesimi (default: prezzo del tier). */
  priceCents?: number;
  note?: string;
};

/**
 * Risultato della RPC assign_membership.
 */
export type AssignMembershipResult = {
  ok: boolean;
  reason?: string;
  membership_id?: string;
  expires_at?: string;
};

/**
 * Risultato generico delle RPC di gestione Pass/Bussola con solo esito.
 */
export type PassActionResult = {
  ok: boolean;
  reason?: string;
};

/**
 * Parametri per requestBussola (cliente tesserato).
 */
export type RequestBussolaParams = {
  /** Preferenza di data/ora (ISO 8601), opzionale. */
  preferredAt?: string;
  /** Cosa vorrebbe affrontare, opzionale. */
  note?: string;
};

/**
 * Risultato della RPC request_bussola.
 */
export type RequestBussolaResult = {
  ok: boolean;
  reason?: string;
  request_id?: string;
};

/**
 * Wrapper tipizzato per la RPC get_my_membership.
 * Ritorna stato del Community Pass dell'utente autenticato: has_pass (attivo e non scaduto),
 * membership, tier e vantaggi.
 *
 * @param client - Il client Supabase autenticato
 * @returns Promise<GetMyMembershipResult>
 * @throws Error se la chiamata RPC fallisce
 */
export async function getMyMembership(
  client: SupabaseClient<Database>
): Promise<GetMyMembershipResult> {
  const { data, error } = await client.rpc('get_my_membership');

  if (error) {
    handleRpcError(error, 'get_my_membership');
  }

  return data as GetMyMembershipResult;
}

/**
 * Wrapper tipizzato per la RPC assign_membership (staff).
 * Assegna il Community Pass a un cliente, calcola la scadenza dal tier e chiude
 * l'eventuale Pass attivo precedente. Usato dal gestionale (assegnazione manuale).
 *
 * @param client - Il client Supabase autenticato (staff)
 * @param params - clientId, tierId, startedAt?, priceCents?, note?
 * @returns Promise<AssignMembershipResult>
 * @throws Error se la chiamata RPC fallisce
 */
export async function assignMembership(
  client: SupabaseClient<Database>,
  params: AssignMembershipParams
): Promise<AssignMembershipResult> {
  const { clientId, tierId, startedAt, priceCents, note } = params;

  const { data, error } = await client.rpc('assign_membership', {
    p_client_id: clientId,
    p_tier_id: tierId,
    p_started_at: startedAt,
    p_price_cents: priceCents,
    p_note: note,
  });

  if (error) {
    handleRpcError(error, 'assign_membership');
  }

  return data as AssignMembershipResult;
}

/**
 * Wrapper tipizzato per la RPC cancel_membership (staff).
 * Annulla un Community Pass.
 *
 * @param client - Il client Supabase autenticato (staff)
 * @param membershipId - id della membership da annullare
 * @returns Promise<PassActionResult>
 * @throws Error se la chiamata RPC fallisce
 */
export async function cancelMembership(
  client: SupabaseClient<Database>,
  membershipId: string
): Promise<PassActionResult> {
  const { data, error } = await client.rpc('cancel_membership', {
    p_membership_id: membershipId,
  });

  if (error) {
    handleRpcError(error, 'cancel_membership');
  }

  return data as PassActionResult;
}

/**
 * Wrapper tipizzato per la RPC request_bussola.
 * Il cliente tesserato (Pass attivo) richiede una consulenza Bussola 15'.
 * Una sola richiesta aperta per volta; lo staff la trasforma in una lezione individuale.
 *
 * @param client - Il client Supabase autenticato (cliente)
 * @param params - preferredAt?, note?
 * @returns Promise<RequestBussolaResult>
 * @throws Error se la chiamata RPC fallisce
 */
export async function requestBussola(
  client: SupabaseClient<Database>,
  params: RequestBussolaParams = {}
): Promise<RequestBussolaResult> {
  const { preferredAt, note } = params;

  const { data, error } = await client.rpc('request_bussola', {
    p_preferred_at: preferredAt,
    p_note: note,
  });

  if (error) {
    handleRpcError(error, 'request_bussola');
  }

  return data as RequestBussolaResult;
}

/**
 * Wrapper tipizzato per la RPC cancel_bussola_request.
 * Annulla una richiesta Bussola aperta (cliente proprietario o staff).
 *
 * @param client - Il client Supabase autenticato
 * @param requestId - id della richiesta da annullare
 * @returns Promise<PassActionResult>
 * @throws Error se la chiamata RPC fallisce
 */
export async function cancelBussolaRequest(
  client: SupabaseClient<Database>,
  requestId: string
): Promise<PassActionResult> {
  const { data, error } = await client.rpc('cancel_bussola_request', {
    p_request_id: requestId,
  });

  if (error) {
    handleRpcError(error, 'cancel_bussola_request');
  }

  return data as PassActionResult;
}

