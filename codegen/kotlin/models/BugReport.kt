// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: bug_reports
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class BugReport(
    val id: String,
    val title: String,
    val description: String,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("created_by_user_id") val createdByUserId: String? = null,
    @SerialName("created_by_client_id") val createdByClientId: String? = null,
    val status: BugStatus,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
)
