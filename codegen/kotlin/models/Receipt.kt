// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: receipts
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class Receipt(
    val id: String,
    @SerialName("transaction_id") val transactionId: String,
    val year: Int,
    val number: Int,
    @SerialName("full_number") val fullNumber: String,
    @SerialName("issued_at") val issuedAt: String,
    @SerialName("recipient_name") val recipientName: String,
    @SerialName("recipient_fiscal_code") val recipientFiscalCode: String? = null,
    @SerialName("recipient_address") val recipientAddress: String? = null,
    @SerialName("issuer_snapshot") val issuerSnapshot: JsonElement,
    val causale: String,
    @SerialName("amount_cents") val amountCents: Int,
    @SerialName("stamp_duty_cents") val stampDutyCents: Int,
    @SerialName("pdf_path") val pdfPath: String? = null,
    @SerialName("sent_at") val sentAt: String? = null,
    @SerialName("voided_at") val voidedAt: String? = null,
    @SerialName("void_reason") val voidReason: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("sent_to") val sentTo: String? = null,
    @SerialName("send_claimed_at") val sendClaimedAt: String? = null,
    @SerialName("send_error") val sendError: String? = null,
)
