package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MatriboxPresetReaderTest {
    private class SendPort : MatriboxPresetReaderSendPort {
        var phaseDSends = 0
        val sentPartIndices = mutableListOf<Int>()
        val addressedSlots = mutableListOf<MatriboxUserPreset>()
        var closes = 0
        override fun sendPhaseDAnnounce(slot: MatriboxUserPreset) { ++phaseDSends; addressedSlots.add(slot) }
        override fun sendPartRequest(slot: MatriboxUserPreset, partIndex: Int) { sentPartIndices.add(partIndex); addressedSlots.add(slot) }
        override fun close() { ++closes }
    }

    private class ReceivePort : ReceiveOnlyMidiPort {
        var connectCalls = 0
        var disconnectCalls = 0
        var closes = 0
        var receiver: ((ByteArray, Long) -> Unit)? = null
        override fun connect(receive: (ByteArray, Long) -> Unit) {
            ++connectCalls
            receiver = receive
        }
        override fun disconnect() { ++disconnectCalls; receiver = null }
        override fun close() { ++closes }
    }

    private fun eligible(
        enabled: Boolean = true,
        connection: String? = "usb/box",
        vendor: Int? = 0x84ef,
        product: Int? = 0x0054,
        open: Boolean = true,
        monitoring: Boolean = false,
    ) = ProbeEligibility(
        enabled = enabled,
        connection = connection,
        vendor = vendor,
        product = product,
        uniqueUsb = true,
        uniqueMidi = true,
        directlyMapped = true,
        deviceOpen = open,
        expectedInput = true,
        monitoring = monitoring,
    )

    private val validAck: ByteArray = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x12, 0x13, 0x01, 0x00, 0x01, 0x00, 0x00, 0x0c, 0x1c, 0x01, 0x40, 0xf7.toByte(),
    )

    /** A structurally valid, matching response for [partIndex] (mirrors V2/V3A's test helper). */
    private fun validResponse(partIndex: Int, deviceIndex: Int = 0): ByteArray {
        val length = VerifiedPresetP01FullReadReference.expectedResponseLengths[partIndex]
        val headerByte12 = if (partIndex == 9) 0x05 else 0x03
        val bytes = ByteArray(length)
        bytes[0] = 0xf0.toByte()
        bytes[4] = 0x51; bytes[5] = 0x4d; bytes[6] = 0x45; bytes[7] = 0x32
        bytes[8] = 0x12; bytes[9] = 0x13
        bytes[10] = 0x01; bytes[11] = 0x00; bytes[12] = headerByte12.toByte()
        bytes[14] = deviceIndex.toByte()
        bytes[16] = partIndex.toByte()
        bytes[length - 1] = 0xf7.toByte()
        return bytes
    }

    private fun deliver(port: ReceivePort, bytes: ByteArray, pieces: Int = 1, timestamp: Long = 1L) {
        val chunkSize = (bytes.size + pieces - 1) / pieces
        var offset = 0
        while (offset < bytes.size) {
            val end = minOf(offset + chunkSize, bytes.size)
            port.receiver?.invoke(bytes.copyOfRange(offset, end), timestamp)
            offset = end
        }
    }

    /** Default delay: answers Phase D, then every part request, in order. */
    private fun happyPathDelay(sendPort: SendPort, receivePort: ReceivePort): (Long) -> Unit = {
        if (sendPort.sentPartIndices.isEmpty() && sendPort.phaseDSends == 1) {
            deliver(receivePort, validAck)
        } else {
            deliver(receivePort, validResponse(sendPort.sentPartIndices.last()))
        }
    }

    @Test fun `happy path sends exactly Phase D plus the ten known requests, in order`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = happyPathDelay(sendPort, receivePort),
        )

        val result = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.SUCCESS, result.outcome)
        assertNull(result.error)
        assertEquals(1, sendPort.phaseDSends)
        assertEquals((0..9).toList(), sendPort.sentPartIndices)
        assertEquals(10, result.parts.size)
        assertEquals(validAck.toList(), result.phaseDResponse!!.toList())
        for ((index, part) in result.parts.withIndex()) {
            assertTrue(VerifiedPresetP01FullReadReference.isValidResponseForPart(part, index))
        }
    }

    @Test fun `no duplicated request bytes across a full run`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = happyPathDelay(sendPort, receivePort),
        )

        reader.readVerifiedUserP01()

        assertEquals(1, sendPort.phaseDSends)
        assertEquals(sendPort.sentPartIndices.size, sendPort.sentPartIndices.toSet().size)
    }

    @Test fun `without a matching Phase-D ack, Part 0 is never sent`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {}, // Phase D always times out.
        )

        val result = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.PHASE_D_TIMEOUT, result.outcome)
        assertEquals(1, sendPort.phaseDSends)
        assertTrue(sendPort.sentPartIndices.isEmpty())
        assertTrue(result.parts.isEmpty())
        assertNull(result.phaseDResponse)
    }

    @Test fun `a structurally wrong Phase-D response is rejected without sending Part 0`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = { deliver(receivePort, validResponse(0)) },
        )

        val result = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.PHASE_D_INVALID, result.outcome)
        assertTrue(sendPort.sentPartIndices.isEmpty())
    }

    @Test fun `a fragmented Phase-D ack across several callbacks is reassembled correctly`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                if (sendPort.sentPartIndices.isEmpty()) {
                    deliver(receivePort, validAck, pieces = 5)
                } else {
                    deliver(receivePort, validResponse(sendPort.sentPartIndices.last()))
                }
            },
        )

        val result = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.SUCCESS, result.outcome)
        assertEquals(10, result.parts.size)
    }

    @Test fun `an incomplete (fragmented, never finished) part response does not advance`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                if (sendPort.sentPartIndices.isEmpty()) {
                    deliver(receivePort, validAck)
                } else {
                    val full = validResponse(sendPort.sentPartIndices.last())
                    receivePort.receiver?.invoke(full.copyOfRange(0, full.size / 2), 1L)
                }
            },
        )

        val result = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.PART_TIMEOUT, result.outcome)
        assertEquals(listOf(0), sendPort.sentPartIndices) // stopped after part 0, never retried
        assertTrue(result.parts.isEmpty())
    }

    @Test fun `a non-matching part response stops immediately, no part sent afterwards`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                if (sendPort.sentPartIndices.isEmpty()) {
                    deliver(receivePort, validAck)
                } else {
                    val part = sendPort.sentPartIndices.last()
                    deliver(receivePort, validResponse((part + 1).coerceAtMost(9)))
                }
            },
        )

        val result = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.PART_INVALID, result.outcome)
        assertEquals(listOf(0), sendPort.sentPartIndices)
        assertTrue(result.parts.isEmpty())
    }

    @Test fun `timeout on a later part stops immediately with no further sends`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                if (sendPort.sentPartIndices.isEmpty()) {
                    deliver(receivePort, validAck)
                } else {
                    val part = sendPort.sentPartIndices.last()
                    if (part < 3) deliver(receivePort, validResponse(part))
                    // else: silence.
                }
            },
        )

        val result = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.PART_TIMEOUT, result.outcome)
        assertEquals(listOf(0, 1, 2, 3), sendPort.sentPartIndices)
        assertTrue(result.parts.isEmpty())
    }

    @Test fun `a matching ack plus another SysEx in the window fails closed`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                deliver(receivePort, validAck)
                deliver(receivePort, validResponse(0))
            },
        )

        val result = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.PHASE_D_INVALID, result.outcome)
        assertTrue(sendPort.sentPartIndices.isEmpty())
    }

    @Test fun `only TRANSPORT_ERROR is a genuine native failure -- port opening exception maps to it`() {
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { throw IllegalStateException("Matribox-Input-Port 0 konnte nicht geöffnet werden.") },
            openReceivePort = { ReceivePort() },
            delay = {},
        )

        val result = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.TRANSPORT_ERROR, result.outcome)
        assertTrue(result.parts.isEmpty())
    }

    @Test fun `compile flag, wrong device or missing connection block before opening any port`() {
        val states = listOf(
            eligible(enabled = false),
            eligible(vendor = 0),
            eligible(product = 0),
            eligible(connection = null),
            eligible(open = false),
            eligible(monitoring = true),
        )
        for (state in states) {
            var opens = 0
            val reader = MatriboxPresetReader(
                eligibility = { state },
                openSendPort = { ++opens; SendPort() },
                openReceivePort = { ++opens; ReceivePort() },
                delay = {},
            )
            val result = reader.readVerifiedUserP01()
            assertEquals(MatriboxPresetReadOutcome.TRANSPORT_ERROR, result.outcome)
            assertEquals(0, opens)
        }
    }

    @Test fun `not one-shot -- a second independent read after success also succeeds`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = happyPathDelay(sendPort, receivePort),
        )

        assertEquals(MatriboxPresetReadOutcome.SUCCESS, reader.readVerifiedUserP01().outcome)
        sendPort.sentPartIndices.clear()
        sendPort.phaseDSends = 0
        val second = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.SUCCESS, second.outcome)
        assertEquals(1, sendPort.phaseDSends)
        assertEquals((0..9).toList(), sendPort.sentPartIndices)
    }

    @Test fun `concurrent reads are rejected -- no overlapping attempt`() {
        lateinit var reader: MatriboxPresetReader
        var reentrantFailed = false
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                runCatching { reader.readVerifiedUserP01() }
                    .onFailure { reentrantFailed = true }
                if (sendPort.sentPartIndices.isEmpty() && sendPort.phaseDSends == 1) {
                    deliver(receivePort, validAck)
                } else {
                    deliver(receivePort, validResponse(sendPort.sentPartIndices.last()))
                }
            },
        )

        reader.readVerifiedUserP01()

        assertTrue(reentrantFailed)
    }

    @Test fun `ports are closed after every attempt, success or failure`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = happyPathDelay(sendPort, receivePort),
        )
        reader.readVerifiedUserP01()
        assertEquals(1, sendPort.closes)
        assertEquals(1, receivePort.closes)
        assertEquals(1, receivePort.disconnectCalls)

        val sendPort2 = SendPort()
        val receivePort2 = ReceivePort()
        val failingReader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort2 },
            openReceivePort = { receivePort2 },
            delay = {},
        )
        failingReader.readVerifiedUserP01()
        assertEquals(1, sendPort2.closes)
        assertEquals(1, receivePort2.closes)
    }

    @Test fun `cancel aborts an in-flight read via the lifecycle generation token`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        lateinit var reader: MatriboxPresetReader
        reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                reader.cancel()
                deliver(receivePort, validAck)
            },
        )

        val result = reader.readVerifiedUserP01()

        assertEquals(MatriboxPresetReadOutcome.PHASE_D_TIMEOUT, result.outcome)
        assertTrue(sendPort.sentPartIndices.isEmpty())
    }

    // ------------------------------------------------------------ multi-slot read (P11..P99)

    private fun hex(bytes: ByteArray) = bytes.joinToString(" ") { "%02x".format(it) }

    @Test fun `P01 addressing is byte-identical to the confirmed references`() {
        MatriboxUserSlotReadReference.validate()
        val p01 = MatriboxUserPreset.P01
        assertEquals(hex(VerifiedPresetP01PhaseDReference.announce), hex(MatriboxUserSlotReadReference.announce(p01)))
        assertEquals(hex(VerifiedPresetP01PhaseDReference.acknowledgement), hex(MatriboxUserSlotReadReference.acknowledgement(p01)))
        for (part in 0..9) {
            assertEquals(hex(VerifiedPresetP01FullReadReference.requests[part]), hex(MatriboxUserSlotReadReference.partRequest(p01, part)))
        }
    }

    @Test fun `a slot read replaces only the confirmed slot byte, P11 is index 0x0a, P99 index 0x62`() {
        for ((preset, index) in listOf(11 to 0x0a, 12 to 0x0b, 50 to 0x31, 99 to 0x62)) {
            val slot = MatriboxUserPreset.of(preset)
            assertEquals(index, slot.deviceIndex)
            assertEquals(slot, MatriboxUserPreset.fromDeviceIndex(index))
            val messages = listOf(
                VerifiedPresetP01PhaseDReference.announce to MatriboxUserSlotReadReference.announce(slot),
                VerifiedPresetP01PhaseDReference.acknowledgement to MatriboxUserSlotReadReference.acknowledgement(slot),
            ) + (0..9).map { VerifiedPresetP01FullReadReference.requests[it] to MatriboxUserSlotReadReference.partRequest(slot, it) }
            for ((reference, derived) in messages) {
                assertEquals(reference.size, derived.size)
                for (i in reference.indices) {
                    if (i == MatriboxUserSlotReadReference.SLOT_OFFSET) {
                        assertEquals(index.toByte(), derived[i])
                    } else {
                        assertEquals("offset $i", reference[i], derived[i])
                    }
                }
            }
        }
        // the references themselves are never mutated by a derivation
        assertEquals(0.toByte(), VerifiedPresetP01PhaseDReference.announce[MatriboxUserSlotReadReference.SLOT_OFFSET])
    }

    @Test fun `reading P37 addresses P37 in every request and accepts only P37 responses`() {
        val slot = MatriboxUserPreset.of(37)
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                if (sendPort.sentPartIndices.isEmpty()) {
                    deliver(receivePort, MatriboxUserSlotReadReference.acknowledgement(slot))
                } else {
                    deliver(receivePort, validResponse(sendPort.sentPartIndices.last(), deviceIndex = 36))
                }
            },
        )
        val result = reader.readVerifiedUserSlot(slot)
        assertEquals(MatriboxPresetReadOutcome.SUCCESS, result.outcome)
        assertEquals((0..9).toList(), sendPort.sentPartIndices)
        assertTrue(sendPort.addressedSlots.all { it == slot })
        assertTrue(result.parts.all { it[MatriboxUserSlotReadReference.SLOT_OFFSET] == 36.toByte() })
    }

    @Test fun `a response of another slot stops a slot read -- P11 never returns P01 or P12 data`() {
        val slot = MatriboxUserPreset.of(11)
        for (wrongIndex in listOf(0, 11)) {
            val sendPort = SendPort()
            val receivePort = ReceivePort()
            val reader = MatriboxPresetReader(
                eligibility = { eligible() },
                openSendPort = { sendPort },
                openReceivePort = { receivePort },
                delay = {
                    if (sendPort.sentPartIndices.isEmpty()) {
                        deliver(receivePort, MatriboxUserSlotReadReference.acknowledgement(slot))
                    } else {
                        deliver(receivePort, validResponse(sendPort.sentPartIndices.last(), deviceIndex = wrongIndex))
                    }
                },
            )
            val result = reader.readVerifiedUserSlot(slot)
            assertEquals(MatriboxPresetReadOutcome.PART_INVALID, result.outcome)
            assertEquals(listOf(0), sendPort.sentPartIndices)
            assertTrue(result.parts.isEmpty())
        }
    }

    @Test fun `the P01 acknowledgement does not satisfy a P11 read`() {
        val slot = MatriboxUserPreset.of(11)
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val reader = MatriboxPresetReader(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = { deliver(receivePort, validAck) },
        )
        val result = reader.readVerifiedUserSlot(slot)
        assertEquals(MatriboxPresetReadOutcome.PHASE_D_INVALID, result.outcome)
        assertTrue(sendPort.sentPartIndices.isEmpty())
    }

    @Test fun `only P11 to P99 can become a transfer read target`() {
        for (protected in listOf(1, 2, 5, 10)) {
            assertEquals("TARGET_PROTECTED", MatriboxWritableUserPreset.contractProblem("USER", protected)?.first)
            assertNull(MatriboxWritableUserPreset.fromContract("USER", protected))
        }
        for (invalid in listOf<Any?>(0, -1, 100, 255, null, "11", 11.0, 11.5)) {
            assertEquals("$invalid", "TARGET_NOT_ALLOWED", MatriboxWritableUserPreset.contractProblem("USER", invalid)?.first)
        }
        assertEquals("TARGET_NOT_ALLOWED", MatriboxWritableUserPreset.contractProblem("FACTORY", 11)?.first)
        assertEquals("TARGET_NOT_ALLOWED", MatriboxWritableUserPreset.contractProblem(null, 11)?.first)
        for (writable in listOf(11, 12, 50, 99)) {
            assertEquals(writable, MatriboxWritableUserPreset.fromContract("USER", writable)!!.presetNumber)
        }
        assertEquals(98, MatriboxWritableUserPreset.fromContract("USER", 99L)!!.deviceIndex)
    }
}
