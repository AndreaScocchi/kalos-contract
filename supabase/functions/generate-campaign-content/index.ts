import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { callGroq, parseGroqJson, getGroqModel } from '../_shared/groq.ts'

interface CampaignTarget {
  segment: string
  categories?: string[]
}

interface RequestBody {
  campaignId: string
  regenerate?: boolean
  regenerateTypes?: string[]
}

interface GeneratedContent {
  brief?: string
  push_notification?: {
    title: string
    body: string
  }
  newsletter?: {
    subject: string
    body: string
  }
  instagram_post?: {
    body: string
    hashtags: string[]
    imageSuggestions: string[]
  }
  instagram_story?: {
    body: string
    imageSuggestions: string[]
  }
  facebook_post?: {
    body: string
    imageSuggestions: string[]
  }
}

interface ResponseBody {
  ok: boolean
  reason?: string
  message?: string
  contents?: GeneratedContent
}

// Map campaign type to Italian label for prompt
const CAMPAIGN_TYPE_LABELS: Record<string, string> = {
  promo: 'promozione/offerta speciale',
  evento: 'evento',
  annuncio: 'annuncio/comunicazione',
  corso_nuovo: 'nuovo corso/attivita',
}

// Map tone to Italian description
const TONE_DESCRIPTIONS: Record<string, string> = {
  formale: 'professionale e formale',
  amichevole: 'amichevole e caloroso',
  urgente: 'urgente e diretto',
}

// Build the AI prompt for content generation
function buildPrompt(campaign: {
  name: string
  type: string
  target: CampaignTarget
  message: string
  event_date: string | null
  tone: string
}): string {
  const typeLabel = CAMPAIGN_TYPE_LABELS[campaign.type] || campaign.type
  const toneDesc = TONE_DESCRIPTIONS[campaign.tone] || campaign.tone

  // Build target description
  let targetDesc = campaign.target.segment
  if (campaign.target.categories && campaign.target.categories.length > 0) {
    targetDesc += ` (focus su: ${campaign.target.categories.join(', ')})`
  }

  const eventDatePart = campaign.event_date
    ? `\n- Data evento: ${new Date(campaign.event_date).toLocaleDateString('it-IT', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}`
    : ''

  return `Sei un esperto di marketing digitale per "Studio Kalos", un centro benessere e yoga.
Il tuo compito e generare contenuti per una campagna marketing multicanale.

INFORMAZIONI CAMPAGNA:
- Nome: ${campaign.name}
- Tipo: ${typeLabel}
- Target: ${targetDesc}
- Messaggio chiave: ${campaign.message}${eventDatePart}
- Tono: ${toneDesc}

GENERA contenuti per i seguenti canali in formato JSON:

{
  "brief": "Riepilogo strutturato della campagna in 2-3 paragrafi. Descrivi obiettivo, target, messaggio chiave e strategia di comunicazione suggerita.",

  "push_notification": {
    "title": "Titolo notifica push (max 50 caratteri, accattivante)",
    "body": "Corpo notifica (max 100 caratteri, chiaro e con call-to-action)"
  },

  "newsletter": {
    "subject": "Oggetto email accattivante che invogli all'apertura",
    "body": "Corpo email in formato testo semplice (150-300 parole). Usa {{nome}} come placeholder per il nome del destinatario. Includi saluto iniziale, corpo del messaggio e call-to-action finale."
  },

  "instagram_post": {
    "body": "Caption per post Instagram (max 2200 caratteri). Usa emoji appropriate, formattazione con spazi e a capo. Includi call-to-action.",
    "hashtags": ["lista", "di", "hashtag", "rilevanti", "senza", "cancelletto"],
    "imageSuggestions": ["Descrizione soggetto foto 1 consigliato", "Descrizione soggetto foto 2 alternativo"]
  },

  "instagram_story": {
    "body": "Testo breve per story (max 100 caratteri, diretto)",
    "imageSuggestions": ["Descrizione soggetto per story"]
  },

  "facebook_post": {
    "body": "Post per Facebook (tono leggermente piu formale di Instagram, senza hashtag nel testo principale)",
    "imageSuggestions": ["Descrizione soggetto foto consigliato"]
  }
}

LINEE GUIDA:
- Adatta il tono a "${toneDesc}"
- Personalizza per il target "${targetDesc}"
- Per Studio Kalos usa temi: benessere, equilibrio, serenita, movimento consapevole
- Non inventare promozioni o sconti specifici se non menzionati nel messaggio chiave
- I suggerimenti immagine devono essere descrizioni di soggetti/scene realistiche e fotografabili

Rispondi SOLO con il JSON, senza testo aggiuntivo.`
}

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

    // Get request body
    const body: RequestBody = await req.json()
    if (!body.campaignId) {
      return jsonResponse({ ok: false, reason: 'MISSING_CAMPAIGN_ID' }, 400)
    }

    // Create admin client
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Get campaign
    const { data: campaign, error: campaignError } = await supabaseAdmin
      .from('campaigns')
      .select('*')
      .eq('id', body.campaignId)
      .single()

    if (campaignError || !campaign) {
      console.error('Error getting campaign:', campaignError)
      return jsonResponse({ ok: false, reason: 'CAMPAIGN_NOT_FOUND' }, 404)
    }

    // Update campaign status to ai_generating
    await supabaseAdmin
      .from('campaigns')
      .update({ status: 'ai_generating' })
      .eq('id', body.campaignId)

    // Build and execute AI prompt
    const prompt = buildPrompt({
      name: campaign.name,
      type: campaign.type,
      target: campaign.target as CampaignTarget,
      message: campaign.message,
      event_date: campaign.event_date,
      tone: campaign.tone,
    })

    const { data: groqResponse, error: groqError } = await callGroq(
      [
        { role: 'system', content: 'Sei un assistente marketing che genera contenuti in formato JSON.' },
        { role: 'user', content: prompt },
      ],
      { temperature: 0.7, maxTokens: 4096, jsonMode: true }
    )

    if (groqError || !groqResponse) {
      console.error('Groq API error:', groqError)
      await supabaseAdmin
        .from('campaigns')
        .update({ status: 'failed' })
        .eq('id', body.campaignId)
      return jsonResponse({ ok: false, reason: 'AI_GENERATION_FAILED', message: groqError?.message }, 500)
    }

    // Parse AI response
    const aiContent = groqResponse.choices[0]?.message?.content
    if (!aiContent) {
      await supabaseAdmin
        .from('campaigns')
        .update({ status: 'failed' })
        .eq('id', body.campaignId)
      return jsonResponse({ ok: false, reason: 'AI_EMPTY_RESPONSE' }, 500)
    }

    const generatedContent = parseGroqJson<GeneratedContent>(aiContent)
    if (!generatedContent) {
      console.error('Failed to parse AI response:', aiContent)
      await supabaseAdmin
        .from('campaigns')
        .update({ status: 'failed' })
        .eq('id', body.campaignId)
      return jsonResponse({ ok: false, reason: 'AI_PARSE_FAILED' }, 500)
    }

    // Save generated contents to database
    const contentRecords = []

    // Brief
    if (generatedContent.brief) {
      contentRecords.push({
        campaign_id: body.campaignId,
        content_type: 'brief',
        body: generatedContent.brief,
        ai_generated_body: generatedContent.brief,
        status: 'generated',
      })
    }

    // Push notification
    if (generatedContent.push_notification) {
      contentRecords.push({
        campaign_id: body.campaignId,
        content_type: 'push_notification',
        title: generatedContent.push_notification.title,
        body: generatedContent.push_notification.body,
        ai_generated_title: generatedContent.push_notification.title,
        ai_generated_body: generatedContent.push_notification.body,
        status: 'generated',
      })
    }

    // Newsletter
    if (generatedContent.newsletter) {
      contentRecords.push({
        campaign_id: body.campaignId,
        content_type: 'newsletter',
        title: generatedContent.newsletter.subject,
        body: generatedContent.newsletter.body,
        ai_generated_title: generatedContent.newsletter.subject,
        ai_generated_body: generatedContent.newsletter.body,
        status: 'generated',
      })
    }

    // Instagram post
    if (generatedContent.instagram_post) {
      contentRecords.push({
        campaign_id: body.campaignId,
        content_type: 'instagram_post',
        platform: 'instagram',
        body: generatedContent.instagram_post.body,
        hashtags: generatedContent.instagram_post.hashtags,
        image_suggestions: generatedContent.instagram_post.imageSuggestions,
        ai_generated_body: generatedContent.instagram_post.body,
        ai_generated_hashtags: generatedContent.instagram_post.hashtags,
        ai_generated_image_suggestions: generatedContent.instagram_post.imageSuggestions,
        status: 'generated',
      })
    }

    // Instagram story
    if (generatedContent.instagram_story) {
      contentRecords.push({
        campaign_id: body.campaignId,
        content_type: 'instagram_story',
        platform: 'instagram',
        body: generatedContent.instagram_story.body,
        image_suggestions: generatedContent.instagram_story.imageSuggestions,
        ai_generated_body: generatedContent.instagram_story.body,
        ai_generated_image_suggestions: generatedContent.instagram_story.imageSuggestions,
        status: 'generated',
      })
    }

    // Facebook post
    if (generatedContent.facebook_post) {
      contentRecords.push({
        campaign_id: body.campaignId,
        content_type: 'facebook_post',
        platform: 'facebook',
        body: generatedContent.facebook_post.body,
        image_suggestions: generatedContent.facebook_post.imageSuggestions,
        ai_generated_body: generatedContent.facebook_post.body,
        ai_generated_image_suggestions: generatedContent.facebook_post.imageSuggestions,
        status: 'generated',
      })
    }

    // Upsert contents (delete existing if regenerating)
    if (body.regenerate) {
      await supabaseAdmin
        .from('campaign_contents')
        .delete()
        .eq('campaign_id', body.campaignId)
    }

    const { error: insertError } = await supabaseAdmin
      .from('campaign_contents')
      .upsert(contentRecords, { onConflict: 'campaign_id,content_type' })

    if (insertError) {
      console.error('Error saving contents:', insertError)
      // Continue anyway, content was generated
    }

    // Update campaign status and AI metadata
    await supabaseAdmin
      .from('campaigns')
      .update({
        status: 'pending_review',
        ai_prompt_used: prompt,
        ai_model_used: getGroqModel(),
        ai_generated_at: new Date().toISOString(),
        current_step: 2,
      })
      .eq('id', body.campaignId)

    return jsonResponse({
      ok: true,
      contents: generatedContent,
    }, 200)

  } catch (error) {
    console.error('Edge function error:', error)
    return jsonResponse({ ok: false, reason: 'INTERNAL_ERROR', message: (error as Error).message }, 500)
  }
})

function jsonResponse(body: ResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
