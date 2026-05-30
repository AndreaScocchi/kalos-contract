// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: auth_email_logs
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class AuthEmailLog(
    val id: String,
    @SerialName("user_id") val userId: String,
    val email: String,
    @SerialName("email_type") val emailType: String,
    val source: String,
    @SerialName("resend_id") val resendId: String? = null,
    val status: String,
    @SerialName("error_message") val errorMessage: String? = null,
    val metadata: JsonElement? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
