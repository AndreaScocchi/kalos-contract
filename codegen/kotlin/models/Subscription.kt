// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: subscriptions
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class Subscription(
    val id: String,
    @SerialName("plan_id") val planId: String,
    val status: SubscriptionStatus,
    @SerialName("started_at") val startedAt: String,
    @SerialName("expires_at") val expiresAt: String,
    @SerialName("custom_name") val customName: String? = null,
    @SerialName("custom_price_cents") val customPriceCents: Int? = null,
    @SerialName("custom_entries") val customEntries: Int? = null,
    @SerialName("custom_validity_days") val customValidityDays: Int? = null,
    val metadata: JsonElement? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("client_id") val clientId: String? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("discount_percent") val discountPercent: Double? = null,
    @SerialName("discount_reason") val discountReason: String? = null,
)
