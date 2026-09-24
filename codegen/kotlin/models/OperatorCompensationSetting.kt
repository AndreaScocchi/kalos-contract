// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: operator_compensation_settings
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class OperatorCompensationSetting(
    @SerialName("operator_id") val operatorId: String,
    @SerialName("withholding_percent") val withholdingPercent: Double,
    val note: String? = null,
    @SerialName("updated_by") val updatedBy: String? = null,
    @SerialName("updated_at") val updatedAt: String,
)
