// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: practice_steps
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PracticeStep(
    val id: String,
    @SerialName("practice_id") val practiceId: String,
    val title: String? = null,
    @SerialName("sort_order") val sortOrder: Int,
    @SerialName("created_at") val createdAt: String,
)
