// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: notification_reads
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class NotificationRead(
    val id: String,
    @SerialName("client_id") val clientId: String,
    @SerialName("notification_log_id") val notificationLogId: String? = null,
    @SerialName("announcement_id") val announcementId: String? = null,
    @SerialName("read_at") val readAt: String,
)
