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
  if (error == null ? void 0 : error.details) {
    throw new Error(`RPC ${rpcName} failed: ${error.details}`);
  }
  if (error == null ? void 0 : error.hint) {
    throw new Error(`RPC ${rpcName} failed: ${error.hint}`);
  }
  throw new Error(`RPC ${rpcName} failed with unknown error: ${JSON.stringify(error)}`);
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
  if (!bookingId || typeof bookingId !== "string") {
    throw new Error("cancelBooking: bookingId must be a non-empty string");
  }
  const { data, error } = await client.rpc("cancel_booking", {
    p_booking_id: bookingId
  });
  if (error) {
    handleRpcError(error, "cancel_booking");
  }
  return data;
}
async function bookEvent(client, params) {
  const { eventId } = params;
  const { data, error } = await client.rpc("book_event", {
    p_event_id: eventId
  });
  if (error) {
    handleRpcError(error, "book_event");
  }
  return data;
}
async function cancelEventBooking(client, params) {
  const { bookingId } = params;
  if (!bookingId || typeof bookingId !== "string") {
    throw new Error("cancelEventBooking: bookingId must be a non-empty string");
  }
  const { data, error } = await client.rpc("cancel_event_booking", {
    p_booking_id: bookingId
  });
  if (error) {
    handleRpcError(error, "cancel_event_booking");
  }
  return data;
}
async function staffBookEvent(client, params) {
  const { eventId, clientId } = params;
  const { data, error } = await client.rpc("staff_book_event", {
    p_event_id: eventId,
    p_client_id: clientId
  });
  if (error) {
    handleRpcError(error, "staff_book_event");
  }
  return data;
}
async function staffCancelEventBooking(client, params) {
  const { bookingId } = params;
  if (!bookingId || typeof bookingId !== "string") {
    throw new Error("staffCancelEventBooking: bookingId must be a non-empty string");
  }
  const { data, error } = await client.rpc("staff_cancel_event_booking", {
    p_booking_id: bookingId
  });
  if (error) {
    handleRpcError(error, "staff_cancel_event_booking");
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
    query = query.gte("start_date", params.from);
  }
  if (params == null ? void 0 : params.to) {
    query = query.lte("start_date", params.to);
  }
  const { data, error } = await query;
  if (error) {
    throw new Error(`Failed to fetch public events: ${error.message}`);
  }
  return data;
}
async function getEventsWithAvailability(client, params) {
  let query = client.from("events").select(`
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
    `).eq("is_active", true).is("deleted_at", null);
  if (params == null ? void 0 : params.from) {
    query = query.gte("starts_at", params.from);
  }
  if (params == null ? void 0 : params.to) {
    query = query.lte("starts_at", params.to);
  }
  const { data: events, error: eventsError } = await query;
  if (eventsError) {
    throw new Error(`Failed to fetch events: ${eventsError.message}`);
  }
  if (!events || events.length === 0) {
    return [];
  }
  const eventIds = events.map((e) => e.id);
  const { data: bookingsCount, error: bookingsError } = await client.from("event_bookings").select("event_id").in("event_id", eventIds).in("status", ["booked", "attended", "no_show"]);
  if (bookingsError) {
    throw new Error(`Failed to fetch bookings count: ${bookingsError.message}`);
  }
  const bookingsCountMap = /* @__PURE__ */ new Map();
  if (bookingsCount) {
    for (const booking of bookingsCount) {
      const count = bookingsCountMap.get(booking.event_id) || 0;
      bookingsCountMap.set(booking.event_id, count + 1);
    }
  }
  const result = events.map((event) => {
    const bookedCount = bookingsCountMap.get(event.id) || 0;
    const availableSpots = event.capacity !== null ? Math.max(0, event.capacity - bookedCount) : null;
    const isFull = event.capacity !== null && availableSpots === 0;
    return {
      ...event,
      booked_count: bookedCount,
      available_spots: availableSpots,
      is_full: isFull
    };
  }).filter((event) => {
    if (params == null ? void 0 : params.onlyAvailable) {
      return !event.is_full;
    }
    return true;
  });
  return result;
}

export { assertSupabaseConfig, bookEvent, bookLesson, cancelBooking, cancelEventBooking, createSupabaseBrowserClient, createSupabaseExpoClient, fromPublic, getEventsWithAvailability, getPublicActivities, getPublicEvents, getPublicOperators, getPublicPricing, getPublicSchedule, staffBookEvent, staffCancelEventBooking };
//# sourceMappingURL=index.mjs.map
//# sourceMappingURL=index.mjs.map