// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: feedback
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class Feedback(
    val id: String,
    @SerialName("client_id") val clientId: String,
    val kind: FeedbackKind,
    @SerialName("lesson_id") val lessonId: String? = null,
    @SerialName("practice_id") val practiceId: String? = null,
    @SerialName("event_id") val eventId: String? = null,
    val rating: Int? = null,
    val comment: String? = null,
    val status: FeedbackStatus,
    val metadata: JsonElement? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
