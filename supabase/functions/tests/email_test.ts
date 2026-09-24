// Email con allegati (sessione 5): struttura MIME, codifiche, testi, PDF.
//
//     cd supabase/functions && deno test --allow-env --allow-write --node-modules-dir=none tests/email_test.ts
//
// Con EML_OUT=<cartella> scrive anche i messaggi completi in .eml, da aprire con un client di posta
// per vedere l'email come arriverà (nessun invio vero).

import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1'
import { bytesToBase64, buildMimeMessage, encodeHeaderValue } from '../_shared/ses.ts'
import { buildReceiptEmail } from '../_shared/receiptEmail.ts'
import { renderReceiptPdf, receiptFileName } from '../_shared/receiptPdf.ts'
import { applicationFileName, renderApplicationPdf, type ApplicationPdfData } from '../_shared/applicationPdf.ts'

const decoder = new TextDecoder()

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value.replace(/\s+/g, ''))
  return Uint8Array.from(binary, (c) => c.charCodeAt(0))
}

/** Le parti di primo livello del messaggio, con le loro intestazioni e il corpo decodificato. */
function parts(message: string, boundary: string): { headers: string; body: string }[] {
  return message
    .split(`--${boundary}`)
    .slice(1, -1)
    .map((chunk) => {
      const [headers, ...rest] = chunk.replace(/^\r\n/, '').split('\r\n\r\n')
      return { headers, body: rest.join('\r\n\r\n').trim() }
    })
}

const receiptData = {
  full_number: '12/2026',
  issued_at: '2026-10-02T09:15:00Z',
  recipient_name: 'Maria Rossi',
  recipient_fiscal_code: 'RSSMRA80A41F205X',
  recipient_address: 'Via Roma 3, 34074 Monfalcone (GO)',
  issuer_snapshot: {
    legal_name: 'Studio Kalòs Associazione di Promozione Sociale',
    short_legal_name: 'Studio Kalòs APS',
    fiscal_code: '01292700315',
    vat_number: '01292700315',
    address: 'Piazza Furlan 5, 34077 Ronchi dei Legionari (GO)',
    pec: 'kalostudio@pec.it',
    email: 'info.studiokalos@gmail.com',
    footer: 'Studio Kalòs APS · Piazza Furlan 5, 34077 Ronchi dei Legionari (GO) · C.F. e P.IVA 01292700315',
  },
  causale: 'Erogazione liberale',
  amount_cents: 5000,
  stamp_duty_cents: 0,
  voided_at: null,
  void_reason: null,
  method: 'stripe',
  occurred_on: '2026-10-02',
}

const application: ApplicationPdfData = {
  id: '6d7f7f5e-5b1a-4b8e-9d0a-1c2b3a4d5e6f',
  channel: 'site',
  first_name: 'Giulia',
  last_name: "D'Àngelo",
  fiscal_code: 'DNGGLI05D42F356X',
  birth_date: '2010-04-02',
  birth_place: 'Monfalcone',
  birth_province: 'GO',
  address_street: "Via Duca d'Aosta 1",
  address_zip: '34074',
  address_city: 'Monfalcone',
  address_province: 'GO',
  email: 'giulia@example.it',
  phone: '333 000 0000',
  minor_at_submission: true,
  guardian_full_name: "Anna D'Àngelo",
  guardian_fiscal_code: 'DNGNNA75A41F356X',
  guardian_relationship: 'madre',
  guardian_email: 'anna@example.it',
  guardian_phone: '333 111 1111',
  guardian_consent_at: '2026-09-24T16:42:00Z',
  accepted_statute_at: '2026-09-24T16:42:00Z',
  accepted_privacy_at: '2026-09-24T16:42:00Z',
  image_release: false,
  submitted_at: '2026-09-24T16:42:00Z',
  submitted_ip: '203.0.113.7',
  submitted_user_agent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15 Version/19.0 Mobile/15E148 Safari/604.1',
}

Deno.test('oggetto con caratteri accentati: parole codificate e corte', () => {
  const encoded = encodeHeaderValue('Grazie! La ricevuta della tua donazione a Studio Kalòs (n. 12/2026) — anche con ə')
  for (const word of encoded.split('\r\n ')) {
    assertMatch(word, /^=\?UTF-8\?B\?[A-Za-z0-9+/=]+\?=$/)
    assert(word.length <= 75, `parola troppo lunga: ${word.length}`)
  }
  const decoded = encoded.split('\r\n ').map((w) => decoder.decode(base64ToBytes(w.slice(10, -2)))).join('')
  assertEquals(decoded, 'Grazie! La ricevuta della tua donazione a Studio Kalòs (n. 12/2026) — anche con ə')
  assertEquals(encodeHeaderValue('Solo ASCII'), 'Solo ASCII')
})

Deno.test('messaggio MIME: testo, HTML e PDF allegato integri', async () => {
  const pdf = await renderReceiptPdf(receiptData)
  const email = buildReceiptEmail({
    recipientName: receiptData.recipient_name, fullNumber: receiptData.full_number, causale: receiptData.causale,
    amountCents: receiptData.amount_cents, method: receiptData.method, occurredOn: receiptData.occurred_on,
    kind: 'donation', voided: false,
  })
  const message = buildMimeMessage({
    from: 'Studio Kalòs <newsletter@kalosstudio.it>',
    to: 'maria@example.it',
    replyTo: 'info.studiokalos@gmail.com',
    subject: email.subject,
    html: email.html,
    text: email.text,
    attachments: [{ filename: receiptFileName(receiptData.full_number), content: pdf, contentType: 'application/pdf' }],
  })

  // Intestazioni
  assertMatch(message, /^From: =\?UTF-8\?B\?[^?]+\?= <newsletter@kalosstudio\.it>\r\n/)
  assertMatch(message, /\r\nTo: maria@example\.it\r\n/)
  assertMatch(message, /\r\nReply-To: info\.studiokalos@gmail\.com\r\n/)
  assertMatch(message, /\r\nMIME-Version: 1\.0\r\n/)
  const mixed = message.match(/boundary="(mixed_[0-9a-f]+)"/)![1]

  const top = parts(message, mixed)
  assertEquals(top.length, 2, 'una parte di testo e un allegato')

  const alt = top[0].headers.match(/boundary="(alt_[0-9a-f]+)"/)![1]
  const bodies = parts(top[0].body + '\r\n', alt)
  assertEquals(bodies.length, 2)
  assertMatch(bodies[0].headers, /text\/plain; charset=UTF-8/)
  assertMatch(bodies[1].headers, /text\/html; charset=UTF-8/)
  const text = decoder.decode(base64ToBytes(bodies[0].body))
  assert(text.startsWith('Ciao Maria,'), text.slice(0, 40))
  assert(text.includes('Erogazione liberale: € 50,00'))
  assert(text.includes('C.F. e P.IVA 01292700315'), 'il footer legale c\'è')
  assert(decoder.decode(base64ToBytes(bodies[1].body)).includes('Studio Kalòs'))

  // Allegato: righe da 76 caratteri al massimo, e i byte tornano identici
  assertMatch(top[1].headers, /Content-Type: application\/pdf; name="Ricevuta-12-2026\.pdf"/)
  assertMatch(top[1].headers, /Content-Disposition: attachment; filename="Ricevuta-12-2026\.pdf"/)
  assert(top[1].body.split('\r\n').every((line) => line.length <= 76))
  assertEquals(base64ToBytes(top[1].body), pdf)
  assertEquals(decoder.decode(pdf.subarray(0, 5)), '%PDF-')

  const out = Deno.env.get('EML_OUT')
  if (out) await Deno.writeTextFile(`${out}/ricevuta-donazione.eml`, message)
})

Deno.test('testi della ricevuta: quota e ricevuta annullata', () => {
  const quota = buildReceiptEmail({
    recipientName: 'Giulia Prova', fullNumber: '3/2026', causale: 'Quota associativa 2026', amountCents: 2500,
    method: 'stripe', occurredOn: '2026-09-24', kind: 'membership_fee', voided: false,
  })
  assertEquals(quota.subject, 'La tua ricevuta Studio Kalòs n. 3/2026')
  assert(quota.text.includes('Quota associativa 2026: € 25,00'))
  assert(quota.text.includes('Pagato il 24/09/2026 (pagamento elettronico)'))

  const voided = buildReceiptEmail({
    recipientName: 'Giulia Prova', fullNumber: '3/2026', causale: 'Quota associativa 2026', amountCents: 2500,
    method: 'cash', occurredOn: '2026-09-24', kind: 'membership_fee', voided: true,
  })
  assert(voided.text.includes('risulta annullata'))
  assert(!quota.html.includes('<script'), 'niente codice nel corpo')
})

Deno.test('PDF della domanda di una minorenne, con apostrofi e accenti', async () => {
  const pdf = await renderApplicationPdf(application)
  assertEquals(decoder.decode(pdf.subarray(0, 5)), '%PDF-')
  assert(pdf.length > 1500)
  assertEquals(applicationFileName(application), 'Domanda-ammissione-D-Angelo-2026-09-24.pdf')

  const out = Deno.env.get('EML_OUT')
  if (out) {
    await Deno.writeFile(`${out}/${applicationFileName(application)}`, pdf)
    await Deno.writeFile(`${out}/ricevuta-12-2026.pdf`, await renderReceiptPdf(receiptData))
  }
})

Deno.test('base64 di un file grande', () => {
  const big = crypto.getRandomValues(new Uint8Array(200_000).subarray(0, 65_536))
  assertEquals(base64ToBytes(bytesToBase64(big)), big)
})
