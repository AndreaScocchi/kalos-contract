// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: members
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Member(
    val id: String,
    @SerialName("client_id") val clientId: String,
    @SerialName("member_number") val memberNumber: String,
    @SerialName("application_id") val applicationId: String? = null,
    @SerialName("admitted_on") val admittedOn: String,
    @SerialName("resolution_date") val resolutionDate: String? = null,
    val status: MemberStatus,
    @SerialName("ceased_on") val ceasedOn: String? = null,
    @SerialName("cease_reason") val ceaseReason: MemberCeaseReason? = null,
    @SerialName("cease_note") val ceaseNote: String? = null,
    @SerialName("card_token") val cardToken: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
