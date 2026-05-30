// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: journal_entries
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class JournalEntry(
    val id: String,
    @SerialName("client_id") val clientId: String,
    val title: String? = null,
    val body: String,
    @SerialName("practice_id") val practiceId: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
