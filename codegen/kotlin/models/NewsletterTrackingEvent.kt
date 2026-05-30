// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: newsletter_tracking_events
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class NewsletterTrackingEvent(
    val id: String,
    @SerialName("email_id") val emailId: String,
    @SerialName("event_type") val eventType: NewsletterEventType,
    @SerialName("event_data") val eventData: JsonElement? = null,
    @SerialName("occurred_at") val occurredAt: String,
    @SerialName("created_at") val createdAt: String,
)
