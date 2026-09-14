package de.neevel.wyrmtone

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VerifiedPresetP01ProbeTest {
    private class Port(private val failAt: Int? = null) : VerifiedPresetP01Port {
        var sends = 0
        var closes = 0
        override fun sendVerifiedPresetP01() {
            ++sends
            if (sends == failAt) error("send failure")
        }
        override fun close() { ++closes }
    }

    private fun eligible(
        enabled: Boolean = true,
        connection: String? = "usb/box",
        vendor: Int? = 0x84ef,
        product: Int? = 0x0054,
        open: Boolean = true,
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
        monitoring = false,
    )

    @Test fun `reference is the exact fixed 22 byte P01 message`() {
        assertArrayEquals(
            byteArrayOf(
                0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
                0x12, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0xf7.toByte(),
            ),
            VerifiedPresetP01Reference.bytes(),
        )
    }

    @Test fun `probe sends exactly twice with fixed three millisecond delay`() {
        val port = Port()
        val delays = mutableListOf<Long>()
        val probe = VerifiedPresetP01Probe({ eligible() }, { port }, delays::add)
        val result = probe.sendVerifiedPresetP01SelectionProbe()
        assertTrue(result["success"] as Boolean)
        assertEquals(2, result["sendCalls"])
        assertEquals(2, port.sends)
        assertEquals(listOf(3L), delays)
        assertEquals(1, port.closes)
    }

    @Test fun `first error aborts without retry or third send`() {
        val port = Port(failAt = 1)
        val probe = VerifiedPresetP01Probe({ eligible() }, { port }, {})
        val result = probe.sendVerifiedPresetP01SelectionProbe()
        assertFalse(result["success"] as Boolean)
        assertEquals(1, port.sends)
        assertEquals(1, result["sendCalls"])
    }

    @Test fun `probe is consumed once per connection including failure`() {
        val port = Port()
        val probe = VerifiedPresetP01Probe({ eligible() }, { port }, {})
        assertTrue(probe.sendVerifiedPresetP01SelectionProbe()["success"] as Boolean)
        assertFalse(probe.sendVerifiedPresetP01SelectionProbe()["success"] as Boolean)
        assertEquals(2, port.sends)
    }

    @Test fun `compile flag wrong device and missing connection block before opening`() {
        val states = listOf(
            eligible(enabled = false),
            eligible(vendor = 0),
            eligible(product = 0),
            eligible(connection = null),
            eligible(open = false),
        )
        for (state in states) {
            var opens = 0
            val probe = VerifiedPresetP01Probe({ state }, { ++opens; Port() }, {})
            assertFalse(probe.sendVerifiedPresetP01SelectionProbe()["success"] as Boolean)
            assertEquals(0, opens)
        }
    }

    @Test fun `pause or detach between calls prevents the second send`() {
        val pausePort = Port()
        lateinit var pauseProbe: VerifiedPresetP01Probe
        pauseProbe = VerifiedPresetP01Probe({ eligible() }, { pausePort }, { pauseProbe.cancel() })
        assertFalse(pauseProbe.sendVerifiedPresetP01SelectionProbe()["success"] as Boolean)
        assertEquals(1, pausePort.sends)

        val detachPort = Port()
        lateinit var detachProbe: VerifiedPresetP01Probe
        detachProbe = VerifiedPresetP01Probe({ eligible() }, { detachPort }, { detachProbe.detached("usb/box") })
        assertFalse(detachProbe.sendVerifiedPresetP01SelectionProbe()["success"] as Boolean)
        assertEquals(1, detachPort.sends)
    }
}
