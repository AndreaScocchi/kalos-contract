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
 * Helper per gestire errori dalle chiamate RPC
 */
function handleRpcError(error: any, rpcName: string): never {
  if (error?.message) {
    throw new Error(`RPC ${rpcName} failed: ${error.message}`);
  }
  throw new Error(`RPC ${rpcName} failed with unknown error`);
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

  const { data, error } = await client.rpc('cancel_booking', {
    p_booking_id: bookingId,
  });

  if (error) {
    handleRpcError(error, 'cancel_booking');
  }

  // Assumiamo che la RPC ritorni un oggetto con ok, reason?
  return data as CancelBookingResult;
}

