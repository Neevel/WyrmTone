package de.neevel.wyrmtone

/**
 * The fixed `FAMILY_EXPANSION_P01_V1` certification plan for User P01: one
 * controlled run that actively tests the model-select, number, signed,
 * decimal, flag and block-CC families still missing hardware evidence
 * (Tier B, FX1 Boost and AMP Sol 100 OD select, is part of it). It runs
 * through the existing Full Live session, port and codec (no second
 * transport). Dart addresses it only by [PLAN_ID] plus the verified backup
 * hash; no operation, byte, slot, algorithm id or parameter index ever comes
 * from the caller. No Store, no `12 11`, no name/BPM/VOL, no User IR.
 *
 * Sent in chain order: slots ascend FX1..RVB; inside a slot MODEL SELECT,
 * then PARAMETERs, then the block CC (a select resets the block's
 * parameters, and a block is switched ON only once it is configured). Must
 * stay identical to lib/presets/matribox_family_expansion_certification.dart
 * (golden test).
 *
 * The run was CERTIFIED on real hardware (2026-09-21, wire = manufacturer ID - 1).
 * The productive families follow from its samples through the generated
 * manufacturer table ([MatriboxToneTransferCatalog]); this certification plan
 * and its own table stay independent of the productive path.
 */
object MatriboxFamilyExpansionPlan {
    const val PLAN_ID = "FAMILY_EXPANSION_P01_V1"

    private const val BOOST = 0x0000001a
    private const val SOL_100_OD = 0x07000047
    private const val GATE_2 = 0x0000001d
    private const val SOL_4X12 = 0x0a000028
    private const val GUITAR_EQ = 0x01000035
    private const val CHORUS_A = 0x04000000
    private const val WARM = 0x0b00000d
    private const val ROOM = 0x0c000000

    val operations: List<FullLiveOperation> = listOf(
        // Tier B
        FullLiveOperation.ModelSelect(ChainSlot.FX1, BOOST, "Boost"),
        FullLiveOperation.ModelSelect(ChainSlot.FX2, BOOST, "Boost"),
        FullLiveOperation.Parameter(ChainSlot.FX2, BOOST, 0, 23f, "Gain"),
        // Bright: editor ID 3, wire index 2 (ID 2 is a hidden parameter); wire = ID - 1
        FullLiveOperation.Parameter(ChainSlot.FX2, BOOST, 2, 1f, "Bright"),
        // Tier B
        FullLiveOperation.ModelSelect(ChainSlot.AMP, SOL_100_OD, "Sol 100 OD"),
        FullLiveOperation.ModelSelect(ChainSlot.NR, GATE_2, "Gate 2"),
        FullLiveOperation.Parameter(ChainSlot.NR, GATE_2, 0, 31f, "THRE"),
        FullLiveOperation.BlockToggle(ChainSlot.NR, enabled = true),
        FullLiveOperation.ModelSelect(ChainSlot.CAB, SOL_4X12, "Sol 4x12"),
        // CAB VOL: editor ID 2, wire index 1 (wire = ID - 1)
        FullLiveOperation.Parameter(ChainSlot.CAB, SOL_4X12, 1, 43f, "VOL"),
        FullLiveOperation.ModelSelect(ChainSlot.EQ, GUITAR_EQ, "Guitar EQ"),
        FullLiveOperation.Parameter(ChainSlot.EQ, GUITAR_EQ, 1, -23f, "400Hz"),
        FullLiveOperation.BlockToggle(ChainSlot.EQ, enabled = true),
        FullLiveOperation.ModelSelect(ChainSlot.MOD, CHORUS_A, "Chorus A"),
        FullLiveOperation.Parameter(ChainSlot.MOD, CHORUS_A, 1, 3.7f, "Rate"),
        FullLiveOperation.ModelSelect(ChainSlot.DLY, WARM, "Warm"),
        FullLiveOperation.Parameter(ChainSlot.DLY, WARM, 1, 743f, "Time"),
        FullLiveOperation.Parameter(ChainSlot.DLY, WARM, 4, 1f, "Trail"),
        FullLiveOperation.ModelSelect(ChainSlot.RVB, ROOM, "Room"),
        FullLiveOperation.Parameter(ChainSlot.RVB, ROOM, 0, 23f, "Mix"),
        FullLiveOperation.Parameter(ChainSlot.RVB, ROOM, 2, 41f, "Decay"),
        FullLiveOperation.Parameter(ChainSlot.RVB, ROOM, 3, 1f, "Trail"),
        FullLiveOperation.BlockToggle(ChainSlot.RVB, enabled = true),
    )
}

/** What a certification run is bound to: User P01 and the verified BEFORE-backup hash. */
internal data class CertificationTarget(val bank: String, val slot: Int, val backupHash: String)

/**
 * Independent native trust table for the family-expansion plan: the
 * manufacturer-catalog identities (slot/category, algorithm code, parameter
 * name, wire index, type and range) of exactly the models the plan selects.
 * The plan is validated against this table BEFORE the port is opened; one
 * mismatch rejects every operation (ZERO SENDS). Nothing here is hardware
 * evidence, and nothing here makes another model or parameter sendable.
 */
internal object MatriboxFamilyExpansionCatalog {
    enum class Kind { NUMBER, SIGNED, DECIMAL, FLAG }

    data class Param(val name: String, val wireIndex: Int, val kind: Kind, val min: Float, val max: Float)

    data class Model(val name: String, val code: Int, val slots: Set<ChainSlot>, val parameters: List<Param>)

    private fun knob(name: String, index: Int, max: Float = 99f) = Param(name, index, Kind.NUMBER, 0f, max)
    private fun eqBand(name: String, index: Int) = Param(name, index, Kind.SIGNED, -50f, 50f)
    private fun flag(name: String, index: Int) = Param(name, index, Kind.FLAG, 0f, 1f)

    val models: List<Model> = listOf(
        // wire index = editor ID - 1: Bright has ID 3 (ID 2 is hidden) -> wire 2
        Model("Boost", 0x0000001a, setOf(ChainSlot.FX1, ChainSlot.FX2), listOf(knob("Gain", 0), flag("Bright", 2))),
        Model(
            "Sol 100 OD", 0x07000047, setOf(ChainSlot.AMP),
            listOf(knob("Gain", 0), knob("PRES", 1), knob("Master", 2), knob("Bass", 3), knob("Middle", 4), knob("Treble", 5)),
        ),
        Model("Gate 2", 0x0000001d, setOf(ChainSlot.NR), listOf(knob("THRE", 0), knob("ATK", 1), knob("Rel", 2))),
        // CAB VOL: editor ID 2 -> wire index 1 (wire = ID - 1).
        Model("Sol 4x12", 0x0a000028, setOf(ChainSlot.CAB), listOf(knob("VOL", 1))),
        Model(
            "Guitar EQ", 0x01000035, setOf(ChainSlot.EQ),
            listOf(eqBand("125Hz", 0), eqBand("400Hz", 1), eqBand("800Hz", 2), eqBand("1.6kHz", 3), eqBand("4kHz", 4), knob("VOL", 5)),
        ),
        Model(
            "Chorus A", 0x04000000, setOf(ChainSlot.MOD),
            listOf(knob("Depth", 0), Param("Rate", 1, Kind.DECIMAL, 0.1f, 10f), knob("Tone", 2), flag("Sync", 3)),
        ),
        Model(
            "Warm", 0x0b00000d, setOf(ChainSlot.DLY),
            listOf(knob("Mix", 0), knob("Time", 1, 4000f).copy(min = 20f), knob("FdBk", 2), flag("Sync", 3), flag("Trail", 4)),
        ),
        Model("Room", 0x0c000000, setOf(ChainSlot.RVB), listOf(knob("Mix", 0), knob("Pre Delay", 1, 100f), knob("Decay", 2), flag("Trail", 3))),
    )


    fun modelByCode(code: Int): Model? = models.firstOrNull { it.code == code }
}

/**
 * Whole-plan preflight of `FAMILY_EXPANSION_P01_V1`, run before the port is
 * opened. It is deliberately independent of the plan constant (it validates
 * whatever list it is given), so an injected invalid list is provably
 * rejected with zero sends.
 */
internal object MatriboxFamilyExpansionValidator {
    private const val MAX_OPERATIONS = 64
    private val HASH = Regex("^[0-9a-f]{64}$")

    private fun reject(code: String, message: String): Nothing = throw ToneTransferRejection(code, message)

    private fun slotOf(op: FullLiveOperation) = when (op) {
        is FullLiveOperation.ModelSelect -> op.slot
        is FullLiveOperation.Parameter -> op.slot
        is FullLiveOperation.BlockToggle -> op.slot
    }

    private fun rank(op: FullLiveOperation) = when (op) {
        is FullLiveOperation.ModelSelect -> 0
        is FullLiveOperation.Parameter -> 1
        is FullLiveOperation.BlockToggle -> 2
    }

    /** Returns null when the plan is not this test's, or the rejection message when it is invalid. */
    fun preflightMessage(planId: String, operations: List<FullLiveOperation>, target: CertificationTarget?): String? {
        if (planId != MatriboxFamilyExpansionPlan.PLAN_ID) return null
        return try {
            validate(planId, operations, target)
            null
        } catch (rejection: ToneTransferRejection) {
            "${rejection.code}: ${rejection.message}"
        }
    }

    fun validate(planId: String, operations: List<FullLiveOperation>, target: CertificationTarget?) {
        if (planId != MatriboxFamilyExpansionPlan.PLAN_ID) reject("PLAN_ID", "Falsche Plan-ID.")
        if (target == null) reject("TARGET_MISSING", "Ziel (User P01) und Backup-Hash fehlen.")
        if (target.bank != "USER") reject("TARGET_NOT_ALLOWED", "Nur die User-Bank ist freigegeben.")
        if (target.slot != 1) reject("TARGET_NOT_ALLOWED", "Nur User P01 ist freigegeben.")
        if (!HASH.matches(target.backupHash)) reject("BACKUP_HASH_INVALID", "Backup-Hash muss ein SHA-256 (hex) sein.")
        if (operations.isEmpty()) reject("EMPTY_PLAN", "Der Plan enthält keine Operation.")
        if (operations.size > MAX_OPERATIONS) reject("PLAN_TOO_LARGE", "Zu viele Operationen.")

        val selectedInSlot = mutableMapOf<ChainSlot, Int>()
        val written = mutableSetOf<Pair<ChainSlot, String>>()
        val toggled = mutableSetOf<ChainSlot>()
        var lastSlot = -1
        var lastRank = -1
        for ((index, op) in operations.withIndex()) {
            val slot = slotOf(op)
            val r = rank(op)
            if (operations.take(index).any { it == op }) reject("DUPLICATE_OPERATION", "Operation #$index ist doppelt.")
            // deterministic chain order: slots ascend; SELECT, then PARAMETERs, then the block CC
            if (slot.ordinal < lastSlot || (slot.ordinal == lastSlot && r < lastRank)) {
                reject("ORDER_INVALID", "Operation #$index (${op.label}) steht in falscher Reihenfolge.")
            }
            if (slot.ordinal != lastSlot) lastRank = -1
            lastSlot = slot.ordinal
            lastRank = r

            when (op) {
                is FullLiveOperation.ModelSelect -> {
                    val model = MatriboxFamilyExpansionCatalog.modelByCode(op.code)
                        ?: reject("MODEL_UNKNOWN", "Operation #$index: Algorithmus 0x${op.code.toString(16)} ist nicht im Katalog.")
                    if (model.name != op.name) reject("MODEL_UNKNOWN", "Operation #$index: Name/Code passen nicht (${op.name}).")
                    if (slot !in model.slots) reject("MODEL_WRONG_SLOT", "Operation #$index: ${model.name} gehört nicht zu ${slot.name}.")
                    if (slot in selectedInSlot) reject("CONFLICTING_OPERATIONS", "Operation #$index: ${slot.name} wählt ein zweites Modell.")
                    selectedInSlot[slot] = op.code
                }
                is FullLiveOperation.Parameter -> {
                    val model = MatriboxFamilyExpansionCatalog.modelByCode(op.code)
                        ?: reject("MODEL_UNKNOWN", "Operation #$index: Algorithmus 0x${op.code.toString(16)} ist nicht im Katalog.")
                    if (slot !in model.slots) reject("MODEL_WRONG_SLOT", "Operation #$index: ${model.name} gehört nicht zu ${slot.name}.")
                    if (selectedInSlot[slot] != op.code) {
                        reject("PARAMETER_MODEL_NOT_SELECTED", "Operation #$index: ${model.name} ist in ${slot.name} nicht gewählt.")
                    }
                    val parameter = model.parameters.firstOrNull { it.name == op.name }
                        ?: reject("PARAMETER_UNKNOWN", "Operation #$index: ${model.name}/${op.name} ist nicht im Katalog.")
                    if (parameter.wireIndex != op.index) {
                        reject("PARAMETER_INDEX_MISMATCH", "Operation #$index: Wire-Index ${op.index} statt ${parameter.wireIndex}.")
                    }
                    if (!op.value.isFinite() || op.value < parameter.min || op.value > parameter.max) {
                        reject("VALUE_OUT_OF_RANGE", "Operation #$index: ${op.value} außerhalb ${parameter.min}..${parameter.max}.")
                    }
                    when (parameter.kind) {
                        MatriboxFamilyExpansionCatalog.Kind.FLAG ->
                            if (op.value != 0f && op.value != 1f) reject("VALUE_TYPE", "Operation #$index: Flag muss 0 oder 1 sein.")
                        MatriboxFamilyExpansionCatalog.Kind.NUMBER ->
                            if (op.value < 0f) reject("VALUE_TYPE", "Operation #$index: negativer Wert für einen Zahlenparameter.")
                        else -> Unit
                    }
                    if (!written.add(slot to op.name)) reject("CONFLICTING_OPERATIONS", "Operation #$index: ${op.name} doppelt in ${slot.name}.")
                }
                is FullLiveOperation.BlockToggle ->
                    if (!toggled.add(slot)) reject("CONFLICTING_OPERATIONS", "Operation #$index: ${slot.name} wird doppelt geschaltet.")
            }
            // the closed codec must be able to encode it (no store/metadata family exists there)
            try {
                MatriboxFullLiveCodec.validate(MatriboxFullLiveCodec.encode(op))
            } catch (error: IllegalArgumentException) {
                reject("ENCODING_INVALID", "Operation #$index: ${error.message}")
            }
        }
    }
}
