// GENERATO — NON MODIFICARE. Fonte: codegen/schema.json (scripts/gen-kotlin-models.mjs)
// Tabella: rendiconto_voci
package it.kalos.contract.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class RendicontoVoci(
    val code: String,
    val kind: String,
    val section: String,
    @SerialName("section_label") val sectionLabel: String,
    val number: Int? = null,
    val label: String,
    val position: Int,
)
