package de.neevel.wyrmtone

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The closed set of Matribox 1 chain slots (wire slot = chain position + 1).
 * CAPTURE_CONFIRMED by the editor big capture; there is no way to build a
 * slot from an arbitrary integer.
 */
enum class ChainSlot(val wire: Int) {
    FX1(1), FX2(2), AMP(3), NR(4), CAB(5), EQ(6), MOD(7), DLY(8), RVB(9);

    /** MIDI controller (channel 2, status 0xB1) that switches this block. */
    val controller: Int get() = 0x2f + wire
}

/** One operation of the fixed Full Live plan. Not constructible from Dart. */
sealed class FullLiveOperation {
    abstract val label: String

    data class ModelSelect(val slot: ChainSlot, val code: Int, val name: String) : FullLiveOperation() {
        override val label get() = "${slot.name} MODEL $name"
    }

    data class Parameter(
        val slot: ChainSlot,
        val code: Int,
        val index: Int,
        val value: Float,
        val name: String,
    ) : FullLiveOperation() {
        override val label get() = "${slot.name} PARAM $name = $value"
    }

    data class BlockToggle(val slot: ChainSlot, val enabled: Boolean) : FullLiveOperation() {
        override val label get() = "${slot.name} BLOCK ${if (enabled) "ON" else "OFF"}"
    }
}

/**
 * Independent Kotlin encoder for the capture-confirmed live-edit messages,
 * cross-checked byte-for-byte against the real big-capture messages in
 * MatriboxFullLiveCodecTest (and against the Dart MatriboxChainEncoder).
 * Only the three families of the Full Live plan exist here: model select
 * (22 B), parameter write (34 B), block toggle (3 B MIDI CC). There is no
 * metadata/commit (`12 11` / `12 12`) encoder and no free-form API.
 */
object MatriboxFullLiveCodec {
    private val PREFIX = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
    )

    private fun nibbles(raw: ByteArray, into: ByteArray, from: Int) {
        var cursor = from
        for (byte in raw) {
            val unsigned = byte.toInt() and 0xff
            into[cursor++] = (unsigned shr 4).toByte()
            into[cursor++] = (unsigned and 0x0f).toByte()
        }
    }

    fun encode(operation: FullLiveOperation): ByteArray = when (operation) {
        is FullLiveOperation.ModelSelect -> {
            val payload = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(operation.code).array()
            val message = ByteArray(22)
            PREFIX.copyInto(message)
            message[8] = 0x12
            message[9] = 0x10
            message[10] = operation.slot.wire.toByte()
            message[11] = 0x00
            message[12] = 0x01
            nibbles(payload, message, 13)
            message[21] = 0xf7.toByte()
            message
        }
        is FullLiveOperation.Parameter -> {
            require(operation.value.isFinite()) { "Wert ist nicht endlich." }
            require(operation.index in 0..15) { "Parameterindex ungültig." }
            val payload = ByteBuffer.allocate(10).order(ByteOrder.LITTLE_ENDIAN)
                .putInt(operation.code).putShort(operation.index.toShort()).putFloat(operation.value).array()
            val message = ByteArray(34)
            PREFIX.copyInto(message)
            message[8] = 0x12
            message[9] = 0x10
            message[10] = operation.slot.wire.toByte()
            message[11] = 0x00
            message[12] = 0x02
            nibbles(payload, message, 13)
            message[33] = 0xf7.toByte()
            message
        }
        is FullLiveOperation.BlockToggle -> byteArrayOf(
            0xb1.toByte(),
            operation.slot.controller.toByte(),
            (if (operation.enabled) 0x00 else 0x7f).toByte(),
        )
    }

    /** Independent structural re-check of already-encoded bytes before sending. */
    fun validate(data: ByteArray) {
        if (data.size == 3) {
            require(data[0] == 0xb1.toByte()) { "CC-Status falsch." }
            require(data[1].toInt() in 0x30..0x38) { "CC-Controller außerhalb der Blocktabelle." }
            require(data[2].toInt() == 0x00 || data[2].toInt() == 0x7f) { "CC-Wert falsch." }
            return
        }
        require(data.size == 22 || data.size == 34) { "Nachrichtenlänge falsch." }
        require(data.first() == 0xf0.toByte() && data.last() == 0xf7.toByte()) { "SysEx-Grenzen falsch." }
        require(data.copyOfRange(0, 8).contentEquals(PREFIX)) { "Header falsch." }
        // Only the live-edit family 12 10; never metadata (12 11) or commit (12 12).
        require(data[8].toInt() == 0x12 && data[9].toInt() == 0x10) { "Nachrichtenfamilie nicht freigegeben." }
        require(data[10].toInt() in 1..9 && data[11].toInt() == 0) { "Slot falsch." }
        val kind = data[12].toInt()
        require((data.size == 22 && kind == 1) || (data.size == 34 && kind == 2)) { "Familie/Länge passt nicht." }
        for (i in 13 until data.size - 1) {
            require(data[i].toInt() in 0..15) { "Nibble ungültig." }
        }
        if (data.size == 34) {
            val raw = ByteArray(10) { i -> ((data[13 + 2 * i].toInt() shl 4) or data[14 + 2 * i].toInt()).toByte() }
            val value = ByteBuffer.wrap(raw, 6, 4).order(ByteOrder.LITTLE_ENDIAN).float
            require(value.isFinite()) { "Wert ungültig." }
        }
    }
}
