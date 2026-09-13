package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SupportedUsbDeviceProfilesTest {
    private val interrupt = 3
    private val bulk = 2

    @Test
    fun recognizesDnafxMatriboxAndUnknownIds() {
        assertEquals(
            SupportedUsbDeviceType.DNAFX_GIT_CORE,
            SupportedUsbDeviceProfiles.find(0x0483, 0x5703)?.type,
        )
        assertEquals(
            SupportedUsbDeviceType.SONICAKE_MATRIBOX_ONE,
            SupportedUsbDeviceProfiles.find(0x84EF, 0x0054)?.type,
        )
        assertNull(SupportedUsbDeviceProfiles.find(0x1234, 0x5678))
    }

    @Test
    fun acceptsOnlyObservedMatriboxMidiStreamingInterface() {
        val descriptor = matriboxDescriptor()

        assertTrue(
            MatriboxUsbDeviceProfile.matchesInterface(descriptor, interrupt, bulk),
        )
        assertFalse(MatriboxUsbDeviceProfile.forceClaim)
    }

    @Test
    fun noSupportedProfileUsesForcedClaim() {
        assertTrue(SupportedUsbDeviceProfiles.all.none { it.forceClaim })
    }

    @Test
    fun rejectsAudioInterfacesAndEndpointDeviations() {
        val audio = matriboxDescriptor().copy(
            id = 1,
            interfaceSubclass = 2,
        )
        val wrongOut = matriboxDescriptor().copy(
            endpoints = listOf(
                endpoint(0x83, 0x80, 64),
                endpoint(0x04, 0x00, 256),
            ),
        )
        val wrongPacketSize = matriboxDescriptor().copy(
            endpoints = listOf(
                endpoint(0x83, 0x80, 64),
                endpoint(0x03, 0x00, 64),
            ),
        )

        assertFalse(MatriboxUsbDeviceProfile.matchesInterface(audio, interrupt, bulk))
        assertFalse(MatriboxUsbDeviceProfile.matchesInterface(wrongOut, interrupt, bulk))
        assertFalse(
            MatriboxUsbDeviceProfile.matchesInterface(wrongPacketSize, interrupt, bulk),
        )
    }

    private fun matriboxDescriptor() = UsbInterfaceDescriptor(
        id = 3,
        alternateSetting = 0,
        interfaceClass = 1,
        interfaceSubclass = 3,
        interfaceProtocol = 0,
        endpoints = listOf(
            endpoint(0x83, 0x80, 64),
            endpoint(0x03, 0x00, 256),
        ),
    )

    private fun endpoint(address: Int, direction: Int, maxPacketSize: Int) =
        UsbEndpointDescriptor(
            address = address,
            transferType = bulk,
            direction = direction,
            maxPacketSize = maxPacketSize,
        )
}
