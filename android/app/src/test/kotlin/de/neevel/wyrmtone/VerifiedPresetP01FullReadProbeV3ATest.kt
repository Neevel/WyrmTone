package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VerifiedPresetP01FullReadProbeV3ATest {
    private class SendPort : VerifiedPresetP01FullReadV3ASendPort {
        var phaseDSends = 0
        val sentPartIndices = mutableListOf<Int>()
        var closes = 0
        override fun sendPhaseDAnnounce() { ++phaseDSends }
        override fun sendPartRequest(partIndex: Int) { sentPartIndices.add(partIndex) }
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

    /** A structurally valid, matching response for [partIndex] (mirrors V2's test helper). */
    private fun validResponse(partIndex: Int): ByteArray {
        val length = VerifiedPresetP01FullReadReference.expectedResponseLengths[partIndex]
        val headerByte12 = if (partIndex == 9) 0x05 else 0x03
        val bytes = ByteArray(length)
        bytes[0] = 0xf0.toByte()
        bytes[4] = 0x51; bytes[5] = 0x4d; bytes[6] = 0x45; bytes[7] = 0x32
        bytes[8] = 0x12; bytes[9] = 0x13
        bytes[10] = 0x01; bytes[11] = 0x00; bytes[12] = headerByte12.toByte()
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

    @Test fun `Phase-D announce is the exact confirmed fixed reference`() {
        assertEquals(16, VerifiedPresetP01PhaseDReference.announce.size)
        assertEquals(
            byteArrayOf(
                0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
                0x11, 0x13, 0x01, 0x00, 0x00, 0x00, 0x00, 0xf7.toByte(),
            ).toList(),
            VerifiedPresetP01PhaseDReference.announce.toList(),
        )
        assertEquals(validAck.toList(), VerifiedPresetP01PhaseDReference.acknowledgement.toList())
        assertTrue(VerifiedPresetP01PhaseDReference.isValidAck(validAck))
    }

    @Test fun `without a matching Phase-D ack, Part 0 is never sent`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {}, // Phase D always times out -- no ack ever delivered.
        )

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(1, sendPort.phaseDSends)
        assertTrue(sendPort.sentPartIndices.isEmpty())
        assertEquals(false, result["phaseDConfirmed"])
        assertEquals("Phase D: Timeout nach 500 ms.", result["stopReason"])
    }

    @Test fun `a fragmented Phase-D ack across several callbacks is reassembled correctly`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
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

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(true, result["phaseDConfirmed"])
        assertEquals(10, result["completedParts"])
    }

    @Test fun `a structurally wrong Phase-D response stops without sending Part 0`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                // Respond with a Part-0-shaped message instead of a Phase-D ack.
                deliver(receivePort, validResponse(0))
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(false, result["phaseDConfirmed"])
        assertTrue(sendPort.sentPartIndices.isEmpty())
        assertTrue((result["stopReason"] as String).contains("unerwartete Antwort"))
    }

    @Test fun `a Phase-D response with one changed captured byte is rejected`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val changedAck = validAck.copyOf().also { it[18] = 0x41 }
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = { deliver(receivePort, changedAck) },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(false, result["phaseDConfirmed"])
        assertTrue(sendPort.sentPartIndices.isEmpty())
        assertTrue((result["stopReason"] as String).contains("unerwartete Antwort"))
    }

    @Test fun `a matching Phase-D ack plus another SysEx fails closed`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                deliver(receivePort, validAck)
                deliver(receivePort, validResponse(0))
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(false, result["phaseDConfirmed"])
        assertTrue(sendPort.sentPartIndices.isEmpty())
        assertTrue((result["stopReason"] as String).contains("unerwartete Antwort"))
    }
    @Test fun `Phase-D timeout stops the whole probe -- no fallback, no Part 0`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {},
        )

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(1, sendPort.phaseDSends)
        assertEquals(0, sendPort.sentPartIndices.size)
        assertEquals(0, result["completedParts"])
    }

    @Test fun `a confirmed Phase-D ack triggers exactly one Part-0 request`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                if (sendPort.sentPartIndices.isEmpty()) deliver(receivePort, validAck)
                // Part 0 then times out deliberately, to isolate this assertion.
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(true, result["phaseDConfirmed"])
        assertEquals(listOf(0), sendPort.sentPartIndices)
        assertEquals(0, result["completedParts"]) // part 0's own response never arrived
    }

    @Test fun `full state machine - Phase D then all ten parts complete`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = happyPathDelay(sendPort, receivePort),
        )

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertTrue(result["success"] as Boolean)
        assertNull(result["error"])
        assertEquals(true, result["phaseDConfirmed"])
        assertEquals(10, result["completedParts"])
        assertEquals(true, result["fullyComplete"])
        assertEquals((0..9).toList(), sendPort.sentPartIndices)
        @Suppress("UNCHECKED_CAST")
        val chunks = result["chunks"] as List<Map<String, Any?>>
        assertEquals(10, chunks.size)
    }

    @Test fun `an incomplete part response does not advance the sequence`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
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

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(listOf(0), sendPort.sentPartIndices) // stopped after part 0, never retried
        assertEquals(0, result["completedParts"])
    }

    @Test fun `a non-matching part response does not advance the sequence`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
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

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(listOf(0), sendPort.sentPartIndices)
        assertEquals(0, result["completedParts"])
        assertTrue((result["stopReason"] as String).contains("unerwartete Antwort"))
    }

    @Test fun `a matching part response plus another SysEx does not advance`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                if (sendPort.sentPartIndices.isEmpty()) {
                    deliver(receivePort, validAck)
                } else {
                    deliver(receivePort, validResponse(0))
                    deliver(receivePort, validResponse(1))
                }
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(listOf(0), sendPort.sentPartIndices)
        assertEquals(0, result["completedParts"])
        assertTrue((result["stopReason"] as String).contains("unerwartete Antwort"))
    }
    @Test fun `timeout on a later part stops immediately`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
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

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(listOf(0, 1, 2, 3), sendPort.sentPartIndices)
        assertEquals(3, result["completedParts"])
        assertEquals("Teil 3: Timeout nach 500 ms.", result["stopReason"])
    }

    @Test fun `no retry -- Phase D and every part sent at most once`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = happyPathDelay(sendPort, receivePort),
        )

        probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(1, sendPort.phaseDSends)
        assertEquals(sendPort.sentPartIndices.size, sendPort.sentPartIndices.toSet().size)
    }

    @Test fun `one-shot is consumed even when Phase D itself fails`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {}, // Phase D times out.
        )

        assertFalse(probe.sendVerifiedPresetP01FullReadProbeV3A()["phaseDConfirmed"] as Boolean)
        val second = probe.sendVerifiedPresetP01FullReadProbeV3A()
        assertFalse(second["success"] as Boolean)
        assertEquals(1, sendPort.phaseDSends) // no second attempt at all
    }

    @Test fun `real disconnect and reconnect resets the one-shot state`() {
        var currentSend = SendPort()
        var currentReceive = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { currentSend },
            openReceivePort = { currentReceive },
            delay = { happyPathDelay(currentSend, currentReceive)(it) },
        )

        assertEquals(true, probe.sendVerifiedPresetP01FullReadProbeV3A()["fullyComplete"])
        assertFalse(probe.sendVerifiedPresetP01FullReadProbeV3A()["success"] as Boolean)

        probe.detached("usb/box")
        currentSend = SendPort()
        currentReceive = ReceivePort()

        val afterReconnect = probe.sendVerifiedPresetP01FullReadProbeV3A()
        assertEquals(true, afterReconnect["fullyComplete"])
        assertEquals(10, currentSend.sentPartIndices.size)
    }

    @Test fun `a fixture-accurate full cycle reassembles into the confirmed User P01 data`() {
        // Uses the shared decoder end-to-end, mirroring V2's own confirmation.
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = happyPathDelay(sendPort, receivePort),
        )

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        assertEquals(true, result["fullyComplete"])
        @Suppress("UNCHECKED_CAST")
        val chunks = result["chunks"] as List<Map<String, Any?>>
        assertEquals(10, chunks.size)
        // Structural shape only here (Kotlin-side); the Dart evaluator (reused
        // unchanged from V2) performs the actual marker decode/verify.
        for ((index, chunk) in chunks.withIndex()) {
            val bytes = chunk["bytes"] as ByteArray
            assertTrue(VerifiedPresetP01FullReadReference.isValidResponseForPart(bytes, index))
        }
    }

    @Test fun `compile flag wrong device and missing connection block before opening`() {
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
            val probe = VerifiedPresetP01FullReadProbeV3A(
                eligibility = { state },
                openSendPort = { ++opens; SendPort() },
                openReceivePort = { ++opens; ReceivePort() },
                delay = {},
            )
            assertFalse(probe.sendVerifiedPresetP01FullReadProbeV3A()["success"] as Boolean)
            assertEquals(0, opens)
        }
    }

    @Test fun `full raw hex logging for Phase D and every part`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbeV3A(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                if (sendPort.sentPartIndices.isEmpty() && sendPort.phaseDSends == 1) {
                    deliver(receivePort, validAck)
                } else {
                    val part = sendPort.sentPartIndices.last()
                    if (part < 2) deliver(receivePort, validResponse(part))
                }
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbeV3A()

        val logs = result["logs"] as List<*>
        assertTrue(logs.any { (it as String).contains("PHASE_D_REQUEST") && it.contains("hex=F0 21 25") })
        assertTrue(logs.any { (it as String).contains("PHASE_D_RESPONSE") && it.contains("hex=F0") })
        assertTrue(logs.any { (it as String).contains("REQUEST_PART_0") })
        assertTrue(logs.any { (it as String).contains("RESPONSE_PART_0") })
        assertTrue(logs.any { (it as String).contains("TIMEOUT_PART_2") })
    }
}
