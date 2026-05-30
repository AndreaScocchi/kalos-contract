// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: practice_activities
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PracticeActivity(
    @SerialName("practice_id") val practiceId: String,
    @SerialName("activity_id") val activityId: String,
    @SerialName("created_at") val createdAt: String,
)
