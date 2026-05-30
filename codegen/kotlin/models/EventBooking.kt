// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: event_bookings
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class EventBooking(
    val id: String,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("event_id") val eventId: String,
    @SerialName("user_id") val userId: String? = null,
    val status: BookingStatus,
    @SerialName("client_id") val clientId: String? = null,
    @SerialName("updated_at") val updatedAt: String,
)
