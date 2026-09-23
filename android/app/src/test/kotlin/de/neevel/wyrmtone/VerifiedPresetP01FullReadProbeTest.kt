package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VerifiedPresetP01FullReadProbeTest {
    private class SendPort : VerifiedPresetP01FullReadSendPort {
        val sentPartIndices = mutableListOf<Int>()
        var closes = 0
        override fun sendPartRequest(partIndex: Int) {
            sentPartIndices.add(partIndex)
        }
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

    /** A structurally valid, matching response for [partIndex]. */
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

    /** Feeds the given complete SysEx to the current receiver, split across [pieces] callbacks. */
    private fun deliver(port: ReceivePort, bytes: ByteArray, pieces: Int = 1, timestamp: Long = 1L) {
        val chunkSize = (bytes.size + pieces - 1) / pieces
        var offset = 0
        while (offset < bytes.size) {
            val end = minOf(offset + chunkSize, bytes.size)
            port.receiver?.invoke(bytes.copyOfRange(offset, end), timestamp)
            offset = end
        }
    }

    @Test fun `reference holds exactly the ten confirmed fixed requests`() {
        assertEquals(10, VerifiedPresetP01FullReadReference.requests.size)
        assertEquals(17, VerifiedPresetP01FullReadReference.requests[0].size)
        for (i in 1..8) assertEquals(19, VerifiedPresetP01FullReadReference.requests[i].size)
        assertEquals(19, VerifiedPresetP01FullReadReference.requests[9].size)
        assertEquals(
            listOf(210, 210, 210, 210, 210, 210, 210, 210, 46, 18),
            VerifiedPresetP01FullReadReference.expectedResponseLengths,
        )
    }

    @Test fun `full ten-part sequence succeeds when every part responds correctly`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                val part = sendPort.sentPartIndices.last()
                deliver(receivePort, validResponse(part))
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbe()

        assertTrue(result["success"] as Boolean)
        assertNull(result["error"])
        assertEquals(10, result["completedParts"])
        assertTrue(result["fullyComplete"] as Boolean)
        assertEquals((0..9).toList(), sendPort.sentPartIndices)
        @Suppress("UNCHECKED_CAST")
        val chunks = result["chunks"] as List<Map<String, Any?>>
        assertEquals(10, chunks.size)
    }

    @Test fun `fragmented responses across several callbacks still advance the sequence`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                val part = sendPort.sentPartIndices.last()
                // Deliver every response split into several small callbacks.
                deliver(receivePort, validResponse(part), pieces = 7)
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbe()

        assertTrue(result["fullyComplete"] as Boolean)
        assertEquals(10, result["completedParts"])
    }

    @Test fun `an incomplete SysEx fragment does not advance the sequence`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                val part = sendPort.sentPartIndices.last()
                val full = validResponse(part)
                // Deliver only the first half; no closing F7 ever arrives.
                receivePort.receiver?.invoke(full.copyOfRange(0, full.size / 2), 1L)
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbe()

        assertEquals(1, sendPort.sentPartIndices.size) // stopped after part 0, never retried
        assertEquals(0, result["completedParts"])
        assertEquals("Teil 0: Timeout nach 500 ms.", result["stopReason"])
        assertTrue(result["success"] as Boolean) // a stalled readback is not a native error
    }

    @Test fun `a complete but non-matching SysEx does not advance and stops`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                val part = sendPort.sentPartIndices.last()
                // Respond with the WRONG part's structure (off-by-one).
                deliver(receivePort, validResponse((part + 1).coerceAtMost(9)))
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbe()

        assertEquals(1, sendPort.sentPartIndices.size)
        assertEquals(0, result["completedParts"])
        assertTrue((result["stopReason"] as String).contains("unerwartete Antwort"))
        assertTrue(result["success"] as Boolean)
    }

    @Test fun `timeout with zero bytes stops after the current part, no retry`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                val part = sendPort.sentPartIndices.last()
                if (part < 3) deliver(receivePort, validResponse(part))
                // else: silence -- simulates the device stopping mid-sequence.
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbe()

        assertEquals(listOf(0, 1, 2, 3), sendPort.sentPartIndices) // stops right after part 3 fails
        assertEquals(3, result["completedParts"])
        assertEquals("Teil 3: Timeout nach 500 ms.", result["stopReason"])
    }

    @Test fun `every part is sent at most once -- no retry even after a failure`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {}, // Never deliver anything -> part 0 always times out.
        )

        probe.sendVerifiedPresetP01FullReadProbe()

        assertEquals(listOf(0), sendPort.sentPartIndices)
        assertEquals(sendPort.sentPartIndices.size, sendPort.sentPartIndices.toSet().size)
    }

    @Test fun `probe is consumed once per connection`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = { deliver(receivePort, validResponse(sendPort.sentPartIndices.last())) },
        )

        assertTrue(probe.sendVerifiedPresetP01FullReadProbe()["fullyComplete"] as Boolean)
        val second = probe.sendVerifiedPresetP01FullReadProbe()
        assertFalse(second["success"] as Boolean)
        assertEquals(10, sendPort.sentPartIndices.size) // no additional sends on the blocked second call
    }

    @Test fun `real disconnect and reconnect of the same device resets the one-shot state`() {
        var currentSend = SendPort()
        var currentReceive = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbe(
            eligibility = { eligible() },
            openSendPort = { currentSend },
            openReceivePort = { currentReceive },
            delay = { deliver(currentReceive, validResponse(currentSend.sentPartIndices.last())) },
        )

        assertTrue(probe.sendVerifiedPresetP01FullReadProbe()["fullyComplete"] as Boolean)
        assertFalse(probe.sendVerifiedPresetP01FullReadProbe()["success"] as Boolean)

        probe.detached("usb/box")
        currentSend = SendPort()
        currentReceive = ReceivePort()

        val afterReconnect = probe.sendVerifiedPresetP01FullReadProbe()
        assertTrue(afterReconnect["fullyComplete"] as Boolean)
        assertEquals(10, currentSend.sentPartIndices.size)
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
            val probe = VerifiedPresetP01FullReadProbe(
                eligibility = { state },
                openSendPort = { ++opens; SendPort() },
                openReceivePort = { ++opens; ReceivePort() },
                delay = {},
            )
            assertFalse(probe.sendVerifiedPresetP01FullReadProbe()["success"] as Boolean)
            assertEquals(0, opens)
        }
    }

    @Test fun `raw hex is logged for every completed and every failed step`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01FullReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                val part = sendPort.sentPartIndices.last()
                if (part < 2) deliver(receivePort, validResponse(part))
            },
        )

        val result = probe.sendVerifiedPresetP01FullReadProbe()

        @Suppress("UNCHECKED_CAST")
        val steps = result["steps"] as List<Map<String, Any?>>
        assertEquals(3, steps.size) // parts 0, 1 succeed, part 2 fails and stops
        assertTrue((steps[0]["requestHex"] as String).startsWith("F0 21 25"))
        assertTrue((steps[0]["responseHex"] as String).startsWith("F0"))
        assertNull(steps[2]["responseHex"])
        assertEquals(true, steps[2]["timedOut"])
        val logs = result["logs"] as List<*>
        assertTrue(logs.any { (it as String).startsWith("[") && it.contains("REQUEST_PART_0") })
        assertTrue(logs.any { (it as String).contains("RESPONSE_PART_0") })
        assertTrue(logs.any { (it as String).contains("TIMEOUT_PART_2") })
    }
}
