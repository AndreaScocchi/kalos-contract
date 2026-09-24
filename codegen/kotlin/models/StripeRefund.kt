// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: stripe_refunds
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class StripeRefund(
    val id: String,
    @SerialName("refund_id") val refundId: String,
    @SerialName("stripe_payment_id") val stripePaymentId: String,
    @SerialName("amount_cents") val amountCents: Int,
    val reason: String? = null,
    val status: String? = null,
    @SerialName("transaction_id") val transactionId: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
