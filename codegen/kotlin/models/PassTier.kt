// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: pass_tiers
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PassTier(
    val id: String,
    val name: String,
    val description: String? = null,
    @SerialName("price_cents") val priceCents: Int,
    val currency: String,
    @SerialName("validity_days") val validityDays: Int,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("display_order") val displayOrder: Int,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
)
