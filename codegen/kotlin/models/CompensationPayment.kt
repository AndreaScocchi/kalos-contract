// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: compensation_payments
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CompensationPayment(
    val id: String,
    @SerialName("operator_id") val operatorId: String,
    @SerialName("period_month") val periodMonth: String,
    @SerialName("paid_on") val paidOn: String,
    val method: PaymentMethod,
    @SerialName("entries_cents") val entriesCents: Long,
    @SerialName("gross_cents") val grossCents: Long,
    @SerialName("withholding_percent") val withholdingPercent: Double,
    @SerialName("withholding_cents") val withholdingCents: Long,
    @SerialName("net_cents") val netCents: Long,
    @SerialName("net_expense_id") val netExpenseId: String? = null,
    @SerialName("withholding_expense_id") val withholdingExpenseId: String? = null,
    val note: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
