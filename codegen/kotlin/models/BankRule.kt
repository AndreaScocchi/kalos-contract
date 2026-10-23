// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: bank_rules
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class BankRule(
    val id: String,
    @SerialName("match_causale") val matchCausale: String? = null,
    @SerialName("match_text") val matchText: String? = null,
    @SerialName("category_id") val categoryId: String,
    val vendor: String? = null,
    val notes: String? = null,
    @SerialName("rendiconto_voce") val rendicontoVoce: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
