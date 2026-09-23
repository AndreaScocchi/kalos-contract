// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: locations
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Location(
    val id: String,
    val slug: String,
    val name: String,
    @SerialName("address_street") val addressStreet: String? = null,
    @SerialName("address_zip") val addressZip: String? = null,
    val city: String,
    val province: String? = null,
    @SerialName("map_url") val mapUrl: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val notes: String? = null,
    @SerialName("access_notes") val accessNotes: String? = null,
    @SerialName("show_on_site") val showOnSite: Boolean,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("display_order") val displayOrder: Int,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
