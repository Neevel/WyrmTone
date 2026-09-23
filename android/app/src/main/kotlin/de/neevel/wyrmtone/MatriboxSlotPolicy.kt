package de.neevel.wyrmtone

/**
 * The native half of WyrmTone's slot rule (Dart: lib/presets/matribox_transfer_slots.dart). It is
 * enforced here independently of Dart -- this is the last boundary before MIDI:
 *
 *   P01..P99 = User bank, device index = preset number - 1 (0..98)
 *   P01..P10 = PROTECTED PLAY PRESETS, never written by the productive transfer
 *   P11..P99 = PRODUCT WRITABLE
 *   Factory  = never written
 *
 * A missing, protected or invalid target is rejected before any port is opened: zero sends. There
 * is no default and no fallback slot.
 */
internal object MatriboxSlotPolicy {
    const val FIRST_USER_PRESET = 1
    const val LAST_USER_PRESET = 99
    const val LAST_PROTECTED_PRESET = 10
    const val FIRST_WRITABLE_PRESET = 11

    fun isUserPreset(presetNumber: Int) = presetNumber in FIRST_USER_PRESET..LAST_USER_PRESET
    fun isProtected(presetNumber: Int) = presetNumber in FIRST_USER_PRESET..LAST_PROTECTED_PRESET
    fun isProductWritable(presetNumber: Int) = presetNumber in FIRST_WRITABLE_PRESET..LAST_USER_PRESET
}

/** A validated User-bank preset P01..P99. */
internal class MatriboxUserPreset private constructor(val presetNumber: Int) {
    /** 0..98: the Bank/Slot byte of the read and the preset-select index. */
    val deviceIndex: Int get() = presetNumber - 1
    val label: String get() = "P%02d".format(presetNumber)

    override fun equals(other: Any?) = other is MatriboxUserPreset && other.presetNumber == presetNumber
    override fun hashCode() = presetNumber
    override fun toString() = label

    companion object {
        val P01 = MatriboxUserPreset(1)

        fun of(presetNumber: Int): MatriboxUserPreset {
            require(MatriboxSlotPolicy.isUserPreset(presetNumber)) { "Kein User-Preset P01–P99: $presetNumber." }
            return MatriboxUserPreset(presetNumber)
        }

        fun fromDeviceIndex(deviceIndex: Int): MatriboxUserPreset = of(deviceIndex + 1)
    }
}

/** A User preset the productive transfer may write. Only constructible for P11..P99. */
internal class MatriboxWritableUserPreset private constructor(val preset: MatriboxUserPreset) {
    val presetNumber: Int get() = preset.presetNumber
    val deviceIndex: Int get() = preset.deviceIndex
    val label: String get() = preset.label

    override fun equals(other: Any?) = other is MatriboxWritableUserPreset && other.preset == preset
    override fun hashCode() = preset.hashCode()
    override fun toString() = label

    companion object {
        fun of(presetNumber: Int): MatriboxWritableUserPreset {
            require(MatriboxSlotPolicy.isProductWritable(presetNumber)) {
                "P01–P10 sind geschützt; beschreibbar sind nur P11–P99 (angefragt: $presetNumber)."
            }
            return MatriboxWritableUserPreset(MatriboxUserPreset.of(presetNumber))
        }

        /** Why a contract target is refused, or null when it is USER + an integral P11..P99. */
        fun contractProblem(bank: Any?, slot: Any?): Pair<String, String>? {
            if (bank != "USER") return "TARGET_NOT_ALLOWED" to "Nur die User-Bank ist beschreibbar."
            val number = when (slot) {
                is Int -> slot.toLong()
                is Long -> slot
                else -> return "TARGET_NOT_ALLOWED" to "targetSlot fehlt oder ist keine Ganzzahl."
            }
            if (number in MatriboxSlotPolicy.FIRST_USER_PRESET..MatriboxSlotPolicy.LAST_PROTECTED_PRESET) {
                return "TARGET_PROTECTED" to "P01–P10 sind geschützt und werden nie beschrieben."
            }
            if (number !in MatriboxSlotPolicy.FIRST_WRITABLE_PRESET..MatriboxSlotPolicy.LAST_USER_PRESET) {
                return "TARGET_NOT_ALLOWED" to "Nur P11–P99 sind beschreibbar."
            }
            return null
        }

        /** The validated target of a closed contract (targetBank, targetSlot), or null. */
        fun fromContract(bank: Any?, slot: Any?): MatriboxWritableUserPreset? =
            if (contractProblem(bank, slot) != null) null else of((slot as Number).toInt())
    }
}

/**
 * Slot addressing of the confirmed read sequence. Nothing new is invented: the P01 references
 * ([VerifiedPresetP01PhaseDReference], [VerifiedPresetP01FullReadReference]) already carry
 * Bank=User(0x00) at offset 13 and Slot=0 at offset 14, the positions confirmed for the Phase-D
 * announce/ack, the part-0 trigger and the part-n requests (docs/MATRIBOX_OFFLINE_ANALYSIS.md). Only
 * the slot byte is replaced; for P01 every derived message is byte-identical to its reference.
 */
internal object MatriboxUserSlotReadReference {
    const val BANK_OFFSET = 13
    const val SLOT_OFFSET = 14
    private const val USER_BANK: Byte = 0x00

    private fun withSlot(reference: ByteArray, slot: MatriboxUserPreset): ByteArray =
        reference.copyOf().also { it[SLOT_OFFSET] = slot.deviceIndex.toByte() }

    fun announce(slot: MatriboxUserPreset): ByteArray = withSlot(VerifiedPresetP01PhaseDReference.announce, slot)

    fun acknowledgement(slot: MatriboxUserPreset): ByteArray =
        withSlot(VerifiedPresetP01PhaseDReference.acknowledgement, slot)

    fun partRequest(slot: MatriboxUserPreset, partIndex: Int): ByteArray =
        withSlot(VerifiedPresetP01FullReadReference.requests[partIndex], slot)

    fun isValidAck(bytes: ByteArray, slot: MatriboxUserPreset): Boolean = bytes.contentEquals(acknowledgement(slot))

    /** The part shape of V2/V3A plus: the response names Bank=User and exactly the requested slot. */
    fun isValidResponse(bytes: ByteArray, slot: MatriboxUserPreset, partIndex: Int): Boolean =
        VerifiedPresetP01FullReadReference.isValidResponseForPart(bytes, partIndex) &&
            bytes[BANK_OFFSET] == USER_BANK &&
            bytes[SLOT_OFFSET] == slot.deviceIndex.toByte()

    /** The references really are User/Slot 0 at the positions this object rewrites. */
    fun validate() {
        VerifiedPresetP01PhaseDReference.validateAnnounce()
        VerifiedPresetP01FullReadReference.validate()
        val all = listOf(VerifiedPresetP01PhaseDReference.announce, VerifiedPresetP01PhaseDReference.acknowledgement) +
            VerifiedPresetP01FullReadReference.requests
        for (reference in all) {
            require(reference[BANK_OFFSET] == USER_BANK && reference[SLOT_OFFSET] == 0.toByte()) {
                "Referenz ist nicht User/Slot 0 an den bestätigten Offsets."
            }
        }
    }
}

/**
 * The evidence-backed proprietary preset select (the 22-byte editor message of
 * [VerifiedPresetP01Reference], confirmed for index 0x00/0x09/0x0A; `index = preset number - 1`
 * additionally confirmed across the User bank via Program Change). Only the index byte at offset 18
 * differs from the P01 reference; it is only ever built for a product-writable target.
 */
internal object MatriboxPresetSelectReference {
    const val INDEX_OFFSET = 18

    fun message(target: MatriboxWritableUserPreset): ByteArray =
        VerifiedPresetP01Reference.bytes().also { it[INDEX_OFFSET] = target.deviceIndex.toByte() }

    fun validate(message: ByteArray, target: MatriboxWritableUserPreset) {
        val reference = VerifiedPresetP01Reference.bytes()
        require(message.size == 22 && reference.size == 22) { "Preset-Select-Länge falsch." }
        for (i in reference.indices) {
            if (i != INDEX_OFFSET) require(message[i] == reference[i]) { "Preset-Select weicht an Offset $i von der Referenz ab." }
        }
        require(MatriboxSlotPolicy.isProductWritable(target.presetNumber)) { "Geschützter Speicherplatz." }
        require(message[INDEX_OFFSET] == target.deviceIndex.toByte()) { "Preset-Select-Index passt nicht zum Ziel." }
    }
}
