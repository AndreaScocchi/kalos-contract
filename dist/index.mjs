import { createClient } from '@supabase/supabase-js';

// src/supabase/client.ts
function assertSupabaseConfig(url, anonKey) {
  if (!url) {
    throw new Error("Supabase URL is required. Please provide a valid URL.");
  }
  if (!anonKey) {
    throw new Error("Supabase anon key is required. Please provide a valid anon key.");
  }
  return { url, anonKey };
}
function createFetchWithTimeout(timeoutMs) {
  return async (input, init) => {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(input, {
        ...init,
        signal: controller.signal
      });
      clearTimeout(timeoutId);
      return response;
    } catch (error) {
      clearTimeout(timeoutId);
      if (error instanceof Error && error.name === "AbortError") {
        throw new Error(`Request timeout after ${timeoutMs}ms`);
      }
      throw error;
    }
  };
}
function createSupabaseBrowserClient(config) {
  var _a, _b, _c;
  const { url, anonKey } = assertSupabaseConfig(config.url, config.anonKey);
  const storageKey = (_a = config.storageKey) != null ? _a : "sb-auth-token";
  const detectSessionInUrl = (_b = config.detectSessionInUrl) != null ? _b : true;
  const enableTimeoutMs = (_c = config.enableTimeoutMs) != null ? _c : 3e4;
  const storage = typeof window !== "undefined" && window.localStorage ? window.localStorage : void 0;
  const customFetch = enableTimeoutMs > 0 ? createFetchWithTimeout(enableTimeoutMs) : void 0;
  return createClient(url, anonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl,
      storage,
      storageKey
    },
    global: {
      fetch: customFetch
    }
  });
}
function createSupabaseExpoClient(config) {
  var _a;
  const { url, anonKey } = assertSupabaseConfig(config.url, config.anonKey);
  const storageKey = (_a = config.storageKey) != null ? _a : "sb-auth-token";
  const storage = config.storage;
  return createClient(url, anonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false,
      // Non supportato in Expo
      storage,
      // Supabase accetta storage custom con questa interfaccia
      storageKey
    }
  });
}

// src/rpc/index.ts
function handleRpcError(error, rpcName) {
  if (error == null ? void 0 : error.message) {
    throw new Error(`RPC ${rpcName} failed: ${error.message}`);
  }
  throw new Error(`RPC ${rpcName} failed with unknown error`);
}
async function bookLesson(client, params) {
  const { lessonId, subscriptionId } = params;
  const { data, error } = await client.rpc("book_lesson", {
    p_lesson_id: lessonId,
    p_subscription_id: subscriptionId
  });
  if (error) {
    handleRpcError(error, "book_lesson");
  }
  return data;
}
async function cancelBooking(client, params) {
  const { bookingId } = params;
  const { data, error } = await client.rpc("cancel_booking", {
    p_booking_id: bookingId
  });
  if (error) {
    handleRpcError(error, "cancel_booking");
  }
  return data;
}

// src/queries/public.ts
function fromPublic(client, view) {
  return client.from(view);
}
async function getPublicSchedule(client, params) {
  let query = fromPublic(client, "public_site_schedule").select("*");
  if (params == null ? void 0 : params.from) {
    query = query.gte("date", params.from);
  }
  if (params == null ? void 0 : params.to) {
    query = query.lte("date", params.to);
  }
  const { data, error } = await query;
  if (error) {
    throw new Error(`Failed to fetch public schedule: ${error.message}`);
  }
  return data;
}
async function getPublicPricing(client) {
  const { data, error } = await fromPublic(client, "public_site_pricing").select("*");
  if (error) {
    throw new Error(`Failed to fetch public pricing: ${error.message}`);
  }
  return data;
}
async function getPublicActivities(client) {
  const { data, error } = await fromPublic(client, "public_site_activities").select("*");
  if (error) {
    throw new Error(`Failed to fetch public activities: ${error.message}`);
  }
  return data;
}
async function getPublicOperators(client) {
  const { data, error } = await fromPublic(client, "public_site_operators").select("*");
  if (error) {
    throw new Error(`Failed to fetch public operators: ${error.message}`);
  }
  return data;
}
async function getPublicEvents(client, params) {
  let query = fromPublic(client, "public_site_events").select("*");
  if (params == null ? void 0 : params.from) {
    query = query.gte("starts_at", params.from);
  }
  if (params == null ? void 0 : params.to) {
    query = query.lte("starts_at", params.to);
  }
  const { data, error } = await query;
  if (error) {
    throw new Error(`Failed to fetch public events: ${error.message}`);
  }
  return data;
}

export { assertSupabaseConfig, bookLesson, cancelBooking, createSupabaseBrowserClient, createSupabaseExpoClient, fromPublic, getPublicActivities, getPublicEvents, getPublicOperators, getPublicPricing, getPublicSchedule };
//# sourceMappingURL=index.mjs.map
//# sourceMappingURL=index.mjs.map