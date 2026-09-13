package de.neevel.wyrmtone

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MidiDeviceMatcherTest {
    private val matriboxUsb = AttachedUsbIdentity("/dev/bus/usb/002/002", 0x84EF, 0x0054)

    @Test
    fun recognizesMatriboxFromUsbIdentity() {
        assertTrue(
            MidiDeviceMatcher.isMatribox(
                midi(usbVendorId = 0x84EF, usbProductId = 0x0054),
                emptyList(),
            ),
        )
    }

    @Test
    fun correlatesDescriptorsWithAttachedMatribox() {
        assertTrue(
            MidiDeviceMatcher.isMatribox(
                midi(manufacturer = "SONICAKE AUDIO", product = "MatriBox PRODUCT"),
                listOf(matriboxUsb),
            ),
        )
        assertFalse(
            MidiDeviceMatcher.isMatribox(
                midi(manufacturer = "Other", product = "Keyboard"),
                listOf(matriboxUsb),
            ),
        )
    }

    @Test
    fun correlatesExactUsbDeviceNameWithoutDescriptors() {
        assertTrue(
            MidiDeviceMatcher.isMatribox(
                midi(usbDeviceName = matriboxUsb.deviceName),
                listOf(matriboxUsb),
            ),
        )
    }

    private fun midi(
        manufacturer: String? = null,
        product: String? = null,
        usbDeviceName: String? = null,
        usbVendorId: Int? = null,
        usbProductId: Int? = null,
    ) = MidiIdentity(
        manufacturer = manufacturer,
        product = product,
        name = null,
        usbDeviceName = usbDeviceName,
        usbVendorId = usbVendorId,
        usbProductId = usbProductId,
    )
}
