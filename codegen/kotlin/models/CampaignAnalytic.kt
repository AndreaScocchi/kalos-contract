// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: campaign_analytics
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CampaignAnalytic(
    val id: String,
    @SerialName("campaign_id") val campaignId: String,
    @SerialName("content_id") val contentId: String? = null,
    val channel: String,
    val reach: Int? = null,
    val impressions: Int? = null,
    val clicks: Int? = null,
    val engagement: Int? = null,
    @SerialName("emails_sent") val emailsSent: Int? = null,
    @SerialName("emails_delivered") val emailsDelivered: Int? = null,
    @SerialName("emails_opened") val emailsOpened: Int? = null,
    @SerialName("emails_clicked") val emailsClicked: Int? = null,
    @SerialName("emails_bounced") val emailsBounced: Int? = null,
    @SerialName("push_sent") val pushSent: Int? = null,
    @SerialName("push_delivered") val pushDelivered: Int? = null,
    @SerialName("push_clicked") val pushClicked: Int? = null,
    val likes: Int? = null,
    val comments: Int? = null,
    val shares: Int? = null,
    val saves: Int? = null,
    @SerialName("story_views") val storyViews: Int? = null,
    @SerialName("story_replies") val storyReplies: Int? = null,
    @SerialName("last_fetched_at") val lastFetchedAt: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
