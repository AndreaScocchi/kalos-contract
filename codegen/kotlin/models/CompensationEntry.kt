// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: compensation_entries
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class CompensationEntry(
    val id: String,
    @SerialName("operator_id") val operatorId: String,
    @SerialName("period_month") val periodMonth: String,
    @SerialName("lesson_id") val lessonId: String? = null,
    @SerialName("event_id") val eventId: String? = null,
    @SerialName("model_id") val modelId: String? = null,
    @SerialName("occurred_at") val occurredAt: String,
    @SerialName("duration_minutes") val durationMinutes: Int,
    val participants: Int,
    @SerialName("revenue_cents") val revenueCents: Long,
    @SerialName("amount_cents") val amountCents: Long,
    val breakdown: JsonElement,
    val status: CompensationEntryStatus,
    @SerialName("approved_by") val approvedBy: String? = null,
    @SerialName("approved_at") val approvedAt: String? = null,
    @SerialName("paid_at") val paidAt: String? = null,
    @SerialName("expense_id") val expenseId: String? = null,
    val note: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("payment_id") val paymentId: String? = null,
)
