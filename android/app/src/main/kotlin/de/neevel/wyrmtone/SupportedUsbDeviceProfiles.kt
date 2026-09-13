package de.neevel.wyrmtone

enum class SupportedUsbDeviceType(val wireName: String) {
    DNAFX_GIT_CORE("dnafxGitCore"),
    SONICAKE_MATRIBOX_ONE("sonicakeMatriboxOne"),
}

sealed interface SupportedUsbDeviceProfile {
    val type: SupportedUsbDeviceType
    val vendorId: Int
    val productId: Int
    val displayName: String
    val forceClaim: Boolean
    val expectedDescription: String

    fun matchesInterface(
        descriptor: UsbInterfaceDescriptor,
        interruptTransferType: Int,
        bulkTransferType: Int,
    ): Boolean
}

object DnafxUsbDeviceProfile : SupportedUsbDeviceProfile {
    override val type = SupportedUsbDeviceType.DNAFX_GIT_CORE
    override val vendorId = 0x0483
    override val productId = 0x5703
    override val displayName = "DNAfx GiT Core"
    override val forceClaim = false
    override val expectedDescription =
        "Interface 0 mit Interrupt-IN 0x81 und Interrupt-OUT 0x02"

    override fun matchesInterface(
        descriptor: UsbInterfaceDescriptor,
        interruptTransferType: Int,
        bulkTransferType: Int,
    ): Boolean = DnafxInterfaceSelector.matches(descriptor, interruptTransferType)
}

object MatriboxUsbDeviceProfile : SupportedUsbDeviceProfile {
    override val type = SupportedUsbDeviceType.SONICAKE_MATRIBOX_ONE
    override val vendorId = 0x84EF
    override val productId = 0x0054
    override val displayName = "Sonicake Matribox 1 – Kandidat"
    override val forceClaim = false
    override val expectedDescription =
        "Interface 3/Alt 0, Klasse 1/Subklasse 3, Bulk-IN 0x83 (64 Byte) und Bulk-OUT 0x03 (256 Byte)"

    override fun matchesInterface(
        descriptor: UsbInterfaceDescriptor,
        interruptTransferType: Int,
        bulkTransferType: Int,
    ): Boolean {
        if (descriptor.id != 3 ||
            descriptor.alternateSetting != 0 ||
            descriptor.interfaceClass != 1 ||
            descriptor.interfaceSubclass != 3 ||
            descriptor.interfaceProtocol != 0
        ) {
            return false
        }
        if (descriptor.endpoints.size != 2) return false
        val input = descriptor.endpoints.singleOrNull { endpoint ->
            endpoint.address == 0x83 &&
                endpoint.direction == 0x80 &&
                endpoint.transferType == bulkTransferType &&
                endpoint.maxPacketSize == 64
        }
        val output = descriptor.endpoints.singleOrNull { endpoint ->
            endpoint.address == 0x03 &&
                endpoint.direction == 0x00 &&
                endpoint.transferType == bulkTransferType &&
                endpoint.maxPacketSize == 256
        }
        return input != null && output != null
    }
}

object SupportedUsbDeviceProfiles {
    val all: List<SupportedUsbDeviceProfile> = listOf(
        DnafxUsbDeviceProfile,
        MatriboxUsbDeviceProfile,
    )

    fun find(vendorId: Int, productId: Int): SupportedUsbDeviceProfile? =
        all.firstOrNull { profile ->
            profile.vendorId == vendorId && profile.productId == productId
        }
}
