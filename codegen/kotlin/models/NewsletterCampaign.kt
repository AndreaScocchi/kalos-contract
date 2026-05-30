// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: newsletter_campaigns
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class NewsletterCampaign(
    val id: String,
    val subject: String,
    val content: String,
    val status: NewsletterCampaignStatus,
    @SerialName("scheduled_at") val scheduledAt: String? = null,
    @SerialName("sent_at") val sentAt: String? = null,
    @SerialName("recipient_count") val recipientCount: Int,
    @SerialName("delivered_count") val deliveredCount: Int,
    @SerialName("opened_count") val openedCount: Int,
    @SerialName("clicked_count") val clickedCount: Int,
    @SerialName("bounced_count") val bouncedCount: Int,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val recipients: JsonElement? = null,
    val archived: Boolean,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("preview_text") val previewText: String? = null,
    @SerialName("marketing_campaign_id") val marketingCampaignId: String? = null,
    @SerialName("delivery_mode") val deliveryMode: String,
    @SerialName("from_name_override") val fromNameOverride: String? = null,
)
