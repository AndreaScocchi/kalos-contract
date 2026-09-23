// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: trials
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Trial(
    val id: String,
    @SerialName("client_id") val clientId: String,
    @SerialName("activity_id") val activityId: String,
    @SerialName("lesson_id") val lessonId: String? = null,
    @SerialName("booking_id") val bookingId: String? = null,
    val status: TrialStatus,
    @SerialName("booked_at") val bookedAt: String,
    @SerialName("converted_subscription_id") val convertedSubscriptionId: String? = null,
    @SerialName("converted_at") val convertedAt: String? = null,
    @SerialName("converted_by") val convertedBy: String? = null,
    @SerialName("was_member_at_booking") val wasMemberAtBooking: Boolean,
    val note: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
