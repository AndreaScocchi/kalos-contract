// Token dei link «disiscriviti» della newsletter: SHA-256 di email + segreto, primi 16 byte in esadecimale.
// Stesso calcolo da quando le newsletter esistono, così i link già inviati restano validi.
// Il segreto (`UNSUBSCRIBE_SECRET`) è obbligatorio: fino al 30/09/2026 c'era un valore di ripiego
// scritto nel codice, e il repo è pubblico.

export async function unsubscribeToken(email: string): Promise<string> {
  const secret = Deno.env.get('UNSUBSCRIBE_SECRET')
  if (!secret) throw new Error('UNSUBSCRIBE_SECRET non impostato')
  const data = new TextEncoder().encode(email + secret)
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  return hashArray.slice(0, 16).map((b) => b.toString(16).padStart(2, '0')).join('')
}
