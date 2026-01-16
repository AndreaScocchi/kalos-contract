import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface TokenResponse {
  access_token: string
  token_type: string
  expires_in?: number
}

interface LongLivedTokenResponse {
  access_token: string
  token_type: string
  expires_in: number
}

interface FacebookPage {
  id: string
  name: string
  access_token: string
  instagram_business_account?: {
    id: string
    username: string
  }
}

interface PagesResponse {
  data: FacebookPage[]
}

interface ResponseBody {
  ok: boolean
  reason?: string
  message?: string
  redirect_url?: string
}

const META_GRAPH_URL = 'https://graph.facebook.com/v18.0'

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = new URL(req.url)
    const code = url.searchParams.get('code')
    const state = url.searchParams.get('state')
    const error = url.searchParams.get('error')
    const errorReason = url.searchParams.get('error_reason')

    // Check for OAuth error
    if (error) {
      console.error('OAuth error:', error, errorReason)
      return redirectWithError('OAUTH_DENIED', errorReason || error)
    }

    if (!code || !state) {
      return redirectWithError('MISSING_PARAMS', 'Missing code or state parameter')
    }

    // Parse state (contains operator_id and redirect URL)
    let stateData: { operator_id: string; redirect_url: string }
    try {
      stateData = JSON.parse(atob(state))
    } catch {
      return redirectWithError('INVALID_STATE', 'Could not parse state parameter')
    }

    const { operator_id, redirect_url } = stateData

    // Get app credentials
    const appId = Deno.env.get('META_APP_ID')
    const appSecret = Deno.env.get('META_APP_SECRET')
    const supabaseUrl = Deno.env.get('SUPABASE_URL')

    if (!appId || !appSecret) {
      return redirectWithError('CONFIG_ERROR', 'Meta app not configured')
    }

    // Exchange code for short-lived token
    const redirectUri = `${supabaseUrl}/functions/v1/meta-oauth-callback`
    const tokenUrl = `${META_GRAPH_URL}/oauth/access_token?` +
      `client_id=${appId}&` +
      `redirect_uri=${encodeURIComponent(redirectUri)}&` +
      `client_secret=${appSecret}&` +
      `code=${code}`

    const tokenRes = await fetch(tokenUrl)
    if (!tokenRes.ok) {
      const err = await tokenRes.text()
      console.error('Token exchange failed:', err)
      return redirectWithError('TOKEN_EXCHANGE_FAILED', 'Could not exchange code for token')
    }

    const tokenData: TokenResponse = await tokenRes.json()

    // Exchange for long-lived token (60 days)
    const longLivedUrl = `${META_GRAPH_URL}/oauth/access_token?` +
      `grant_type=fb_exchange_token&` +
      `client_id=${appId}&` +
      `client_secret=${appSecret}&` +
      `fb_exchange_token=${tokenData.access_token}`

    const longLivedRes = await fetch(longLivedUrl)
    if (!longLivedRes.ok) {
      console.error('Long-lived token exchange failed')
      // Continue with short-lived token
    }

    const longLivedData: LongLivedTokenResponse = longLivedRes.ok
      ? await longLivedRes.json()
      : { access_token: tokenData.access_token, token_type: 'bearer', expires_in: 3600 }

    // Get Facebook pages
    const pagesUrl = `${META_GRAPH_URL}/me/accounts?` +
      `fields=id,name,access_token,instagram_business_account{id,username}&` +
      `access_token=${longLivedData.access_token}`

    const pagesRes = await fetch(pagesUrl)
    if (!pagesRes.ok) {
      console.error('Failed to fetch pages')
      return redirectWithError('PAGES_FETCH_FAILED', 'Could not fetch Facebook pages')
    }

    const pagesData: PagesResponse = await pagesRes.json()

    if (!pagesData.data || pagesData.data.length === 0) {
      return redirectWithError('NO_PAGES', 'No Facebook pages found. Please ensure your account manages at least one page.')
    }

    // Create admin client
    const supabaseAdmin = createClient(
      supabaseUrl ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Calculate token expiry
    const tokenExpiresAt = new Date(Date.now() + longLivedData.expires_in * 1000).toISOString()

    // Save connections for each page
    const connections = []

    for (const page of pagesData.data) {
      // Facebook connection
      connections.push({
        operator_id,
        platform: 'facebook',
        account_id: page.id,
        account_name: page.name,
        page_id: page.id,
        page_name: page.name,
        access_token: page.access_token,
        token_expires_at: tokenExpiresAt,
        permissions: ['pages_manage_posts', 'pages_read_engagement'],
        is_active: true,
      })

      // Instagram connection (if business account linked)
      if (page.instagram_business_account) {
        connections.push({
          operator_id,
          platform: 'instagram',
          account_id: page.instagram_business_account.id,
          account_name: page.instagram_business_account.username,
          page_id: page.id,
          page_name: page.name,
          instagram_business_id: page.instagram_business_account.id,
          instagram_username: page.instagram_business_account.username,
          access_token: page.access_token, // Use page token for Instagram
          token_expires_at: tokenExpiresAt,
          permissions: ['instagram_basic', 'instagram_content_publish', 'instagram_manage_insights'],
          is_active: true,
        })
      }
    }

    // Upsert connections
    const { error: upsertError } = await supabaseAdmin
      .from('social_connections')
      .upsert(connections, { onConflict: 'operator_id,platform' })

    if (upsertError) {
      console.error('Failed to save connections:', upsertError)
      return redirectWithError('SAVE_FAILED', 'Could not save social connections')
    }

    // Redirect back to management app with success
    const successUrl = new URL(redirect_url)
    successUrl.searchParams.set('meta_connected', 'true')
    successUrl.searchParams.set('pages_count', String(pagesData.data.length))

    return Response.redirect(successUrl.toString(), 302)

  } catch (error) {
    console.error('Meta OAuth error:', error)
    return redirectWithError('INTERNAL_ERROR', (error as Error).message)
  }
})

function redirectWithError(reason: string, message: string): Response {
  // Redirect to management app with error
  const errorUrl = new URL(Deno.env.get('MANAGEMENT_URL') || 'https://gestionale.kalosstudio.it')
  errorUrl.pathname = '/marketing'
  errorUrl.searchParams.set('meta_error', reason)
  errorUrl.searchParams.set('meta_error_message', message)

  return Response.redirect(errorUrl.toString(), 302)
}
