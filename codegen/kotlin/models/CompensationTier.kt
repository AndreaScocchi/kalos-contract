// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: compensation_tiers
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CompensationTier(
    val id: String,
    @SerialName("model_id") val modelId: String,
    @SerialName("min_participants") val minParticipants: Int,
    @SerialName("max_participants") val maxParticipants: Int? = null,
    @SerialName("amount_cents") val amountCents: Int,
    val note: String? = null,
    @SerialName("created_at") val createdAt: String,
)
