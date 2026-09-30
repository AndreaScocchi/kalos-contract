// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: client_staff_notes
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ClientStaffNote(
    @SerialName("client_id") val clientId: String,
    val notes: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("updated_by") val updatedBy: String? = null,
)
