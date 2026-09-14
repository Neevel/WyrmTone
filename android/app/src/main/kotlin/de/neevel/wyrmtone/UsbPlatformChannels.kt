package de.neevel.wyrmtone

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class UsbPlatformChannels(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methodChannel = MethodChannel(messenger, "de.neevel.wyrmtone/usb_methods")
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
            "getVerifiedPresetP01ProbeStatus" -> result.success(midiManager.presetP01ProbeStatus())
            "sendVerifiedPresetP01SelectionProbe" -> {
                if (call.arguments != null) {
                    result.error("PROBE_ARGUMENTS_FORBIDDEN", "Der P01-Einmaltest nimmt keine Argumente entgegen.", null)
                } else {
                    try { result.success(midiManager.sendVerifiedPresetP01SelectionProbe()) }
                    catch (error: Exception) {
                        midiManager.closeDevice()
                        result.error("P01_PROBE_FAILED", "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt.", null)
                    }
                }
            }
            "getVerifiedMatriboxProbeStatus" -> result.success(midiManager.writeProbeStatus())
            "sendVerifiedSol100OdGain41Probe" -> {
                if (call.arguments != null) {
                    result.error("PROBE_ARGUMENTS_FORBIDDEN", "Der Einmaltest nimmt keine Argumente entgegen.", null)
                } else {
                    try { result.success(midiManager.sendVerifiedSol100OdGain41Probe()) }
                    catch (error: Exception) {
                        midiManager.closeDevice()
                        result.error("PROBE_FAILED", "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt.", null)
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
    }

    fun pause() = midiManager.pause()
    fun resume() = midiManager.resume()
}
