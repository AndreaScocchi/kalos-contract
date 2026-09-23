// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: volunteer_reimbursements
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class VolunteerReimbursement(
    val id: String,
    @SerialName("volunteer_id") val volunteerId: String,
    @SerialName("spent_on") val spentOn: String,
    @SerialName("amount_cents") val amountCents: Int,
    val description: String,
    @SerialName("attachment_path") val attachmentPath: String,
    val status: ReimbursementStatus,
    @SerialName("approved_by") val approvedBy: String? = null,
    @SerialName("approved_at") val approvedAt: String? = null,
    @SerialName("paid_at") val paidAt: String? = null,
    @SerialName("rejection_reason") val rejectionReason: String? = null,
    @SerialName("expense_id") val expenseId: String? = null,
    val note: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
