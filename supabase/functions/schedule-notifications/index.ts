// Edge Function: schedule-notifications
// Chiamata dai cron job pg_cron per accodare notifiche.
// Esegue la RPC appropriata in base a jobType.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

type JobType =
  | 'lesson_reminders'
  | 'subscription_expiry'
  | 'entries_low'
  | 're_engagement'
  | 'birthday'

interface RequestBody {
  jobType: JobType
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify service role authentication
    const authHeader = req.headers.get('Authorization')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!authHeader || !authHeader.includes(serviceKey ?? '')) {
      return new Response(
        JSON.stringify({ ok: false, reason: 'UNAUTHORIZED' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse request body
    const body: RequestBody = await req.json()
    if (!body.jobType) {
      return new Response(
        JSON.stringify({ ok: false, reason: 'MISSING_JOB_TYPE' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create admin client
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Execute the appropriate RPC
    let result
    switch (body.jobType) {
      case 'lesson_reminders':
        result = await supabaseAdmin.rpc('queue_lesson_reminders')
        break
      case 'subscription_expiry':
        result = await supabaseAdmin.rpc('queue_subscription_expiry')
        break
      case 'entries_low':
        result = await supabaseAdmin.rpc('queue_entries_low')
        break
      case 're_engagement':
        result = await supabaseAdmin.rpc('queue_re_engagement')
        break
      case 'birthday':
        result = await supabaseAdmin.rpc('queue_birthday')
        break
      default:
        return new Response(
          JSON.stringify({ ok: false, reason: 'UNKNOWN_JOB_TYPE', jobType: body.jobType }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }

    if (result.error) {
      console.error(`Error running ${body.jobType}:`, result.error)
      return new Response(
        JSON.stringify({ ok: false, reason: 'RPC_ERROR', error: result.error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Scheduled notifications for ${body.jobType}:`, result.data)

    return new Response(
      JSON.stringify({ ok: true, jobType: body.jobType, result: result.data }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Schedule notifications error:', error)
    return new Response(
      JSON.stringify({ ok: false, reason: 'INTERNAL_ERROR', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
