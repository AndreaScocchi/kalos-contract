// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: memberships
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class Membership(
    val id: String,
    @SerialName("client_id") val clientId: String,
    @SerialName("tier_id") val tierId: String,
    val status: MembershipStatus,
    @SerialName("started_at") val startedAt: String,
    @SerialName("expires_at") val expiresAt: String,
    @SerialName("price_cents_paid") val priceCentsPaid: Int? = null,
    val note: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    val metadata: JsonElement? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
)
