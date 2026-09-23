// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: member_number_sequences
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class MemberNumberSequence(
    val year: Int,
    @SerialName("last_number") val lastNumber: Int,
)
