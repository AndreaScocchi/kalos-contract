// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: transactions
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class Transaction(
    val id: String,
    @SerialName("client_id") val clientId: String? = null,
    val kind: TransactionKind,
    @SerialName("amount_cents") val amountCents: Int,
    val currency: String,
    val method: PaymentMethod,
    val source: TransactionSource,
    val status: TransactionStatus,
    @SerialName("occurred_on") val occurredOn: String,
    @SerialName("subscription_id") val subscriptionId: String? = null,
    @SerialName("event_booking_id") val eventBookingId: String? = null,
    @SerialName("member_fee_id") val memberFeeId: String? = null,
    @SerialName("booking_id") val bookingId: String? = null,
    @SerialName("refund_of_id") val refundOfId: String? = null,
    @SerialName("stripe_payment_id") val stripePaymentId: String? = null,
    @SerialName("is_commercial") val isCommercial: Boolean,
    val description: String? = null,
    val note: String? = null,
    val metadata: JsonElement? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("rendiconto_voce") val rendicontoVoce: String? = null,
)
