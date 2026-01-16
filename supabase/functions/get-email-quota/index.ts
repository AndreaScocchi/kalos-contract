import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface QuotaResponse {
  ok: boolean
  reason?: string
  quota?: {
    daily?: {
      remaining: number
      limit: number
      used: number
    }
    monthly?: {
      remaining: number
      limit: number
      used: number
    }
  }
}

// Known limits for free tier (update these if plan changes)
const FREE_TIER_LIMITS = {
  daily: 100,
  monthly: 3000,
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

    // Create admin client with service_role key for querying
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Calculate date ranges
    const now = new Date()

    // Start of today (UTC)
    const todayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))

    // Start of current month (UTC)
    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))

    // Count emails from TWO sources:
    // 1. newsletter_emails - newsletter campaigns
    // 2. notification_logs where channel = 'email' - transactional emails

    // Newsletter emails sent today
    const { count: newsletterDailyCount } = await supabaseAdmin
      .from('newsletter_emails')
      .select('*', { count: 'exact', head: true })
      .gte('sent_at', todayStart.toISOString())
      .in('status', ['sent', 'delivered', 'opened', 'clicked'])

    // Newsletter emails sent this month
    const { count: newsletterMonthlyCount } = await supabaseAdmin
      .from('newsletter_emails')
      .select('*', { count: 'exact', head: true })
      .gte('sent_at', monthStart.toISOString())
      .in('status', ['sent', 'delivered', 'opened', 'clicked'])

    // Notification emails sent today
    const { count: notificationDailyCount } = await supabaseAdmin
      .from('notification_logs')
      .select('*', { count: 'exact', head: true })
      .eq('channel', 'email')
      .gte('sent_at', todayStart.toISOString())
      .in('status', ['sent', 'delivered'])

    // Notification emails sent this month
    const { count: notificationMonthlyCount } = await supabaseAdmin
      .from('notification_logs')
      .select('*', { count: 'exact', head: true })
      .eq('channel', 'email')
      .gte('sent_at', monthStart.toISOString())
      .in('status', ['sent', 'delivered'])

    // Sum all email sources
    const dailyUsed = (newsletterDailyCount ?? 0) + (notificationDailyCount ?? 0)
    const monthlyUsed = (newsletterMonthlyCount ?? 0) + (notificationMonthlyCount ?? 0)

    const quota: QuotaResponse['quota'] = {
      daily: {
        used: dailyUsed,
        limit: FREE_TIER_LIMITS.daily,
        remaining: Math.max(0, FREE_TIER_LIMITS.daily - dailyUsed),
      },
      monthly: {
        used: monthlyUsed,
        limit: FREE_TIER_LIMITS.monthly,
        remaining: Math.max(0, FREE_TIER_LIMITS.monthly - monthlyUsed),
      },
    }

    return jsonResponse({
      ok: true,
      quota,
    }, 200)

  } catch (error) {
    console.error('Edge function error:', error)
    return jsonResponse({ ok: false, reason: 'INTERNAL_ERROR' }, 500)
  }
})

function jsonResponse(body: QuotaResponse, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
