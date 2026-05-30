// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: feature_flags
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class FeatureFlag(
    val key: String,
    val enabled: Boolean,
    val description: String? = null,
    val payload: JsonElement,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("updated_by") val updatedBy: String? = null,
)
