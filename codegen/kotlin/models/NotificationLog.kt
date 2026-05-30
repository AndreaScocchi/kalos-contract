// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: notification_logs
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class NotificationLog(
    val id: String,
    @SerialName("client_id") val clientId: String,
    val category: NotificationCategory,
    val channel: NotificationChannel,
    val title: String,
    val body: String? = null,
    val data: JsonElement? = null,
    @SerialName("expo_receipt_id") val expoReceiptId: String? = null,
    @SerialName("resend_id") val resendId: String? = null,
    val status: NotificationStatus,
    @SerialName("sent_at") val sentAt: String,
    @SerialName("delivered_at") val deliveredAt: String? = null,
    @SerialName("error_message") val errorMessage: String? = null,
)
