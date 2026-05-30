// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: plans
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Plan(
    val id: String,
    val name: String,
    val discipline: String? = null,
    @SerialName("price_cents") val priceCents: Int,
    val currency: String? = null,
    val entries: Int? = null,
    @SerialName("validity_days") val validityDays: Int,
    val description: String? = null,
    @SerialName("is_active") val isActive: Boolean? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("discount_percent") val discountPercent: Double? = null,
)
