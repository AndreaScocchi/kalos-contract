// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: compensation_assignments
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CompensationAssignment(
    val id: String,
    @SerialName("operator_id") val operatorId: String,
    @SerialName("activity_id") val activityId: String? = null,
    @SerialName("model_id") val modelId: String,
    @SerialName("valid_from") val validFrom: String,
    @SerialName("valid_to") val validTo: String? = null,
    val note: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
