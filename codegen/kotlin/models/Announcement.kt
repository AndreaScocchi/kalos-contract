// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: announcements
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Announcement(
    val id: String,
    val title: String,
    val body: String,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("link_url") val linkUrl: String? = null,
    @SerialName("link_label") val linkLabel: String? = null,
    val category: String,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("marketing_campaign_id") val marketingCampaignId: String? = null,
    @SerialName("is_test") val isTest: Boolean,
    @SerialName("test_client_id") val testClientId: String? = null,
    @SerialName("is_recurring") val isRecurring: Boolean,
    @SerialName("recurrence_frequency") val recurrenceFrequency: AnnouncementRecurrenceFrequency? = null,
    @SerialName("recurrence_day_of_week") val recurrenceDayOfWeek: Int? = null,
    @SerialName("recurrence_day_of_month") val recurrenceDayOfMonth: Int? = null,
    @SerialName("recurrence_time") val recurrenceTime: String? = null,
    @SerialName("next_occurrence_at") val nextOccurrenceAt: String? = null,
    @SerialName("last_sent_at") val lastSentAt: String? = null,
)
