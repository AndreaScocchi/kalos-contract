/**
 * Groq API helper for AI content generation
 * Uses Llama 3.3 70B model via Groq's OpenAI-compatible API
 */

const GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions'
const GROQ_MODEL = 'llama-3.3-70b-versatile'

export interface GroqMessage {
  role: 'system' | 'user' | 'assistant'
  content: string
}

export interface GroqResponse {
  id: string
  object: string
  created: number
  model: string
  choices: {
    index: number
    message: {
      role: string
      content: string
    }
    finish_reason: string
  }[]
  usage: {
    prompt_tokens: number
    completion_tokens: number
    total_tokens: number
  }
}

export interface GroqError {
  error: {
    message: string
    type: string
    code: string
  }
}

/**
 * Call Groq API with chat completion
 */
export async function callGroq(
  messages: GroqMessage[],
  options: {
    temperature?: number
    maxTokens?: number
    jsonMode?: boolean
  } = {}
): Promise<{ data: GroqResponse | null; error: Error | null }> {
  const apiKey = Deno.env.get('GROQ_API_KEY')

  if (!apiKey) {
    return { data: null, error: new Error('GROQ_API_KEY not configured') }
  }

  const { temperature = 0.7, maxTokens = 4096, jsonMode = false } = options

  try {
    const response = await fetch(GROQ_API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: GROQ_MODEL,
        messages,
        temperature,
        max_tokens: maxTokens,
        ...(jsonMode && { response_format: { type: 'json_object' } }),
      }),
    })

    if (!response.ok) {
      const errorData: GroqError = await response.json()
      return {
        data: null,
        error: new Error(errorData.error?.message || `Groq API error: ${response.status}`)
      }
    }

    const data: GroqResponse = await response.json()
    return { data, error: null }
  } catch (err) {
    return { data: null, error: err as Error }
  }
}

/**
 * Parse JSON from Groq response, handling markdown code blocks
 */
export function parseGroqJson<T>(content: string): T | null {
  try {
    // Remove markdown code blocks if present
    let jsonStr = content.trim()

    // Handle ```json ... ``` format
    if (jsonStr.startsWith('```')) {
      const endIndex = jsonStr.lastIndexOf('```')
      if (endIndex > 3) {
        jsonStr = jsonStr.slice(jsonStr.indexOf('\n') + 1, endIndex).trim()
      }
    }

    return JSON.parse(jsonStr) as T
  } catch {
    console.error('Failed to parse Groq JSON response:', content)
    return null
  }
}

/**
 * Get the model name for metadata
 */
export function getGroqModel(): string {
  return GROQ_MODEL
}
