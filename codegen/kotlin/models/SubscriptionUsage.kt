// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: subscription_usages
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SubscriptionUsage(
    val id: String,
    @SerialName("subscription_id") val subscriptionId: String,
    @SerialName("booking_id") val bookingId: String? = null,
    val delta: Int,
    val reason: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)
