// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: expenses
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Expense(
    val id: String,
    @SerialName("amount_cents") val amountCents: Int,
    @SerialName("expense_date") val expenseDate: String,
    val category: String,
    val vendor: String? = null,
    val notes: String? = null,
    @SerialName("is_fixed") val isFixed: Boolean,
    @SerialName("activity_id") val activityId: String? = null,
    @SerialName("operator_id") val operatorId: String? = null,
    @SerialName("lesson_id") val lessonId: String? = null,
    @SerialName("event_id") val eventId: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("updated_at") val updatedAt: String,
)
