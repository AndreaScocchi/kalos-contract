/**
 * Rendering del contenuto di una newsletter per l'email HTML.
 *
 * Il gestionale salva HTML ristretto (vedi kalos-management/src/lib/richText.ts):
 *   blocchi: <p> <h1> <h2> <h3> <ul> <ol> <li> <blockquote> <hr>
 *   inline:  <strong> <em> <u> <s> <a> <span style="color:..."> <br>
 * Le bozze piu vecchie sono testo semplice con marcatori (*grassetto*,
 * **corsivo**, ***entrambi***) e a capo come \n: restano supportate.
 *
 * Qui i tag vengono filtrati (whitelist) e arricchiti con stili inline, perche
 * i client di posta ignorano i fogli di stile.
 */

export type NewsletterRenderMode = 'promotions' | 'primary'

const ALLOWED_TAGS = new Set([
  'p', 'h1', 'h2', 'h3', 'ul', 'ol', 'li', 'blockquote', 'hr', 'br',
  'strong', 'em', 'u', 's', 'a', 'span',
])

const VOID_TAGS = new Set(['br', 'hr'])

const ALIGNMENTS = new Set(['left', 'center', 'right', 'justify'])

const SAFE_URL_SCHEMES = ['http:', 'https:', 'mailto:', 'tel:']

/** Classe dei link resi come pulsante. */
const CTA_CLASS = 'kalos-cta'

const PROMOTIONS_STYLES: Record<string, string> = {
  p: 'margin: 0 0 16px 0;',
  h1: 'margin: 0 0 12px 0; font-size: 26px; line-height: 1.3; font-weight: 600; color: #0F2D3B;',
  h2: 'margin: 0 0 10px 0; font-size: 21px; line-height: 1.35; font-weight: 600; color: #0F2D3B;',
  h3: 'margin: 0 0 8px 0; font-size: 18px; line-height: 1.4; font-weight: 600; color: #0F2D3B;',
  ul: 'margin: 0 0 16px 0; padding-left: 24px;',
  ol: 'margin: 0 0 16px 0; padding-left: 24px;',
  li: 'margin: 0 0 6px 0;',
  blockquote:
    'margin: 0 0 16px 0; padding: 4px 0 4px 16px; border-left: 3px solid #F75C2C; color: #4B5563; font-style: italic;',
  a: 'color: #036257; text-decoration: underline;',
  hr: 'border: none; border-top: 1px solid #E5E7EB; margin: 24px 0;',
}

const PRIMARY_STYLES: Record<string, string> = {
  p: 'margin: 0 0 14px 0;',
  h1: 'margin: 0 0 10px 0; font-size: 20px; line-height: 1.35; font-weight: 600;',
  h2: 'margin: 0 0 10px 0; font-size: 17px; line-height: 1.4; font-weight: 600;',
  h3: 'margin: 0 0 8px 0; font-size: 16px; line-height: 1.4; font-weight: 600;',
  ul: 'margin: 0 0 14px 0; padding-left: 22px;',
  ol: 'margin: 0 0 14px 0; padding-left: 22px;',
  li: 'margin: 0 0 4px 0;',
  blockquote: 'margin: 0 0 14px 0; padding-left: 12px; border-left: 2px solid #E5E7EB; color: #4B5563;',
  a: 'color: #036257;',
  hr: 'border: none; border-top: 1px solid #E5E7EB; margin: 20px 0;',
}

// In modalita "Principale" il pulsante resta un link normale: un bottone
// colorato e un segnale marketing che spinge la mail nella scheda Promozioni.
const CTA_STYLE =
  'display: inline-block; margin: 4px 0; padding: 12px 26px; border-radius: 999px; background-color: #036257; color: #ffffff; font-weight: 600; text-decoration: none;'

export function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}

/** true se il contenuto e HTML (nuovo editor), false se testo con marcatori. */
export function isHtmlContent(content: string): boolean {
  return /<(p|div|h[1-3]|ul|ol|li|blockquote|hr|br|strong|em|u|s|span|a)\b[^>]*>/i.test(content)
}

/** Marcatori del vecchio formato -> tag HTML. */
export function parseMarkdownFormatting(text: string): string {
  // ***testo*** -> grassetto + corsivo, **testo** -> corsivo, *testo* -> grassetto
  let result = text.replace(/\*\*\*(.+?)\*\*\*/g, '<strong><em>$1</em></strong>')
  result = result.replace(/\*\*(.+?)\*\*/g, '<em>$1</em>')
  result = result.replace(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/g, '<strong>$1</strong>')
  return result
}

function readAttribute(attrs: string, name: string): string | null {
  const match = attrs.match(new RegExp(`${name}\\s*=\\s*("([^"]*)"|'([^']*)')`, 'i'))
  if (!match) return null
  return (match[2] ?? match[3] ?? '').trim()
}

function readStyleProperty(attrs: string, property: string): string | null {
  const style = readAttribute(attrs, 'style')
  if (!style) return null
  const match = style.match(new RegExp(`(?:^|;)\\s*${property}\\s*:\\s*([^;]+)`, 'i'))
  return match ? match[1].trim() : null
}

function safeColor(rawColor: string | null): string | null {
  if (!rawColor) return null
  const color = rawColor.toLowerCase()
  if (/^#[0-9a-f]{3}$/.test(color) || /^#[0-9a-f]{6}$/.test(color)) return color
  if (/^rgb\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*\)$/.test(color)) return color
  return null
}

function safeUrl(rawUrl: string | null): string | null {
  if (!rawUrl) return null
  try {
    const parsed = new URL(rawUrl)
    if (!SAFE_URL_SCHEMES.includes(parsed.protocol)) return null
    return parsed.href
  } catch {
    return null
  }
}

/** Filtra i tag ammessi e applica gli stili inline per i client di posta. */
export function renderRichContent(html: string, mode: NewsletterRenderMode): string {
  const styles = mode === 'primary' ? PRIMARY_STYLES : PROMOTIONS_STYLES

  let out = html.replace(/<!--[\s\S]*?-->/g, '')
  out = out.replace(/<(script|style)\b[\s\S]*?<\/\1\s*>/gi, '')

  return out.replace(
    /<(\/?)([a-zA-Z][a-zA-Z0-9]*)((?:"[^"]*"|'[^']*'|[^>"'])*)>/g,
    (_match, slash: string, rawTag: string, rawAttrs: string) => {
      const tag = rawTag.toLowerCase()
      if (!ALLOWED_TAGS.has(tag)) return ''
      if (slash) return VOID_TAGS.has(tag) ? '' : `</${tag}>`

      const declarations: string[] = []
      const isCta = tag === 'a' && (readAttribute(rawAttrs, 'class') || '').includes(CTA_CLASS)

      if (tag === 'a' && isCta && mode === 'promotions') {
        declarations.push(CTA_STYLE)
      } else if (styles[tag]) {
        declarations.push(styles[tag])
      }

      const align = readStyleProperty(rawAttrs, 'text-align')
      if (align && ALIGNMENTS.has(align.toLowerCase())) {
        declarations.push(`text-align: ${align.toLowerCase()};`)
      }

      const color = safeColor(readStyleProperty(rawAttrs, 'color'))
      if (color) declarations.push(`color: ${color};`)

      const attributes: string[] = []
      if (tag === 'a') {
        const href = safeUrl(readAttribute(rawAttrs, 'href'))
        // un link senza href valido resta testo: il tag viene scartato
        if (!href) return ''
        attributes.push(`href="${escapeHtml(href)}"`)
        attributes.push('target="_blank"')
        attributes.push('rel="noopener noreferrer"')
      }
      if (declarations.length > 0) {
        attributes.push(`style="${declarations.join(' ')}"`)
      }

      const attributeText = attributes.length > 0 ? ` ${attributes.join(' ')}` : ''
      return VOID_TAGS.has(tag) ? `<${tag}${attributeText}>` : `<${tag}${attributeText}>`
    }
  )
}

/**
 * Contenuto della campagna -> HTML del corpo email.
 * Gestisce sia il nuovo formato HTML sia le vecchie bozze con marcatori.
 */
export function renderNewsletterContent(content: string, mode: NewsletterRenderMode): string {
  if (isHtmlContent(content)) return renderRichContent(content, mode)

  const escaped = escapeHtml(content)
  return parseMarkdownFormatting(escaped).replace(/\n/g, '<br>')
}

/**
 * Sostituisce le variabili `{{...}}` nel contenuto.
 * Sui contenuti HTML i valori vengono escapati: un nome con `<` o `&` non deve
 * poter rompere (o iniettare) markup nell'email.
 */
export function personalizeContent(content: string, variables: Record<string, string>): string {
  const html = isHtmlContent(content)
  return content.replace(/\{\{(\w+)\}\}/g, (match, key: string) => {
    const value = variables[key]
    if (value === undefined) return match
    return html ? escapeHtml(value) : value
  })
}

/** Versione testo semplice del contenuto, per la parte text/plain dell'email. */
export function toPlainText(content: string): string {
  if (!isHtmlContent(content)) return content

  let text = content.replace(/<(script|style)\b[\s\S]*?<\/\1\s*>/gi, '')
  // i link mantengono l'indirizzo tra parentesi
  text = text.replace(
    /<a\b[^>]*href\s*=\s*("([^"]*)"|'([^']*)')[^>]*>([\s\S]*?)<\/a\s*>/gi,
    (_match, _quoted, doubleQuoted: string, singleQuoted: string, label: string) => {
      const href = (doubleQuoted ?? singleQuoted ?? '').trim()
      const plainLabel = label.replace(/<[^>]+>/g, '').trim()
      if (!href) return plainLabel
      return plainLabel && plainLabel !== href ? `${plainLabel} (${href})` : href
    }
  )
  text = text.replace(/<br\s*\/?>/gi, '\n')
  text = text.replace(/<hr\s*\/?>/gi, '\n---\n')
  text = text.replace(/<li\b[^>]*>/gi, '- ')
  text = text.replace(/<\/(p|h1|h2|h3|blockquote|li|ul|ol)\s*>/gi, '\n')
  text = text.replace(/<[^>]+>/g, '')
  text = text
    .replace(/&nbsp;/gi, ' ')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&amp;/gi, '&')
  return text.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim()
}
