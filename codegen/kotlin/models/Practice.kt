// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: practices
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class Practice(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val description: String? = null,
    @SerialName("duration_minutes") val durationMinutes: Int? = null,
    val category: PracticeCategory,
    val level: PracticeLevel,
    val goals: JsonElement? = null,
    @SerialName("cover_image_url") val coverImageUrl: String? = null,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("is_featured") val isFeatured: Boolean,
    @SerialName("sort_order") val sortOrder: Int,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
)
