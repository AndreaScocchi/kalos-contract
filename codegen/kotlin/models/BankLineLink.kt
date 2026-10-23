// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: bank_line_links
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class BankLineLink(
    val id: String,
    @SerialName("line_id") val lineId: String,
    @SerialName("closing_id") val closingId: String,
    @SerialName("transaction_id") val transactionId: String? = null,
    @SerialName("expense_id") val expenseId: String? = null,
    @SerialName("transfer_id") val transferId: String? = null,
    @SerialName("created_at") val createdAt: String,
)
