// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: compensation_line_overrides
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class CompensationLineOverride(
    val id: String,
    @SerialName("operator_id") val operatorId: String,
    @SerialName("lesson_id") val lessonId: String? = null,
    @SerialName("event_id") val eventId: String? = null,
    @SerialName("model_id") val modelId: String? = null,
    @SerialName("revenue_cents") val revenueCents: Long? = null,
    val costs: JsonElement? = null,
    @SerialName("amount_cents") val amountCents: Long? = null,
    val note: String,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("updated_by") val updatedBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
