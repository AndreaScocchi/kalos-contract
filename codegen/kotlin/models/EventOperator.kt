// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: event_operators
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class EventOperator(
    val id: String,
    @SerialName("event_id") val eventId: String,
    @SerialName("operator_id") val operatorId: String,
    val role: String? = null,
    @SerialName("model_id") val modelId: String? = null,
    @SerialName("created_at") val createdAt: String,
)
