// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: account_transfers
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AccountTransfer(
    val id: String,
    @SerialName("occurred_on") val occurredOn: String,
    @SerialName("from_account") val fromAccount: CashAccount,
    @SerialName("to_account") val toAccount: CashAccount,
    @SerialName("amount_cents") val amountCents: Int,
    val note: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
