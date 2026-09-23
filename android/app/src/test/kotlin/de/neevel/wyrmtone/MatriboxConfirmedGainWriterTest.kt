package de.neevel.wyrmtone

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MatriboxConfirmedGainWriterTest {
    private fun bytes(hex: String): ByteArray =
        ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }

    // Byte-for-byte against the same historical golden references used by
    // VerifiedGain41Reference and by the Dart-side confirmed_parameter_codec
    // golden test -- no semantic-only comparison.
    private val golden40 = bytes("f021257f514d453212100300020407000000000007000000000000000002000402f7")
    private val golden41 = bytes("f021257f514d453212100300020407000000000007000000000000000002040402f7")

    @Test fun `encodes Gain 41 byte-for-byte identical to the golden editor reference`() {
        assertArrayEquals(golden41, MatriboxConfirmedGainWriter.encode(41.0f))
    }

    @Test fun `encodes Gain 40 byte-for-byte identical to the golden editor reference`() {
        assertArrayEquals(golden40, MatriboxConfirmedGainWriter.encode(40.0f))
    }

    @Test fun `matches the existing VerifiedGain41Reference bytes exactly`() {
        assertArrayEquals(VerifiedGain41Reference.bytes(), MatriboxConfirmedGainWriter.encode(41.0f))
    }

    // Real host->device Gain messages extracted programmatically from the
    // original matribox1_p01_store.pcapng (no hand transcription).
    private val captured = listOf(
        29.0f to "f021257f514d45321210030002040700000000000700000000000000000e080401f7",
        23.0f to "f021257f514d45321210030002040700000000000700000000000000000b080401f7",
        17.0f to "f021257f514d453212100300020407000000000007000000000000000008080401f7",
    )

    @Test fun `reproduces real captured Gain messages byte-for-byte`() {
        for ((value, hex) in captured) {
            assertArrayEquals(hex, bytes(hex), MatriboxConfirmedGainWriter.encode(value))
        }
    }

    @Test fun `accepts the validated boundary values 0 and 99`() {
        MatriboxConfirmedGainWriter.encode(0.0f)
        MatriboxConfirmedGainWriter.encode(99.0f)
    }

    @Test fun `rejects a value below the validated range`() {
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxConfirmedGainWriter.encode(-1.0f)
        }
    }

    @Test fun `rejects a value above the validated range`() {
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxConfirmedGainWriter.encode(100.0f)
        }
    }

    @Test fun `rejects non-finite values`() {
        for (value in listOf(Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY)) {
            assertThrows(IllegalArgumentException::class.java) {
                MatriboxConfirmedGainWriter.encode(value)
            }
        }
    }

    @Test fun `validate accepts a freshly encoded message`() {
        MatriboxConfirmedGainWriter.validate(MatriboxConfirmedGainWriter.encode(18.0f))
    }

    @Test fun `validate rejects a message with a tampered algorithm code`() {
        val message = MatriboxConfirmedGainWriter.encode(41.0f).copyOf()
        message[13] = 0x09 // corrupt the first algorithm nibble
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxConfirmedGainWriter.validate(message)
        }
    }

    @Test fun `validate rejects a message with a tampered parameter index`() {
        val message = MatriboxConfirmedGainWriter.encode(41.0f).copyOf()
        message[21] = 0x01 // index becomes non-zero
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxConfirmedGainWriter.validate(message)
        }
    }

    @Test fun `validate rejects the wrong length`() {
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxConfirmedGainWriter.validate(MatriboxConfirmedGainWriter.encode(41.0f).copyOf(33))
        }
    }
}
