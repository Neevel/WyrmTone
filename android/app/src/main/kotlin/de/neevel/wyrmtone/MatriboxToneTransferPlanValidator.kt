package de.neevel.wyrmtone

/** Why a whole plan was refused BEFORE the first send. */
internal class ToneTransferRejection(val code: String, message: String) : Exception(message)

/** The whole-plan result of a successful validation. */
internal data class ValidatedToneTransfer(
    val planId: String,
    /** The one User preset (P11..P99) this plan is selected on and written to. */
    val target: MatriboxWritableUserPreset,
    val backupHash: String,
    val operations: List<FullLiveOperation>,
)

/**
 * Closed contract Dart -> Kotlin:
 *
 *   {planId, targetBank: "USER", targetSlot: 11..99, backupHash, operations: [...]}
 *
 * P01..P10 are protected play presets and the Factory bank is never a
 * target ([MatriboxSlotPolicy]): such a plan is rejected as a whole before
 * anything is opened -- no preset select, no model select, no parameter, no
 * block CC. There is no default slot.
 *
 * with operations of exactly four shapes (no bytes, no algorithm id, no
 * parameter index ever crosses the channel; Kotlin resolves names itself):
 *
 *   SELECT_MODEL   {type, slot, model}
 *   SET_PARAMETER  {type, slot, model, parameter, value}
 *   ENABLE_BLOCK   {type, slot}
 *   DISABLE_BLOCK  {type, slot}
 *
 * The WHOLE plan is validated before anything is sent: one invalid operation
 * rejects every operation. Evidence is checked natively against the
 * manufacturer table in [MatriboxToneTransferCatalog]; Dart's evidence claims
 * are not trusted.
 * There is no operation type for Store, metadata, name, BPM or volume, so
 * they cannot even be expressed.
 */
internal object MatriboxToneTransferPlanValidator {
    private const val MAX_OPERATIONS = 64
    private val TOP_LEVEL_KEYS = setOf("planId", "targetBank", "targetSlot", "backupHash", "operations")
    private val PLAN_ID = Regex("^[A-Za-z0-9_-]{1,128}$")
    private val HASH = Regex("^[0-9a-f]{64}$")

    private fun reject(code: String, message: String): Nothing = throw ToneTransferRejection(code, message)

    private fun stringOf(map: Map<*, *>, key: String): String =
        map[key] as? String ?: reject("ARGUMENTS_INVALID", "Feld \"$key\" fehlt oder ist kein Text.")

    private fun slotOf(map: Map<*, *>): ChainSlot {
        val name = stringOf(map, "slot")
        return ChainSlot.values().firstOrNull { it.name == name }
            ?: reject("UNKNOWN_SLOT", "Unbekannter Slot \"$name\".")
    }

    fun validate(request: Any?): ValidatedToneTransfer {
        val map = request as? Map<*, *> ?: reject("ARGUMENTS_INVALID", "Anfrage ist keine Map.")
        if (map.keys != TOP_LEVEL_KEYS) {
            reject("ARGUMENTS_INVALID", "Nur ${TOP_LEVEL_KEYS.sorted()} sind erlaubt (gefunden: ${map.keys}).")
        }
        val planId = stringOf(map, "planId")
        if (!PLAN_ID.matches(planId)) reject("ARGUMENTS_INVALID", "planId ungültig.")
        // User bank, P11..P99 only: never Factory, never a protected P01..P10, never a default.
        MatriboxWritableUserPreset.contractProblem(map["targetBank"], map["targetSlot"])?.let { (code, message) ->
            reject(code, message)
        }
        val target = MatriboxWritableUserPreset.fromContract(map["targetBank"], map["targetSlot"])
            ?: reject("TARGET_NOT_ALLOWED", "Kein beschreibbarer Speicherplatz.")
        val backupHash = stringOf(map, "backupHash")
        if (!HASH.matches(backupHash)) reject("ARGUMENTS_INVALID", "backupHash muss ein SHA-256 (hex) sein.")
        val raw = map["operations"] as? List<*> ?: reject("ARGUMENTS_INVALID", "operations fehlt.")
        if (raw.isEmpty()) reject("EMPTY_PLAN", "Der Plan enthält keine Operation.")
        if (raw.size > MAX_OPERATIONS) reject("ARGUMENTS_INVALID", "Zu viele Operationen.")

        val operations = raw.mapIndexed { index, item ->
            val op = item as? Map<*, *> ?: reject("ARGUMENTS_INVALID", "Operation #$index ist keine Map.")
            parse(index, op)
        }
        checkOrder(operations)
        return ValidatedToneTransfer(planId, target, backupHash, operations)
    }

    private fun parse(index: Int, op: Map<*, *>): FullLiveOperation {
        fun keys(vararg expected: String) {
            if (op.keys != expected.toSet()) {
                reject("ARGUMENTS_INVALID", "Operation #$index: erlaubte Felder ${expected.toList()} (gefunden: ${op.keys}).")
            }
        }
        return when (val type = stringOf(op, "type")) {
            "SELECT_MODEL" -> {
                keys("type", "slot", "model")
                val slot = slotOf(op)
                val name = stringOf(op, "model")
                // the algorithm code comes from the manufacturer table of THIS slot, never from Dart
                val model = MatriboxToneTransferCatalog.model(slot, name)
                    ?: reject("MODEL_NOT_CONFIRMED", "Operation #$index: $name ist im Herstellerkatalog von ${slot.name} nicht bekannt.")
                if (!model.selectable) {
                    reject("MODEL_NOT_CONFIRMED", "Operation #$index: Modellwahl $name in ${slot.name} ist nicht freigegeben (${model.blockedBy}).")
                }
                FullLiveOperation.ModelSelect(slot, model.code, model.name)
            }
            "SET_PARAMETER" -> {
                keys("type", "slot", "model", "parameter", "value")
                val slot = slotOf(op)
                val name = stringOf(op, "model")
                val parameterName = stringOf(op, "parameter")
                val model = MatriboxToneTransferCatalog.model(slot, name)
                    ?: reject("MODEL_NOT_CONFIRMED", "Operation #$index: $name ist im Herstellerkatalog von ${slot.name} nicht bekannt.")
                val parameter = model.parameter(parameterName)
                    ?: reject("PARAMETER_NOT_CONFIRMED", "Operation #$index: $name/$parameterName ist im Herstellerkatalog nicht bekannt.")
                if (!parameter.writable) {
                    reject("PARAMETER_NOT_CONFIRMED", "Operation #$index: $name/$parameterName ist nicht freigegeben (${parameter.blockedBy}).")
                }
                val number = op["value"] as? Number ?: reject("ARGUMENTS_INVALID", "Operation #$index: value ist keine Zahl.")
                val value = number.toFloat()
                MatriboxToneTransferCatalog.valueProblem(parameter, value)?.let {
                    reject("VALUE_OUT_OF_RANGE", "Operation #$index: $it")
                }
                // wire index = manufacturer ID - 1, resolved natively
                FullLiveOperation.Parameter(slot, model.code, parameter.wireIndex, value, parameterName)
            }
            "ENABLE_BLOCK", "DISABLE_BLOCK" -> {
                keys("type", "slot")
                val slot = slotOf(op)
                val enabled = type == "ENABLE_BLOCK"
                if ((slot to enabled) !in MatriboxToneTransferCatalog.confirmedToggles) {
                    reject("TOGGLE_NOT_CONFIRMED", "Operation #$index: ${slot.name} ${if (enabled) "ON" else "OFF"} ist nicht hardware-bestätigt.")
                }
                FullLiveOperation.BlockToggle(slot, enabled)
            }
            else -> reject("UNKNOWN_OPERATION", "Operation #$index: unbekannter Typ \"$type\".")
        }
    }

    /** Slots ascend along the chain; inside a slot: MODEL, then PARAMETERs, then the block toggle. */
    private fun checkOrder(operations: List<FullLiveOperation>) {
        fun rank(op: FullLiveOperation) = when (op) {
            is FullLiveOperation.ModelSelect -> 0
            is FullLiveOperation.Parameter -> 1
            is FullLiveOperation.BlockToggle -> 2
        }
        fun slot(op: FullLiveOperation) = when (op) {
            is FullLiveOperation.ModelSelect -> op.slot
            is FullLiveOperation.Parameter -> op.slot
            is FullLiveOperation.BlockToggle -> op.slot
        }
        var lastSlot = -1
        var lastRank = -1
        for ((index, op) in operations.withIndex()) {
            val s = slot(op).ordinal
            val r = rank(op)
            if (s < lastSlot || (s == lastSlot && r < lastRank)) {
                reject("ORDER_INVALID", "Operation #$index steht in falscher Reihenfolge.")
            }
            if (operations.take(index).any { it == op }) reject("ORDER_INVALID", "Operation #$index ist doppelt.")
            if (s != lastSlot) lastRank = -1
            lastSlot = s
            lastRank = r
        }
    }
}
