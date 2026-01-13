// Edge Function: register-push-token
// Registra un token push Expo per un utente autenticato.
// Chiamata dall'app quando l'utente accetta le notifiche push.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface RequestBody {
  expoPushToken: string
  deviceId?: string
  platform?: 'ios' | 'android' | 'web'
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
    if (!body.expoPushToken) {
      return new Response(
        JSON.stringify({ ok: false, reason: 'MISSING_TOKEN' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate token format (Expo Push Token or web push)
    const isValidToken = body.expoPushToken.startsWith('ExponentPushToken[') ||
                         body.expoPushToken.startsWith('ExpoPushToken[') ||
                         body.platform === 'web'
    if (!isValidToken) {
      return new Response(
        JSON.stringify({ ok: false, reason: 'INVALID_TOKEN_FORMAT' }),
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
          expo_push_token: body.expoPushToken,
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
