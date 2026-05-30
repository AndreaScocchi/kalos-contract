// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: clients
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Client(
    val id: String,
    @SerialName("full_name") val fullName: String,
    val phone: String? = null,
    val email: String? = null,
    @SerialName("profile_id") val profileId: String? = null,
    val notes: String? = null,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val birthday: String? = null,
    @SerialName("email_bounced") val emailBounced: Boolean? = null,
    @SerialName("email_bounced_at") val emailBouncedAt: String? = null,
    @SerialName("newsletter_subscribed") val newsletterSubscribed: Boolean,
)
