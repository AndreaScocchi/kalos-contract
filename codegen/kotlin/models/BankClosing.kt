// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: bank_closings
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class BankClosing(
    val id: String,
    @SerialName("period_from") val periodFrom: String,
    @SerialName("period_to") val periodTo: String,
    @SerialName("account_ref") val accountRef: String? = null,
    @SerialName("opening_cents") val openingCents: Int,
    @SerialName("movements_cents") val movementsCents: Int,
    @SerialName("closing_cents") val closingCents: Int,
    @SerialName("ledger_cents") val ledgerCents: Int,
    val note: String? = null,
    @SerialName("file_path") val filePath: String? = null,
    @SerialName("file_name") val fileName: String? = null,
    @SerialName("printed_on") val printedOn: String? = null,
    @SerialName("closed_by") val closedBy: String? = null,
    @SerialName("closed_at") val closedAt: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
