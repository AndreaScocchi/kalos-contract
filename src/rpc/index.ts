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

