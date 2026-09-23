// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: compensation_models
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CompensationModel(
    val id: String,
    val name: String,
    val description: String? = null,
    @SerialName("min_guaranteed_cents") val minGuaranteedCents: Int? = null,
    @SerialName("max_hourly_cents") val maxHourlyCents: Int? = null,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
