package de.neevel.wyrmtone

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The one hardware-confirmed single-parameter write this project exposes
 * on a production (non-experimental) pathway: Sol-100-OD Gain (algorithm
 * `0x07000047`, parameter index 0), using the exact 34-byte QME2 message
 * shape already confirmed by the historical Gain 40/41 editor reference
 * ([VerifiedGain41Reference]). This is a new, independent Kotlin
 * implementation of that byte construction -- Dart
 * (lib/presets/confirmed_parameter_codec.dart's `encodeMessageBytes`) and
 * native code cannot share a single implementation across languages; both
 * are cross-checked byte-for-byte against the same golden Gain 40/41
 * references in their respective test suites.
 *
 * There is no free `writeParameter(algorithm, index, value)` API anywhere
 * in this file or its callers: [encode] can only ever address Sol-100-OD
 * Gain at index 0, for a value it independently validates itself -- it
 * never trusts that a caller (Dart or otherwise) already validated
 * anything. [validate] re-checks an already-encoded message's actual
 * bytes as a second, independent line of defense before it is ever sent.
 */
object MatriboxConfirmedGainWriter {
    const val ALGORITHM_CODE = 0x07000047
    const val PARAMETER_INDEX = 0
    const val MIN_VALUE = 0.0f
    const val MAX_VALUE = 99.0f

    private val PREFIX = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x12, 0x10, 0x03, 0x00, 0x02,
    )

    /** Throws if [value] is not finite or outside [MIN_VALUE, MAX_VALUE]. */
    fun encode(value: Float): ByteArray {
        require(value.isFinite()) { "Gain-Wert ist nicht endlich." }
        require(value in MIN_VALUE..MAX_VALUE) {
            "Gain-Wert außerhalb des bestätigten Bereichs [$MIN_VALUE, $MAX_VALUE]: $value."
        }
        val payload = ByteBuffer.allocate(10).order(ByteOrder.LITTLE_ENDIAN)
        payload.putInt(ALGORITHM_CODE)
        payload.putShort(PARAMETER_INDEX.toShort())
        payload.putFloat(value)
        val raw = payload.array()
        val message = ByteArray(PREFIX.size + raw.size * 2 + 1)
        PREFIX.copyInto(message)
        var cursor = PREFIX.size
        for (byte in raw) {
            val unsigned = byte.toInt() and 0xff
            message[cursor++] = (unsigned shr 4).toByte()
            message[cursor++] = (unsigned and 0x0f).toByte()
        }
        message[cursor] = 0xf7.toByte()
        return message
    }

    /**
     * Independent re-validation of an already-encoded message. Decodes
     * the actual bytes and checks the algorithm, parameter index and
     * value range again -- defense in depth even if [encode] were somehow
     * bypassed or the resulting bytes altered before sending.
     */
    fun validate(data: ByteArray) {
        require(data.size == 34) { "Nachrichtenlänge falsch." }
        require(data.first() == 0xf0.toByte() && data.last() == 0xf7.toByte()) {
            "SysEx-Grenzen falsch."
        }
        require(data.copyOfRange(0, PREFIX.size).contentEquals(PREFIX)) {
            "Header falsch."
        }
        fun unpack(start: Int, count: Int): ByteArray = ByteArray(count) { i ->
            val high = data[start + 2 * i].toInt()
            val low = data[start + 2 * i + 1].toInt()
            require(high in 0..15 && low in 0..15) { "Nibble ungültig." }
            (high * 16 + low).toByte()
        }
        val algorithm = ByteBuffer.wrap(unpack(13, 4)).order(ByteOrder.LITTLE_ENDIAN).int
        require(algorithm == ALGORITHM_CODE) { "Algorithmus falsch." }
        val index = ByteBuffer.wrap(unpack(21, 2)).order(ByteOrder.LITTLE_ENDIAN).short.toInt()
        require(index == PARAMETER_INDEX) { "Parameterindex falsch." }
        val value = ByteBuffer.wrap(unpack(25, 4)).order(ByteOrder.LITTLE_ENDIAN).float
        require(value.isFinite() && value in MIN_VALUE..MAX_VALUE) {
            "Zielwert außerhalb des bestätigten Bereichs."
        }
    }
}
