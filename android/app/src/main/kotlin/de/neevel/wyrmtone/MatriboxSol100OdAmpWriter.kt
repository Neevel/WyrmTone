package de.neevel.wyrmtone

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The closed set of Sol 100 OD AMP knobs whose 34-byte QME2 write message
 * is byte-confirmed against the original editor capture
 * (matribox1_p01_store.pcapng). The parameter index is a property of the
 * enum entry -- no caller can supply one.
 */
enum class Sol100OdAmpField(val wireName: String, val parameterIndex: Int) {
    GAIN("gain", 0),
    PRESENCE("presence", 1),
    VOLUME("volume", 2),
    BASS("bass", 3),
    MIDDLE("middle", 4),
    TREBLE("treble", 5);

    companion object {
        /** Exact whitelist lookup; anything else is null, never guessed. */
        fun fromWireName(name: String?): Sol100OdAmpField? =
            values().firstOrNull { it.wireName == name }

        /** Fields the certification mode may send (Gain is already certified). */
        val CERTIFICATION_FIELDS = listOf(PRESENCE, VOLUME, BASS, MIDDLE, TREBLE)
    }
}

/**
 * ENCODABLE, not permission to send: this object only builds and
 * re-validates bytes. Whether a field may be sent is decided by
 * [MatriboxSol100OdCertificationSession]. Algorithm is fixed to
 * Sol 100 OD (0x07000047); there is no free algorithm, index or byte API.
 * Independent Kotlin implementation cross-checked byte-for-byte against
 * real capture messages (and the Dart MatriboxSol100OdEncoder) in tests.
 */
object MatriboxSol100OdAmpWriter {
    const val ALGORITHM_CODE = 0x07000047
    const val MIN_VALUE = 0.0f
    const val MAX_VALUE = 99.0f

    private val PREFIX = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x12, 0x10, 0x03, 0x00, 0x02,
    )

    fun encode(field: Sol100OdAmpField, value: Float): ByteArray {
        require(value.isFinite()) { "Wert ist nicht endlich." }
        require(value in MIN_VALUE..MAX_VALUE) {
            "Wert außerhalb des bestätigten Bereichs [$MIN_VALUE, $MAX_VALUE]: $value."
        }
        val payload = ByteBuffer.allocate(10).order(ByteOrder.LITTLE_ENDIAN)
        payload.putInt(ALGORITHM_CODE)
        payload.putShort(field.parameterIndex.toShort())
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

    /** Independent re-check of the actual bytes against the expected field. */
    fun validate(field: Sol100OdAmpField, data: ByteArray) {
        require(data.size == 34) { "Nachrichtenlänge falsch." }
        require(data.first() == 0xf0.toByte() && data.last() == 0xf7.toByte()) {
            "SysEx-Grenzen falsch."
        }
        require(data.copyOfRange(0, PREFIX.size).contentEquals(PREFIX)) { "Header falsch." }
        fun unpack(start: Int, count: Int): ByteArray = ByteArray(count) { i ->
            val high = data[start + 2 * i].toInt()
            val low = data[start + 2 * i + 1].toInt()
            require(high in 0..15 && low in 0..15) { "Nibble ungültig." }
            (high * 16 + low).toByte()
        }
        val algorithm = ByteBuffer.wrap(unpack(13, 4)).order(ByteOrder.LITTLE_ENDIAN).int
        require(algorithm == ALGORITHM_CODE) { "Algorithmus falsch." }
        val index = ByteBuffer.wrap(unpack(21, 2)).order(ByteOrder.LITTLE_ENDIAN).short.toInt()
        require(index == field.parameterIndex) { "Parameterindex passt nicht zum Feld." }
        val value = ByteBuffer.wrap(unpack(25, 4)).order(ByteOrder.LITTLE_ENDIAN).float
        require(value.isFinite() && value in MIN_VALUE..MAX_VALUE) { "Wert ungültig." }
    }
}
