// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: practice_user_state
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PracticeUserState(
    val id: String,
    @SerialName("client_id") val clientId: String,
    @SerialName("practice_id") val practiceId: String,
    val status: PracticeUserStatus,
    @SerialName("current_step_index") val currentStepIndex: Int,
    @SerialName("is_favorite") val isFavorite: Boolean,
    @SerialName("started_at") val startedAt: String,
    @SerialName("completed_at") val completedAt: String? = null,
    @SerialName("last_accessed_at") val lastAccessedAt: String,
    @SerialName("time_spent_seconds") val timeSpentSeconds: Int,
)
