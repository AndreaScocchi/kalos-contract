// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: waitlist
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Waitlist(
    val id: String,
    @SerialName("lesson_id") val lessonId: String,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("client_id") val clientId: String? = null,
    val status: WaitlistStatus,
    val position: Int? = null,
    @SerialName("offered_at") val offeredAt: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null,
    @SerialName("notified_at") val notifiedAt: String? = null,
    @SerialName("updated_at") val updatedAt: String,
)
