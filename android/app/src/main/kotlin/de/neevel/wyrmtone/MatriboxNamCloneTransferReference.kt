package de.neevel.wyrmtone

/**
 * V5B.1: the confirmed NAM Clone-transfer block-frame wire format
 * (`tool/matribox_nam_analysis/nam_transfer_codec.dart`'s
 * `namTransferPrefix`/`NamTransferFrame`, reproduced byte-identically
 * here so native code has its OWN validation, not just trust in the Dart
 * side -- the same defense-in-depth [MatriboxFullLiveCodec.validate] and
 * [MatriboxUserSlotReadReference] give the other two senders).
 *
 * [NamCloneTransferFrame] is intentionally opaque and can ONLY be built
 * through [MatriboxNamCloneTransferReference.parseValidated]: there is no
 * public constructor, so [MatriboxNamCloneSendPort] never accepts a raw
 * `ByteArray` -- only an already-fully-validated frame, exactly like
 * [FullLiveOperation]/[MatriboxWritableUserPreset] for the other senders.
 */
class NamCloneTransferFrame internal constructor(internal val bytes: ByteArray, val block: Int, val slot: Int)

/**
 * V5B.2a: an opaque, already-validated NAM Clone-transfer ACK -- the
 * device's reply to one [NamCloneTransferFrame]. Only constructible via
 * [MatriboxNamCloneTransferReference.parseValidatedAck].
 */
class NamCloneTransferAck internal constructor(val slot: Int, val block: Int, val status: Int) {
    val isSuccess: Boolean get() = status == 0x01
}

object MatriboxNamCloneTransferReference {
    /** `F0 21 25 7F 'QME2' 12 12 00 10 13`. */
    private val prefix = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x12, 0x12, 0x00, 0x10, 0x13,
    )

    /** Clone 5's confirmed wire slot byte (`nam_transfer_codec.dart`'s `MatriboxCloneSlot(5)`). */
    const val CLONE5_SLOT: Int = 0x04

    /** Clone 1's confirmed wire slot byte (`nam_transfer_codec.dart`'s `MatriboxCloneSlot(1)`). */
    const val CLONE1_SLOT: Int = 0x00

    /**
     * Wire range of the five Clone slots (Clone n -> n-1). Only [CLONE1_SLOT] and [CLONE5_SLOT]
     * are hardware-confirmed (real captures); 0x01..0x03 (Clone 2..4) are protocol-derived /
     * strongly inferred only -- see `nam_transfer_codec.dart`'s `CloneSlotEvidence`. Never widen
     * this range: it is the only thing standing between this validator and an arbitrary SysEx slot.
     */
    const val MIN_CLONE_SLOT: Int = CLONE1_SLOT
    const val MAX_CLONE_SLOT: Int = CLONE5_SLOT

    const val MESSAGE_LENGTH: Int = 47
    const val PAYLOAD_NIBBLES: Int = 28
    const val MAX_BLOCK: Int = 587 // 8232 / 14 - 1

    /**
     * Validates [bytes] against the confirmed frame shape and returns an
     * opaque, already-validated [NamCloneTransferFrame]. Throws
     * [IllegalArgumentException] for anything that is not a well-formed
     * block message targeting a Clone slot in [MIN_CLONE_SLOT]..[MAX_CLONE_SLOT]
     * -- never returns a partially-checked result.
     */
    fun parseValidated(bytes: ByteArray): NamCloneTransferFrame {
        require(bytes.size == MESSAGE_LENGTH) { "NAM-Clone-Frame muss $MESSAGE_LENGTH Byte lang sein." }
        for (i in prefix.indices) {
            require(bytes[i] == prefix[i]) { "Kein NAM-Clone-Transfer-Frame (Präfix)." }
        }
        val slot = bytes[13].toInt() and 0xff
        require(slot in MIN_CLONE_SLOT..MAX_CLONE_SLOT) { "Nur Clone 1..5 (0x00..0x04) ist erlaubt." }
        val block = ((bytes[14].toInt() and 0x7f) shl 7) or (bytes[15].toInt() and 0x7f)
        require(block in 0..MAX_BLOCK) { "Blocknummer außerhalb des bekannten Bereichs." }
        for (i in 16 until 16 + PAYLOAD_NIBBLES) {
            require(bytes[i].toInt() and 0xff in 0..0x0f) { "Payload-Byte ist kein Nibble." }
        }
        var sum = 0
        for (i in 16 until 16 + PAYLOAD_NIBBLES) sum += bytes[i].toInt() and 0xff
        val checksum = sum and 0xff
        val expectedHigh = (checksum shr 4) and 0x0f
        val expectedLow = checksum and 0x0f
        require(bytes[44].toInt() and 0xff == expectedHigh && bytes[45].toInt() and 0xff == expectedLow) {
            "Checksumme stimmt nicht."
        }
        require(bytes[46].toInt() and 0xff == 0xf7) { "Kein F7-Abschluss." }
        return NamCloneTransferFrame(bytes.copyOf(), block, slot)
    }

    const val ACK_MESSAGE_LENGTH: Int = 18

    /**
     * Validates raw bytes received during a NAM Clone-transfer session
     * against the confirmed ACK shape (`nam_transfer_codec.dart`'s
     * `NamTransferAck`) and returns an opaque [NamCloneTransferAck].
     * Throws [IllegalArgumentException] for anything that is not a
     * well-formed ACK of this exact family -- unrelated MIDI traffic (a
     * different length, a different prefix) is never coerced into a
     * result, only ever rejected.
     */
    fun parseValidatedAck(bytes: ByteArray): NamCloneTransferAck {
        require(bytes.size == ACK_MESSAGE_LENGTH) { "NAM-Clone-ACK muss $ACK_MESSAGE_LENGTH Byte lang sein." }
        for (i in prefix.indices) {
            require(bytes[i] == prefix[i]) { "Keine bekannte NAM-Clone-Transfer-Nachrichtenfamilie (Präfix)." }
        }
        require(bytes[17].toInt() and 0xff == 0xf7) { "Kein F7-Abschluss." }
        val slot = bytes[13].toInt() and 0xff
        val block = ((bytes[14].toInt() and 0x7f) shl 7) or (bytes[15].toInt() and 0x7f)
        val status = bytes[16].toInt() and 0xff
        return NamCloneTransferAck(slot, block, status)
    }
}
