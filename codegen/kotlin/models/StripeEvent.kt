// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: stripe_events
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class StripeEvent(
    val id: String,
    val type: String,
    val payload: JsonElement,
    val livemode: Boolean,
    @SerialName("received_at") val receivedAt: String,
    @SerialName("processed_at") val processedAt: String? = null,
    @SerialName("error_message") val errorMessage: String? = null,
    val attempts: Int,
)
