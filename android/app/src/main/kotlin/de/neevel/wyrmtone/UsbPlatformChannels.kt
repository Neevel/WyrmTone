package de.neevel.wyrmtone

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class UsbPlatformChannels(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methodChannel = MethodChannel(messenger, "de.neevel.wyrmtone/usb_methods")
    // The preset reads and the tone transfer block for multi-second windows;
    // they must never run on the platform-channel/UI thread. Every other
    // method here completes fast enough to stay synchronous.
    private val mainHandler = Handler(Looper.getMainLooper())
    private val blockingExecutor = Executors.newSingleThreadExecutor()
    private val eventChannel = EventChannel(messenger, "de.neevel.wyrmtone/usb_events")
    private var eventSink: EventChannel.EventSink? = null
    private var captureSink: EventChannel.EventSink? = null
    private val captureChannel = EventChannel(messenger, "de.neevel.wyrmtone/midi_capture_events")
    private val midiManager = MidiDiagnosticsManager(
        context,
        emitEvent = { event -> eventSink?.success(event) },
        emitCapture = { event -> captureSink?.success(event) },
    )
    private val manager = UsbConnectionManager(
        context = context,
        emitEvent = { event -> eventSink?.success(event) },
        onUsbDetached = midiManager::onUsbDetached,
    )

    fun start() {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        captureChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { captureSink = events }
            override fun onCancel(arguments: Any?) { captureSink = null; midiManager.stopCapture() }
        })
        manager.start()
        midiManager.start()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listUsbDevices" -> manager.listDevicesAsync(
                onSuccess = result::success,
                onError = { error -> result.error("LIST_FAILED", error.message, null) },
            )
            "requestUsbPermission" -> withDeviceName(call, result) { deviceName ->
                manager.requestPermission(deviceName)
                result.success(null)
            }
            "openDevice" -> withDeviceName(call, result) { deviceName ->
                if (midiManager.blocksRawUsb(deviceName)) {
                    result.error("RAW_USB_BLOCKED", "Android verwaltet die geöffnete Matribox-MIDI-Schnittstelle.", null)
                    return@withDeviceName
                }
                manager.openAsync(
                    deviceName,
                    onSuccess = result::success,
                    onError = { error -> result.error("OPEN_FAILED", error.message, null) },
                )
            }
            "closeDevice" -> manager.closeAsync { result.success(null) }
            "getConnectionStatus" -> result.success(manager.connectionStatus())
            "listMidiDevices" -> result.success(midiManager.listDevices())
            "openMidiDevice" -> {
                val deviceId = call.argument<Int>("deviceId")
                if (deviceId == null) {
                    result.error("INVALID_ARGUMENT", "MIDI-Geräte-ID fehlt.", null)
                } else {
                    midiManager.openDevice(
                        deviceId,
                        onSuccess = result::success,
                        onError = { error -> result.error("MIDI_OPEN_FAILED", error.message, null) },
                    )
                }
            }
            "closeMidiDevice" -> {
                midiManager.closeDevice()
                result.success(null)
            }
            "getMidiConnectionStatus" -> result.success(midiManager.statusMap())
            "startMidiCapture" -> {
                try { result.success(midiManager.startCapture()) }
                catch (error: Exception) { result.error("MIDI_CAPTURE_FAILED", error.message, null) }
            }
            "stopMidiCapture" -> { midiManager.stopCapture(); result.success(null) }
            "getMatriboxPresetReaderStatus" -> result.success(midiManager.presetReaderStatus())
            "readMatriboxUserP01" -> {
                if (call.arguments != null) {
                    result.error("READER_ARGUMENTS_FORBIDDEN", "Der Raw-Backup-Read nimmt keine Argumente entgegen.", null)
                } else {
                    blockingExecutor.execute {
                        val outcome = runCatching { midiManager.readMatriboxUserP01() }
                        mainHandler.post {
                            outcome.onSuccess { result.success(it) }
                                .onFailure { error ->
                                    midiManager.closeDevice()
                                    result.error(
                                        "MATRIBOX_PRESET_READ_FAILED",
                                        "${error.message} Es wurde kein weiterer Leseversuch durchgeführt.",
                                        null,
                                    )
                                }
                        }
                    }
                }
            }
            "readMatriboxUserSlot" -> {
                // Exactly {targetBank: "USER", targetSlot: 11..99}. A protected P01..P10, Factory,
                // missing or malformed target is refused here, before the reader is ever reached.
                val arguments = call.arguments as? Map<*, *>
                val problem = if (arguments == null || arguments.keys != setOf("targetBank", "targetSlot")) {
                    "ARGUMENTS_INVALID" to "Nur targetBank und targetSlot sind erlaubt."
                } else {
                    MatriboxWritableUserPreset.contractProblem(arguments["targetBank"], arguments["targetSlot"])
                }
                if (problem != null) {
                    result.error("READER_${problem.first}", problem.second, null)
                } else {
                    val target = requireNotNull(
                        MatriboxWritableUserPreset.fromContract(arguments!!["targetBank"], arguments["targetSlot"]),
                    )
                    blockingExecutor.execute {
                        val outcome = runCatching { midiManager.readMatriboxUserSlot(target) }
                        mainHandler.post {
                            outcome.onSuccess { result.success(it) }
                                .onFailure { error ->
                                    midiManager.closeDevice()
                                    result.error(
                                        "MATRIBOX_PRESET_READ_FAILED",
                                        "${error.message} Es wurde kein weiterer Leseversuch durchgeführt.",
                                        null,
                                    )
                                }
                        }
                    }
                }
            }
            "getToneTransferStatus" -> result.success(midiManager.toneTransferStatus())
            "executeToneTransfer" -> {
                // Only the closed contract map (planId, targetBank, targetSlot, backupHash,
                // operations). The whole plan is validated natively before the first send;
                // no bytes, algorithm id or parameter index is ever accepted from Dart.
                val request = call.arguments
                blockingExecutor.execute {
                    val outcome = runCatching { midiManager.executeToneTransfer(request) }
                    mainHandler.post {
                        outcome.onSuccess { result.success(it) }
                            .onFailure { error ->
                                midiManager.closeDevice()
                                result.error(
                                    "TONE_TRANSFER_FAILED",
                                    "${error.message} Restliche Operationen wurden nicht gesendet.",
                                    null,
                                )
                            }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun withDeviceName(
        call: MethodCall,
        result: MethodChannel.Result,
        action: (String) -> Unit,
    ) {
        val deviceName = call.argument<String>("deviceName")
        if (deviceName.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Device Name fehlt.", null)
            return
        }
        action(deviceName)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        captureChannel.setStreamHandler(null)
        captureSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        manager.dispose()
        midiManager.dispose()
        blockingExecutor.shutdown()
    }

    fun pause() = midiManager.pause()
    fun resume() = midiManager.resume()
}
