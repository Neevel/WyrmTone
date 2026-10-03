package de.neevel.wyrmtone

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class UsbPlatformChannels(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    /**
     * Product NAM transfer V1 hardware-certification fix: an upper bound on
     * how long the UI ever waits for [MidiDiagnosticsManager.executeNamCloneTransferSession]
     * to report back, independent of whether the underlying native/system
     * call actually returns -- see that method channel case's own docs.
     * Generously above any legitimate 590-frame transfer (observed on real
     * hardware: well under 30s including port-opening) so it never
     * interferes with a working transfer, but short enough that a real
     * hardware failure resolves in the UI within a couple of minutes
     * instead of indefinitely.
     */
    private val NAM_TRANSFER_SESSION_WATCHDOG_MILLIS = 120_000L
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
    // Product NAM transfer V1: real per-ACK progress ("347 von 590"), a dedicated
    // channel (not the general usb_events stream) so up to 590 progress events per
    // transfer never compete with/delay other USB event consumers -- same reasoning
    // as midi_capture_events having its own channel.
    private var namTransferProgressSink: EventChannel.EventSink? = null
    private val namTransferProgressChannel = EventChannel(messenger, "de.neevel.wyrmtone/nam_transfer_progress")
    private val midiManager = MidiDiagnosticsManager(
        context,
        emitEvent = { event -> eventSink?.success(event) },
        emitCapture = { event -> captureSink?.success(event) },
        // Progress is produced on the transfer's worker thread (one event per confirmed ACK);
        // a Flutter EventSink must only be used from the main thread. Measured on a real device:
        // sent directly from the worker, 0 of 590 events reached Dart (the progress bar never
        // moved); posted through the main handler, all 590 arrived.
        emitNamTransferProgress = { event -> mainHandler.post { namTransferProgressSink?.success(event) } },
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
        namTransferProgressChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { namTransferProgressSink = events }
            override fun onCancel(arguments: Any?) { namTransferProgressSink = null }
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
            // V5B.1: narrow NAM Clone-transfer send primitive. Accepts ONLY a
            // byte array -- no slot, no NAM path, no protocol type. Fails
            // closed inside sendNamCloneTransferFrame/MatriboxNamCloneSendPort
            // unless BuildConfig.REAL_MATRIBOX_WRITE is enabled (hardcoded
            // false in this milestone, see build.gradle.kts).
            "sendNamCloneTransferFrame" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null) {
                    result.error("INVALID_ARGUMENT", "bytes fehlt oder ist kein Byte-Array.", null)
                } else {
                    blockingExecutor.execute {
                        val outcome = runCatching { midiManager.sendNamCloneTransferFrame(bytes) }
                        mainHandler.post {
                            outcome.onSuccess { result.success(it) }
                                .onFailure { error ->
                                    result.error("NAM_CLONE_SEND_FAILED", error.message, null)
                                }
                        }
                    }
                }
            }
            // V5B.2a: the real, strict stop-and-wait NAM Clone-transfer path.
            // Accepts ONLY a list of already-built frame byte arrays -- no
            // slot, no NAM path, no protocol type -- and blocks (like
            // executeToneTransfer) until the whole run completes or aborts.
            // Fails closed the same way sendNamCloneTransferFrame does.
            //
            // Product NAM transfer V1 hardware-certification fix: a real
            // Matribox USB disconnect/reconnect mid-session was observed to
            // block the underlying Android MIDI/USB system call (port open)
            // indefinitely -- a known platform behaviour where a blocked
            // synchronous Binder call does not respond to Thread.interrupt()
            // (session.cancel() alone could not unblock it; see
            // MatriboxNamTransferSession.cancel()'s own docs on what it does
            // and does not interrupt). A watchdog on THIS channel call is the
            // fix: it bounds how long the UI ever waits, independent of
            // whether the underlying native thread ever actually returns.
            // [resultDelivered] guards against delivering the MethodChannel
            // result twice (Flutter throws if that happens) -- whichever of
            // the real completion or the watchdog fires FIRST wins; the
            // other is a silent no-op. This never causes a second send: the
            // process-lifetime write budget (namTransferAttempted) is set
            // the moment the real call starts, regardless of which path
            // eventually reports back to Dart.
            "executeNamCloneTransferSession" -> {
                val frames = call.argument<List<*>>("frames")?.map { it as? ByteArray }
                if (frames == null || frames.any { it == null }) {
                    result.error("INVALID_ARGUMENT", "frames fehlt oder enthält kein Byte-Array.", null)
                } else {
                    val resultDelivered = AtomicBoolean(false)
                    val watchdog = Runnable {
                        if (resultDelivered.compareAndSet(false, true)) {
                            result.error(
                                "NAM_CLONE_SESSION_TIMEOUT",
                                "Die Matribox hat nicht innerhalb der erwarteten Zeit geantwortet " +
                                    "(möglicherweise USB-Verbindungsabbruch). Kein weiterer Frame wurde gesendet.",
                                null,
                            )
                        }
                    }
                    mainHandler.postDelayed(watchdog, NAM_TRANSFER_SESSION_WATCHDOG_MILLIS)
                    blockingExecutor.execute {
                        val outcome = runCatching { midiManager.executeNamCloneTransferSession(frames.filterNotNull()) }
                        mainHandler.post {
                            mainHandler.removeCallbacks(watchdog)
                            if (resultDelivered.compareAndSet(false, true)) {
                                outcome.onSuccess { result.success(it) }
                                    .onFailure { error ->
                                        result.error("NAM_CLONE_SESSION_FAILED", error.message, null)
                                    }
                            }
                            // else: the watchdog already reported a timeout to Dart; the underlying
                            // native call finished late (or never truly unblocks) -- its result is
                            // discarded, never delivered as a second, contradicting response.
                        }
                    }
                }
            }
            // Product NAM transfer V1 hardware-certification fix: the product UI's "Abbrechen"
            // during an active transfer must reach THIS (cancels only the NAM session), never the
            // general closeDevice (which only tears down UsbConnectionManager and never touches
            // MidiDiagnosticsManager -- cancelling from the UI previously did nothing).
            "cancelNamCloneTransferSession" -> {
                midiManager.cancelNamCloneTransferSession()
                result.success(null)
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
        namTransferProgressChannel.setStreamHandler(null)
        namTransferProgressSink = null
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
