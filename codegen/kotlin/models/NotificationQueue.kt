// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: notification_queue
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class NotificationQueue(
    val id: String,
    @SerialName("client_id") val clientId: String,
    val category: NotificationCategory,
    val channel: NotificationChannel,
    val title: String,
    val body: String,
    val data: JsonElement? = null,
    @SerialName("scheduled_for") val scheduledFor: String,
    val status: NotificationStatus,
    val attempts: Int,
    @SerialName("last_attempt_at") val lastAttemptAt: String? = null,
    @SerialName("error_message") val errorMessage: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("processed_at") val processedAt: String? = null,
)
