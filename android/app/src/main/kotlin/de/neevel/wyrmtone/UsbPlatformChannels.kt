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
    // The read probes block for multi-second listening windows; they must
    // never run on the platform-channel/UI thread. Every other probe/method
    // here completes fast enough to stay synchronous.
    private val mainHandler = Handler(Looper.getMainLooper())
    private val blockingProbeExecutor = Executors.newSingleThreadExecutor()
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
            "getVerifiedPresetP01ReadProbeStatus" -> result.success(midiManager.p01ReadProbeStatus())
            "sendVerifiedPresetP01ReadProbe" -> {
                if (call.arguments != null) {
                    result.error("PROBE_ARGUMENTS_FORBIDDEN", "Der Read-Einmaltest nimmt keine Argumente entgegen.", null)
                } else {
                    blockingProbeExecutor.execute {
                        val outcome = runCatching { midiManager.sendVerifiedPresetP01ReadProbe() }
                        mainHandler.post {
                            outcome.onSuccess { result.success(it) }
                                .onFailure { error ->
                                    midiManager.closeDevice()
                                    result.error(
                                        "P01_READ_PROBE_FAILED",
                                        "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt.",
                                        null,
                                    )
                                }
                        }
                    }
                }
            }
            "getVerifiedPresetP01FullReadProbeStatus" -> result.success(midiManager.p01FullReadProbeStatus())
            "sendVerifiedPresetP01FullReadProbe" -> {
                if (call.arguments != null) {
                    result.error("PROBE_ARGUMENTS_FORBIDDEN", "Der Full-Read-Test nimmt keine Argumente entgegen.", null)
                } else {
                    blockingProbeExecutor.execute {
                        val outcome = runCatching { midiManager.sendVerifiedPresetP01FullReadProbe() }
                        mainHandler.post {
                            outcome.onSuccess { result.success(it) }
                                .onFailure { error ->
                                    midiManager.closeDevice()
                                    result.error(
                                        "P01_FULL_READ_PROBE_FAILED",
                                        "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt.",
                                        null,
                                    )
                                }
                        }
                    }
                }
            }
            "getVerifiedPresetP01FullReadProbeV3AStatus" -> result.success(midiManager.p01FullReadProbeV3AStatus())
            "sendVerifiedPresetP01FullReadProbeV3A" -> {
                if (call.arguments != null) {
                    result.error("PROBE_ARGUMENTS_FORBIDDEN", "Der Full-Read-Test V3A nimmt keine Argumente entgegen.", null)
                } else {
                    blockingProbeExecutor.execute {
                        val outcome = runCatching { midiManager.sendVerifiedPresetP01FullReadProbeV3A() }
                        mainHandler.post {
                            outcome.onSuccess { result.success(it) }
                                .onFailure { error ->
                                    midiManager.closeDevice()
                                    result.error(
                                        "P01_FULL_READ_PROBE_V3A_FAILED",
                                        "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt.",
                                        null,
                                    )
                                }
                        }
                    }
                }
            }
            "getMatriboxPresetReaderStatus" -> result.success(midiManager.presetReaderStatus())
            "readMatriboxUserP01" -> {
                if (call.arguments != null) {
                    result.error("READER_ARGUMENTS_FORBIDDEN", "Der Raw-Backup-Read nimmt keine Argumente entgegen.", null)
                } else {
                    blockingProbeExecutor.execute {
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
                    blockingProbeExecutor.execute {
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
            "getMatriboxConfirmedGainWriteStatus" -> result.success(midiManager.gainWriteStatus())
            "writeConfirmedSol100OdGain" -> {
                val arguments = call.arguments
                // Exactly one argument, "targetGain" -- never an algorithm
                // ID, parameter index, bank, slot or raw bytes. Rejected
                // here, on the platform-channel boundary, before the
                // native writer (which independently re-validates the
                // value again) is ever reached.
                val targetGain = (arguments as? Map<*, *>)?.get("targetGain") as? Number
                if (arguments !is Map<*, *> || arguments.keys != setOf("targetGain") || targetGain == null) {
                    result.error(
                        "GAIN_WRITE_ARGUMENTS_INVALID",
                        "Der Gain-Write nimmt ausschließlich targetGain entgegen.",
                        null,
                    )
                } else {
                    blockingProbeExecutor.execute {
                        val outcome = runCatching {
                            midiManager.writeConfirmedSol100OdGain(targetGain.toDouble())
                        }
                        mainHandler.post {
                            outcome.onSuccess { result.success(it) }
                                .onFailure { error ->
                                    midiManager.closeDevice()
                                    result.error(
                                        "GAIN_WRITE_FAILED",
                                        "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt.",
                                        null,
                                    )
                                }
                        }
                    }
                }
            }
            "getMatriboxCertificationStatus" -> result.success(midiManager.certificationStatus())
            "writeCertificationAmpField" -> {
                val arguments = call.arguments
                // Exactly two arguments: a whitelisted field name and the
                // target value. Never an algorithm ID, parameter index,
                // raw bytes, bank or slot; the native session validates
                // the field and value again.
                val map = arguments as? Map<*, *>
                val fieldName = map?.get("field") as? String
                val targetValue = map?.get("targetValue") as? Number
                if (map == null || map.keys != setOf("field", "targetValue") ||
                    fieldName == null || targetValue == null
                ) {
                    result.error(
                        "CERTIFICATION_ARGUMENTS_INVALID",
                        "Die Certification nimmt ausschließlich field und targetValue entgegen.",
                        null,
                    )
                } else {
                    blockingProbeExecutor.execute {
                        val outcome = runCatching {
                            midiManager.writeCertificationAmpField(fieldName, targetValue.toDouble())
                        }
                        mainHandler.post {
                            outcome.onSuccess { result.success(it) }
                                .onFailure { error ->
                                    midiManager.closeDevice()
                                    result.error(
                                        "CERTIFICATION_WRITE_FAILED",
                                        "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt.",
                                        null,
                                    )
                                }
                        }
                    }
                }
            }
            "getMatriboxFullLiveStatus" -> result.success(midiManager.fullLiveStatus())
            "getToneTransferStatus" -> result.success(midiManager.toneTransferStatus())
            "executeToneTransfer" -> {
                // Only the closed contract map (planId, targetBank, targetSlot, backupHash,
                // operations). The whole plan is validated natively before the first send;
                // no bytes, algorithm id or parameter index is ever accepted from Dart.
                val request = call.arguments
                blockingProbeExecutor.execute {
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
            "runFullLiveP01Certification" -> {
                val arguments = call.arguments
                // Exactly one argument: the plan id. The operation list is a
                // native constant; no slot, algorithm, index, bytes, bank or
                // value ever comes from the caller.
                val map = arguments as? Map<*, *>
                val planId = map?.get("planId") as? String
                if (map == null || map.keys != setOf("planId") || planId == null) {
                    result.error(
                        "FULL_LIVE_ARGUMENTS_INVALID",
                        "Der Full-Live-Test nimmt ausschließlich planId entgegen.",
                        null,
                    )
                } else {
                    blockingProbeExecutor.execute {
                        val outcome = runCatching { midiManager.runFullLiveP01Certification(planId) }
                        mainHandler.post {
                            outcome.onSuccess { result.success(it) }
                                .onFailure { error ->
                                    midiManager.closeDevice()
                                    result.error(
                                        "FULL_LIVE_FAILED",
                                        "${error.message} Restliche Operationen wurden nicht gesendet.",
                                        null,
                                    )
                                }
                        }
                    }
                }
            }
            "runFamilyExpansionP01Certification" -> {
                // Exactly planId, targetBank, targetSlot and the verified backup hash. The
                // operation list is a native constant that is validated as a whole before the
                // first send; nothing but these four values ever comes from the caller.
                val map = call.arguments as? Map<*, *>
                val planId = map?.get("planId") as? String
                val targetBank = map?.get("targetBank") as? String
                val targetSlot = map?.get("targetSlot") as? Int
                val backupHash = map?.get("backupHash") as? String
                if (map == null || map.keys != setOf("planId", "targetBank", "targetSlot", "backupHash") ||
                    planId == null || targetBank == null || targetSlot == null || backupHash == null
                ) {
                    result.error(
                        "FAMILY_EXPANSION_ARGUMENTS_INVALID",
                        "Der Test nimmt ausschließlich planId, targetBank, targetSlot und backupHash entgegen.",
                        null,
                    )
                } else {
                    blockingProbeExecutor.execute {
                        val outcome = runCatching {
                            midiManager.runFamilyExpansionP01Certification(
                                planId,
                                CertificationTarget(targetBank, targetSlot, backupHash),
                            )
                        }
                        mainHandler.post {
                            outcome.onSuccess { result.success(it) }
                                .onFailure { error ->
                                    midiManager.closeDevice()
                                    result.error(
                                        "FAMILY_EXPANSION_FAILED",
                                        "${error.message} Restliche Operationen wurden nicht gesendet.",
                                        null,
                                    )
                                }
                        }
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
        blockingProbeExecutor.shutdown()
    }

    fun pause() = midiManager.pause()
    fun resume() = midiManager.resume()
}
