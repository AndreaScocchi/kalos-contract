// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: campaign_contents
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class CampaignContent(
    val id: String,
    @SerialName("campaign_id") val campaignId: String,
    @SerialName("content_type") val contentType: CampaignContentType,
    val platform: SocialPlatform? = null,
    val title: String? = null,
    val body: String? = null,
    val hashtags: List<String>? = null,
    @SerialName("image_suggestions") val imageSuggestions: List<String>? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("video_url") val videoUrl: String? = null,
    @SerialName("link_url") val linkUrl: String? = null,
    @SerialName("link_label") val linkLabel: String? = null,
    @SerialName("ai_generated_title") val aiGeneratedTitle: String? = null,
    @SerialName("ai_generated_body") val aiGeneratedBody: String? = null,
    @SerialName("ai_generated_hashtags") val aiGeneratedHashtags: List<String>? = null,
    @SerialName("ai_generated_image_suggestions") val aiGeneratedImageSuggestions: List<String>? = null,
    @SerialName("is_edited") val isEdited: Boolean? = null,
    val status: ContentStatus,
    @SerialName("scheduled_for") val scheduledFor: String? = null,
    @SerialName("sent_at") val sentAt: String? = null,
    @SerialName("published_at") val publishedAt: String? = null,
    @SerialName("newsletter_campaign_id") val newsletterCampaignId: String? = null,
    @SerialName("meta_post_id") val metaPostId: String? = null,
    @SerialName("meta_container_id") val metaContainerId: String? = null,
    @SerialName("error_message") val errorMessage: String? = null,
    @SerialName("retry_count") val retryCount: Int? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("social_connection_id") val socialConnectionId: String? = null,
    val slides: JsonElement? = null,
    @SerialName("story_text_overlays") val storyTextOverlays: List<String>? = null,
    @SerialName("scheduled_offset_days") val scheduledOffsetDays: Int? = null,
    @SerialName("sequence_index") val sequenceIndex: Int? = null,
)
