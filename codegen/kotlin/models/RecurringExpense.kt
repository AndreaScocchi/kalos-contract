// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: recurring_expenses
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class RecurringExpense(
    val id: String,
    @SerialName("category_id") val categoryId: String,
    val label: String,
    @SerialName("amount_cents") val amountCents: Int,
    val vendor: String? = null,
    @SerialName("day_of_month") val dayOfMonth: Int,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("starts_on") val startsOn: String,
    @SerialName("ends_on") val endsOn: String? = null,
    @SerialName("last_generated_month") val lastGeneratedMonth: String? = null,
    val notes: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
