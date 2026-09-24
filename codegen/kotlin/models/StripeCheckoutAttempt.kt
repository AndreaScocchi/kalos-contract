// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: stripe_checkout_attempts
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class StripeCheckoutAttempt(
    val id: Long,
    @SerialName("ip_hash") val ipHash: String,
    val purpose: StripePurpose,
    @SerialName("created_at") val createdAt: String,
)
