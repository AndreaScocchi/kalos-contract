// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: notification_preferences
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class NotificationPreference(
    val id: String,
    @SerialName("client_id") val clientId: String,
    val category: NotificationCategory,
    @SerialName("push_enabled") val pushEnabled: Boolean,
    @SerialName("email_enabled") val emailEnabled: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
