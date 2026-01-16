// Resend API utilities for newsletter functionality

export interface ResendEmailOptions {
  from: string
  to: string
  subject: string
  html: string
  text?: string
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
 * Get the configured "from" email address
 */
export function getFromEmail(): string {
  return Deno.env.get('RESEND_FROM_EMAIL') || 'newsletter@kalosstudio.it'
}

/**
 * Delay helper for rate limiting
 */
export function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}