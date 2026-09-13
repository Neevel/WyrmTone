package de.neevel.wyrmtone

data class AttachedUsbIdentity(
    val deviceName: String,
    val vendorId: Int,
    val productId: Int,
)

data class MidiIdentity(
    val manufacturer: String?,
    val product: String?,
    val name: String?,
    val usbDeviceName: String?,
    val usbVendorId: Int?,
    val usbProductId: Int?,
)

object MidiDeviceMatcher {
    fun isMatribox(
        midi: MidiIdentity,
        attachedUsbDevices: Collection<AttachedUsbIdentity>,
    ): Boolean {
        if (midi.usbVendorId == MatriboxUsbDeviceProfile.vendorId &&
            midi.usbProductId == MatriboxUsbDeviceProfile.productId
        ) {
            return true
        }

        val attachedMatriboxes = attachedUsbDevices.filter {
            it.vendorId == MatriboxUsbDeviceProfile.vendorId &&
                it.productId == MatriboxUsbDeviceProfile.productId
        }
        if (midi.usbDeviceName != null &&
            attachedMatriboxes.any { it.deviceName == midi.usbDeviceName }
        ) {
            return true
        }

        val descriptors = listOfNotNull(midi.manufacturer, midi.product, midi.name)
            .joinToString(" ")
            .lowercase()
        return attachedMatriboxes.size == 1 &&
            ("sonicake" in descriptors || "matribox" in descriptors)
    }
}
