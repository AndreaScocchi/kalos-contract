// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: practice_blocks
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PracticeBlock(
    val id: String,
    @SerialName("step_id") val stepId: String,
    @SerialName("block_type") val blockType: PracticeBlockType,
    val content: String,
    val caption: String? = null,
    @SerialName("sort_order") val sortOrder: Int,
    @SerialName("created_at") val createdAt: String,
)
