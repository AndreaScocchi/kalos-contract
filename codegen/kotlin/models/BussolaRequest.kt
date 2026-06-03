// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: bussola_requests
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class BussolaRequest(
    val id: String,
    @SerialName("client_id") val clientId: String,
    val status: BussolaRequestStatus,
    @SerialName("preferred_at") val preferredAt: String? = null,
    val note: String? = null,
    @SerialName("lesson_id") val lessonId: String? = null,
    @SerialName("handled_by") val handledBy: String? = null,
    val metadata: JsonElement? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
