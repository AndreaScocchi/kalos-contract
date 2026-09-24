'use strict';

var supabaseJs = require('@supabase/supabase-js');

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
  const STORAGE_TIMEOUT_MS = 5 * 60 * 1e3;
  return async (input, init) => {
    var _a;
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    const isStorageUpload = url.includes("/storage/") && ((_a = init == null ? void 0 : init.method) == null ? void 0 : _a.toUpperCase()) === "POST";
    const effectiveTimeout = isStorageUpload ? STORAGE_TIMEOUT_MS : timeoutMs;
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), effectiveTimeout);
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
        throw new Error(`Request timeout after ${effectiveTimeout}ms`);
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
  return supabaseJs.createClient(url, anonKey, {
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
  var _a, _b;
  const { url, anonKey } = assertSupabaseConfig(config.url, config.anonKey);
  const storageKey = (_a = config.storageKey) != null ? _a : "sb-auth-token";
  const storage = config.storage;
  const detectSessionInUrl = (_b = config.detectSessionInUrl) != null ? _b : false;
  return supabaseJs.createClient(url, anonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl,
      storage,
      // Supabase accetta storage custom con questa interfaccia
      storageKey,
      ...config.lock ? { lock: config.lock } : {}
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
async function submitFeedback(client, params) {
  const { kind, targetId, rating, comment } = params;
  const { data, error } = await client.rpc("submit_feedback", {
    p_kind: kind,
    p_target_id: targetId,
    p_rating: rating,
    p_comment: comment
  });
  if (error) {
    handleRpcError(error, "submit_feedback");
  }
  return data;
}
async function queueFeedbackRequest(client, params) {
  const { clientId, kind, targetId, scheduledFor } = params;
  const { data, error } = await client.rpc("queue_feedback_request", {
    p_client_id: clientId,
    p_kind: kind,
    p_target_id: targetId,
    p_scheduled_for: scheduledFor
  });
  if (error) {
    handleRpcError(error, "queue_feedback_request");
  }
  return data;
}
async function getMyMembership(client) {
  const { data, error } = await client.rpc("get_my_membership");
  if (error) {
    handleRpcError(error, "get_my_membership");
  }
  return data;
}
async function assignMembership(client, params) {
  const { clientId, tierId, startedAt, priceCents, note } = params;
  const { data, error } = await client.rpc("assign_membership", {
    p_client_id: clientId,
    p_tier_id: tierId,
    p_started_at: startedAt,
    p_price_cents: priceCents,
    p_note: note
  });
  if (error) {
    handleRpcError(error, "assign_membership");
  }
  return data;
}
async function cancelMembership(client, membershipId) {
  const { data, error } = await client.rpc("cancel_membership", {
    p_membership_id: membershipId
  });
  if (error) {
    handleRpcError(error, "cancel_membership");
  }
  return data;
}
async function requestBussola(client, params = {}) {
  const { preferredAt, note } = params;
  const { data, error } = await client.rpc("request_bussola", {
    p_preferred_at: preferredAt,
    p_note: note
  });
  if (error) {
    handleRpcError(error, "request_bussola");
  }
  return data;
}
async function cancelBussolaRequest(client, requestId) {
  const { data, error } = await client.rpc("cancel_bussola_request", {
    p_request_id: requestId
  });
  if (error) {
    handleRpcError(error, "cancel_bussola_request");
  }
  return data;
}
async function submitMemberApplication(client, params) {
  const payload = {
    year: params.year,
    first_name: params.firstName,
    last_name: params.lastName,
    birth_date: params.birthDate,
    fiscal_code: params.fiscalCode,
    birth_place: params.birthPlace,
    birth_province: params.birthProvince,
    address_street: params.addressStreet,
    address_city: params.addressCity,
    address_zip: params.addressZip,
    address_province: params.addressProvince,
    email: params.email,
    phone: params.phone,
    accepted_statute: params.acceptedStatute ? "true" : "false",
    accepted_privacy: params.acceptedPrivacy ? "true" : "false",
    image_release: params.imageRelease === void 0 ? void 0 : String(params.imageRelease),
    health_declaration: params.healthDeclaration === void 0 ? void 0 : String(params.healthDeclaration),
    guardian_full_name: params.guardianFullName,
    guardian_fiscal_code: params.guardianFiscalCode,
    guardian_relationship: params.guardianRelationship,
    guardian_email: params.guardianEmail,
    guardian_phone: params.guardianPhone,
    guardian_consent: params.guardianConsent ? "true" : void 0,
    channel: params.channel,
    user_agent: params.userAgent
  };
  for (const key of Object.keys(payload)) {
    if (payload[key] === void 0) delete payload[key];
  }
  const { data, error } = await client.rpc("submit_member_application", {
    p_payload: payload
  });
  if (error) {
    handleRpcError(error, "submit_member_application");
  }
  return data;
}
async function getMyMembershipStatus(client) {
  const { data, error } = await client.rpc("get_my_membership_status");
  if (error) {
    handleRpcError(error, "get_my_membership_status");
  }
  return data;
}
async function getMyMemberCard(client) {
  const { data, error } = await client.rpc("get_my_member_card");
  if (error) {
    handleRpcError(error, "get_my_member_card");
  }
  return data;
}
async function prepareMyFeePayment(client, year) {
  const { data, error } = await client.rpc("prepare_my_fee_payment", year ? { p_year: year } : {});
  if (error) {
    handleRpcError(error, "prepare_my_fee_payment");
  }
  return data;
}
async function bookTrialLesson(client, lessonId) {
  const { data, error } = await client.rpc("book_trial_lesson", {
    p_lesson_id: lessonId
  });
  if (error) {
    handleRpcError(error, "book_trial_lesson");
  }
  return data;
}
async function joinWaitlist(client, lessonId) {
  const { data, error } = await client.rpc("join_waitlist", {
    p_lesson_id: lessonId
  });
  if (error) {
    handleRpcError(error, "join_waitlist");
  }
  return data;
}
async function leaveWaitlist(client, lessonId) {
  const { data, error } = await client.rpc("leave_waitlist", {
    p_lesson_id: lessonId
  });
  if (error) {
    handleRpcError(error, "leave_waitlist");
  }
  return data;
}
async function submitTrialFeedback(client, params) {
  var _a;
  const { data, error } = await client.rpc("submit_trial_feedback", {
    p_trial_id: params.trialId,
    p_rating: params.rating,
    p_answers: (_a = params.answers) != null ? _a : {},
    p_comment: params.comment
  });
  if (error) {
    handleRpcError(error, "submit_trial_feedback");
  }
  return data;
}

// src/labels.ts
var EVENT_TYPE_LABELS = {
  evento: "Evento",
  laboratorio: "Laboratorio",
  incontro: "Incontro"
};
var EVENT_TYPE_LABELS_PLURAL = {
  evento: "Eventi",
  laboratorio: "Laboratori",
  incontro: "Incontri"
};
var TRIAL_FEEDBACK_RATING_QUESTION = "Com'\xE8 andata la lezione di prova?";
var TRIAL_FEEDBACK_QUESTIONS = [
  {
    key: "accoglienza",
    question: "Ti sei sentit\u0259 a tuo agio?",
    options: [
      { value: "si", label: "S\xEC" },
      { value: "abbastanza", label: "Abbastanza" },
      { value: "no", label: "Non molto" }
    ]
  },
  {
    key: "livello",
    question: "Il livello della lezione era adatto a te?",
    options: [
      { value: "giusto", label: "Giusto per me" },
      { value: "facile", label: "Troppo facile" },
      { value: "impegnativo", label: "Troppo impegnativo" }
    ]
  },
  {
    key: "continuare",
    question: "Pensi di continuare?",
    options: [
      { value: "si", label: "S\xEC" },
      { value: "forse", label: "Forse" },
      { value: "no", label: "Per ora no" }
    ]
  }
];
var TRIAL_FEEDBACK_COMMENT_QUESTION = "Vuoi dirci altro?";

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

exports.EVENT_TYPE_LABELS = EVENT_TYPE_LABELS;
exports.EVENT_TYPE_LABELS_PLURAL = EVENT_TYPE_LABELS_PLURAL;
exports.TRIAL_FEEDBACK_COMMENT_QUESTION = TRIAL_FEEDBACK_COMMENT_QUESTION;
exports.TRIAL_FEEDBACK_QUESTIONS = TRIAL_FEEDBACK_QUESTIONS;
exports.TRIAL_FEEDBACK_RATING_QUESTION = TRIAL_FEEDBACK_RATING_QUESTION;
exports.assertSupabaseConfig = assertSupabaseConfig;
exports.assignMembership = assignMembership;
exports.bookEvent = bookEvent;
exports.bookLesson = bookLesson;
exports.bookTrialLesson = bookTrialLesson;
exports.cancelBooking = cancelBooking;
exports.cancelBussolaRequest = cancelBussolaRequest;
exports.cancelEventBooking = cancelEventBooking;
exports.cancelMembership = cancelMembership;
exports.createSupabaseBrowserClient = createSupabaseBrowserClient;
exports.createSupabaseExpoClient = createSupabaseExpoClient;
exports.fromPublic = fromPublic;
exports.getEventsWithAvailability = getEventsWithAvailability;
exports.getMyMemberCard = getMyMemberCard;
exports.getMyMembership = getMyMembership;
exports.getMyMembershipStatus = getMyMembershipStatus;
exports.getPublicActivities = getPublicActivities;
exports.getPublicEvents = getPublicEvents;
exports.getPublicOperators = getPublicOperators;
exports.getPublicPricing = getPublicPricing;
exports.getPublicSchedule = getPublicSchedule;
exports.joinWaitlist = joinWaitlist;
exports.leaveWaitlist = leaveWaitlist;
exports.prepareMyFeePayment = prepareMyFeePayment;
exports.queueFeedbackRequest = queueFeedbackRequest;
exports.requestBussola = requestBussola;
exports.staffBookEvent = staffBookEvent;
exports.staffCancelEventBooking = staffCancelEventBooking;
exports.submitFeedback = submitFeedback;
exports.submitMemberApplication = submitMemberApplication;
exports.submitTrialFeedback = submitTrialFeedback;
//# sourceMappingURL=index.js.map
//# sourceMappingURL=index.js.map