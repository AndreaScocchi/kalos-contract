import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';

/**
 * Tipo per i nomi delle views pubbliche del sito.
 * Le views devono iniziare con "public_site_" per essere considerate pubbliche.
 */
export type PublicViewName = `public_site_${string}`;

/**
 * Helper per accedere alle views pubbliche in modo type-safe.
 * Questo impedisce l'uso accidentale di tabelle non pubbliche.
 * 
 * NOTA: Le views pubbliche (public_site_*) devono essere create nel database e i types
 * devono essere rigenerati prima di usare questa funzione.
 * 
 * @param client - Il client Supabase (può essere anonimo per views pubbliche)
 * @param view - Il nome della view pubblica (deve iniziare con "public_site_")
 * @returns Il query builder per la view specificata
 */
export function fromPublic<T extends PublicViewName>(
  client: SupabaseClient<Database>,
  view: T
) {
  // @ts-expect-error - Le views public_site_* non sono ancora presenti nel database types
  // Verrà risolto quando le views verranno create e i types rigenerati
  return client.from(view);
}
 
/**
 * Parametri opzionali per filtrare lo schedule pubblico per date
 */
export type GetPublicScheduleParams = {
  from?: string;
  to?: string;
};

/**
 * Recupera lo schedule pubblico dal database.
 * Questa funzione accede alla view public_site_schedule e applica filtri opzionali per date.
 * 
 * NOTA: La view public_site_schedule deve essere creata nel database e i types devono essere rigenerati
 * prima di usare questa funzione.
 * 
 * @param client - Il client Supabase (anonimo ok per views pubbliche)
 * @param params - Parametri opzionali per filtrare per date
 * @returns Promise con i dati dello schedule
 * @throws Error se la query fallisce
 */
export async function getPublicSchedule(
  client: SupabaseClient<Database>,
  params?: GetPublicScheduleParams
) {
  let query = fromPublic(client, 'public_site_schedule').select('*');

  if (params?.from) {
    query = query.gte('date', params.from);
  }
  if (params?.to) {
    query = query.lte('date', params.to);
  }

  const { data, error } = await query;

  if (error) {
    throw new Error(`Failed to fetch public schedule: ${error.message}`);
  }

  return data;
}

/**
 * Recupera i prezzi pubblici dal database.
 * Questa funzione accede alla view public_site_pricing.
 * 
 * NOTA: La view public_site_pricing deve essere creata nel database e i types devono essere rigenerati
 * prima di usare questa funzione.
 * 
 * @param client - Il client Supabase (anonimo ok per views pubbliche)
 * @returns Promise con i dati dei prezzi
 * @throws Error se la query fallisce
 */
export async function getPublicPricing(client: SupabaseClient<Database>) {
  const { data, error } = await fromPublic(client, 'public_site_pricing')
    .select('*');

  if (error) {
    throw new Error(`Failed to fetch public pricing: ${error.message}`);
  }

  return data;
}

/**
 * Recupera le attività pubbliche dal database.
 * Questa funzione accede alla view public_site_activities.
 * 
 * NOTA: La view public_site_activities deve essere creata nel database e i types devono essere rigenerati
 * prima di usare questa funzione.
 * 
 * @param client - Il client Supabase (anonimo ok per views pubbliche)
 * @returns Promise con i dati delle attività
 * @throws Error se la query fallisce
 */
export async function getPublicActivities(client: SupabaseClient<Database>) {
  const { data, error } = await fromPublic(client, 'public_site_activities')
    .select('*');

  if (error) {
    throw new Error(`Failed to fetch public activities: ${error.message}`);
  }

  return data;
}

/**
 * Recupera gli operatori attivi dal database.
 * Questa funzione accede alla view public_site_operators.
 * 
 * NOTA: La view public_site_operators deve essere creata nel database e i types devono essere rigenerati
 * prima di usare questa funzione.
 * 
 * @param client - Il client Supabase (anonimo ok per views pubbliche)
 * @returns Promise con i dati degli operatori
 * @throws Error se la query fallisce
 */
export async function getPublicOperators(client: SupabaseClient<Database>) {
  const { data, error } = await fromPublic(client, 'public_site_operators')
    .select('*');

  if (error) {
    throw new Error(`Failed to fetch public operators: ${error.message}`);
  }

  return data;
}

/**
 * Parametri opzionali per filtrare gli eventi pubblici per date
 */
export type GetPublicEventsParams = {
  from?: string;
  to?: string;
};

/**
 * Recupera gli eventi pubblici dal database.
 * Questa funzione accede alla view public_site_events e applica filtri opzionali per date.
 * 
 * NOTA: Ogni evento è un record separato con una singola data/orario (starts_at/ends_at).
 * Se un evento ha più date/orari, vengono creati record separati nel database.
 * Per raggruppare eventi con lo stesso nome, farlo lato client.
 * 
 * @param client - Il client Supabase (anonimo ok per views pubbliche)
 * @param params - Parametri opzionali per filtrare per date
 * @returns Promise con i dati degli eventi (ogni evento ha una singola data/orario)
 * @throws Error se la query fallisce
 */
export async function getPublicEvents(
  client: SupabaseClient<Database>,
  params?: GetPublicEventsParams
) {
  let query = fromPublic(client, 'public_site_events').select('*');

  // NOTA: La view public_site_events espone start_date (non starts_at)
  if (params?.from) {
    query = query.gte('start_date', params.from);
  }
  if (params?.to) {
    query = query.lte('start_date', params.to);
  }

  const { data, error } = await query;

  if (error) {
    throw new Error(`Failed to fetch public events: ${error.message}`);
  }

  return data;
}

/**
 * Tipo per evento con conteggio posti disponibili
 */
export type EventWithAvailability = {
  id: string;
  name: string;
  description: string | null;
  image_url: string | null;
  link: string | null;
  starts_at: string;
  ends_at: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  capacity: number | null;
  location: string | null;
  price_cents: number | null;
  currency: string | null;
  booked_count: number;
  available_spots: number | null; // null se capacity è null (illimitato)
  is_full: boolean;
};

/**
 * Parametri opzionali per filtrare gli eventi con disponibilità
 */
export type GetEventsWithAvailabilityParams = {
  from?: string;
  to?: string;
  onlyAvailable?: boolean; // Se true, mostra solo eventi con posti disponibili
};

/**
 * Recupera gli eventi con conteggio posti disponibili.
 * Questa funzione è utile per mostrare all'utente quanti posti sono ancora disponibili.
 * 
 * @param client - Il client Supabase autenticato
 * @param params - Parametri opzionali per filtrare
 * @returns Promise con gli eventi arricchiti con disponibilità
 * @throws Error se la query fallisce
 */
export async function getEventsWithAvailability(
  client: SupabaseClient<Database>,
  params?: GetEventsWithAvailabilityParams
): Promise<EventWithAvailability[]> {
  // Query base per eventi attivi e non soft-deleted
  let query = client
    .from('events')
    .select(`
      id,
      name,
      description,
      image_url,
      link,
      starts_at,
      ends_at,
      is_active,
      created_at,
      updated_at,
      deleted_at,
      capacity,
      location,
      price_cents,
      currency
    `)
    .eq('is_active', true)
    .is('deleted_at', null);

  // Filtri per data
  if (params?.from) {
    query = query.gte('starts_at', params.from);
  }
  if (params?.to) {
    query = query.lte('starts_at', params.to);
  }

  const { data: events, error: eventsError } = await query;

  if (eventsError) {
    throw new Error(`Failed to fetch events: ${eventsError.message}`);
  }

  if (!events || events.length === 0) {
    return [];
  }

  // Recupera conteggio prenotazioni per ogni evento
  const eventIds = events.map((e) => e.id);

  const { data: bookingsCount, error: bookingsError } = await client
    .from('event_bookings')
    .select('event_id')
    .in('event_id', eventIds)
    .in('status', ['booked', 'attended', 'no_show']);

  if (bookingsError) {
    throw new Error(`Failed to fetch bookings count: ${bookingsError.message}`);
  }

  // Calcola conteggio per evento
  const bookingsCountMap = new Map<string, number>();
  if (bookingsCount) {
    for (const booking of bookingsCount) {
      const count = bookingsCountMap.get(booking.event_id) || 0;
      bookingsCountMap.set(booking.event_id, count + 1);
    }
  }

  // Costruisci risultato con disponibilità
  const result: EventWithAvailability[] = events
    .map((event) => {
      const bookedCount = bookingsCountMap.get(event.id) || 0;
      const availableSpots =
        event.capacity !== null ? Math.max(0, event.capacity - bookedCount) : null;
      const isFull = event.capacity !== null && availableSpots === 0;

      return {
        ...event,
        booked_count: bookedCount,
        available_spots: availableSpots,
        is_full: isFull,
      };
    })
    .filter((event) => {
      // Filtra solo disponibili se richiesto
      if (params?.onlyAvailable) {
        return !event.is_full;
      }
      return true;
    });

  return result;
}

