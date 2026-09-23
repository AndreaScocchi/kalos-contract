// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: compensation_components
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CompensationComponent(
    val id: String,
    @SerialName("model_id") val modelId: String,
    val kind: CompensationComponentKind,
    @SerialName("value_cents") val valueCents: Int? = null,
    @SerialName("value_percent") val valuePercent: Double? = null,
    @SerialName("display_order") val displayOrder: Int,
    val note: String? = null,
    @SerialName("created_at") val createdAt: String,
)
