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

    // Parse state (contains operator_id, redirect URL, and is_test flag)
    let stateData: { operator_id: string; redirect_url: string; is_test?: boolean }
    try {
      stateData = JSON.parse(atob(state))
    } catch {
      return redirectWithError('INVALID_STATE', 'Could not parse state parameter')
    }

    const { operator_id, redirect_url, is_test = false } = stateData

    // Helper to redirect with error, preserving the redirect_url
    const redirectWithErrorAndUrl = (reason: string, message: string) => {
      return createCallbackPage({
        success: false,
        error: reason,
        error_message: message,
        redirect_url,
      })
    }

    // Get app credentials
    const appId = Deno.env.get('META_APP_ID')
    const appSecret = Deno.env.get('META_APP_SECRET')
    const supabaseUrl = Deno.env.get('SUPABASE_URL')

    if (!appId || !appSecret) {
      return redirectWithErrorAndUrl('CONFIG_ERROR', 'Meta app not configured')
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
      return redirectWithErrorAndUrl('TOKEN_EXCHANGE_FAILED', 'Could not exchange code for token')
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

    let longLivedData: LongLivedTokenResponse
    if (longLivedRes.ok) {
      const parsed = await longLivedRes.json()
      longLivedData = {
        access_token: parsed.access_token,
        token_type: parsed.token_type || 'bearer',
        // Default to 60 days if expires_in is missing
        expires_in: typeof parsed.expires_in === 'number' ? parsed.expires_in : 60 * 24 * 60 * 60,
      }
    } else {
      // Fallback to short-lived token with 1 hour expiry
      longLivedData = {
        access_token: tokenData.access_token,
        token_type: 'bearer',
        expires_in: 3600,
      }
    }

    // Get Facebook pages
    const pagesUrl = `${META_GRAPH_URL}/me/accounts?` +
      `fields=id,name,access_token,instagram_business_account{id,username}&` +
      `access_token=${longLivedData.access_token}`

    const pagesRes = await fetch(pagesUrl)
    if (!pagesRes.ok) {
      console.error('Failed to fetch pages')
      return redirectWithErrorAndUrl('PAGES_FETCH_FAILED', 'Could not fetch Facebook pages')
    }

    const pagesData: PagesResponse = await pagesRes.json()

    if (!pagesData.data || pagesData.data.length === 0) {
      return redirectWithErrorAndUrl('NO_PAGES', 'No Facebook pages found. Please ensure your account manages at least one page.')
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
        is_test,
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
          is_test,
        })
      }
    }

    // Upsert connections (unique constraint includes is_test)
    const { error: upsertError } = await supabaseAdmin
      .from('social_connections')
      .upsert(connections, { onConflict: 'operator_id,platform,is_test' })

    if (upsertError) {
      console.error('Failed to save connections:', upsertError)
      return redirectWithErrorAndUrl('SAVE_FAILED', 'Could not save social connections')
    }

    // Redirect back to the wizard with success
    return createCallbackPage({
      success: true,
      is_test,
      pages_count: pagesData.data.length,
      redirect_url,
    })

  } catch (error) {
    console.error('Meta OAuth error:', error)
    return createCallbackPage({
      success: false,
      error: 'INTERNAL_ERROR',
      error_message: (error as Error).message,
      // No redirect_url available here, will use default
    })
  }
})

interface CallbackResult {
  success: boolean
  is_test?: boolean
  pages_count?: number
  error?: string
  error_message?: string
  redirect_url?: string
}

function createCallbackPage(result: CallbackResult): Response {
  // Build redirect URL to kalos-management OAuth callback page
  // Extract base URL from redirect_url or use production default
  let baseUrl = 'https://gestionale.kalosstudio.it'
  if (result.redirect_url) {
    try {
      const redirectUrlObj = new URL(result.redirect_url)
      baseUrl = redirectUrlObj.origin
    } catch {
      // Keep default if URL parsing fails
    }
  }

  const params = new URLSearchParams()
  params.set('success', result.success ? 'true' : 'false')
  if (result.error) params.set('error', result.error)
  if (result.error_message) params.set('error_message', result.error_message)
  if (result.is_test) params.set('is_test', 'true')
  if (result.pages_count) params.set('pages_count', String(result.pages_count))

  const redirectUrl = `${baseUrl}/oauth/callback?${params.toString()}`

  return new Response(null, {
    status: 302,
    headers: {
      'Location': redirectUrl,
    },
  })
}

function redirectWithError(reason: string, message: string): Response {
  return createCallbackPage({
    success: false,
    error: reason,
    error_message: message,
  })
}
