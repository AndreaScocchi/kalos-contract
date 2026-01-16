import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface RequestBody {
  contentId: string
  scheduledPublishTime?: number // Unix timestamp
}

interface ResponseBody {
  ok: boolean
  reason?: string
  message?: string
  post_id?: string
}

interface MediaContainerResponse {
  id: string
}

interface PublishResponse {
  id: string
}

const META_GRAPH_URL = 'https://graph.facebook.com/v18.0'

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify authorization
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)
    }

    // Create client with user's token to verify they are staff
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

    // Get user ID
    const { data: { user } } = await supabaseUser.auth.getUser()
    if (!user) {
      return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)
    }

    // Get request body
    const body: RequestBody = await req.json()
    if (!body.contentId) {
      return jsonResponse({ ok: false, reason: 'MISSING_CONTENT_ID' }, 400)
    }

    // Create admin client
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Get content
    const { data: content, error: contentError } = await supabaseAdmin
      .from('campaign_contents')
      .select('*, campaigns(*)')
      .eq('id', body.contentId)
      .single()

    if (contentError || !content) {
      console.error('Content not found:', contentError)
      return jsonResponse({ ok: false, reason: 'CONTENT_NOT_FOUND' }, 404)
    }

    // Determine platform
    const platform = content.platform
    if (!platform || (platform !== 'instagram' && platform !== 'facebook')) {
      return jsonResponse({ ok: false, reason: 'INVALID_PLATFORM' }, 400)
    }

    // Get social connection
    const { data: connection, error: connError } = await supabaseAdmin
      .from('social_connections')
      .select('*')
      .eq('platform', platform)
      .eq('is_active', true)
      .single()

    if (connError || !connection) {
      console.error('No active connection found:', connError)
      return jsonResponse({ ok: false, reason: 'NO_CONNECTION' }, 400)
    }

    // Check token expiry
    if (connection.token_expires_at && new Date(connection.token_expires_at) < new Date()) {
      return jsonResponse({ ok: false, reason: 'TOKEN_EXPIRED', message: 'Please reconnect your Meta account' }, 400)
    }

    let postId: string

    if (platform === 'instagram') {
      postId = await publishInstagramPost(content, connection, body.scheduledPublishTime)
    } else {
      postId = await publishFacebookPost(content, connection, body.scheduledPublishTime)
    }

    // Update content with post ID
    await supabaseAdmin
      .from('campaign_contents')
      .update({
        meta_post_id: postId,
        status: body.scheduledPublishTime ? 'scheduled' : 'published',
        published_at: body.scheduledPublishTime ? null : new Date().toISOString(),
        scheduled_for: body.scheduledPublishTime ? new Date(body.scheduledPublishTime * 1000).toISOString() : null,
      })
      .eq('id', body.contentId)

    // Update connection last used
    await supabaseAdmin
      .from('social_connections')
      .update({ last_used_at: new Date().toISOString() })
      .eq('id', connection.id)

    return jsonResponse({ ok: true, post_id: postId }, 200)

  } catch (error) {
    console.error('Meta publish error:', error)
    return jsonResponse({ ok: false, reason: 'INTERNAL_ERROR', message: (error as Error).message }, 500)
  }
})

async function publishInstagramPost(
  content: Record<string, unknown>,
  connection: Record<string, unknown>,
  scheduledTime?: number
): Promise<string> {
  const igUserId = connection.instagram_business_id as string
  const accessToken = connection.access_token as string

  // Build caption with hashtags
  let caption = content.body as string || ''
  const hashtags = content.hashtags as string[] | null
  if (hashtags && hashtags.length > 0) {
    caption += '\n\n' + hashtags.map(h => `#${h}`).join(' ')
  }

  // Step 1: Create media container
  const containerParams = new URLSearchParams({
    access_token: accessToken,
    caption,
  })

  // Add image or video
  if (content.image_url) {
    containerParams.set('image_url', content.image_url as string)
  } else if (content.video_url) {
    containerParams.set('video_url', content.video_url as string)
    containerParams.set('media_type', 'REELS') // or VIDEO for regular
  } else {
    throw new Error('Instagram posts require an image or video URL')
  }

  const containerRes = await fetch(`${META_GRAPH_URL}/${igUserId}/media`, {
    method: 'POST',
    body: containerParams,
  })

  if (!containerRes.ok) {
    const err = await containerRes.json()
    console.error('Container creation failed:', err)
    throw new Error(err.error?.message || 'Failed to create media container')
  }

  const container: MediaContainerResponse = await containerRes.json()

  // Step 2: Publish the container
  const publishParams = new URLSearchParams({
    access_token: accessToken,
    creation_id: container.id,
  })

  // Add scheduled time if provided (must be 10min to 75 days in future)
  if (scheduledTime) {
    const now = Math.floor(Date.now() / 1000)
    const minTime = now + 600 // 10 minutes
    const maxTime = now + 75 * 24 * 60 * 60 // 75 days

    if (scheduledTime < minTime || scheduledTime > maxTime) {
      throw new Error('Scheduled time must be between 10 minutes and 75 days from now')
    }

    // For scheduled posts, we don't publish immediately
    // Instead we store the container ID and publish later
    // Note: Instagram API doesn't support scheduled_publish_time directly
    // We would need to handle this via our CRON job
    return container.id // Return container ID for later publishing
  }

  const publishRes = await fetch(`${META_GRAPH_URL}/${igUserId}/media_publish`, {
    method: 'POST',
    body: publishParams,
  })

  if (!publishRes.ok) {
    const err = await publishRes.json()
    console.error('Publish failed:', err)
    throw new Error(err.error?.message || 'Failed to publish post')
  }

  const published: PublishResponse = await publishRes.json()
  return published.id
}

async function publishFacebookPost(
  content: Record<string, unknown>,
  connection: Record<string, unknown>,
  scheduledTime?: number
): Promise<string> {
  const pageId = connection.page_id as string
  const accessToken = connection.access_token as string

  const postParams = new URLSearchParams({
    access_token: accessToken,
    message: content.body as string || '',
  })

  // Add link if present
  if (content.link_url) {
    postParams.set('link', content.link_url as string)
  }

  // Add scheduled time if provided
  if (scheduledTime) {
    const now = Math.floor(Date.now() / 1000)
    const minTime = now + 600 // 10 minutes
    const maxTime = now + 75 * 24 * 60 * 60 // 75 days

    if (scheduledTime < minTime || scheduledTime > maxTime) {
      throw new Error('Scheduled time must be between 10 minutes and 75 days from now')
    }

    postParams.set('published', 'false')
    postParams.set('scheduled_publish_time', String(scheduledTime))
  }

  // Determine endpoint based on media type
  let endpoint = `${META_GRAPH_URL}/${pageId}/feed`

  if (content.image_url) {
    endpoint = `${META_GRAPH_URL}/${pageId}/photos`
    postParams.set('url', content.image_url as string)
  }

  const postRes = await fetch(endpoint, {
    method: 'POST',
    body: postParams,
  })

  if (!postRes.ok) {
    const err = await postRes.json()
    console.error('Facebook post failed:', err)
    throw new Error(err.error?.message || 'Failed to create Facebook post')
  }

  const published: PublishResponse = await postRes.json()
  return published.id
}

function jsonResponse(body: ResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
