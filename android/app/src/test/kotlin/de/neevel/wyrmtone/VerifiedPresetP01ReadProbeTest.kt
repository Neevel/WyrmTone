package de.neevel.wyrmtone

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VerifiedPresetP01ReadProbeTest {
    private class SendPort(private val failAt: Int? = null) : VerifiedPresetP01ReadSendPort {
        var sends = 0
        var closes = 0
        override fun sendVerifiedPresetP01ReadRequest() {
            ++sends
            if (sends == failAt) error("send failure")
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

    @Test fun `reference is the exact fixed 17 byte connect-sync trigger`() {
        assertArrayEquals(
            byteArrayOf(
                0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
                0x12, 0x13, 0x01, 0x00, 0x02, 0x00, 0x00, 0x01, 0xf7.toByte(),
            ),
            VerifiedPresetP01ReadRequestReference.bytes(),
        )
    }

    @Test fun `probe sends exactly once, listens for the fixed window, then reports collected chunks`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val delays = mutableListOf<Long>()
        val probe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = delays::add,
        )

        val result = probe.sendVerifiedPresetP01ReadProbe()

        assertTrue(result["success"] as Boolean)
        assertEquals(1, sendPort.sends)
        assertEquals(1, sendPort.closes)
        assertEquals(listOf(3000L), delays)
        assertEquals(1, receivePort.connectCalls)
        assertEquals(1, receivePort.disconnectCalls)
        assertEquals(1, receivePort.closes)
    }

    @Test fun `receiver is attached before the request is sent`() {
        val sendPort = object : VerifiedPresetP01ReadSendPort {
            var sentWhileConnected = false
            override fun sendVerifiedPresetP01ReadRequest() {}
            override fun close() {}
        }
        val receivePort = ReceivePort()
        var connectedBeforeSend = false
        val probe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = {
                connectedBeforeSend = receivePort.connectCalls == 1
                sendPort
            },
            openReceivePort = { receivePort },
            delay = {},
        )
        probe.sendVerifiedPresetP01ReadProbe()
        assertTrue(connectedBeforeSend)
    }

    @Test fun `collected device bytes are returned as chunks with timestamps`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = { receivePort.receiver?.invoke(byteArrayOf(0x01, 0x02), 123L) },
        )

        val result = probe.sendVerifiedPresetP01ReadProbe()

        @Suppress("UNCHECKED_CAST")
        val chunks = result["chunks"] as List<Map<String, Any?>>
        assertEquals(1, chunks.size)
        assertArrayEquals(byteArrayOf(0x01, 0x02), chunks.single()["bytes"] as ByteArray)
        assertEquals(123L, chunks.single()["timestampNanos"])
    }

    @Test fun `bytes arriving after the window closes are not collected`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {},
        )
        probe.sendVerifiedPresetP01ReadProbe()
        // Simulate a stray callback arriving after close(); it must be a no-op.
        receivePort.receiver?.invoke(byteArrayOf(0x09), 1L)
    }

    @Test fun `first error aborts without retry`() {
        val sendPort = SendPort(failAt = 1)
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {},
        )
        val result = probe.sendVerifiedPresetP01ReadProbe()
        assertFalse(result["success"] as Boolean)
        assertEquals(1, sendPort.sends)
    }

    @Test fun `probe is consumed once per connection including failure`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {},
        )
        assertTrue(probe.sendVerifiedPresetP01ReadProbe()["success"] as Boolean)
        val second = probe.sendVerifiedPresetP01ReadProbe()
        assertFalse(second["success"] as Boolean)
        assertEquals(1, sendPort.sends)
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
            val probe = VerifiedPresetP01ReadProbe(
                eligibility = { state },
                openSendPort = { ++opens; SendPort() },
                openReceivePort = { ++opens; ReceivePort() },
                delay = {},
            )
            assertFalse(probe.sendVerifiedPresetP01ReadProbe()["success"] as Boolean)
            assertEquals(0, opens)
        }
    }

    @Test fun `pause or detach between opening and sending prevents the send`() {
        val pauseSend = SendPort()
        val pauseReceive = ReceivePort()
        lateinit var pauseProbe: VerifiedPresetP01ReadProbe
        pauseProbe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { pauseProbe.cancel(); pauseSend },
            openReceivePort = { pauseReceive },
            delay = {},
        )
        assertFalse(pauseProbe.sendVerifiedPresetP01ReadProbe()["success"] as Boolean)
        assertEquals(0, pauseSend.sends)

        val detachSend = SendPort()
        val detachReceive = ReceivePort()
        lateinit var detachProbe: VerifiedPresetP01ReadProbe
        detachProbe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { detachProbe.detached("usb/box"); detachSend },
            openReceivePort = { detachReceive },
            delay = {},
        )
        assertFalse(detachProbe.sendVerifiedPresetP01ReadProbe()["success"] as Boolean)
        assertEquals(0, detachSend.sends)
    }

    @Test fun `real disconnect and reconnect of the same device resets the one-shot state`() {
        val firstSend = SendPort()
        val firstReceive = ReceivePort()
        var currentSend = firstSend
        var currentReceive = firstReceive
        val probe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { currentSend },
            openReceivePort = { currentReceive },
            delay = {},
        )

        assertTrue(probe.sendVerifiedPresetP01ReadProbe()["success"] as Boolean)
        assertFalse(probe.sendVerifiedPresetP01ReadProbe()["success"] as Boolean)
        assertEquals(1, firstSend.sends)

        // A real USB detach followed by a fresh connect for the SAME device
        // (same connection id, e.g. "usb/box") must clear the latch: the
        // probe is one-shot per *connection*, not permanently spent for a
        // device identity.
        probe.detached("usb/box")
        currentSend = SendPort()
        currentReceive = ReceivePort()

        val afterReconnect = probe.sendVerifiedPresetP01ReadProbe()
        assertTrue(afterReconnect["success"] as Boolean)
        assertEquals(1, currentSend.sends)
    }

    @Test fun `detaching a different connection does not reset this one's latch`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {},
        )
        assertTrue(probe.sendVerifiedPresetP01ReadProbe()["success"] as Boolean)

        probe.detached("usb/some-other-device")

        assertFalse(probe.sendVerifiedPresetP01ReadProbe()["success"] as Boolean)
        assertEquals(1, sendPort.sends)
    }

    @Test fun `fragmented device responses across several callbacks are collected in order`() {
        val sendPort = SendPort()
        val receivePort = ReceivePort()
        val probe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { sendPort },
            openReceivePort = { receivePort },
            delay = {
                // Simulates Android's MidiReceiver.onSend firing multiple
                // times for one logical SysEx response, as real USB-MIDI
                // delivery does.
                receivePort.receiver?.invoke(byteArrayOf(0xf0.toByte(), 0x21, 0x25), 10L)
                receivePort.receiver?.invoke(byteArrayOf(0x7f, 0x51, 0x4d), 20L)
                receivePort.receiver?.invoke(byteArrayOf(0x45, 0x32, 0xf7.toByte()), 30L)
            },
        )

        val result = probe.sendVerifiedPresetP01ReadProbe()

        @Suppress("UNCHECKED_CAST")
        val chunks = result["chunks"] as List<Map<String, Any?>>
        assertEquals(3, chunks.size)
        assertArrayEquals(byteArrayOf(0xf0.toByte(), 0x21, 0x25), chunks[0]["bytes"] as ByteArray)
        assertArrayEquals(byteArrayOf(0x7f, 0x51, 0x4d), chunks[1]["bytes"] as ByteArray)
        assertArrayEquals(byteArrayOf(0x45, 0x32, 0xf7.toByte()), chunks[2]["bytes"] as ByteArray)
        assertEquals(listOf(10L, 20L, 30L), chunks.map { it["timestampNanos"] })
    }

    @Test fun `cancel during the listening window still closes the receive port`() {
        val receivePort = ReceivePort()
        lateinit var probe: VerifiedPresetP01ReadProbe
        probe = VerifiedPresetP01ReadProbe(
            eligibility = { eligible() },
            openSendPort = { SendPort() },
            openReceivePort = { receivePort },
            delay = { probe.cancel() },
        )
        val result = probe.sendVerifiedPresetP01ReadProbe()
        assertNull(result["error"])
        assertEquals(1, receivePort.disconnectCalls)
        assertEquals(1, receivePort.closes)
    }
}
