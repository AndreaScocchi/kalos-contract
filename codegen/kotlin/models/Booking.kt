// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: bookings
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Booking(
    val id: String,
    @SerialName("lesson_id") val lessonId: String,
    val status: BookingStatus,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("subscription_id") val subscriptionId: String? = null,
    @SerialName("client_id") val clientId: String? = null,
)
