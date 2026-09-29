// Edge Function: delete-account
//
// Elimina l'account di chi chiama (dall'app: Impostazioni → Elimina account).
// 1. Legge l'utente dal token.
// 2. `delete_account_data` (solo service_role), in una transazione: disdice le prenotazioni future
//    (non quelle passate né gli eventi già pagati), libera la lista d'attesa, cancella diario,
//    pratiche, notifiche e dispositivi, toglie telefono e compleanno, disattiva la scheda con una
//    nota in fondo a quelle dello staff. Restano libro soci, quote, ricevute e incassi: l'iscrizione
//    all'associazione non cambia. L'account di chi è staff non si elimina da qui (STAFF_ACCOUNT).
// 3. Cancella l'utente di Supabase Auth: tutte le sessioni finiscono. Chi si registra di nuovo con
//    la stessa email ritrova la sua scheda (`internal.handle_new_user`).
//
// Se il punto 3 fallisce, il punto 2 è già fatto e si può ripetere senza danni: un secondo tentativo
// ritrova la scheda e cancella l'utente.
//
// Risposte: { ok: true } oppure { ok: false, reason } con UNAUTHORIZED (401), STAFF_ACCOUNT (403),
// DATA_DELETE_FAILED, AUTH_DELETE_FAILED, INTERNAL_ERROR (500).

import { corsHeaders } from '../_shared/cors.ts'
import { adminClient, jsonResponse, userClient } from '../_shared/http.ts'

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)

    const { data: { user }, error: userError } = await userClient(authHeader).auth.getUser()
    if (userError || !user) return jsonResponse({ ok: false, reason: 'UNAUTHORIZED' }, 401)

    const admin = adminClient()

    const { data: result, error: dataError } = await admin.rpc('delete_account_data', { p_user_id: user.id })
    if (dataError) {
      console.error('delete_account_data:', dataError.message)
      return jsonResponse({ ok: false, reason: 'DATA_DELETE_FAILED' }, 500)
    }
    if (!result?.ok) {
      const reason = result?.reason ?? 'DATA_DELETE_FAILED'
      return jsonResponse({ ok: false, reason }, reason === 'STAFF_ACCOUNT' ? 403 : 500)
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id)
    if (deleteError) {
      console.error('deleteUser:', deleteError.message)
      return jsonResponse({ ok: false, reason: 'AUTH_DELETE_FAILED' }, 500)
    }

    console.log(`Account eliminato: utente ${user.id}, schede ${JSON.stringify(result.client_ids ?? [])}`)
    return jsonResponse({ ok: true })
  } catch (error) {
    console.error('delete-account:', error)
    return jsonResponse({ ok: false, reason: 'INTERNAL_ERROR' }, 500)
  }
})
