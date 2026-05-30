// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: campaigns
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class Campaign(
    val id: String,
    val name: String,
    val type: CampaignType,
    val target: JsonElement,
    val message: String,
    @SerialName("event_date") val eventDate: String? = null,
    val tone: CampaignTone,
    val status: MarketingCampaignStatus,
    @SerialName("current_step") val currentStep: Int,
    @SerialName("skipped_steps") val skippedSteps: List<Int>? = null,
    @SerialName("ai_prompt_used") val aiPromptUsed: String? = null,
    @SerialName("ai_model_used") val aiModelUsed: String? = null,
    @SerialName("ai_generated_at") val aiGeneratedAt: String? = null,
    @SerialName("scheduled_for") val scheduledFor: String? = null,
    @SerialName("executed_at") val executedAt: String? = null,
    @SerialName("total_reach") val totalReach: Int? = null,
    @SerialName("total_engagement") val totalEngagement: Int? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("test_client_id") val testClientId: String? = null,
)
