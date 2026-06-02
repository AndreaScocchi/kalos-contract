// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: activities
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class Activity(
    val id: String,
    val name: String,
    val description: String? = null,
    val discipline: String,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val color: String? = null,
    @SerialName("duration_minutes") val durationMinutes: Int? = null,
    val slug: String? = null,
    @SerialName("landing_title") val landingTitle: String? = null,
    @SerialName("landing_subtitle") val landingSubtitle: String? = null,
    @SerialName("active_months") val activeMonths: JsonElement? = null,
    @SerialName("target_audience") val targetAudience: JsonElement? = null,
    @SerialName("program_objectives") val programObjectives: JsonElement? = null,
    @SerialName("why_participate") val whyParticipate: JsonElement? = null,
    @SerialName("journey_structure") val journeyStructure: JsonElement? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("is_active") val isActive: Boolean? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("icon_name") val iconName: String? = null,
    val category: ActivityCategory,
)
