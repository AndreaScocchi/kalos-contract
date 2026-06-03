// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: pass_tier_benefits
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PassTierBenefit(
    val id: String,
    @SerialName("tier_id") val tierId: String,
    @SerialName("benefit_type") val benefitType: PassBenefitType,
    @SerialName("value_percent") val valuePercent: Double? = null,
    @SerialName("value_int") val valueInt: Int? = null,
    val label: String? = null,
    val description: String? = null,
    @SerialName("display_order") val displayOrder: Int,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
