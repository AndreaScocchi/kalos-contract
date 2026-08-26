// Amazon SES (API v2) email utilities.
//
// Drop-in replacement for _shared/resend.ts: the exported surface is identical,
// so call sites only need to change the import path. The old resend.ts is kept
// in place as a rollback path until the SES migration is confirmed in production.
//
// Required secrets (supabase secrets set ...):
//   SES_ACCESS_KEY_ID       IAM access key with ses:SendEmail
//   SES_SECRET_ACCESS_KEY   matching secret
//   SES_REGION              e.g. eu-central-1
//   SES_CONFIGURATION_SET   configuration set wired to the SNS event destination
// Optional:
//   MAIL_FROM_EMAIL / MAIL_REPLY_TO / MAIL_UNSUBSCRIBE_MAILTO
//   (each falls back to the legacy RESEND_* name so nothing breaks mid-migration)
//   SES_SEND_DELAY_MS       pacing between sends, default 100ms (10/sec)

import { AwsClient } from 'https://esm.sh/aws4fetch@1.0.20'

export interface EmailOptions {
  from: string
  to: string
  subject: string
  html: string
  text?: string
  replyTo?: string
  tags?: { name: string; value: string }[]
  headers?: Record<string, string>
}

export interface EmailResponse {
  id: string
}

export interface EmailError {
  statusCode: number
  message: string
  name: string
}

// Aliases kept so any code still typed against the Resend names keeps compiling.
export type ResendEmailOptions = EmailOptions
export type ResendEmailResponse = EmailResponse
export type ResendError = EmailError

/**
 * Pacing between consecutive sends. SES accepts 14 emails/sec once the account is
 * out of the sandbox; 100ms (10/sec) leaves headroom. While still in the sandbox
 * the rate is 1/sec — the retry-on-throttle below absorbs that, but you can also
 * set SES_SEND_DELAY_MS=1100 until production access is granted.
 */
export const SEND_DELAY_MS = Number(Deno.env.get('SES_SEND_DELAY_MS') ?? '100')

let cachedClient: AwsClient | null = null

function getClient(): AwsClient | null {
  if (cachedClient) return cachedClient

  const accessKeyId = Deno.env.get('SES_ACCESS_KEY_ID')
  const secretAccessKey = Deno.env.get('SES_SECRET_ACCESS_KEY')
  if (!accessKeyId || !secretAccessKey) return null

  cachedClient = new AwsClient({
    accessKeyId,
    secretAccessKey,
    region: getRegion(),
    service: 'ses',
  })
  return cachedClient
}

function getRegion(): string {
  return Deno.env.get('SES_REGION') || 'eu-central-1'
}

/**
 * SES rejects non-ASCII display names unless they are MIME encoded-word wrapped
 * (RFC 2047). "Studio Kalòs" would otherwise be refused or mangled, so any
 * address whose display name leaves the ASCII range gets base64 encoded here.
 */
export function encodeDisplayName(address: string): string {
  const match = address.match(/^\s*(.*?)\s*<([^>]+)>\s*$/)
  if (!match) return address

  const [, rawName, email] = match
  const name = rawName.replace(/^"(.*)"$/, '$1')
  if (!name) return email
  // eslint-disable-next-line no-control-regex
  if (!/[^\x00-\x7F]/.test(name)) return `${name} <${email}>`

  const base64 = btoa(String.fromCharCode(...new TextEncoder().encode(name)))
  return `=?UTF-8?B?${base64}?= <${email}>`
}

/** SES tag names and values accept only letters, digits, dash and underscore. */
function sanitizeTagValue(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 256)
}

function isRetryable(status: number, errorName: string): boolean {
  if (status === 429 || status >= 500) return true
  return errorName === 'TooManyRequestsException' || errorName === 'ThrottlingException'
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

/**
 * Send a single email through the SES v2 SendEmail endpoint.
 *
 * Returns the same { data, error } shape as the Resend helper so call sites are
 * untouched. `data.id` carries the SES MessageId, which is what the SES event
 * notifications reference — it is stored in the existing `resend_id` columns.
 */
export async function sendEmail(options: EmailOptions): Promise<{ data: EmailResponse | null; error: EmailError | null }> {
  const client = getClient()
  if (!client) {
    return { data: null, error: { statusCode: 500, message: 'SES credentials not configured', name: 'ConfigError' } }
  }

  const endpoint = `https://email.${getRegion()}.amazonaws.com/v2/email/outbound-emails`
  const configurationSet = Deno.env.get('SES_CONFIGURATION_SET')

  const payload: Record<string, unknown> = {
    FromEmailAddress: encodeDisplayName(options.from),
    Destination: { ToAddresses: [options.to] },
    Content: {
      Simple: {
        Subject: { Data: options.subject, Charset: 'UTF-8' },
        Body: {
          Html: { Data: options.html, Charset: 'UTF-8' },
          ...(options.text ? { Text: { Data: options.text, Charset: 'UTF-8' } } : {}),
        },
        ...(options.headers && Object.keys(options.headers).length > 0
          ? { Headers: Object.entries(options.headers).map(([Name, Value]) => ({ Name, Value })) }
          : {}),
      },
    },
  }

  if (options.replyTo) payload.ReplyToAddresses = [options.replyTo]
  if (configurationSet) payload.ConfigurationSetName = configurationSet
  if (options.tags && options.tags.length > 0) {
    payload.EmailTags = options.tags.map(t => ({
      Name: sanitizeTagValue(t.name),
      Value: sanitizeTagValue(t.value),
    }))
  }

  const body = JSON.stringify(payload)
  const backoffMs = [500, 1500, 3500]

  for (let attempt = 0; attempt <= backoffMs.length; attempt++) {
    try {
      const response = await client.fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body,
      })

      if (response.ok) {
        const data = await response.json()
        return { data: { id: data.MessageId }, error: null }
      }

      // SES error bodies vary between { message } and { Message }, with the
      // error class in __type or the x-amzn-errortype header.
      const raw = await response.text()
      let message = raw
      let name = response.headers.get('x-amzn-errortype')?.split(':')[0] ?? 'SESError'
      try {
        const parsed = JSON.parse(raw)
        message = parsed.message ?? parsed.Message ?? raw
        if (parsed.__type) name = String(parsed.__type).split('#').pop() ?? name
      } catch {
        // non-JSON body: keep the raw text
      }

      if (isRetryable(response.status, name) && attempt < backoffMs.length) {
        await sleep(backoffMs[attempt])
        continue
      }

      return { data: null, error: { statusCode: response.status, message, name } }
    } catch (error) {
      if (attempt < backoffMs.length) {
        await sleep(backoffMs[attempt])
        continue
      }
      return {
        data: null,
        error: { statusCode: 500, message: error instanceof Error ? error.message : String(error), name: 'NetworkError' },
      }
    }
  }

  return { data: null, error: { statusCode: 500, message: 'Send retries exhausted', name: 'RetryError' } }
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
 * Overridable via MAIL_FROM_EMAIL (bare address or already-formatted "Name <email>").
 * The display name is MIME-encoded at send time, so the ò is safe to keep here.
 */
export function getFromEmail(): string {
  const configured = Deno.env.get('MAIL_FROM_EMAIL') || Deno.env.get('RESEND_FROM_EMAIL')
  if (configured && configured.trim().length > 0) {
    if (configured.includes('<')) return configured
    return `Studio Kalòs <${configured}>`
  }
  return 'Studio Kalòs <newsletter@kalosstudio.it>'
}

/**
 * Get the Reply-To address. Must be a real, monitored mailbox so user replies don't bounce.
 */
export function getReplyToEmail(): string {
  return Deno.env.get('MAIL_REPLY_TO') || Deno.env.get('RESEND_REPLY_TO') || 'info.studiokalos@gmail.com'
}

/**
 * Get the mailto address used in the List-Unsubscribe header. Some inbox providers
 * (notably Yahoo) treat the mailto form as a stronger signal than the URL form.
 */
export function getUnsubscribeMailto(): string {
  return Deno.env.get('MAIL_UNSUBSCRIBE_MAILTO') || Deno.env.get('RESEND_UNSUBSCRIBE_MAILTO') || 'info.studiokalos@gmail.com'
}

/**
 * Build the standard set of deliverability headers for a bulk marketing email.
 *
 *  - List-Unsubscribe: both mailto and https (RFC 8058 + Gmail/Yahoo 2024 bulk-sender)
 *  - List-Unsubscribe-Post: enables one-click POST unsubscribe
 *  - Precedence: bulk → helps providers classify as bulk rather than transactional
 *  - Feedback-ID: per-campaign FBL identifier consumed by Gmail Postmaster
 *
 * All four are permitted as SES custom headers with Simple content.
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
    'Feedback-ID': `${opts.campaignId}:newsletter:kalosstudio:ses`,
  }
}

/**
 * Build neutral headers for "primary mode" sends. Deliberately omits
 * `Precedence: bulk` and `Feedback-ID` (which are strong "this is broadcast"
 * signals to Gmail) so the message reads as a personal email.
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
 * Default display name used when sending in "primary" mode and no per-campaign
 * override is provided.
 */
export const PRIMARY_DEFAULT_FROM_NAME = 'Alice da Studio Kalòs'

/**
 * Build a "From" address with an optional display-name override. The email
 * portion is always the configured sender (verified domain for DKIM).
 */
export function buildFromAddress(overrideDisplayName?: string | null): string {
  const configured = getFromEmail()
  const trimmed = (overrideDisplayName ?? '').trim()
  if (!trimmed) return configured

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

export interface SesSendQuota {
  /** Emails allowed per rolling 24h window. -1 in SES means "no limit". */
  max24HourSend: number
  maxSendRate: number
  sentLast24Hours: number
}

/**
 * Read the live sending quota from SES instead of hardcoding a provider limit.
 * Requires ses:GetAccount on the IAM user.
 */
export async function getSendQuota(): Promise<{ data: SesSendQuota | null; error: EmailError | null }> {
  const client = getClient()
  if (!client) {
    return { data: null, error: { statusCode: 500, message: 'SES credentials not configured', name: 'ConfigError' } }
  }

  try {
    const response = await client.fetch(`https://email.${getRegion()}.amazonaws.com/v2/email/account`, {
      method: 'GET',
    })

    if (!response.ok) {
      const message = await response.text()
      return { data: null, error: { statusCode: response.status, message, name: 'SESError' } }
    }

    const json = await response.json()
    return {
      data: {
        max24HourSend: json.SendQuota?.Max24HourSend ?? -1,
        maxSendRate: json.SendQuota?.MaxSendRate ?? 0,
        sentLast24Hours: json.SendQuota?.SentLast24Hours ?? 0,
      },
      error: null,
    }
  } catch (error) {
    return {
      data: null,
      error: { statusCode: 500, message: error instanceof Error ? error.message : String(error), name: 'NetworkError' },
    }
  }
}

/**
 * Self-imposed ceiling on emails sent in any rolling 24h window, checked before
 * every bulk send.
 *
 * AWS grants ~50.000/day on leaving the sandbox and offers no self-service way to
 * lower it, so this is the only real-time stop against a bug that sends in a loop:
 * AWS Budgets only notices hours later, when the money is already spent. At the
 * default of 1500 the worst case is $0.15/day.
 *
 * Raise it with: supabase secrets set MAIL_DAILY_CAP=<n>
 */
export const DAILY_CAP = Number(Deno.env.get('MAIL_DAILY_CAP') ?? '1500')

export interface DailyCapResult {
  allowed: boolean
  /** How many more emails fit under the lower of our cap and the AWS quota. */
  available: number
  cap: number
  sentLast24Hours: number
}

/**
 * Check whether `requested` more emails fit under the effective 24h ceiling.
 *
 * Fails open when the SES account API is unreachable: blocking every email on a
 * transient API hiccup would take down lesson reminders, and in the runaway-loop
 * scenario this guard exists for, the API is working fine.
 */
export async function checkDailyCap(requested: number): Promise<DailyCapResult> {
  const { data: quota, error } = await getSendQuota()

  if (!quota) {
    console.error('Daily cap check skipped, SES quota unavailable:', error?.message)
    return { allowed: true, available: Number.POSITIVE_INFINITY, cap: DAILY_CAP, sentLast24Hours: 0 }
  }

  // SES reports -1 when the account has no 24h limit at all.
  const awsCap = quota.max24HourSend > 0 ? quota.max24HourSend : Number.POSITIVE_INFINITY
  const cap = Math.min(DAILY_CAP, awsCap)
  const sentLast24Hours = Math.round(quota.sentLast24Hours)
  const available = Math.max(0, cap - sentLast24Hours)

  return { allowed: requested <= available, available, cap, sentLast24Hours }
}
