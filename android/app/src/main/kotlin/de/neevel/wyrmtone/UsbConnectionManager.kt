package de.neevel.wyrmtone

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/**
 * Owns the Android USB lifecycle. Deliberately contains no controlTransfer,
 * bulkTransfer or UsbRequest calls: milestone one is descriptor-only.
 */
class UsbConnectionManager(
    private val context: Context,
    private val emitEvent: (Map<String, Any?>) -> Unit,
    private val onUsbDetached: (String?) -> Unit = {},
) {
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private val permissionAction = "${context.packageName}.USB_PERMISSION"
    private var connection: UsbDeviceConnection? = null
    private var claimedInterface: UsbInterface? = null
    private var connectedDeviceName: String? = null
    private var receiversRegistered = false

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(receivedContext: Context?, intent: Intent?) {
            if (intent?.action != permissionAction) return
            val device = intent.usbDeviceExtra()
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            emitEvent(
                mapOf(
                    "type" to "permissionResult",
                    "deviceName" to device?.deviceName,
                    "granted" to granted,
                ),
            )
        }
    }

    private val deviceReceiver = object : BroadcastReceiver() {
        override fun onReceive(receivedContext: Context?, intent: Intent?) {
            val device = intent?.usbDeviceExtra()
            when (intent?.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> emitEvent(
                    mapOf("type" to "attached", "deviceName" to device?.deviceName),
                )
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val wasConnected = synchronized(lock) {
                        device?.deviceName != null && device.deviceName == connectedDeviceName
                    }
                    if (wasConnected) closeNow()
                    onUsbDetached(device?.deviceName)
                    emitEvent(
                        mapOf("type" to "detached", "deviceName" to device?.deviceName),
                    )
                }
            }
        }
    }

    fun start() {
        if (receiversRegistered) return
        registerReceiver(permissionReceiver, IntentFilter(permissionAction), exported = false)
        val deviceFilter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        // USB attach/detach originates outside this app, so this receiver must be exported.
        registerReceiver(deviceReceiver, deviceFilter, exported = true)
        receiversRegistered = true
    }

    private fun registerReceiver(
        receiver: BroadcastReceiver,
        filter: IntentFilter,
        exported: Boolean,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(
                receiver,
                filter,
                if (exported) Context.RECEIVER_EXPORTED else Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            context.registerReceiver(receiver, filter)
        }
    }

    fun listDevicesAsync(
        onSuccess: (List<Map<String, Any?>>) -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        ioExecutor.execute {
            runCatching { usbManager.deviceList.values.map(::deviceToMap) }
                .onSuccess { devices -> mainHandler.post { onSuccess(devices) } }
                .onFailure { error -> mainHandler.post { onError(error) } }
        }
    }

    fun requestPermission(deviceName: String) {
        val device = requireDevice(deviceName)
        requireNotNull(SupportedUsbDeviceProfiles.find(device.vendorId, device.productId)) {
            "Das ausgewählte USB-Gerät wird nicht unterstützt."
        }
        if (usbManager.hasPermission(device)) {
            emitEvent(
                mapOf(
                    "type" to "permissionResult",
                    "deviceName" to device.deviceName,
                    "granted" to true,
                ),
            )
            return
        }
        val intent = Intent(permissionAction).setPackage(context.packageName)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        usbManager.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
    }

    fun openAsync(
        deviceName: String,
        onSuccess: (Map<String, Any?>) -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        ioExecutor.execute {
            runCatching { openNow(deviceName) }
                .onSuccess { status -> mainHandler.post { onSuccess(status) } }
                .onFailure { error -> mainHandler.post { onError(error) } }
        }
    }

    fun closeAsync(onComplete: () -> Unit) {
        ioExecutor.execute {
            closeNow()
            mainHandler.post(onComplete)
        }
    }

    fun connectionStatus(): Map<String, Any?> = synchronized(lock) { statusMap() }

    private fun openNow(deviceName: String): Map<String, Any?> = synchronized(lock) {
        if (connection != null && connectedDeviceName == deviceName) return statusMap()
        val device = requireDevice(deviceName)
        val profile = requireNotNull(
            SupportedUsbDeviceProfiles.find(device.vendorId, device.productId),
        ) { "Das ausgewählte USB-Gerät wird nicht unterstützt." }
        require(usbManager.hasPermission(device)) { "USB-Berechtigung wurde noch nicht erteilt." }

        val usbInterface = findExpectedInterface(device, profile)
            ?: error(
                "Das erwartete ${profile.expectedDescription} wurde nicht gefunden. " +
                    "Aus Sicherheitsgründen wird kein anderes Interface beansprucht.",
            )
        // Switching supported devices first releases the previous interface.
        // A second open for the same device returned above without another claim.
        closeLocked()
        val openedConnection = usbManager.openDevice(device)
            ?: error("UsbManager.openDevice hat keine Verbindung geliefert.")
        if (!openedConnection.claimInterface(usbInterface, profile.forceClaim)) {
            openedConnection.close()
            error(
                "Interface ${usbInterface.id} konnte ohne aggressiven Wiederholungsversuch nicht beansprucht werden.",
            )
        }

        connection = openedConnection
        claimedInterface = usbInterface
        connectedDeviceName = device.deviceName
        statusMap()
    }

    private fun findExpectedInterface(
        device: UsbDevice,
        profile: SupportedUsbDeviceProfile,
    ): UsbInterface? {
        return allInterfaces(device).firstOrNull { usbInterface ->
            profile.matchesInterface(
                UsbInterfaceDescriptor(
                    id = usbInterface.id,
                    alternateSetting = usbInterface.alternateSetting,
                    interfaceClass = usbInterface.interfaceClass,
                    interfaceSubclass = usbInterface.interfaceSubclass,
                    interfaceProtocol = usbInterface.interfaceProtocol,
                    endpoints = (0 until usbInterface.endpointCount).map { index ->
                        val endpoint = usbInterface.getEndpoint(index)
                        UsbEndpointDescriptor(
                            address = endpoint.address,
                            transferType = endpoint.type,
                            direction = endpoint.direction,
                            maxPacketSize = endpoint.maxPacketSize,
                        )
                    },
                ),
                interruptTransferType = UsbConstants.USB_ENDPOINT_XFER_INT,
                bulkTransferType = UsbConstants.USB_ENDPOINT_XFER_BULK,
            )
        }
    }

    private fun closeNow() = synchronized(lock) { closeLocked() }

    private fun closeLocked() {
        val currentConnection = connection
        val currentInterface = claimedInterface
        if (currentConnection != null && currentInterface != null) {
            runCatching { currentConnection.releaseInterface(currentInterface) }
        }
        runCatching { currentConnection?.close() }
        connection = null
        claimedInterface = null
        connectedDeviceName = null
    }

    private fun statusMap(): Map<String, Any?> = mapOf(
        "isOpen" to (connection != null),
        "deviceName" to connectedDeviceName,
        "claimedInterfaceId" to claimedInterface?.id,
    )

    private fun requireDevice(deviceName: String): UsbDevice =
        usbManager.deviceList[deviceName] ?: error("USB-Gerät wurde getrennt oder nicht gefunden.")

    private fun deviceToMap(device: UsbDevice): Map<String, Any?> {
        val hasPermission = usbManager.hasPermission(device)
        val interfaces = allInterfaces(device).map { usbInterface ->
            mapOf(
                "id" to usbInterface.id,
                "alternateSetting" to usbInterface.alternateSetting,
                "class" to usbInterface.interfaceClass,
                "subclass" to usbInterface.interfaceSubclass,
                "protocol" to usbInterface.interfaceProtocol,
                "endpoints" to (0 until usbInterface.endpointCount).map { index ->
                    val endpoint = usbInterface.getEndpoint(index)
                    mapOf(
                        "address" to endpoint.address,
                        "direction" to if (endpoint.direction == UsbConstants.USB_DIR_IN) "in" else "out",
                        "type" to transferTypeName(endpoint.type),
                        "maxPacketSize" to endpoint.maxPacketSize,
                        "interval" to endpoint.interval,
                    )
                },
            )
        }
        return mapOf(
            "deviceName" to device.deviceName,
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "deviceClass" to device.deviceClass,
            "deviceSubclass" to device.deviceSubclass,
            "deviceProtocol" to device.deviceProtocol,
            "configurationCount" to device.configurationCount,
            "hasPermission" to hasPermission,
            "manufacturerName" to safeDescriptor(hasPermission) { device.manufacturerName },
            "productName" to safeDescriptor(hasPermission) { device.productName },
            "serialNumber" to safeDescriptor(hasPermission) { device.serialNumber },
            "supportedDeviceType" to SupportedUsbDeviceProfiles
                .find(device.vendorId, device.productId)
                ?.type
                ?.wireName,
            "interfaces" to interfaces,
        )
    }

    private fun allInterfaces(device: UsbDevice): List<UsbInterface> {
        val interfaces = mutableListOf<UsbInterface>()
        for (configurationIndex in 0 until device.configurationCount) {
            val configuration = device.getConfiguration(configurationIndex)
            for (interfaceIndex in 0 until configuration.interfaceCount) {
                interfaces += configuration.getInterface(interfaceIndex)
            }
        }
        return interfaces
    }

    private fun safeDescriptor(hasPermission: Boolean, getter: () -> String?): String? {
        if (!hasPermission) return null
        return try {
            getter()
        } catch (_: SecurityException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun transferTypeName(type: Int): String = when (type) {
        UsbConstants.USB_ENDPOINT_XFER_CONTROL -> "control"
        UsbConstants.USB_ENDPOINT_XFER_ISOC -> "isochronous"
        UsbConstants.USB_ENDPOINT_XFER_BULK -> "bulk"
        UsbConstants.USB_ENDPOINT_XFER_INT -> "interrupt"
        else -> "unknown"
    }

    fun dispose() {
        if (receiversRegistered) {
            runCatching { context.unregisterReceiver(permissionReceiver) }
            runCatching { context.unregisterReceiver(deviceReceiver) }
            receiversRegistered = false
        }
        closeNow()
        ioExecutor.shutdownNow()
    }
}

private fun Intent.usbDeviceExtra(): UsbDevice? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
    } else {
        @Suppress("DEPRECATION")
        getParcelableExtra(UsbManager.EXTRA_DEVICE)
    }
}
