// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: volunteers
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Volunteer(
    val id: String,
    @SerialName("full_name") val fullName: String,
    @SerialName("fiscal_code") val fiscalCode: String? = null,
    @SerialName("client_id") val clientId: String? = null,
    @SerialName("operator_id") val operatorId: String? = null,
    @SerialName("started_on") val startedOn: String,
    @SerialName("ended_on") val endedOn: String? = null,
    @SerialName("is_occasional") val isOccasional: Boolean,
    @SerialName("activity_note") val activityNote: String? = null,
    @SerialName("insurance_note") val insuranceNote: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
