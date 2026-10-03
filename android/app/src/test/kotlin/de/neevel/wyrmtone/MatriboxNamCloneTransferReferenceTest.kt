package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class MatriboxNamCloneTransferReferenceTest {
    /** Builds a well-formed, valid Clone-5 block frame for [block] (0..587) with payload [fill]. */
    private fun frame(block: Int, slot: Int = MatriboxNamCloneTransferReference.CLONE5_SLOT, fill: Int = 0x00): ByteArray {
        val prefix = byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x12, 0x00, 0x10, 0x13,
        )
        val nibbles = IntArray(28) { fill and 0x0f }
        val sum = nibbles.sum() and 0xff
        val bytes = mutableListOf<Byte>()
        bytes.addAll(prefix.toList())
        bytes.add(slot.toByte())
        bytes.add((block ushr 7).toByte())
        bytes.add((block and 0x7f).toByte())
        nibbles.forEach { bytes.add(it.toByte()) }
        bytes.add(((sum shr 4) and 0x0f).toByte())
        bytes.add((sum and 0x0f).toByte())
        bytes.add(0xf7.toByte())
        return bytes.toByteArray()
    }

    @Test
    fun `a well-formed Clone-5 frame validates and round-trips its bytes`() {
        val bytes = frame(block = 0)
        val parsed = MatriboxNamCloneTransferReference.parseValidated(bytes)
        assertTrue(parsed.bytes.contentEquals(bytes))
    }

    @Test
    fun `every Clone slot 1 to 5 (0x00 to 0x04) validates and reports its own slot`() {
        for (slot in 0x00..0x04) {
            val parsed = MatriboxNamCloneTransferReference.parseValidated(frame(block = 0, slot = slot))
            assertEquals(slot, parsed.slot)
        }
    }

    @Test
    fun `any slot outside 0x00 to 0x04 is rejected, even a well-formed frame otherwise`() {
        for (badSlot in listOf(0x05, 0x06, 0x7f)) {
            assertThrows(IllegalArgumentException::class.java) {
                MatriboxNamCloneTransferReference.parseValidated(frame(block = 0, slot = badSlot))
            }
        }
    }

    @Test
    fun `wrong length is rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxNamCloneTransferReference.parseValidated(frame(block = 0).copyOf(46))
        }
    }

    @Test
    fun `wrong prefix is rejected`() {
        val bytes = frame(block = 0)
        bytes[0] = 0x00
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxNamCloneTransferReference.parseValidated(bytes)
        }
    }

    @Test
    fun `block number above the known range is rejected`() {
        val bytes = frame(block = 0)
        // Force an out-of-range block number directly into the byte layout.
        bytes[14] = (600 ushr 7).toByte()
        bytes[15] = (600 and 0x7f).toByte()
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxNamCloneTransferReference.parseValidated(bytes)
        }
    }

    @Test
    fun `a tampered checksum is rejected`() {
        val bytes = frame(block = 5)
        bytes[44] = (bytes[44] + 1).toByte()
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxNamCloneTransferReference.parseValidated(bytes)
        }
    }

    @Test
    fun `a missing F7 trailer is rejected`() {
        val bytes = frame(block = 0)
        bytes[46] = 0x00
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxNamCloneTransferReference.parseValidated(bytes)
        }
    }

    @Test
    fun `the maximum known block number is accepted, one above it is not`() {
        MatriboxNamCloneTransferReference.parseValidated(frame(block = MatriboxNamCloneTransferReference.MAX_BLOCK))
        val bytes = frame(block = 0)
        val over = MatriboxNamCloneTransferReference.MAX_BLOCK + 1
        bytes[14] = (over ushr 7).toByte()
        bytes[15] = (over and 0x7f).toByte()
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxNamCloneTransferReference.parseValidated(bytes)
        }
    }

    // Release hardening V1 safety matrix, asserted on the COMPILED flags of whichever variant
    // this test is built against (JVM unit tests only run the debug variant here; the release
    // half of the matrix is pinned statically in test/native_safety_static_test.dart, which
    // reads android/app/build.gradle.kts):
    //
    //   variant | NAM Clone write | Tone transfer | P01 raw backup
    //   --------+-----------------+---------------+---------------
    //   release | open            | closed        | closed
    //   debug   | closed*         | closed*       | closed*        (* unless an explicit dart-define)

    @Test
    fun `the NAM Clone write gate follows the variant - open in release, closed in a plain debug build`() {
        assertEquals(!BuildConfig.DEBUG, BuildConfig.REAL_MATRIBOX_WRITE)
    }

    @Test
    fun `tone transfer and P01 raw backup stay closed in every plain variant`() {
        // They are diagnostics/research paths, never shipped: closed in release (hardcoded
        // false) and in a debug build that does not pass their own explicit dart-define.
        assertFalse(BuildConfig.ENABLE_MATRIBOX_TONE_TRANSFER)
        assertFalse(BuildConfig.ENABLE_MATRIBOX_P01_RAW_BACKUP)
    }

    @Test
    fun `opening the NAM Clone gate does not open any other write path`() {
        // The three gates are independent: REAL_MATRIBOX_WRITE is never derived from, and never
        // implies, the other two.
        if (BuildConfig.REAL_MATRIBOX_WRITE) {
            assertFalse(BuildConfig.ENABLE_MATRIBOX_TONE_TRANSFER)
            assertFalse(BuildConfig.ENABLE_MATRIBOX_P01_RAW_BACKUP)
        }
    }
}
