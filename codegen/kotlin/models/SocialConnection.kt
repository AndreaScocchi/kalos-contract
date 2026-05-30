// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: social_connections
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SocialConnection(
    val id: String,
    @SerialName("operator_id") val operatorId: String,
    val platform: SocialPlatform,
    @SerialName("account_id") val accountId: String,
    @SerialName("account_name") val accountName: String? = null,
    @SerialName("page_id") val pageId: String? = null,
    @SerialName("page_name") val pageName: String? = null,
    @SerialName("instagram_business_id") val instagramBusinessId: String? = null,
    @SerialName("instagram_username") val instagramUsername: String? = null,
    @SerialName("access_token") val accessToken: String,
    @SerialName("token_expires_at") val tokenExpiresAt: String? = null,
    val permissions: List<String>? = null,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("last_used_at") val lastUsedAt: String? = null,
    @SerialName("last_error") val lastError: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("is_test") val isTest: Boolean,
)
