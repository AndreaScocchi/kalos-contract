// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: newsletter_emails
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class NewsletterEmail(
    val id: String,
    @SerialName("campaign_id") val campaignId: String,
    @SerialName("client_id") val clientId: String? = null,
    @SerialName("email_address") val emailAddress: String,
    @SerialName("client_name") val clientName: String,
    @SerialName("resend_id") val resendId: String? = null,
    val status: NewsletterEmailStatus,
    @SerialName("sent_at") val sentAt: String? = null,
    @SerialName("delivered_at") val deliveredAt: String? = null,
    @SerialName("opened_at") val openedAt: String? = null,
    @SerialName("clicked_at") val clickedAt: String? = null,
    @SerialName("bounced_at") val bouncedAt: String? = null,
    @SerialName("error_message") val errorMessage: String? = null,
    @SerialName("created_at") val createdAt: String,
)
