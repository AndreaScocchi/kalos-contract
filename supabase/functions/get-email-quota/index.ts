import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { getSendQuota } from '../_shared/ses.ts'

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

// Fallbacks used only when the SES account API is unreachable. Neither value caps
// sending: the real gate reads the live 24h quota from SES before each campaign.
//  - daily   mirrors the account's 24h sending quota (200 in sandbox, 50k after
//            production access — AWS grants the default and documents no way down)
//  - monthly is a self-imposed budget guardrail: SES has no monthly cap, but a
//    visible ceiling keeps a runaway send from turning into a surprise bill
const FALLBACK_LIMITS = {
  daily: Number(Deno.env.get('SES_DAILY_QUOTA') ?? '5000'),
  monthly: Number(Deno.env.get('MAIL_MONTHLY_BUDGET') ?? '50000'),
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

    // The daily figure that actually gates sending is SES's own rolling 24h
    // counter, so prefer it over our calendar-day count from the database.
    // SES reports Max24HourSend = -1 for accounts with no cap.
    let dailyLimit = FALLBACK_LIMITS.daily
    let dailyCount = dailyUsed
    const { data: sendQuota, error: quotaError } = await getSendQuota()
    if (sendQuota) {
      if (sendQuota.max24HourSend > 0) dailyLimit = sendQuota.max24HourSend
      dailyCount = Math.round(sendQuota.sentLast24Hours)
    } else if (quotaError) {
      console.error('SES quota lookup failed, using database counts:', quotaError.message)
    }

    const quota: QuotaResponse['quota'] = {
      daily: {
        used: dailyCount,
        limit: dailyLimit,
        remaining: Math.max(0, dailyLimit - dailyCount),
      },
      monthly: {
        used: monthlyUsed,
        limit: FALLBACK_LIMITS.monthly,
        remaining: Math.max(0, FALLBACK_LIMITS.monthly - monthlyUsed),
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
