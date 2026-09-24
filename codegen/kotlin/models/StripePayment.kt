// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: stripe_payments
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class StripePayment(
    val id: String,
    @SerialName("payment_intent_id") val paymentIntentId: String? = null,
    @SerialName("checkout_session_id") val checkoutSessionId: String? = null,
    @SerialName("client_id") val clientId: String? = null,
    val purpose: StripePurpose,
    @SerialName("target_id") val targetId: String? = null,
    @SerialName("amount_cents") val amountCents: Int,
    val currency: String,
    @SerialName("fee_cents") val feeCents: Int? = null,
    @SerialName("net_cents") val netCents: Int? = null,
    val status: StripePaymentStatus,
    val livemode: Boolean,
    @SerialName("transaction_id") val transactionId: String? = null,
    @SerialName("fee_expense_id") val feeExpenseId: String? = null,
    @SerialName("payment_method_type") val paymentMethodType: String? = null,
    @SerialName("receipt_email") val receiptEmail: String? = null,
    @SerialName("failure_message") val failureMessage: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("succeeded_at") val succeededAt: String? = null,
    @SerialName("updated_at") val updatedAt: String,
    val source: TransactionSource? = null,
    val metadata: JsonElement,
    @SerialName("is_duplicate") val isDuplicate: Boolean,
)
