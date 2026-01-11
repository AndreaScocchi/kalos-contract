import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface RequestBody {
  userId: string
}

interface ResponseBody {
  ok: boolean
  reason?: string
  message?: string
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify request has authorization
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)
    }

    // Create client with the user's token to verify they are staff
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    // Verify user is staff
    const { data: isStaff, error: staffError } = await supabaseUser.rpc('is_staff')
    if (staffError || !isStaff) {
      return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 403)
    }

    // Get request body
    const body: RequestBody = await req.json()
    if (!body.userId) {
      return jsonResponse({ ok: false, reason: 'MISSING_USER_ID' }, 400)
    }

    // Create admin client with service_role key
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Get user info
    const { data: userData, error: userError } = await supabaseAdmin.auth.admin.getUserById(body.userId)
    if (userError || !userData?.user) {
      console.error('Error getting user:', userError)
      return jsonResponse({ ok: false, reason: 'USER_NOT_FOUND' }, 404)
    }

    // Check if email is already confirmed
    if (userData.user.email_confirmed_at) {
      return jsonResponse({ ok: false, reason: 'ALREADY_CONFIRMED' }, 400)
    }

    // Check if user has an email
    if (!userData.user.email) {
      return jsonResponse({ ok: false, reason: 'NO_EMAIL' }, 400)
    }

    // Generate a new confirmation link - this will send the email
    const { error: linkError } = await supabaseAdmin.auth.admin.generateLink({
      type: 'signup',
      email: userData.user.email,
    })

    if (linkError) {
      console.error('Error generating confirmation link:', linkError)
      return jsonResponse(
        { ok: false, reason: 'RESEND_FAILED', message: linkError.message },
        500
      )
    }

    return jsonResponse({ ok: true }, 200)
  } catch (error) {
    console.error('Edge function error:', error)
    return jsonResponse({ ok: false, reason: 'INTERNAL_ERROR' }, 500)
  }
})

function jsonResponse(body: ResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
