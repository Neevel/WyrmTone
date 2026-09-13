package de.neevel.wyrmtone

import android.content.Context
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.media.midi.MidiDevice
import android.media.midi.MidiDeviceInfo
import android.media.midi.MidiManager
import android.media.midi.MidiReceiver
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Receive-only diagnostics: only device Output-Port -> app receiver is allowed.
 * There is no input-port, transmitter or device-write operation.
 */
class MidiDiagnosticsManager(
    context: Context,
    private val emitEvent: (Map<String, Any?>) -> Unit,
    private val emitCapture: (Map<String, Any?>) -> Unit,
) {
    private val midiManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        context.getSystemService(Context.MIDI_SERVICE) as? MidiManager
    } else {
        null
    }
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val session = ReadOnlyMidiSession()
    private var callbackRegistered = false
    private var openedMidiDevice: MidiDevice? = null
    private var openedInfo: MidiDeviceInfo? = null
    private var openGeneration = 0
    private var disposed = false
    private val batchBuffer = MidiCaptureBatchBuffer()
    private val monitor = PassiveMidiMonitor(
        openOutput = { number ->
            val output = requireNotNull(openedMidiDevice?.openOutputPort(number)) {
                "Matribox-Output-Port konnte nicht geöffnet werden."
            }
            object : ReceiveOnlyMidiPort {
                private var receiver: MidiReceiver? = null
                override fun connect(receive: (ByteArray, Long) -> Unit) {
                    val receiving = object : MidiReceiver() {
                        override fun onSend(data: ByteArray, offset: Int, count: Int, timestamp: Long) {
                            // Callback only: no call to send or flush is made.
                            if (count > 4096) {
                                receive(ByteArray(0), timestamp)
                                return
                            }
                            if (count > 0 && offset >= 0 && offset <= data.size - count) {
                                receive(data.copyOfRange(offset, offset + count), timestamp)
                            }
                        }
                    }
                    receiver = receiving
                    output.connect(receiving)
                }
                override fun disconnect() { receiver?.let { output.disconnect(it) }; receiver = null }
                override fun close() { output.close() }
            }
        },
        receive = { data, timestamp ->
            batchBuffer.add(data, 0, if (data.isEmpty()) 4097 else data.size, timestamp, System.currentTimeMillis())
        },
    )
    private val deliverBatch = object : Runnable {
        override fun run() {
            if (!monitor.monitoring) return
            val (chunks, dropped) = batchBuffer.drain()
            if (chunks.isNotEmpty() || dropped > 0) {
                emitCapture(mapOf("type" to "batch", "dropped" to dropped,
                    "chunks" to chunks.map { mapOf("bytes" to it.bytes,
                        "timestampNanos" to it.timestampNanos, "receivedAtMillis" to it.receivedAtMillis) }))
            }
            mainHandler.postDelayed(this, 50)
        }
    }

    private val callback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        object : MidiManager.DeviceCallback() {
            override fun onDeviceAdded(device: MidiDeviceInfo) = devicesChanged()

            override fun onDeviceRemoved(device: MidiDeviceInfo) {
                if (session.deviceId == device.id) { closeDevice(); connectionClosed("midiRemoved") }
                ++openGeneration
                devicesChanged()
            }
        }
    } else {
        null
    }

    fun start() {
        val manager = midiManager ?: return
        val deviceCallback = callback ?: return
        if (!callbackRegistered) {
            manager.registerDeviceCallback(deviceCallback, mainHandler)
            callbackRegistered = true
        }
    }

    fun listDevices(): List<Map<String, Any?>> =
        midiManager?.devices?.map(::deviceToMap).orEmpty()

    fun openDevice(
        deviceId: Int,
        onSuccess: (Map<String, Any?>) -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        val manager = midiManager
        if (manager == null) {
            onError(IllegalStateException("Android MIDI wird auf diesem Gerät nicht unterstützt."))
            return
        }
        val info = manager.devices.firstOrNull { it.id == deviceId }
        if (info == null) {
            onError(IllegalStateException("MIDI-Gerät wurde entfernt oder nicht gefunden."))
            return
        }
        val mapped = deviceToMap(info)
        if (mapped["isMatribox"] != true) {
            onError(IllegalArgumentException("Nur das zugeordnete Matribox-MIDI-Gerät darf geöffnet werden."))
            return
        }
        if (session.deviceId == deviceId && session.isOpen) {
            onSuccess(statusMap())
            return
        }

        val token = ++openGeneration
        manager.openDevice(
            info,
            { device: MidiDevice? ->
                if (device == null) {
                    onError(IllegalStateException("MidiManager konnte das Gerät nicht öffnen."))
                    return@openDevice
                }
                if (disposed || token != openGeneration ||
                    manager.devices.none { it.id == info.id } ||
                    usbManager.deviceList[mapped["usbDeviceName"]] == null) {
                    device.close()
                    onError(IllegalStateException("MIDI-Öffnen durch Lifecycle oder Detach abgebrochen."))
                    return@openDevice
                }
                stopCapture()
                session.opened(
                    deviceId = info.id,
                    usbDeviceName = mapped["usbDeviceName"] as String?,
                    handle = ReadOnlyMidiHandle { device.close() },
                )
                openedMidiDevice = device
                openedInfo = info
                onSuccess(statusMap())
            },
            mainHandler,
        )
    }

    fun closeDevice() {
        ++openGeneration
        stopCapture()
        session.close()
        openedMidiDevice = null
        openedInfo = null
    }

    fun startCapture(): Int {
        require(session.isOpen && openedMidiDevice != null) { "Matribox-MIDI-Gerät ist nicht geöffnet." }
        require(usbManager.deviceList[session.usbDeviceName] != null) { "Matribox-USB-Gerät wurde getrennt." }
        val info = requireNotNull(openedInfo)
        require(deviceToMap(info)["isMatribox"] == true) { "MIDI-Gerät nicht eindeutig zugeordnet." }
        val output = requireNotNull(info.ports.singleOrNull { it.type == MidiDeviceInfo.PortInfo.TYPE_OUTPUT }) {
            "Kein eindeutiger Matribox-Output-Port vorhanden."
        }
        if (!monitor.monitoring) {
            batchBuffer.clear()
            monitor.start(output.portNumber)
            mainHandler.postDelayed(deliverBatch, 50)
        }
        return output.portNumber
    }

    fun blocksRawUsb(deviceName: String): Boolean = session.isOpen && session.usbDeviceName == deviceName

    fun stopCapture() {
        monitor.stop()
        mainHandler.removeCallbacks(deliverBatch)
        batchBuffer.clear()
    }

    fun pause() {
        closeDevice()
        emitCapture(mapOf("type" to "stopped", "reason" to "appPause"))
        connectionClosed("appPause")
    }

    fun statusMap(): Map<String, Any?> = mapOf(
        "isOpen" to session.isOpen,
        "deviceId" to session.deviceId,
        "monitoring" to monitor.monitoring,
        "outputPort" to monitor.outputPortNumber,
    )

    fun onUsbDetached(deviceName: String?) {
        ++openGeneration
        if (deviceName != null && session.usbDeviceName == deviceName) {
            closeDevice(); connectionClosed("usbDetached")
        }
    }

    private fun deviceToMap(info: MidiDeviceInfo): Map<String, Any?> {
        val properties = info.properties
        @Suppress("DEPRECATION")
        val usbDevice = properties.getParcelable(MidiDeviceInfo.PROPERTY_USB_DEVICE) as? UsbDevice
        val identity = MidiIdentity(
            manufacturer = properties.getString(MidiDeviceInfo.PROPERTY_MANUFACTURER),
            product = properties.getString(MidiDeviceInfo.PROPERTY_PRODUCT),
            name = properties.getString(MidiDeviceInfo.PROPERTY_NAME),
            usbDeviceName = usbDevice?.deviceName,
            usbVendorId = usbDevice?.vendorId,
            usbProductId = usbDevice?.productId,
        )
        val attached = usbManager.deviceList.values.map {
            AttachedUsbIdentity(it.deviceName, it.vendorId, it.productId)
        }
        val isMatribox = MidiDeviceMatcher.isMatribox(identity, attached)
        val matchedUsbDeviceName = identity.usbDeviceName ?: attached
            .singleOrNull {
                isMatribox &&
                    it.vendorId == MatriboxUsbDeviceProfile.vendorId &&
                    it.productId == MatriboxUsbDeviceProfile.productId
            }
            ?.deviceName
        return mapOf(
            "id" to info.id,
            "name" to identity.name,
            "manufacturer" to identity.manufacturer,
            "product" to identity.product,
            "usbDeviceName" to matchedUsbDeviceName,
            "inputPortCount" to info.inputPortCount,
            "outputPortCount" to info.outputPortCount,
            "isMatribox" to isMatribox,
            "ports" to info.ports.map { port ->
                mapOf(
                    "number" to port.portNumber,
                    "direction" to if (port.type == MidiDeviceInfo.PortInfo.TYPE_INPUT) {
                        "input"
                    } else {
                        "output"
                    },
                    "name" to port.name,
                )
            },
        )
    }

    private fun devicesChanged() {
        emitEvent(mapOf("type" to "midiDevicesChanged"))
    }

    private fun connectionClosed(reason: String) {
        emitCapture(mapOf("type" to "stopped", "reason" to reason))
        emitEvent(mapOf("type" to "midiConnectionClosed", "reason" to reason))
    }

    fun dispose() {
        disposed = true
        if (callbackRegistered && callback != null) {
            runCatching { midiManager?.unregisterDeviceCallback(callback) }
            callbackRegistered = false
        }
        closeDevice()
    }
}
