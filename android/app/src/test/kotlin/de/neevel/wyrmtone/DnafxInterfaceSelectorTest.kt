package de.neevel.wyrmtone

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DnafxInterfaceSelectorTest {
    private val interrupt = 3

    @Test
    fun acceptsHardwareVerifiedInterfaceAndInterruptEndpoints() {
        val descriptor = UsbInterfaceDescriptor(
            id = 0,
            endpoints = listOf(
                UsbEndpointDescriptor(0x81, interrupt),
                UsbEndpointDescriptor(0x02, interrupt),
            ),
        )

        assertTrue(DnafxInterfaceSelector.matches(descriptor, interrupt))
    }

    @Test
    fun rejectsUnknownInterfaceEvenWithMatchingEndpoints() {
        val descriptor = UsbInterfaceDescriptor(
            id = 1,
            endpoints = listOf(
                UsbEndpointDescriptor(0x81, interrupt),
                UsbEndpointDescriptor(0x02, interrupt),
            ),
        )

        assertFalse(DnafxInterfaceSelector.matches(descriptor, interrupt))
    }

    @Test
    fun rejectsNonInterruptOrIncompleteEndpoints() {
        val wrongType = UsbInterfaceDescriptor(
            id = 0,
            endpoints = listOf(
                UsbEndpointDescriptor(0x81, 2),
                UsbEndpointDescriptor(0x02, interrupt),
            ),
        )
        val incomplete = UsbInterfaceDescriptor(
            id = 0,
            endpoints = listOf(UsbEndpointDescriptor(0x81, interrupt)),
        )

        assertFalse(DnafxInterfaceSelector.matches(wrongType, interrupt))
        assertFalse(DnafxInterfaceSelector.matches(incomplete, interrupt))
    }
}
