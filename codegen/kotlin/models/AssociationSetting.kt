// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: association_settings
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AssociationSetting(
    val id: Boolean,
    @SerialName("legal_name") val legalName: String,
    @SerialName("short_legal_name") val shortLegalName: String,
    @SerialName("fiscal_code") val fiscalCode: String,
    @SerialName("vat_number") val vatNumber: String? = null,
    @SerialName("address_street") val addressStreet: String,
    @SerialName("address_zip") val addressZip: String,
    @SerialName("address_city") val addressCity: String,
    @SerialName("address_province") val addressProvince: String,
    val pec: String? = null,
    val email: String? = null,
    val phone: String? = null,
    @SerialName("legal_representative") val legalRepresentative: String? = null,
    @SerialName("runts_registered") val runtsRegistered: Boolean,
    @SerialName("runts_number") val runtsNumber: String? = null,
    @SerialName("ledger_start_date") val ledgerStartDate: String,
    @SerialName("receipt_prefix") val receiptPrefix: String,
    @SerialName("receipt_footer") val receiptFooter: String? = null,
    @SerialName("stamp_duty_threshold_cents") val stampDutyThresholdCents: Int,
    @SerialName("stamp_duty_cents") val stampDutyCents: Int,
    @SerialName("updated_by") val updatedBy: String? = null,
    @SerialName("updated_at") val updatedAt: String,
)
