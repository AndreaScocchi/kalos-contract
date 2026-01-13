import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface ResponseBody {
  ok: boolean
  message?: string
  updated?: number
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
      return jsonResponse({ ok: false, message: 'UNAUTHORIZED' }, 401)
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
      return jsonResponse({ ok: false, message: 'UNAUTHORIZED' }, 403)
    }

    // Create admin client with service_role key
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Get all campaigns with status 'sent'
    const { data: campaigns, error: campaignsError } = await supabaseAdmin
      .from('newsletter_campaigns')
      .select('id')
      .eq('status', 'sent')

    if (campaignsError) {
      console.error('Error fetching campaigns:', campaignsError)
      return jsonResponse({ ok: false, message: 'Error fetching campaigns' }, 500)
    }

    let updatedCount = 0

    for (const campaign of campaigns || []) {
      // Get counts for each status from newsletter_emails
      const { data: emails } = await supabaseAdmin
        .from('newsletter_emails')
        .select('status')
        .eq('campaign_id', campaign.id)

      if (!emails) continue

      const counts = {
        delivered_count: 0,
        opened_count: 0,
        clicked_count: 0,
        bounced_count: 0,
      }

      for (const email of emails) {
        switch (email.status) {
          case 'delivered':
            counts.delivered_count++
            break
          case 'opened':
            counts.delivered_count++ // Opened implies delivered
            counts.opened_count++
            break
          case 'clicked':
            counts.delivered_count++ // Clicked implies delivered and opened
            counts.opened_count++
            counts.clicked_count++
            break
          case 'bounced':
          case 'complained':
            counts.bounced_count++
            break
        }
      }

      await supabaseAdmin
        .from('newsletter_campaigns')
        .update(counts)
        .eq('id', campaign.id)

      updatedCount++
    }

    return jsonResponse({
      ok: true,
      message: `Recalculated stats for ${updatedCount} campaigns`,
      updated: updatedCount
    }, 200)

  } catch (error) {
    console.error('Error:', error)
    return jsonResponse({ ok: false, message: error.message }, 500)
  }
})

function jsonResponse(body: ResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
