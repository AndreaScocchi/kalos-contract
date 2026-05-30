// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: waitlist
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Waitlist(
    val id: String,
    @SerialName("lesson_id") val lessonId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("created_at") val createdAt: String? = null,
)
