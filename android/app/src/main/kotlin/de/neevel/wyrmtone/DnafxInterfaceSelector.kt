package de.neevel.wyrmtone

/** Pure descriptor logic, kept independent from Android USB objects for JVM tests. */
data class UsbEndpointDescriptor(
    val address: Int,
    val transferType: Int,
    val direction: Int = -1,
    val maxPacketSize: Int = -1,
)

data class UsbInterfaceDescriptor(
    val id: Int,
    val alternateSetting: Int = 0,
    val interfaceClass: Int = -1,
    val interfaceSubclass: Int = -1,
    val interfaceProtocol: Int = -1,
    val endpoints: List<UsbEndpointDescriptor>,
)

object DnafxInterfaceSelector {
    const val EXPECTED_INTERFACE_ID = 0
    const val EXPECTED_IN_ADDRESS = 0x81
    const val EXPECTED_OUT_ADDRESS = 0x02

    fun matches(descriptor: UsbInterfaceDescriptor, expectedTransferType: Int): Boolean {
        if (descriptor.id != EXPECTED_INTERFACE_ID) return false
        val matchingAddresses = descriptor.endpoints
            .filter { endpoint -> endpoint.transferType == expectedTransferType }
            .map { endpoint -> endpoint.address }
            .toSet()
        return EXPECTED_IN_ADDRESS in matchingAddresses &&
            EXPECTED_OUT_ADDRESS in matchingAddresses
    }
}
