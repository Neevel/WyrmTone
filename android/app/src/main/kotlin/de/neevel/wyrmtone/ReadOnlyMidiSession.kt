package de.neevel.wyrmtone

fun interface ReadOnlyMidiHandle {
    fun close()
}

/** Owns only a MidiDevice handle. It deliberately has no port or send API. */
class ReadOnlyMidiSession {
    var deviceId: Int? = null
        private set
    var usbDeviceName: String? = null
        private set
    private var handle: ReadOnlyMidiHandle? = null

    val isOpen: Boolean
        get() = handle != null

    fun opened(deviceId: Int, usbDeviceName: String?, handle: ReadOnlyMidiHandle) {
        close()
        this.deviceId = deviceId
        this.usbDeviceName = usbDeviceName
        this.handle = handle
    }

    fun close(): Boolean {
        val current = handle ?: return false
        runCatching { current.close() }
        handle = null
        deviceId = null
        usbDeviceName = null
        return true
    }

    fun onMidiDeviceRemoved(removedDeviceId: Int): Boolean =
        if (removedDeviceId == deviceId) close() else false

    fun onUsbDetached(detachedDeviceName: String?): Boolean =
        if (detachedDeviceName != null && detachedDeviceName == usbDeviceName) close() else false
}
