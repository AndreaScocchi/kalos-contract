// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: member_fees
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class MemberFee(
    val id: String,
    @SerialName("client_id") val clientId: String,
    val year: Int,
    @SerialName("amount_cents") val amountCents: Int? = null,
    val status: MemberFeeStatus,
    @SerialName("paid_at") val paidAt: String? = null,
    @SerialName("transaction_id") val transactionId: String? = null,
    @SerialName("waived_reason") val waivedReason: String? = null,
    @SerialName("refunded_at") val refundedAt: String? = null,
    @SerialName("refund_reason") val refundReason: String? = null,
    val note: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
