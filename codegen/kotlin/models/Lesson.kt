// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: lessons
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Lesson(
    val id: String,
    @SerialName("activity_id") val activityId: String,
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String,
    val capacity: Int,
    @SerialName("booking_deadline_minutes") val bookingDeadlineMinutes: Int? = null,
    @SerialName("cancel_deadline_minutes") val cancelDeadlineMinutes: Int? = null,
    val notes: String? = null,
    @SerialName("operator_id") val operatorId: String? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("recurring_series_id") val recurringSeriesId: String? = null,
    @SerialName("is_individual") val isIndividual: Boolean,
    @SerialName("assigned_client_id") val assignedClientId: String? = null,
    @SerialName("assigned_subscription_id") val assignedSubscriptionId: String? = null,
)
