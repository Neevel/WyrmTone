package de.neevel.wyrmtone

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * CONFIRMED protocol evidence, pinned byte for byte: the references first confirmed by the historical
 * P01 probes (editor capture, read probe V2/V3A, preset-select probe) and used today by the productive
 * reader and transfer. The probe runners are gone; these literals must never change silently.
 */
class MatriboxProtocolReferencesTest {
    private fun bytes(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }
    private fun hex(b: ByteArray) = b.joinToString(" ") { "%02x".format(it) }

    @Test fun `the Phase-D announce and acknowledgement are the exact captured bytes`() {
        VerifiedPresetP01PhaseDReference.validateAnnounce()
        assertArrayEquals(
            bytes(0xf0, 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32, 0x11, 0x13, 0x01, 0x00, 0x00, 0x00, 0x00, 0xf7),
            VerifiedPresetP01PhaseDReference.announce,
        )
        val ack = bytes(0xf0, 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32, 0x12, 0x13, 0x01, 0x00, 0x01, 0x00, 0x00, 0x0c, 0x1c, 0x01, 0x40, 0xf7)
        assertArrayEquals(ack, VerifiedPresetP01PhaseDReference.acknowledgement)
        assertTrue(VerifiedPresetP01PhaseDReference.isValidAck(ack))
        // one changed captured byte is not the confirmed acknowledgement
        assertFalse(VerifiedPresetP01PhaseDReference.isValidAck(ack.copyOf().also { it[18] = 0x41 }))
    }

    @Test fun `the ten part requests and response lengths are the exact confirmed ones`() {
        VerifiedPresetP01FullReadReference.validate()
        val requests = VerifiedPresetP01FullReadReference.requests.map(::hex)
        assertEquals("f0 21 25 7f 51 4d 45 32 12 13 01 00 02 00 00 01 f7", requests[0])
        for (part in 1..9) {
            assertEquals("f0 21 25 7f 51 4d 45 32 12 13 01 00 04 00 00 00 %02x 01 f7".format(part - 1), requests[part])
        }
        assertEquals(listOf(210, 210, 210, 210, 210, 210, 210, 210, 46, 18), VerifiedPresetP01FullReadReference.expectedResponseLengths)
    }

    @Test fun `a part response is only valid with the confirmed length, header and part index`() {
        fun response(part: Int, length: Int = VerifiedPresetP01FullReadReference.expectedResponseLengths[part]): ByteArray =
            ByteArray(length).also {
                it[0] = 0xf0.toByte(); it[4] = 0x51; it[5] = 0x4d; it[6] = 0x45; it[7] = 0x32
                it[8] = 0x12; it[9] = 0x13; it[10] = 0x01; it[12] = (if (part == 9) 0x05 else 0x03).toByte()
                it[16] = part.toByte(); it[length - 1] = 0xf7.toByte()
            }
        for (part in 0..9) assertTrue("part $part", VerifiedPresetP01FullReadReference.isValidResponseForPart(response(part), part))
        assertFalse(VerifiedPresetP01FullReadReference.isValidResponseForPart(response(1), 2)) // other part index
        assertFalse(VerifiedPresetP01FullReadReference.isValidResponseForPart(response(0, 46), 0)) // wrong length
        assertFalse(VerifiedPresetP01FullReadReference.isValidResponseForPart(response(3).also { it[9] = 0x12 }, 3)) // other family
    }

    @Test fun `the preset-select reference is the exact 22-byte editor message for index 0`() {
        val reference = bytes(0xf0, 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32, 0x12, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf7)
        assertArrayEquals(reference, VerifiedPresetP01Reference.bytes())
        VerifiedPresetP01Reference.validate(reference)
        // every call returns a fresh copy: a caller cannot mutate the reference
        VerifiedPresetP01Reference.bytes()[18] = 0x0a
        assertArrayEquals(reference, VerifiedPresetP01Reference.bytes())
        assertTrue(runCatching { VerifiedPresetP01Reference.validate(reference.copyOf().also { it[18] = 0x0a }) }.isFailure)
    }

    @Test fun `SysEx reassembly handles fragments and a fresh F0 discards an unfinished message`() {
        val accumulator = SysExAccumulator()
        assertTrue(accumulator.feed(bytes(0xf0, 0x21, 0x25)).isEmpty())
        val done = accumulator.feed(bytes(0x7f, 0xf7, 0x90, 0xf0, 0x01))
        assertEquals(listOf("f0 21 25 7f f7"), done.map(::hex))
        // the unfinished 0xf0 0x01 is dropped by the next start
        assertEquals(listOf("f0 02 f7"), accumulator.feed(bytes(0xf0, 0x02, 0xf7)).map(::hex))
    }
}
