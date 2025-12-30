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

