/**
 * Immagine di una newsletter: la versione JPEG larga 1200 px (il doppio della colonna dell'email)
 * che il gestionale salva accanto a ogni foto caricata, invece dell'originale fino a 2400 px.
 * Regole in supabase/storage/FOTO.md. Si controlla che la versione esista: una foto caricata prima
 * del 07/10/2026 e non ancora ottimizzata resta l'originale. JPEG e non WebP perché alcuni
 * programmi di posta (Outlook per Windows) non leggono WebP.
 */
export async function urlImmagineEmail(imageUrl: string | null): Promise<string | null> {
  if (!imageUrl) return null
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const originale = /^https?:\/\//.test(imageUrl)
    ? imageUrl
    : `${supabaseUrl}/storage/v1/object/public/newsletter/${imageUrl}`

  const m = originale.match(/^(https?:\/\/[^?#]+\/storage\/v1\/object\/public\/)([^/?#]+)\/([^?#]+)$/)
  if (!m || m[3].startsWith('varianti/')) return originale
  const versione = `${m[1]}${m[2]}/varianti/${m[3]}/jpeg1200`
  try {
    const risposta = await fetch(versione, { method: 'HEAD', signal: AbortSignal.timeout(5000) })
    return risposta.ok ? versione : originale
  } catch {
    return originale
  }
}
