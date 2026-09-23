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
 * The passive monitor never writes. An isolated compile-gated probe owns its input port.
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
    private var foreground = false
    private val writeProbe = VerifiedMatriboxProbe(
        eligibility = ::probeEligibility,
        openPort = {
            probeEligibility().check()
            VerifiedMatriboxProbePort(requireNotNull(openedMidiDevice?.openInputPort(0)) {
                "Matribox-Input-Port 0 konnte nicht geöffnet werden."
            })
        },
    )
    private val presetP01Probe = VerifiedPresetP01Probe(
        eligibility = { probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_PRESET_P01_PROBE) },
        openPort = {
            probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_PRESET_P01_PROBE).check()
            VerifiedPresetP01ProbePort(requireNotNull(openedMidiDevice?.openInputPort(0)) {
                "Matribox-Input-Port 0 konnte nicht geöffnet werden."
            })
        },
    )
    private val p01ReadProbe = VerifiedPresetP01ReadProbe(
        eligibility = { probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_READ_PROBE) },
        openSendPort = {
            probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_READ_PROBE).check()
            VerifiedPresetP01ReadProbePort(requireNotNull(openedMidiDevice?.openInputPort(0)) {
                "Matribox-Input-Port 0 konnte nicht geöffnet werden."
            })
        },
        openReceivePort = {
            val info = requireNotNull(openedInfo)
            val output = requireNotNull(
                info.ports.singleOrNull { it.type == MidiDeviceInfo.PortInfo.TYPE_OUTPUT },
            ) { "Kein eindeutiger Matribox-Output-Port vorhanden." }
            val port = requireNotNull(openedMidiDevice?.openOutputPort(output.portNumber)) {
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
                    port.connect(receiving)
                }
                override fun disconnect() { receiver?.let { port.disconnect(it) }; receiver = null }
                override fun close() { port.close() }
            }
        },
    )
    private val p01FullReadProbe = VerifiedPresetP01FullReadProbe(
        eligibility = { probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_FULL_READ_PROBE) },
        openSendPort = {
            probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_FULL_READ_PROBE).check()
            VerifiedPresetP01FullReadProbePort(requireNotNull(openedMidiDevice?.openInputPort(0)) {
                "Matribox-Input-Port 0 konnte nicht geöffnet werden."
            })
        },
        openReceivePort = {
            val info = requireNotNull(openedInfo)
            val output = requireNotNull(
                info.ports.singleOrNull { it.type == MidiDeviceInfo.PortInfo.TYPE_OUTPUT },
            ) { "Kein eindeutiger Matribox-Output-Port vorhanden." }
            val port = requireNotNull(openedMidiDevice?.openOutputPort(output.portNumber)) {
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
                    port.connect(receiving)
                }
                override fun disconnect() { receiver?.let { port.disconnect(it) }; receiver = null }
                override fun close() { port.close() }
            }
        },
    )
    private val p01FullReadProbeV3A = VerifiedPresetP01FullReadProbeV3A(
        eligibility = { probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_FULL_READ_PROBE_V3A) },
        openSendPort = {
            probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_FULL_READ_PROBE_V3A).check()
            VerifiedPresetP01FullReadProbeV3APort(requireNotNull(openedMidiDevice?.openInputPort(0)) {
                "Matribox-Input-Port 0 konnte nicht geöffnet werden."
            })
        },
        openReceivePort = {
            val info = requireNotNull(openedInfo)
            val output = requireNotNull(
                info.ports.singleOrNull { it.type == MidiDeviceInfo.PortInfo.TYPE_OUTPUT },
            ) { "Kein eindeutiger Matribox-Output-Port vorhanden." }
            val port = requireNotNull(openedMidiDevice?.openOutputPort(output.portNumber)) {
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
                    port.connect(receiving)
                }
                override fun disconnect() { receiver?.let { port.disconnect(it) }; receiver = null }
                override fun close() { port.close() }
            }
        },
    )
    private val presetReader = MatriboxPresetReader(
        eligibility = { probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_RAW_BACKUP) },
        openSendPort = {
            probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_RAW_BACKUP).check()
            MatriboxPresetReaderPort(requireNotNull(openedMidiDevice?.openInputPort(0)) {
                "Matribox-Input-Port 0 konnte nicht geöffnet werden."
            })
        },
        openReceivePort = {
            val info = requireNotNull(openedInfo)
            val output = requireNotNull(
                info.ports.singleOrNull { it.type == MidiDeviceInfo.PortInfo.TYPE_OUTPUT },
            ) { "Kein eindeutiger Matribox-Output-Port vorhanden." }
            val port = requireNotNull(openedMidiDevice?.openOutputPort(output.portNumber)) {
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
                    port.connect(receiving)
                }
                override fun disconnect() { receiver?.let { port.disconnect(it) }; receiver = null }
                override fun close() { port.close() }
            }
        },
    )
    private val gainWriteSession = MatriboxConfirmedGainWriteSession(
        eligibility = { probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_GAIN_WRITE) },
        openSendPort = {
            probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_GAIN_WRITE).check()
            MatriboxConfirmedGainWriterPort(requireNotNull(openedMidiDevice?.openInputPort(0)) {
                "Matribox-Input-Port 0 konnte nicht geöffnet werden."
            })
        },
    )
    private val certificationSession = MatriboxSol100OdCertificationSession(
        eligibility = { probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION) },
        openSendPort = {
            probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION).check()
            MatriboxSol100OdAmpWriterPort(requireNotNull(openedMidiDevice?.openInputPort(0)) {
                "Matribox-Input-Port 0 konnte nicht geöffnet werden."
            })
        },
    )
    // Three mutually exclusive compile gates share the one closed Full Live transport.
    private fun fullLiveOrAngelsGate(): Boolean =
        (BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION) ||
            (BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION) ||
            (BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1)

    private val fullLiveSession = MatriboxFullLiveCertificationSession(
        eligibility = { probeEligibility(fullLiveOrAngelsGate()) },
        planResolver = { planId ->
            MatriboxCertificationPlans.operations(
                planId,
                fullLiveEnabled = BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION,
                angelsEnabled = BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION,
                familyExpansionEnabled = BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1,
            )
        },
        preflight = MatriboxFamilyExpansionValidator::preflightMessage,
        openSendPort = {
            probeEligibility(fullLiveOrAngelsGate()).check()
            MatriboxFullLiveWriterPort(requireNotNull(openedMidiDevice?.openInputPort(0)) {
                "Matribox-Input-Port 0 konnte nicht geöffnet werden."
            })
        },
    )
    // Productive Tone Transfer: own debug gate (exclusive with every certification sender).
    private val toneTransferSession = MatriboxToneTransferSession(
        eligibility = { probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_TONE_TRANSFER) },
        openSendPort = {
            probeEligibility(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_TONE_TRANSFER).check()
            MatriboxToneTransferWriterPort(requireNotNull(openedMidiDevice?.openInputPort(0)) {
                "Matribox-Input-Port 0 konnte nicht geöffnet werden."
            })
        },
    )
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
        writeProbe.cancel()
        presetP01Probe.cancel()
        p01ReadProbe.cancel()
        p01FullReadProbe.cancel()
        p01FullReadProbeV3A.cancel()
        presetReader.cancel()
        gainWriteSession.cancel()
        certificationSession.cancel()
        fullLiveSession.cancel()
        toneTransferSession.cancel()
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
        foreground = false
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
        writeProbe.detached(deviceName)
        presetP01Probe.detached(deviceName)
        p01ReadProbe.detached(deviceName)
        p01FullReadProbe.detached(deviceName)
        p01FullReadProbeV3A.detached(deviceName)
        presetReader.cancel()
        gainWriteSession.detached(deviceName)
        certificationSession.detached(deviceName)
        fullLiveSession.detached(deviceName)
        toneTransferSession.detached(deviceName)
        ++openGeneration
        if (deviceName != null && session.usbDeviceName == deviceName) {
            closeDevice(); connectionClosed("usbDetached")
        }
    }

    fun resume() { foreground = true }

    fun writeProbeStatus(): Map<String, Any?> = writeProbe.status() + mapOf("sessionToken" to openGeneration)

    fun sendVerifiedSol100OdGain41Probe(): Map<String, Any?> {
        val result = writeProbe.sendVerifiedSol100OdGain41Probe()
        if (result["success"] != true) {
            closeDevice()
            connectionClosed("probeFailed")
        }
        return result
    }

    fun presetP01ProbeStatus(): Map<String, Any?> =
        presetP01Probe.status() + mapOf("sessionToken" to openGeneration)

    fun sendVerifiedPresetP01SelectionProbe(): Map<String, Any?> {
        val result = presetP01Probe.sendVerifiedPresetP01SelectionProbe()
        if (result["success"] != true) {
            closeDevice()
            connectionClosed("presetP01ProbeFailed")
        }
        return result
    }

    fun p01ReadProbeStatus(): Map<String, Any?> =
        p01ReadProbe.status() + mapOf("sessionToken" to openGeneration)

    /** Runs on the caller's thread; the caller must not invoke this on the UI/main thread. */
    fun sendVerifiedPresetP01ReadProbe(): Map<String, Any?> {
        val result = p01ReadProbe.sendVerifiedPresetP01ReadProbe()
        if (result["success"] != true) {
            closeDevice()
            connectionClosed("p01ReadProbeFailed")
        }
        return result
    }

    fun p01FullReadProbeStatus(): Map<String, Any?> =
        p01FullReadProbe.status() + mapOf("sessionToken" to openGeneration)

    /** Runs on the caller's thread; the caller must not invoke this on the UI/main thread. */
    fun sendVerifiedPresetP01FullReadProbe(): Map<String, Any?> {
        val result = p01FullReadProbe.sendVerifiedPresetP01FullReadProbe()
        if (result["success"] != true) {
            closeDevice()
            connectionClosed("p01FullReadProbeFailed")
        }
        return result
    }

    fun p01FullReadProbeV3AStatus(): Map<String, Any?> =
        p01FullReadProbeV3A.status() + mapOf("sessionToken" to openGeneration)

    /** Runs on the caller's thread; the caller must not invoke this on the UI/main thread. */
    fun sendVerifiedPresetP01FullReadProbeV3A(): Map<String, Any?> {
        val result = p01FullReadProbeV3A.sendVerifiedPresetP01FullReadProbeV3A()
        if (result["success"] != true) {
            closeDevice()
            connectionClosed("p01FullReadProbeV3AFailed")
        }
        return result
    }

    fun presetReaderStatus(): Map<String, Any?> =
        presetReader.status() + mapOf("sessionToken" to openGeneration)

    /**
     * Runs on the caller's thread; the caller must not invoke this on the
     * UI/main thread. Unlike the probes above, [MatriboxPresetReadOutcome]
     * distinguishes genuine transport failures from expected, informational
     * outcomes (timeouts, structural mismatches): only TRANSPORT_ERROR
     * force-closes the device connection, mirroring the fix already applied
     * to V2/V3A's `success` semantics -- a Phase-D or part timeout is not a
     * native error and must not disconnect a device the user can simply
     * try reading again.
     */
    fun readMatriboxUserP01(): Map<String, Any?> = readResult(presetReader.readVerifiedUserP01())

    /**
     * The productive transfer's fresh read of exactly [target] (P11..P99; the type cannot exist for
     * a protected slot). Same outcome/closing semantics as [readMatriboxUserP01].
     */
    internal fun readMatriboxUserSlot(target: MatriboxWritableUserPreset): Map<String, Any?> =
        readResult(presetReader.readVerifiedUserSlot(target.preset)) + mapOf("targetSlot" to target.presetNumber)

    private fun readResult(result: MatriboxPresetReadResult): Map<String, Any?> {
        if (result.outcome == MatriboxPresetReadOutcome.TRANSPORT_ERROR) {
            closeDevice()
            connectionClosed("presetReaderTransportError")
        }
        return mapOf(
            "outcome" to result.outcome.name,
            "phaseDResponse" to result.phaseDResponse,
            "parts" to result.parts,
            "error" to result.error,
        )
    }

    fun fullLiveStatus(): Map<String, Any?> =
        fullLiveSession.status() + mapOf("sessionToken" to openGeneration)

    fun toneTransferStatus(): Map<String, Any?> =
        toneTransferSession.status() + mapOf("sessionToken" to openGeneration)

    /**
     * Productive Tone Transfer. Only the closed contract map is accepted; the
     * whole plan is validated natively before the first send. A transport
     * failure closes the device connection. No retry, no rollback, no store.
     */
    fun executeToneTransfer(request: Any?): Map<String, Any?> {
        val token = openGeneration
        val result = toneTransferSession.execute(request)
        if (result["outcome"] == ToneTransferOutcome.SEND_FAILED.name) {
            closeDevice()
            connectionClosed("toneTransferFailed")
        }
        return result + mapOf("sessionToken" to token)
    }

    /**
     * Runs on the caller's thread (never the UI thread). Runs the fixed plan;
     * only SEND_FAILED (a genuine native/transport exception) closes the
     * device connection. No retry, no rollback, no store.
     */
    fun runFullLiveP01Certification(planId: String): Map<String, Any?> {
        val result = fullLiveSession.run(planId)
        if (result["outcome"] == MatriboxFullLiveOutcome.SEND_FAILED.name) {
            closeDevice()
            connectionClosed("fullLiveFailed")
        }
        return result
    }

    /**
     * FAMILY_EXPANSION_P01_V1: the same closed Full Live transport, but bound
     * to User P01 and the verified backup hash and preflighted as a whole
     * before the first send. Runs on the caller's thread (never the UI
     * thread). Only SEND_FAILED closes the connection. No retry, no store.
     */
    internal fun runFamilyExpansionP01Certification(planId: String, target: CertificationTarget): Map<String, Any?> {
        val result = fullLiveSession.run(planId, target)
        if (result["outcome"] == MatriboxFullLiveOutcome.SEND_FAILED.name) {
            closeDevice()
            connectionClosed("familyExpansionFailed")
        }
        return result
    }

    fun certificationStatus(): Map<String, Any?> =
        certificationSession.status() + mapOf("sessionToken" to openGeneration)

    /**
     * Runs on the caller's thread (never the UI thread). Only SEND_FAILED
     * (a genuine native/transport exception) closes the device connection;
     * every other outcome means nothing was attempted. No retry.
     */
    fun writeCertificationAmpField(fieldName: String, targetValue: Double): Map<String, Any?> {
        val result = certificationSession.writeCertificationAmpField(fieldName, targetValue)
        if (result["outcome"] == MatriboxCertificationWriteOutcome.SEND_FAILED.name) {
            closeDevice()
            connectionClosed("certificationWriteFailed")
        }
        return result
    }

    fun gainWriteStatus(): Map<String, Any?> =
        gainWriteSession.status() + mapOf("sessionToken" to openGeneration)

    /**
     * Runs on the caller's thread; the caller must not invoke this on the
     * UI/main thread. Only SEND_FAILED (a genuine native/transport
     * exception) closes the device connection -- every other outcome
     * (DEVICE_NOT_CONNECTED, MIDI_NOT_AVAILABLE, INVALID_VALUE,
     * SAFETY_REJECTED) means the write was never attempted at all and
     * must not disconnect a device the user may simply need to prepare
     * again.
     */
    fun writeConfirmedSol100OdGain(targetGain: Double): Map<String, Any?> {
        val result = gainWriteSession.writeConfirmedSol100OdGain(targetGain)
        if (result["outcome"] == MatriboxGainWriteOutcome.SEND_FAILED.name) {
            closeDevice()
            connectionClosed("gainWriteFailed")
        }
        return result
    }

    private fun probeEligibility(
        enabled: Boolean = BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_WRITE_PROBE,
    ): ProbeEligibility {
        val info = openedInfo
        val attached = usbManager.deviceList.values.filter { it.vendorId == 0x84ef && it.productId == 0x0054 }
        val usb = attached.singleOrNull()
        @Suppress("DEPRECATION")
        fun directUsb(candidate: MidiDeviceInfo): UsbDevice? =
            candidate.properties.getParcelable(MidiDeviceInfo.PROPERTY_USB_DEVICE) as? UsbDevice
        val matchingMidi = midiManager?.devices.orEmpty().filter {
            val direct = directUsb(it)
            it.type == MidiDeviceInfo.TYPE_USB && direct != null && usb != null &&
                direct.deviceName == usb.deviceName && direct.vendorId == 0x84ef && direct.productId == 0x0054
        }
        val direct = info?.let(::directUsb)
        val input = info?.ports?.filter { it.type == MidiDeviceInfo.PortInfo.TYPE_INPUT }.orEmpty()
        return ProbeEligibility(
            enabled = enabled,
            connection = usb?.deviceName, vendor = usb?.vendorId, product = usb?.productId,
            uniqueUsb = attached.size == 1, uniqueMidi = matchingMidi.size == 1,
            directlyMapped = info != null && matchingMidi.singleOrNull()?.id == info.id &&
                direct?.deviceName == session.usbDeviceName && direct?.deviceName == usb?.deviceName,
            deviceOpen = foreground && !disposed && session.isOpen && openedMidiDevice != null,
            expectedInput = input.size == 1 && input.single().portNumber == 0,
            monitoring = monitor.monitoring,
        )
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
