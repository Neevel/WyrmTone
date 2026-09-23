package de.neevel.wyrmtone

/*
 * Confirmed protocol references and helpers used by the productive Matribox reader and transfer.
 * They were first confirmed by the historical P01 probes (read probe V2/V3A, preset-select probe;
 * see docs/MATRIBOX_OFFLINE_ANALYSIS.md) and are kept byte-identical here; the probe runners, ports
 * and panels were removed. "P01" in the names refers to the capture/probe they were confirmed with:
 * the productive paths address other slots only through MatriboxUserSlotReadReference /
 * MatriboxPresetSelectReference, which change exactly the confirmed slot/index byte.
 */

internal data class ProbeEligibility(
    val enabled: Boolean, val connection: String?, val vendor: Int?, val product: Int?,
    val uniqueUsb: Boolean, val uniqueMidi: Boolean, val directlyMapped: Boolean,
    val deviceOpen: Boolean, val expectedInput: Boolean, val monitoring: Boolean,
) {
    fun check() {
        require(enabled) { "Compile-Time-Freigabe fehlt." }
        require(connection != null && vendor == 0x84ef && product == 0x0054) { "Falsches oder getrenntes USB-Gerät." }
        require(uniqueUsb && uniqueMidi && directlyMapped) { "Matribox nicht eindeutig direkt USB/MIDI zugeordnet." }
        require(deviceOpen) { "MIDI-Gerät nicht geöffnet." }
        require(expectedInput) { "Erwarteter eindeutiger Input-Port 0 fehlt." }
        require(!monitoring) { "Passiven Monitor zuerst stoppen." }
    }
}

object VerifiedPresetP01Reference {
    fun bytes(): ByteArray = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x12, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0xf7.toByte(),
    )

    internal fun validate(data: ByteArray) {
        require(data.size == 22) { "P01-Referenzlänge falsch." }
        require(data.contentEquals(bytes())) { "Keine bytegleiche P01-Editor-Referenz." }
    }
}

/**
 * The exact ten Host->Device requests confirmed byte-identical in the
 * official Sonicake-editor connect/sync capture for User-Bank Slot 0
 * (P01) -- see docs/MATRIBOX_OFFLINE_ANALYSIS.md, "Vollstaendige
 * Request/Response-Sequenz fuer User P01". These ten byte arrays are the
 * entire universe of read requests; the productive reader only replaces the
 * confirmed slot byte ([MatriboxUserSlotReadReference]).
 */
object VerifiedPresetP01FullReadReference {
    val requests: List<ByteArray> = listOf(
        // Part 0 request (17 bytes) -> expects a 210-byte response.
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x02, 0x00, 0x00, 0x01, 0xf7.toByte(),
        ),
        // Parts 1-7 requests (19 bytes each) -> expect 210-byte responses.
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x02, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x03, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x05, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x06, 0x01, 0xf7.toByte(),
        ),
        // Part 8 request (19 bytes) -> expects a 46-byte response.
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x07, 0x01, 0xf7.toByte(),
        ),
        // Part 9 request (19 bytes) -> expects an 18-byte, payload-less response.
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x08, 0x01, 0xf7.toByte(),
        ),
    )

    /** Confirmed response length per part index (0-9). */
    val expectedResponseLengths: List<Int> =
        listOf(210, 210, 210, 210, 210, 210, 210, 210, 46, 18)

    internal fun validate() {
        require(requests.size == 10) { "Es muessen genau zehn Requests sein." }
        require(expectedResponseLengths.size == 10)
        for ((index, request) in requests.withIndex()) {
            require(request.first() == 0xf0.toByte() && request.last() == 0xf7.toByte()) {
                "Request $index: SysEx-Grenzen falsch."
            }
            val expectedLength = if (index == 0) 17 else 19
            require(request.size == expectedLength) { "Request $index: Laenge falsch." }
        }
    }

    /**
     * True only if [bytes] is a complete SysEx of exactly the confirmed
     * length and header shape for [partIndex] (offsets 8/9 = QME2 class
     * 0x12/0x13, offset 10 in {0x01,0x02}, offset 11 = 0x00, offset 12 in
     * {0x03,0x05}, offset 16 = partIndex). Mirrors (intentionally
     * duplicated, native side needs this synchronously)
     * lib/presets/p01_readback_decoder.dart's `readbackHeader`.
     */
    fun isValidResponseForPart(bytes: ByteArray, partIndex: Int): Boolean {
        if (bytes.size != expectedResponseLengths[partIndex]) return false
        if (bytes.size < 18) return false
        if (bytes.first() != 0xf0.toByte() || bytes.last() != 0xf7.toByte()) return false
        if (bytes[8] != 0x12.toByte() || bytes[9] != 0x13.toByte()) return false
        val offset10 = bytes[10].toInt() and 0xff
        if (offset10 != 0x01 && offset10 != 0x02) return false
        if (bytes[11] != 0x00.toByte()) return false
        val offset12 = bytes[12].toInt() and 0xff
        if (offset12 != 0x03 && offset12 != 0x05) return false
        val actualPart = bytes[16].toInt() and 0xff
        return actualPart == partIndex
    }
}

/** Reassembles a plain MIDI byte stream into complete SysEx messages (F0..F7). */
internal class SysExAccumulator {
    private val buffer = mutableListOf<Byte>()
    private var active = false

    /** Returns every SysEx message completed by bytes in [chunk], in order. */
    fun feed(chunk: ByteArray): List<ByteArray> {
        val completed = mutableListOf<ByteArray>()
        for (byte in chunk) {
            if (byte == 0xf0.toByte()) {
                // A fresh start discards any prior incomplete message, same
                // as the existing pure Dart MidiParser.
                buffer.clear()
                buffer.add(byte)
                active = true
                continue
            }
            if (!active) continue
            buffer.add(byte)
            if (byte == 0xf7.toByte()) {
                completed.add(buffer.toByteArray())
                buffer.clear()
                active = false
            }
        }
        return completed
    }
}

/**
 * The single confirmed "Phase D" announce/acknowledge pair for User-Bank
 * Slot 0 (P01), observed byte-identically in both Sonicake-editor
 * connect/sync captures immediately before every Part-0 trigger of every
 * one of the 199 observed slot transitions -- see
 * docs/MATRIBOX_OFFLINE_ANALYSIS.md, "Präambel-Analyse: die fehlende
 * Phase D vor Part 0". Hardware-confirmed (V3A probe, reproduced): Phase D
 * alone, without the session-global Ping/Capability/Enumeration phases,
 * establishes the context for an isolated multi-part read.
 */
object VerifiedPresetP01PhaseDReference {
    /** Host->Device announce for Bank=User(0x00)/Slot=0(0x00). */
    val announce: ByteArray = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x11, 0x13, 0x01, 0x00, 0x00, 0x00, 0x00, 0xf7.toByte(),
    )

    /** Device->Host acknowledgement for Bank=User(0x00)/Slot=0(0x00). */
    val acknowledgement: ByteArray = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x12, 0x13, 0x01, 0x00, 0x01, 0x00, 0x00, 0x0c, 0x1c, 0x01, 0x40, 0xf7.toByte(),
    )

    internal fun validateAnnounce() {
        require(announce.size == 16) { "Phase-D-Announce-Länge falsch." }
        require(announce.first() == 0xf0.toByte() && announce.last() == 0xf7.toByte()) {
            "Phase-D-Announce-Grenzen falsch."
        }
        require(acknowledgement.size == 20) { "Phase-D-Ack-Länge falsch." }
        require(
            acknowledgement.first() == 0xf0.toByte() &&
                acknowledgement.last() == 0xf7.toByte(),
        ) { "Phase-D-Ack-Grenzen falsch." }
    }

    /**
     * True only for the complete byte-identical acknowledgement observed
     * for User-P01 in both reference captures. V3A deliberately does not
     * generalise any field of this single confirmed response.
     */
    fun isValidAck(bytes: ByteArray): Boolean = bytes.contentEquals(acknowledgement)
}
