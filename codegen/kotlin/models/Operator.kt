// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: operators
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Operator(
    val id: String,
    val name: String,
    val role: String,
    val bio: String? = null,
    val disciplines: List<String>? = null,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("profile_id") val profileId: String? = null,
    @SerialName("is_admin") val isAdmin: Boolean? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("display_order") val displayOrder: Int? = null,
    @SerialName("is_visible_on_site") val isVisibleOnSite: Boolean,
)
