// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: plan_activities
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PlanActivity(
    @SerialName("plan_id") val planId: String,
    @SerialName("activity_id") val activityId: String,
    @SerialName("created_at") val createdAt: String? = null,
)
