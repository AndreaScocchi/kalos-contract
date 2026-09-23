// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: expense_categories
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ExpenseCategory(
    val id: String,
    val slug: String,
    val name: String,
    val description: String? = null,
    @SerialName("legacy_category") val legacyCategory: String? = null,
    @SerialName("rendiconto_bucket") val rendicontoBucket: String? = null,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("display_order") val displayOrder: Int,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
