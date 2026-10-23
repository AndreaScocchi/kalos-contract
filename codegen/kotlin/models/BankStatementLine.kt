// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: bank_statement_lines
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class BankStatementLine(
    val id: String,
    @SerialName("closing_id") val closingId: String,
    val position: Int,
    @SerialName("booked_on") val bookedOn: String,
    @SerialName("value_on") val valueOn: String? = null,
    @SerialName("amount_cents") val amountCents: Int,
    val causale: String,
    val description: String,
    val note: String? = null,
    @SerialName("created_at") val createdAt: String,
)
