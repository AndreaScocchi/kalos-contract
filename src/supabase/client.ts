import { createClient, SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';

/**
 * Valida la configurazione Supabase e ritorna URL e anonKey garantiti non undefined.
 * Lancia errori chiari se mancano.
 */
export function assertSupabaseConfig(
  url: string | undefined,
  anonKey: string | undefined
): { url: string; anonKey: string } {
  if (!url) {
    throw new Error('Supabase URL is required. Please provide a valid URL.');
  }
  if (!anonKey) {
    throw new Error('Supabase anon key is required. Please provide a valid anon key.');
  }
  return { url, anonKey };
}

/**
 * Configurazione per il client browser Supabase
 */
export type SupabaseBrowserClientConfig = {
  url: string;
  anonKey: string;
  storageKey?: string;
  enableTimeoutMs?: number;
  detectSessionInUrl?: boolean;
};

/**
 * Crea un fetch wrapper con timeout usando AbortController
 */
function createFetchWithTimeout(timeoutMs: number): typeof fetch {
  return async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

    try {
      const response = await fetch(input, {
        ...init,
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      return response;
    } catch (error) {
      clearTimeout(timeoutId);
      if (error instanceof Error && error.name === 'AbortError') {
        throw new Error(`Request timeout after ${timeoutMs}ms`);
      }
      throw error;
    }
  };
}

/**
 * Crea un Supabase client per browser (React web apps).
 * 
 * Configurazioni predefinite:
 * - persistSession: true
 * - autoRefreshToken: true
 * - detectSessionInUrl: true (configurabile, utile per web reset/login)
 * - storage: window.localStorage se disponibile
 * - fetch timeout: 30000ms se enableTimeoutMs non specificato
 */
export function createSupabaseBrowserClient(
  config: SupabaseBrowserClientConfig
): SupabaseClient<Database> {
  const { url, anonKey } = assertSupabaseConfig(config.url, config.anonKey);
  
  const storageKey = config.storageKey ?? 'sb-auth-token';
  const detectSessionInUrl = config.detectSessionInUrl ?? true;
  const enableTimeoutMs = config.enableTimeoutMs ?? 30000;

  // Determina storage: usa window.localStorage se disponibile, altrimenti undefined
  const storage = typeof window !== 'undefined' && window.localStorage ? window.localStorage : undefined;

  // Configura fetch con timeout se necessario
  const customFetch = enableTimeoutMs > 0 
    ? createFetchWithTimeout(enableTimeoutMs)
    : undefined;

  return createClient<Database>(url, anonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl,
      storage,
      storageKey,
    },
    global: {
      fetch: customFetch,
    },
  });
}

/**
 * Configurazione per il client Expo Supabase
 */
export type SupabaseExpoClientConfig = {
  url: string;
  anonKey: string;
  storage?: {
    getItem: (key: string) => Promise<string | null> | string | null;
    setItem: (key: string, value: string) => Promise<void> | void;
    removeItem: (key: string) => Promise<void> | void;
  };
  storageKey?: string;
};

/**
 * Crea un Supabase client per Expo/React Native.
 * 
 * Configurazioni predefinite:
 * - persistSession: true
 * - autoRefreshToken: true
 * - detectSessionInUrl: false (non supportato in Expo)
 * - storage: passato dal consumer (es. expo-secure-store, AsyncStorage, ecc.)
 * 
 * NOTA: Non assume localStorage. Il consumer deve passare uno storage compatibile.
 * Esempio con expo-secure-store o @react-native-async-storage/async-storage
 */
export function createSupabaseExpoClient(
  config: SupabaseExpoClientConfig
): SupabaseClient<Database> {
  const { url, anonKey } = assertSupabaseConfig(config.url, config.anonKey);
  
  const storageKey = config.storageKey ?? 'sb-auth-token';
  const storage = config.storage;

  return createClient<Database>(url, anonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false, // Non supportato in Expo
      storage: storage as any, // Supabase accetta storage custom con questa interfaccia
      storageKey,
    },
  });
}

