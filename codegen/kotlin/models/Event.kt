// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: events
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class Event(
    val id: String,
    val name: String,
    val description: String? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    val link: String? = null,
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String? = null,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val capacity: Int? = null,
    val location: String? = null,
    @SerialName("price_cents") val priceCents: Int? = null,
    val currency: String? = null,
    @SerialName("time_slots") val timeSlots: JsonElement? = null,
)
