// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: user_preferences
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class UserPreference(
    @SerialName("profile_id") val profileId: String,
    val goals: JsonElement,
    val interests: JsonElement,
    @SerialName("onboarding_completed_at") val onboardingCompletedAt: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
