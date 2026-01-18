import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface ResponseBody {
  ok: boolean
  reason?: string
  message?: string
  executed_count?: number
}

interface Campaign {
  id: string
  name: string
  type: string
  status: string
  skipped_steps: number[]
  test_client_id: string | null
}

interface Content {
  id: string
  campaign_id: string
  content_type: string
  platform: string | null
  status: string
  title: string | null
  body: string | null
  image_url: string | null
  link_url: string | null
  link_label: string | null
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''

    // Parse body for manual execution
    let body: { campaignId?: string } = {}
    try {
      body = await req.json()
    } catch {
      // No body or invalid JSON - that's OK for CRON calls
    }

    const isServiceRole = authHeader?.includes(serviceKey || '')
    let isStaffUser = false

    // If not service role, check if it's a valid staff user
    if (!isServiceRole && authHeader) {
      const token = authHeader.replace('Bearer ', '')
      const supabaseUser = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY') ?? '', {
        global: { headers: { Authorization: `Bearer ${token}` } },
        auth: { autoRefreshToken: false, persistSession: false },
      })

      // Verify user and check if staff
      const { data: { user } } = await supabaseUser.auth.getUser()
      if (user) {
        const { data: profile } = await supabaseUser
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single()

        isStaffUser = profile?.role && ['admin', 'operator', 'finance'].includes(profile.role)
      }
    }

    if (!isServiceRole && !isStaffUser) {
      return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)
    }

    // Create admin client for operations
    const supabaseAdmin = createClient(
      supabaseUrl,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // If campaignId is provided, execute that specific campaign
    // Otherwise, execute all scheduled campaigns that are due (CRON mode)
    let campaignQuery = supabaseAdmin
      .from('campaigns')
      .select('id, name, type, status, skipped_steps, test_client_id')
      .is('deleted_at', null)

    if (body.campaignId) {
      // Manual execution - execute specific campaign regardless of status
      campaignQuery = campaignQuery.eq('id', body.campaignId)
    } else {
      // CRON execution - only scheduled campaigns that are due
      campaignQuery = campaignQuery
        .eq('status', 'scheduled')
        .lte('scheduled_for', new Date().toISOString())
    }

    const { data: campaigns, error: campaignsError } = await campaignQuery

    if (campaignsError) {
      console.error('Failed to fetch campaigns:', campaignsError)
      return jsonResponse({ ok: false, reason: 'FETCH_FAILED' }, 500)
    }

    console.log('Campaigns found:', JSON.stringify(campaigns, null, 2))

    if (!campaigns || campaigns.length === 0) {
      return jsonResponse({ ok: true, message: 'No campaigns to execute', executed_count: 0 }, 200)
    }

    let executedCount = 0
    const errors: string[] = []

    for (const campaign of campaigns as Campaign[]) {
      try {
        console.log(`Executing campaign: ${campaign.name} (${campaign.id})`)

        // Update status to executing
        await supabaseAdmin
          .from('campaigns')
          .update({ status: 'executing' })
          .eq('id', campaign.id)

        // Get campaign contents
        const { data: contents, error: contentsError } = await supabaseAdmin
          .from('campaign_contents')
          .select('*')
          .eq('campaign_id', campaign.id)
          .neq('status', 'skipped')

        if (contentsError || !contents) {
          throw new Error('Failed to fetch campaign contents')
        }

        const skippedSteps = campaign.skipped_steps || []
        let hasErrors = false

        // Process each content type
        for (const content of contents as Content[]) {
          try {
            // Check if this content type's step was skipped
            const stepMap: Record<string, number> = {
              'brief': 3,
              'push_notification': 4,
              'newsletter': 5,
              'instagram_post': 6,
              'instagram_story': 6,
              'facebook_post': 6,
            }

            const stepId = stepMap[content.content_type]
            if (stepId && skippedSteps.includes(stepId)) {
              await supabaseAdmin
                .from('campaign_contents')
                .update({ status: 'skipped' })
                .eq('id', content.id)
              continue
            }

            // Execute based on content type
            switch (content.content_type) {
              case 'push_notification':
                await executePushNotification(supabaseAdmin, campaign, content)
                break

              case 'newsletter':
                await executeNewsletter(supabaseAdmin, campaign, content, campaign.test_client_id)
                break

              case 'instagram_post':
              case 'instagram_story':
              case 'facebook_post':
                await executeSocialPost(supabaseAdmin, content)
                break

              case 'brief':
                // Brief is just informational, mark as sent
                await supabaseAdmin
                  .from('campaign_contents')
                  .update({ status: 'sent', sent_at: new Date().toISOString() })
                  .eq('id', content.id)
                break
            }

          } catch (err) {
            const errorMessage = err instanceof Error ? err.message : String(err)
            console.error(`Error executing content ${content.id} (type: ${content.content_type}):`, errorMessage)
            hasErrors = true

            // Update content status to failed
            await supabaseAdmin
              .from('campaign_contents')
              .update({
                status: 'failed',
                error_message: errorMessage,
                retry_count: (content as unknown as { retry_count: number }).retry_count + 1,
              })
              .eq('id', content.id)
          }
        }

        // Update campaign status
        await supabaseAdmin
          .from('campaigns')
          .update({
            status: hasErrors ? 'failed' : 'completed',
            executed_at: new Date().toISOString(),
          })
          .eq('id', campaign.id)

        if (!hasErrors) {
          executedCount++
        }

      } catch (err) {
        console.error(`Error executing campaign ${campaign.id}:`, err)
        errors.push(`Campaign ${campaign.id}: ${(err as Error).message}`)

        // Update campaign status to failed
        await supabaseAdmin
          .from('campaigns')
          .update({ status: 'failed' })
          .eq('id', campaign.id)
      }
    }

    return jsonResponse({
      ok: true,
      executed_count: executedCount,
      message: errors.length > 0 ? `Executed ${executedCount} with ${errors.length} errors` : undefined,
    }, 200)

  } catch (error) {
    console.error('Execute campaigns error:', error)
    return jsonResponse({ ok: false, reason: 'INTERNAL_ERROR', message: (error as Error).message }, 500)
  }
})

async function executePushNotification(
  supabase: ReturnType<typeof createClient>,
  campaign: Campaign,
  content: Content
): Promise<void> {
  const testClientId = campaign.test_client_id

  // Get target clients
  let clientIds: string[] = []

  if (testClientId) {
    // Test mode: only send to specific client
    clientIds = [testClientId]
  } else {
    // Production mode: get all active clients
    const { data: clients, error: clientsError } = await supabase
      .from('clients')
      .select('id')
      .eq('is_active', true)
      .is('deleted_at', null)

    if (clientsError) {
      throw new Error(`Failed to fetch clients: ${clientsError.message}`)
    }

    clientIds = (clients || []).map((c: { id: string }) => c.id)
  }

  if (clientIds.length === 0) {
    console.log('No clients to notify')
    await supabase
      .from('campaign_contents')
      .update({ status: 'sent', sent_at: new Date().toISOString() })
      .eq('id', content.id)
    return
  }

  // Map campaign type to announcement category
  const categoryMap: Record<string, string> = {
    'promo': 'promotion',
    'evento': 'event',
    'annuncio': 'general',
    'corso_nuovo': 'course',
  }
  const announcementCategory = categoryMap[campaign.type] || 'general'

  // Create an announcement record so it appears in the app's notification list
  // Only create if not in test mode (to avoid polluting the announcements table)
  let announcementId: string | null = null
  if (!testClientId) {
    const { data: announcement, error: announcementError } = await supabase
      .from('announcements')
      .insert({
        title: content.title || 'Notifica',
        body: content.body || '',
        category: announcementCategory,
        image_url: content.image_url,
        link_url: content.link_url,
        link_label: content.link_label,
        is_active: true,
        starts_at: new Date().toISOString(),
        ends_at: null, // No expiration - stays visible until manually deactivated
      })
      .select('id')
      .single()

    if (announcementError) {
      console.error('Failed to create announcement:', announcementError)
      // Don't throw - push notifications can still be sent without the announcement
    } else {
      announcementId = announcement?.id
      console.log(`Created announcement ${announcementId} for campaign push notification`)
    }
  }

  // Create notification queue entries for each client
  const now = new Date().toISOString()
  const notifications = clientIds.map(clientId => ({
    client_id: clientId,
    category: 'announcement' as const,
    channel: 'push' as const,
    title: content.title || 'Notifica',
    body: content.body || '',
    scheduled_for: now,
    status: 'pending' as const,
    data: {
      campaign_content_id: content.id,
      campaign_id: content.campaign_id,
      announcement_id: announcementId,
      is_test: !!testClientId,
    },
  }))

  const { error } = await supabase
    .from('notification_queue')
    .insert(notifications)

  if (error) {
    throw new Error(`Failed to queue push notifications: ${error.message}`)
  }

  console.log(`Queued ${notifications.length} push notifications`)

  // Update content status
  await supabase
    .from('campaign_contents')
    .update({ status: 'sent', sent_at: new Date().toISOString() })
    .eq('id', content.id)
}

async function executeNewsletter(
  supabase: ReturnType<typeof createClient>,
  _campaign: Campaign,
  content: Content,
  testClientId: string | null
): Promise<void> {
  // Create newsletter_campaign (existing system)
  const { data: newsletterCampaign, error: createError } = await supabase
    .from('newsletter_campaigns')
    .insert({
      subject: content.title || 'Newsletter',
      content: content.body || '',
      status: 'draft',
    })
    .select()
    .single()

  if (createError || !newsletterCampaign) {
    throw new Error(`Failed to create newsletter campaign: ${createError?.message}`)
  }

  console.log(`Created newsletter campaign ${newsletterCampaign.id} for content ${content.id}, testClientId: ${testClientId}`)

  // Update content with newsletter reference
  await supabase
    .from('campaign_contents')
    .update({ newsletter_campaign_id: newsletterCampaign.id })
    .eq('id', content.id)

  // Trigger send-newsletter edge function
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

  const response = await fetch(`${supabaseUrl}/functions/v1/send-newsletter`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${serviceKey}`,
    },
    body: JSON.stringify({
      campaignId: newsletterCampaign.id,
      testClientId: testClientId, // Pass to newsletter for single recipient
    }),
  })

  if (!response.ok) {
    const err = await response.text()
    throw new Error(`Failed to send newsletter: ${err}`)
  }

  // Update content status
  await supabase
    .from('campaign_contents')
    .update({ status: 'sent', sent_at: new Date().toISOString() })
    .eq('id', content.id)
}

async function executeSocialPost(
  supabase: ReturnType<typeof createClient>,
  content: Content
): Promise<void> {
  // Check if we have a media URL (required for Instagram)
  if (content.platform === 'instagram' && !content.body) {
    // For Instagram, we need at least a caption
    // Image would need to be uploaded separately
    console.warn(`Instagram post ${content.id} has no content, skipping`)
    await supabase
      .from('campaign_contents')
      .update({ status: 'skipped', error_message: 'No content to publish' })
      .eq('id', content.id)
    return
  }

  // Call meta-publish-post edge function
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

  const response = await fetch(`${supabaseUrl}/functions/v1/meta-publish-post`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${serviceKey}`,
    },
    body: JSON.stringify({ contentId: content.id }),
  })

  if (!response.ok) {
    const err = await response.json()
    throw new Error(err.message || 'Failed to publish social post')
  }

  // Content status is updated by meta-publish-post
}

function jsonResponse(body: ResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
