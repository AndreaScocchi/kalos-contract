// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: payouts
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Payout(
    val id: String,
    val month: String,
    @SerialName("operator_id") val operatorId: String? = null,
    @SerialName("amount_cents") val amountCents: Int,
    val reason: String? = null,
    val status: String,
    @SerialName("paid_at") val paidAt: String? = null,
    val notes: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("updated_at") val updatedAt: String,
)
