// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: association_years
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AssociationYear(
    val year: Int,
    @SerialName("fee_cents") val feeCents: Int? = null,
    @SerialName("fee_due_date") val feeDueDate: String? = null,
    @SerialName("is_open") val isOpen: Boolean,
    val notes: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
