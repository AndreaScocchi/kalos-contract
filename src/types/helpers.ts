import type { Database } from './database';

/**
 * Helper types per lavorare con il database schema.
 * Questi types assumono la struttura standard di Supabase:
 * Database['public']['Tables'], Database['public']['Views'], Database['public']['Enums']
 */

/**
 * Estrae tutte le tabelle dal database schema
 */
export type Tables<
  T extends keyof Database['public']['Tables'] = keyof Database['public']['Tables']
> = Database['public']['Tables'][T]['Row'];

/**
 * Estrae i tipi per INSERT di una tabella
 */
export type TablesInsert<
  T extends keyof Database['public']['Tables'] = keyof Database['public']['Tables']
> = Database['public']['Tables'][T]['Insert'];

/**
 * Estrae i tipi per UPDATE di una tabella
 */
export type TablesUpdate<
  T extends keyof Database['public']['Tables'] = keyof Database['public']['Tables']
> = Database['public']['Tables'][T]['Update'];

/**
 * Estrae gli enums dal database schema
 */
export type Enums<
  T extends keyof Database['public']['Enums'] = keyof Database['public']['Enums']
> = Database['public']['Enums'][T];

/**
 * Estrae i tipi per le views
 */
export type Views<
  T extends keyof Database['public']['Views'] = keyof Database['public']['Views']
> = Database['public']['Views'][T] extends { Row: infer R } ? R : never;

