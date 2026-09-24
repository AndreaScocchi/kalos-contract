// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: site_rebuild_state
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SiteRebuildState(
    val id: Boolean,
    @SerialName("requested_at") val requestedAt: String? = null,
    @SerialName("requested_by") val requestedBy: String? = null,
    @SerialName("triggered_at") val triggeredAt: String? = null,
    @SerialName("reported_at") val reportedAt: String? = null,
    @SerialName("last_ok") val lastOk: Boolean? = null,
    @SerialName("last_status") val lastStatus: Int? = null,
    @SerialName("last_error") val lastError: String? = null,
)
