package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadOnlyMidiSessionTest {
    @Test
    fun opensAndClosesDeviceHandle() {
        val handle = FakeHandle()
        val session = ReadOnlyMidiSession()

        session.opened(7, "/dev/bus/usb/002/002", handle)
        assertTrue(session.isOpen)
        assertEquals(7, session.deviceId)

        assertTrue(session.close())
        assertFalse(session.isOpen)
        assertEquals(1, handle.closeCalls)
    }

    @Test
    fun detachClosesOnlyMatchingUsbDevice() {
        val handle = FakeHandle()
        val session = ReadOnlyMidiSession()
        session.opened(7, "/dev/bus/usb/002/002", handle)

        assertFalse(session.onUsbDetached("/dev/bus/usb/001/001"))
        assertTrue(session.isOpen)
        assertTrue(session.onUsbDetached("/dev/bus/usb/002/002"))
        assertFalse(session.isOpen)
        assertEquals(1, handle.closeCalls)
    }

    @Test
    fun midiRemovalClosesMatchingDevice() {
        val handle = FakeHandle()
        val session = ReadOnlyMidiSession()
        session.opened(7, null, handle)

        assertFalse(session.onMidiDeviceRemoved(8))
        assertTrue(session.onMidiDeviceRemoved(7))
        assertEquals(1, handle.closeCalls)
    }

    private class FakeHandle : ReadOnlyMidiHandle {
        var closeCalls = 0
        override fun close() {
            closeCalls++
        }
    }
}
