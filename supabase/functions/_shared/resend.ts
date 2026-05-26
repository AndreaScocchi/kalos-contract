// Resend API utilities for newsletter functionality

export interface ResendEmailOptions {
  from: string
  to: string
  subject: string
  html: string
  text?: string
  replyTo?: string
  tags?: { name: string; value: string }[]
  headers?: Record<string, string>
}

export interface ResendEmailResponse {
  id: string
}

export interface ResendError {
  statusCode: number
  message: string
  name: string
}

/**
 * Send an email via Resend API
 */
export async function sendEmail(options: ResendEmailOptions): Promise<{ data: ResendEmailResponse | null; error: ResendError | null }> {
  const apiKey = Deno.env.get('RESEND_API_KEY')
  if (!apiKey) {
    return { data: null, error: { statusCode: 500, message: 'RESEND_API_KEY not configured', name: 'ConfigError' } }
  }

  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: options.from,
        to: [options.to],
        subject: options.subject,
        html: options.html,
        text: options.text,
        reply_to: options.replyTo,
        tags: options.tags,
        headers: options.headers,
      }),
    })

    const data = await response.json()

    if (!response.ok) {
      return { data: null, error: { statusCode: response.status, message: data.message || 'Unknown error', name: data.name || 'ResendError' } }
    }

    return { data: { id: data.id }, error: null }
  } catch (error) {
    return { data: null, error: { statusCode: 500, message: error.message, name: 'NetworkError' } }
  }
}

/**
 * Replace template variables in a string
 * Variables are in format {{variable_name}}
 */
export function replaceTemplateVariables(template: string, variables: Record<string, string>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (match, key) => {
    return variables[key] ?? match
  })
}

/**
 * Get the configured "from" email address.
 * Returns an RFC 5322 address with display name, e.g.
 *   Studio Kalòs <newsletter@kalosstudio.it>
 * The full value can be overridden by RESEND_FROM_EMAIL (which may be either a bare
 * address or an already-formatted "Name <email>" string).
 */
export function getFromEmail(): string {
  const configured = Deno.env.get('RESEND_FROM_EMAIL')
  if (configured && configured.trim().length > 0) {
    // If already includes a display name (contains "<"), use as-is.
    if (configured.includes('<')) return configured
    return `Studio Kalòs <${configured}>`
  }
  return 'Studio Kalòs <newsletter@kalosstudio.it>'
}

/**
 * Get the Reply-To address. Must be a real, monitored mailbox so user replies don't bounce.
 * Override via RESEND_REPLY_TO env var. Default points to the Gmail mailbox actually in use
 * (kalosstudio.it inbound receiving is currently disabled on Resend).
 */
export function getReplyToEmail(): string {
  return Deno.env.get('RESEND_REPLY_TO') || 'info.studiokalos@gmail.com'
}

/**
 * Get the mailto address used in the List-Unsubscribe header. Some inbox providers
 * (notably Yahoo) treat the mailto form as a stronger signal than the URL form.
 * Must point to a mailbox that actually receives, otherwise the unsubscribe request
 * bounces and the signal is wasted.
 * Override via RESEND_UNSUBSCRIBE_MAILTO.
 */
export function getUnsubscribeMailto(): string {
  return Deno.env.get('RESEND_UNSUBSCRIBE_MAILTO') || 'info.studiokalos@gmail.com'
}

/**
 * Build the standard set of deliverability headers for a bulk marketing email.
 *
 *  - List-Unsubscribe: both mailto and https (RFC 8058 + Gmail/Yahoo 2024 bulk-sender)
 *  - List-Unsubscribe-Post: enables one-click POST unsubscribe
 *  - Precedence: bulk → helps providers classify as bulk rather than transactional
 *  - Feedback-ID: per-campaign FBL identifier consumed by Gmail Postmaster
 */
export function buildBulkHeaders(opts: {
  unsubscribeUrl: string
  campaignId: string
  mailto?: string
}): Record<string, string> {
  const mailto = opts.mailto ?? getUnsubscribeMailto()
  return {
    'List-Unsubscribe': `<mailto:${mailto}?subject=Unsubscribe>, <${opts.unsubscribeUrl}>`,
    'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
    'Precedence': 'bulk',
    'Feedback-ID': `${opts.campaignId}:newsletter:kalosstudio:resend`,
  }
}

/**
 * Build neutral headers for "primary mode" sends. Deliberately omits
 * `Precedence: bulk` and `Feedback-ID` (which are strong "this is broadcast"
 * signals to Gmail) so the message reads as a personal email. We keep
 * `List-Unsubscribe` and the one-click POST because they are still required
 * for any list mail under Gmail/Yahoo 2024 bulk-sender rules.
 */
export function buildPrimaryHeaders(opts: {
  unsubscribeUrl: string
  mailto?: string
}): Record<string, string> {
  const mailto = opts.mailto ?? getUnsubscribeMailto()
  return {
    'List-Unsubscribe': `<mailto:${mailto}?subject=Unsubscribe>, <${opts.unsubscribeUrl}>`,
    'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
  }
}

/**
 * Build a "From" address with an optional display-name override. The email
 * portion is always the configured sender (verified domain for DKIM).
 * If `overrideDisplayName` is non-empty, it replaces the default display name.
 *
 * Examples:
 *   buildFromAddress()                     → "Studio Kalòs <newsletter@kalosstudio.it>"
 *   buildFromAddress("Tommaso da Kalòs")   → "Tommaso da Kalòs <newsletter@kalosstudio.it>"
 */
export function buildFromAddress(overrideDisplayName?: string | null): string {
  const configured = getFromEmail()
  const trimmed = (overrideDisplayName ?? '').trim()
  if (!trimmed) return configured

  // Extract the bare email out of the configured "Name <email>" string.
  const match = configured.match(/<([^>]+)>/)
  const bareEmail = match ? match[1] : configured
  return `${trimmed} <${bareEmail}>`
}

/**
 * Delay helper for rate limiting
 */
export function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}
