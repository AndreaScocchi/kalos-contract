/**
 * Dati legali dell'associazione per le email.
 *
 * Studio Kalòs è un'associazione di promozione sociale dal 19/08/2026, e le email che manda devono
 * dirlo: denominazione, sede legale, codice fiscale e partita IVA. Fino alla sessione 3 i footer
 * riportavano ancora l'indirizzo della gestione precedente (Località Casello Ferroviario 3,
 * Staranzano), che non è più il nostro.
 *
 * ⚠️ Piazza Furlan 5 è SOLO sede legale e non è aperta al pubblico: compare come dato legale, mai
 * come posto dove presentarsi. Le attività si svolgono in più luoghi fra Ronchi dei Legionari,
 * Monfalcone e Staranzano.
 *
 * Questi valori sono gli stessi di `association_settings` nel database e di `associazione.json` sul
 * sito. Qui stanno in chiaro perché un'edge function deve poter comporre il footer anche quando la
 * query al database fallisce: un'email senza footer legale è peggio di un'email con un footer di un
 * minuto fa. Quando si iscrive al RUNTS, la denominazione diventa "Studio Kalòs APS - ETS" e si
 * cambia qui, in `association_settings` e in `associazione.json`.
 */

export const ASSOCIATION = {
  legalName: 'Studio Kalòs Associazione di Promozione Sociale',
  shortLegalName: 'Studio Kalòs APS',
  fiscalCode: '01292700315',
  vatNumber: '01292700315',
  addressStreet: 'Piazza Furlan 5',
  addressZip: '34077',
  addressCity: 'Ronchi dei Legionari',
  addressProvince: 'GO',
  email: 'info.studiokalos@gmail.com',
  site: 'https://kalosstudio.it',
} as const

/** Sede legale su una riga sola. */
export function legalAddress(): string {
  const a = ASSOCIATION
  return `${a.addressStreet}, ${a.addressZip} ${a.addressCity} (${a.addressProvince})`
}

/**
 * Riga legale in testo semplice, quella che va in fondo a ogni email.
 * Esempio: "Studio Kalòs APS · Piazza Furlan 5, 34077 Ronchi dei Legionari (GO) · C.F. e P.IVA 01292700315"
 */
export function legalLine(): string {
  return `${ASSOCIATION.shortLegalName} · ${legalAddress()} · C.F. e P.IVA ${ASSOCIATION.fiscalCode}`
}

/** La stessa riga in HTML, con l'escape dei caratteri speciali già fatto. */
export function legalLineHtml(): string {
  return escapeHtml(legalLine())
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}
