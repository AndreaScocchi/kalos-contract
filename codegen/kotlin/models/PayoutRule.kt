// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: payout_rules
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PayoutRule(
    val id: String,
    val month: String,
    @SerialName("cash_reserve_pct") val cashReservePct: Double,
    @SerialName("marketing_pct") val marketingPct: Double,
    @SerialName("team_pct") val teamPct: Double,
    val notes: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("updated_at") val updatedAt: String,
)
