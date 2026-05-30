// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: profiles
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Profile(
    val id: String,
    val email: String? = null,
    @SerialName("full_name") val fullName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val phone: String? = null,
    val notes: String? = null,
    @SerialName("accepted_terms_at") val acceptedTermsAt: String? = null,
    @SerialName("accepted_privacy_at") val acceptedPrivacyAt: String? = null,
    val role: UserRole,
)
