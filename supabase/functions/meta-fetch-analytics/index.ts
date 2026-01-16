import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface ResponseBody {
  ok: boolean
  reason?: string
  message?: string
  updated_count?: number
}

interface InsightsData {
  data: Array<{
    name: string
    values: Array<{ value: number }>
  }>
}

interface PostInsights {
  reach?: number
  impressions?: number
  engagement?: number
  likes?: number
  comments?: number
  shares?: number
  saves?: number
}

const META_GRAPH_URL = 'https://graph.facebook.com/v18.0'

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // This function is called by CRON, verify service role key
    const authHeader = req.headers.get('Authorization')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!authHeader || !authHeader.includes(serviceKey || '')) {
      // Allow staff to trigger manual refresh
      const supabaseUser = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_ANON_KEY') ?? '',
        { global: { headers: { Authorization: authHeader || '' } } }
      )

      const { data: isStaff } = await supabaseUser.rpc('is_staff')
      if (!isStaff) {
        return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)
      }
    }

    // Create admin client
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Get all published contents with meta_post_id
    const { data: contents, error: contentsError } = await supabaseAdmin
      .from('campaign_contents')
      .select('id, campaign_id, content_type, platform, meta_post_id')
      .not('meta_post_id', 'is', null)
      .in('status', ['published', 'sent'])

    if (contentsError) {
      console.error('Failed to fetch contents:', contentsError)
      return jsonResponse({ ok: false, reason: 'FETCH_FAILED' }, 500)
    }

    if (!contents || contents.length === 0) {
      return jsonResponse({ ok: true, message: 'No published posts to update', updated_count: 0 }, 200)
    }

    // Get active social connections
    const { data: connections, error: connError } = await supabaseAdmin
      .from('social_connections')
      .select('*')
      .eq('is_active', true)

    if (connError || !connections || connections.length === 0) {
      return jsonResponse({ ok: false, reason: 'NO_CONNECTIONS' }, 400)
    }

    // Create connection map by platform
    const connectionMap = new Map<string, typeof connections[0]>()
    for (const conn of connections) {
      connectionMap.set(conn.platform, conn)
    }

    let updatedCount = 0
    const errors: string[] = []

    // Process each content
    for (const content of contents) {
      try {
        const connection = connectionMap.get(content.platform || '')
        if (!connection) {
          console.warn(`No connection found for platform: ${content.platform}`)
          continue
        }

        // Check token expiry
        if (connection.token_expires_at && new Date(connection.token_expires_at) < new Date()) {
          console.warn(`Token expired for ${connection.platform}`)
          continue
        }

        let insights: PostInsights

        if (content.platform === 'instagram') {
          insights = await fetchInstagramInsights(content.meta_post_id, connection.access_token)
        } else {
          insights = await fetchFacebookInsights(content.meta_post_id, connection.access_token)
        }

        // Upsert analytics
        const { error: upsertError } = await supabaseAdmin
          .from('campaign_analytics')
          .upsert({
            campaign_id: content.campaign_id,
            content_id: content.id,
            channel: content.platform,
            reach: insights.reach || 0,
            impressions: insights.impressions || 0,
            engagement: insights.engagement || 0,
            likes: insights.likes || 0,
            comments: insights.comments || 0,
            shares: insights.shares || 0,
            saves: insights.saves || 0,
            last_fetched_at: new Date().toISOString(),
          }, { onConflict: 'campaign_id,channel' })

        if (upsertError) {
          console.error(`Failed to upsert analytics for content ${content.id}:`, upsertError)
          errors.push(`Content ${content.id}: ${upsertError.message}`)
        } else {
          updatedCount++
        }

        // Update campaign totals
        await updateCampaignTotals(supabaseAdmin, content.campaign_id)

      } catch (err) {
        console.error(`Error processing content ${content.id}:`, err)
        errors.push(`Content ${content.id}: ${(err as Error).message}`)
      }
    }

    return jsonResponse({
      ok: true,
      updated_count: updatedCount,
      message: errors.length > 0 ? `Updated ${updatedCount} with ${errors.length} errors` : undefined,
    }, 200)

  } catch (error) {
    console.error('Meta analytics error:', error)
    return jsonResponse({ ok: false, reason: 'INTERNAL_ERROR', message: (error as Error).message }, 500)
  }
})

async function fetchInstagramInsights(mediaId: string, accessToken: string): Promise<PostInsights> {
  // Instagram media insights
  const metrics = 'reach,impressions,engagement,saved'
  const url = `${META_GRAPH_URL}/${mediaId}/insights?metric=${metrics}&access_token=${accessToken}`

  const res = await fetch(url)
  if (!res.ok) {
    const err = await res.json()
    throw new Error(err.error?.message || 'Failed to fetch Instagram insights')
  }

  const data: InsightsData = await res.json()
  const insights: PostInsights = {}

  for (const metric of data.data || []) {
    const value = metric.values?.[0]?.value || 0
    switch (metric.name) {
      case 'reach':
        insights.reach = value
        break
      case 'impressions':
        insights.impressions = value
        break
      case 'engagement':
        insights.engagement = value
        break
      case 'saved':
        insights.saves = value
        break
    }
  }

  // Also get basic engagement counts from the media object
  const mediaUrl = `${META_GRAPH_URL}/${mediaId}?fields=like_count,comments_count&access_token=${accessToken}`
  const mediaRes = await fetch(mediaUrl)
  if (mediaRes.ok) {
    const mediaData = await mediaRes.json()
    insights.likes = mediaData.like_count || 0
    insights.comments = mediaData.comments_count || 0
  }

  return insights
}

async function fetchFacebookInsights(postId: string, accessToken: string): Promise<PostInsights> {
  // Facebook post insights
  const metrics = 'post_impressions,post_impressions_unique,post_engaged_users,post_clicks'
  const url = `${META_GRAPH_URL}/${postId}/insights?metric=${metrics}&access_token=${accessToken}`

  const res = await fetch(url)
  if (!res.ok) {
    // Some posts might not have insights (e.g., organic posts under 100 impressions)
    console.warn(`No insights available for post ${postId}`)
    return {}
  }

  const data: InsightsData = await res.json()
  const insights: PostInsights = {}

  for (const metric of data.data || []) {
    const value = metric.values?.[0]?.value || 0
    switch (metric.name) {
      case 'post_impressions':
        insights.impressions = value
        break
      case 'post_impressions_unique':
        insights.reach = value
        break
      case 'post_engaged_users':
        insights.engagement = value
        break
    }
  }

  // Get reactions/comments/shares from the post object
  const postUrl = `${META_GRAPH_URL}/${postId}?fields=reactions.summary(true),comments.summary(true),shares&access_token=${accessToken}`
  const postRes = await fetch(postUrl)
  if (postRes.ok) {
    const postData = await postRes.json()
    insights.likes = postData.reactions?.summary?.total_count || 0
    insights.comments = postData.comments?.summary?.total_count || 0
    insights.shares = postData.shares?.count || 0
  }

  return insights
}

async function updateCampaignTotals(
  supabase: ReturnType<typeof createClient>,
  campaignId: string
): Promise<void> {
  // Get all analytics for this campaign
  const { data: analytics } = await supabase
    .from('campaign_analytics')
    .select('reach, engagement')
    .eq('campaign_id', campaignId)

  if (!analytics) return

  // Sum totals
  const totalReach = analytics.reduce((sum, a) => sum + (a.reach || 0), 0)
  const totalEngagement = analytics.reduce((sum, a) => sum + (a.engagement || 0), 0)

  // Update campaign
  await supabase
    .from('campaigns')
    .update({
      total_reach: totalReach,
      total_engagement: totalEngagement,
    })
    .eq('id', campaignId)
}

function jsonResponse(body: ResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
