// Edge Function: register-push-token
// Registra un token push per un utente autenticato.
// Supporta sia Web Push subscription che Expo Push Token (legacy).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface WebPushSubscription {
  endpoint: string
  keys: {
    p256dh: string
    auth: string
  }
}

interface RequestBody {
  // Web Push subscription
  webPushSubscription?: WebPushSubscription
  // Expo Push Token (legacy per app native)
  expoPushToken?: string
  // Platform
  platform: 'ios' | 'android' | 'web'
  // Optional metadata
  deviceId?: string
  appVersion?: string
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ ok: false, reason: 'UNAUTHORIZED' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create client with user's auth
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    // Get user's client_id
    const { data: clientId, error: clientError } = await supabaseUser.rpc('get_my_client_id')
    if (clientError || !clientId) {
      console.error('Error getting client_id:', clientError)
      return new Response(
        JSON.stringify({ ok: false, reason: 'CLIENT_NOT_FOUND' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse request body
    const body: RequestBody = await req.json()

    // Validate request
    if (!body.webPushSubscription && !body.expoPushToken) {
      return new Response(
        JSON.stringify({ ok: false, reason: 'MISSING_TOKEN_OR_SUBSCRIPTION' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Determine token value based on platform
    let tokenValue: string

    if (body.platform === 'web' && body.webPushSubscription) {
      // Per Web Push, salviamo la subscription come JSON
      tokenValue = JSON.stringify(body.webPushSubscription)

      // Validate web push subscription
      if (!body.webPushSubscription.endpoint || !body.webPushSubscription.keys?.p256dh || !body.webPushSubscription.keys?.auth) {
        return new Response(
          JSON.stringify({ ok: false, reason: 'INVALID_WEB_PUSH_SUBSCRIPTION' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    } else if (body.expoPushToken) {
      // Expo token per app native
      tokenValue = body.expoPushToken

      // Validate Expo token format
      const isValidExpoToken = body.expoPushToken.startsWith('ExponentPushToken[') ||
                               body.expoPushToken.startsWith('ExpoPushToken[')
      if (!isValidExpoToken) {
        return new Response(
          JSON.stringify({ ok: false, reason: 'INVALID_EXPO_TOKEN_FORMAT' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    } else {
      return new Response(
        JSON.stringify({ ok: false, reason: 'INVALID_REQUEST' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create admin client for database operations
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Upsert the token (update if exists, insert if new)
    const { error: upsertError } = await supabaseAdmin
      .from('device_tokens')
      .upsert(
        {
          client_id: clientId,
          expo_push_token: tokenValue,
          device_id: body.deviceId || null,
          platform: body.platform || null,
          app_version: body.appVersion || null,
          is_active: true,
          last_used_at: new Date().toISOString(),
        },
        {
          onConflict: 'expo_push_token',
          ignoreDuplicates: false,
        }
      )

    if (upsertError) {
      console.error('Error upserting token:', upsertError)
      return new Response(
        JSON.stringify({ ok: false, reason: 'DB_ERROR', message: upsertError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Registered push token for client ${clientId}, platform: ${body.platform}`)

    return new Response(
      JSON.stringify({ ok: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Edge function error:', error)
    return new Response(
      JSON.stringify({ ok: false, reason: 'INTERNAL_ERROR', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
