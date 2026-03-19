// Edge Function: delete-account
// Elimina l'account dell'utente autenticato e tutti i dati correlati.
// Cancella: client, profile, device_tokens, notification data, journal, practice state.
// L'utente auth viene eliminato tramite admin API.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

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

    // Create user client to get identity
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    // Get current user
    const { data: { user }, error: userError } = await supabaseUser.auth.getUser()
    if (userError || !user) {
      return new Response(
        JSON.stringify({ ok: false, reason: 'USER_NOT_FOUND' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get client_id
    const { data: clientId, error: clientError } = await supabaseUser.rpc('get_my_client_id')
    if (clientError) {
      console.error('Error getting client_id:', clientError)
    }

    // Create admin client for deletion operations
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Delete user data if client exists
    if (clientId) {
      // Delete in order to respect FK constraints
      // 1. Journal entries
      await supabaseAdmin.from('journal_entries').delete().eq('client_id', clientId)

      // 2. Practice user state
      await supabaseAdmin.from('practice_user_state').delete().eq('client_id', clientId)

      // 3. Notification-related data
      await supabaseAdmin.from('notification_queue').delete().eq('client_id', clientId)
      await supabaseAdmin.from('notification_logs').delete().eq('client_id', clientId)
      await supabaseAdmin.from('notification_preferences').delete().eq('client_id', clientId)
      await supabaseAdmin.from('notification_reads').delete().eq('client_id', clientId)
      await supabaseAdmin.from('device_tokens').delete().eq('client_id', clientId)

      // 4. Bookings (soft delete - keep for audit)
      await supabaseAdmin.from('bookings').update({ status: 'canceled' }).eq('client_id', clientId).eq('status', 'booked')
      await supabaseAdmin.from('event_bookings').update({ status: 'canceled' }).eq('client_id', clientId).eq('status', 'booked')

      // 5. Soft-delete client record
      await supabaseAdmin.from('clients').update({
        deleted_at: new Date().toISOString(),
        is_active: false,
        notes: `Account eliminato dall'utente il ${new Date().toLocaleDateString('it-IT')}`,
      }).eq('id', clientId)
    }

    // Soft-delete profile
    await supabaseAdmin.from('profiles').update({
      deleted_at: new Date().toISOString(),
      full_name: 'Account eliminato',
      phone: null,
      avatar_url: null,
    }).eq('id', user.id)

    // Delete auth user (this invalidates all sessions)
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(user.id)
    if (deleteError) {
      console.error('Error deleting auth user:', deleteError)
      return new Response(
        JSON.stringify({ ok: false, reason: 'AUTH_DELETE_FAILED', message: deleteError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Account deleted: user=${user.id}, client=${clientId}`)

    return new Response(
      JSON.stringify({ ok: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Delete account error:', error)
    return new Response(
      JSON.stringify({ ok: false, reason: 'INTERNAL_ERROR', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
