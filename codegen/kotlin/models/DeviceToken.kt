// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: device_tokens
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DeviceToken(
    val id: String,
    @SerialName("client_id") val clientId: String,
    @SerialName("expo_push_token") val expoPushToken: String,
    @SerialName("device_id") val deviceId: String? = null,
    val platform: String? = null,
    @SerialName("app_version") val appVersion: String? = null,
    @SerialName("is_active") val isActive: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("last_used_at") val lastUsedAt: String,
)
