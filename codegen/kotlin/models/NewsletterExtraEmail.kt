// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: newsletter_extra_emails
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class NewsletterExtraEmail(
    val id: String,
    val email: String,
    val name: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
)
