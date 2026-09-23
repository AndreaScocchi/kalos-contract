// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: member_applications
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class MemberApplication(
    val id: String,
    @SerialName("client_id") val clientId: String? = null,
    @SerialName("profile_id") val profileId: String? = null,
    val year: Int,
    val channel: MemberApplicationChannel,
    val status: MemberApplicationStatus,
    @SerialName("first_name") val firstName: String,
    @SerialName("last_name") val lastName: String,
    @SerialName("fiscal_code") val fiscalCode: String? = null,
    @SerialName("birth_date") val birthDate: String,
    @SerialName("birth_place") val birthPlace: String? = null,
    @SerialName("birth_province") val birthProvince: String? = null,
    @SerialName("address_street") val addressStreet: String? = null,
    @SerialName("address_city") val addressCity: String? = null,
    @SerialName("address_zip") val addressZip: String? = null,
    @SerialName("address_province") val addressProvince: String? = null,
    val email: String? = null,
    val phone: String? = null,
    @SerialName("minor_at_submission") val minorAtSubmission: Boolean,
    @SerialName("guardian_full_name") val guardianFullName: String? = null,
    @SerialName("guardian_fiscal_code") val guardianFiscalCode: String? = null,
    @SerialName("guardian_relationship") val guardianRelationship: String? = null,
    @SerialName("guardian_email") val guardianEmail: String? = null,
    @SerialName("guardian_phone") val guardianPhone: String? = null,
    @SerialName("guardian_consent_at") val guardianConsentAt: String? = null,
    @SerialName("accepted_statute_at") val acceptedStatuteAt: String,
    @SerialName("accepted_privacy_at") val acceptedPrivacyAt: String,
    @SerialName("image_release") val imageRelease: Boolean? = null,
    @SerialName("health_declaration") val healthDeclaration: Boolean? = null,
    @SerialName("submitted_at") val submittedAt: String,
    @SerialName("submitted_ip") val submittedIp: String? = null,
    @SerialName("submitted_user_agent") val submittedUserAgent: String? = null,
    @SerialName("decided_at") val decidedAt: String? = null,
    @SerialName("decided_by") val decidedBy: String? = null,
    @SerialName("resolution_date") val resolutionDate: String? = null,
    @SerialName("decision_note") val decisionNote: String? = null,
    @SerialName("rejection_reason") val rejectionReason: String? = null,
    @SerialName("pdf_path") val pdfPath: String? = null,
    val metadata: JsonElement? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)
