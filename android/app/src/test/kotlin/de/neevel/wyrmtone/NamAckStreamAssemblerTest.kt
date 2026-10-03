package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NamAckStreamAssemblerTest {
    private fun ack(block: Int = 0, status: Int = 0x01): ByteArray {
        val prefix = byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x12, 0x00, 0x10, 0x13,
        )
        val bytes = mutableListOf<Byte>()
        bytes.addAll(prefix.toList())
        bytes.add(0x04) // Clone 5 slot
        bytes.add((block ushr 7).toByte())
        bytes.add((block and 0x7f).toByte())
        bytes.add(status.toByte())
        bytes.add(0xf7.toByte())
        return bytes.toByteArray()
    }

    // A: 18-byte ACK in one callback -> exactly one ACK.
    @Test
    fun `A - single callback with one full ACK yields exactly one message`() {
        val assembler = NamAckStreamAssembler()
        val out = assembler.feed(ack(block = 5))
        assertEquals(1, out.size)
        assertTrue(out[0].contentEquals(ack(block = 5)))
        assertFalse(assembler.hasIncompleteMessage)
    }

    // B: ACK split across 2 callbacks -> exactly one ACK.
    @Test
    fun `B - ACK fragmented across two callbacks yields exactly one message`() {
        val assembler = NamAckStreamAssembler()
        val full = ack(block = 9)
        val first = assembler.feed(full.copyOfRange(0, 10))
        assertTrue(first.isEmpty())
        assertTrue(assembler.hasIncompleteMessage)
        val second = assembler.feed(full.copyOfRange(10, full.size))
        assertEquals(1, second.size)
        assertTrue(second[0].contentEquals(full))
        assertFalse(assembler.hasIncompleteMessage)
    }

    // C: ACK fragmented across many callbacks (1 byte at a time) -> exactly one ACK.
    @Test
    fun `C - ACK fragmented byte-by-byte across many callbacks yields exactly one message`() {
        val assembler = NamAckStreamAssembler()
        val full = ack(block = 100)
        val collected = mutableListOf<ByteArray>()
        for (b in full) {
            collected += assembler.feed(byteArrayOf(b))
        }
        assertEquals(1, collected.size)
        assertTrue(collected[0].contentEquals(full))
    }

    // D: two complete SysEx in one callback -> exactly two messages.
    @Test
    fun `D - two complete ACKs in one callback yield exactly two messages`() {
        val assembler = NamAckStreamAssembler()
        val combined = ack(block = 1) + ack(block = 2)
        val out = assembler.feed(combined)
        assertEquals(2, out.size)
        assertTrue(out[0].contentEquals(ack(block = 1)))
        assertTrue(out[1].contentEquals(ack(block = 2)))
    }

    // E: end of one ACK + start of the next in the same callback -> correct framing.
    @Test
    fun `E - end of one ACK and start of the next in the same callback frame correctly`() {
        val assembler = NamAckStreamAssembler()
        val a = ack(block = 3)
        val b = ack(block = 4)
        val firstPart = assembler.feed(a.copyOfRange(0, a.size - 3))
        assertTrue(firstPart.isEmpty())
        // remaining 3 bytes of `a` (including its F7) + start of `b`
        val boundary = a.copyOfRange(a.size - 3, a.size) + b.copyOfRange(0, 5)
        val secondPart = assembler.feed(boundary)
        assertEquals(1, secondPart.size)
        assertTrue(secondPart[0].contentEquals(a))
        assertTrue(assembler.hasIncompleteMessage) // `b` is mid-flight
        val rest = assembler.feed(b.copyOfRange(5, b.size))
        assertEquals(1, rest.size)
        assertTrue(rest[0].contentEquals(b))
    }

    // F: garbage before F0 -> deterministic safe behavior (ignored, no crash, no message).
    @Test
    fun `F - garbage before the first F0 is safely ignored`() {
        val assembler = NamAckStreamAssembler()
        val out = assembler.feed(byteArrayOf(0x01, 0x02, 0x03))
        assertTrue(out.isEmpty())
        assertFalse(assembler.hasIncompleteMessage)
        // A subsequent real ACK still frames correctly.
        val real = assembler.feed(ack(block = 7))
        assertEquals(1, real.size)
    }

    // G: F0 without F7 -> bounded incomplete state, no ACK emitted.
    @Test
    fun `G - F0 without a following F7 stays incomplete, no message emitted`() {
        val assembler = NamAckStreamAssembler()
        val out = assembler.feed(ack(block = 1).copyOfRange(0, 13)) // prefix only, no trailer
        assertTrue(out.isEmpty())
        assertTrue(assembler.hasIncompleteMessage)
    }

    // H: new F0 before the previous F7 -> deterministic malformed/reset behavior.
    @Test
    fun `H - a new F0 before the previous F7 discards the incomplete message and starts fresh`() {
        val assembler = NamAckStreamAssembler()
        assembler.feed(ack(block = 1).copyOfRange(0, 10)) // incomplete first message
        val full = ack(block = 2)
        val out = assembler.feed(full) // starts a NEW F0 immediately
        assertEquals(1, out.size)
        assertTrue(out[0].contentEquals(full))
    }

    // I: oversized SysEx -> abort/reset without unbounded memory.
    @Test
    fun `I - an oversized SysEx resets deterministically without growing without bound`() {
        val assembler = NamAckStreamAssembler(maxBytes = 32)
        val oversized = byteArrayOf(0xf0.toByte()) + ByteArray(100) { 0x01 } + byteArrayOf(0xf7.toByte())
        val out = assembler.feed(oversized)
        assertTrue(out.isEmpty())
        assertFalse(assembler.hasIncompleteMessage)
        // Assembler recovers cleanly for the next real message.
        val real = assembler.feed(ack(block = 3, status = 0x01))
        assertEquals(1, real.size)
    }

    // J: offset/count subrange -- only the selected bytes are processed (the caller is
    // responsible for slicing; this proves the assembler itself does not read past what it's
    // given).
    @Test
    fun `J - only the bytes actually passed in are processed, nothing beyond`() {
        val assembler = NamAckStreamAssembler()
        val full = ack(block = 6)
        val backing = ByteArray(full.size + 10) { 0x00 }
        full.copyInto(backing, 5)
        // Simulate offset=5,count=full.size slicing, exactly like the native receive callback
        // wrapper does before calling feed().
        val sliced = backing.copyOfRange(5, 5 + full.size)
        val out = assembler.feed(sliced)
        assertEquals(1, out.size)
        assertTrue(out[0].contentEquals(full))
    }
}
