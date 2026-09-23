package de.neevel.wyrmtone

import java.util.concurrent.atomic.AtomicBoolean

/**
 * The exact ten Host->Device requests confirmed byte-identical in the
 * official Sonicake-editor connect/sync capture for User-Bank Slot 0
 * (P01) -- see docs/MATRIBOX_OFFLINE_ANALYSIS.md, "Vollstaendige
 * Request/Response-Sequenz fuer User P01". No bank, slot or part number is
 * ever accepted as input anywhere in this probe: these ten byte arrays are
 * the entire universe of what can be sent.
 */
object VerifiedPresetP01FullReadReference {
    val requests: List<ByteArray> = listOf(
        // Part 0 request (17 bytes) -> expects a 210-byte response.
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x02, 0x00, 0x00, 0x01, 0xf7.toByte(),
        ),
        // Parts 1-7 requests (19 bytes each) -> expect 210-byte responses.
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x02, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x03, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x05, 0x01, 0xf7.toByte(),
        ),
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x06, 0x01, 0xf7.toByte(),
        ),
        // Part 8 request (19 bytes) -> expects a 46-byte response.
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x07, 0x01, 0xf7.toByte(),
        ),
        // Part 9 request (19 bytes) -> expects an 18-byte, payload-less response.
        byteArrayOf(
            0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
            0x12, 0x13, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x08, 0x01, 0xf7.toByte(),
        ),
    )

    /** Confirmed response length per part index (0-9). */
    val expectedResponseLengths: List<Int> =
        listOf(210, 210, 210, 210, 210, 210, 210, 210, 46, 18)

    internal fun validate() {
        require(requests.size == 10) { "Es muessen genau zehn Requests sein." }
        require(expectedResponseLengths.size == 10)
        for ((index, request) in requests.withIndex()) {
            require(request.first() == 0xf0.toByte() && request.last() == 0xf7.toByte()) {
                "Request $index: SysEx-Grenzen falsch."
            }
            val expectedLength = if (index == 0) 17 else 19
            require(request.size == expectedLength) { "Request $index: Laenge falsch." }
        }
    }

    /**
     * True only if [bytes] is a complete SysEx of exactly the confirmed
     * length and header shape for [partIndex] (offsets 8/9 = QME2 class
     * 0x12/0x13, offset 10 in {0x01,0x02}, offset 11 = 0x00, offset 12 in
     * {0x03,0x05}, offset 16 = partIndex). Mirrors (intentionally
     * duplicated, native side needs this synchronously)
     * lib/presets/p01_readback_decoder.dart's `readbackHeader`.
     */
    fun isValidResponseForPart(bytes: ByteArray, partIndex: Int): Boolean {
        if (bytes.size != expectedResponseLengths[partIndex]) return false
        if (bytes.size < 18) return false
        if (bytes.first() != 0xf0.toByte() || bytes.last() != 0xf7.toByte()) return false
        if (bytes[8] != 0x12.toByte() || bytes[9] != 0x13.toByte()) return false
        val offset10 = bytes[10].toInt() and 0xff
        if (offset10 != 0x01 && offset10 != 0x02) return false
        if (bytes[11] != 0x00.toByte()) return false
        val offset12 = bytes[12].toInt() and 0xff
        if (offset12 != 0x03 && offset12 != 0x05) return false
        val actualPart = bytes[16].toInt() and 0xff
        return actualPart == partIndex
    }
}

/** This interface cannot accept bytes, a bank, a slot or an arbitrary part number. */
internal interface VerifiedPresetP01FullReadSendPort {
    /** [partIndex] only selects among the ten fixed, hardcoded requests above (0-9). */
    fun sendPartRequest(partIndex: Int)
    fun close()
}

/** Reassembles a plain MIDI byte stream into complete SysEx messages (F0..F7). */
internal class SysExAccumulator {
    private val buffer = mutableListOf<Byte>()
    private var active = false

    /** Returns every SysEx message completed by bytes in [chunk], in order. */
    fun feed(chunk: ByteArray): List<ByteArray> {
        val completed = mutableListOf<ByteArray>()
        for (byte in chunk) {
            if (byte == 0xf0.toByte()) {
                // A fresh start discards any prior incomplete message, same
                // as the existing pure Dart MidiParser.
                buffer.clear()
                buffer.add(byte)
                active = true
                continue
            }
            if (!active) continue
            buffer.add(byte)
            if (byte == 0xf7.toByte()) {
                completed.add(buffer.toByteArray())
                buffer.clear()
                active = false
            }
        }
        return completed
    }
}

/** One logged step of the ten-part sequence, for the copyable diagnostic protocol. */
internal data class FullReadStepLog(
    val partIndex: Int,
    val requestHex: String,
    val responseHex: String?,
    val responseTimestampNanos: Long?,
    val unexpectedHex: List<String>,
    val timedOut: Boolean,
)

/**
 * Strictly sequential, read-only ten-part P01 readback probe: for each part
 * 0-9, sends exactly the one confirmed fixed request, waits a bounded
 * window for a complete AND structurally matching response, and only then
 * proceeds to the next part. A single receiver-not-yet-complete MIDI chunk
 * never advances the sequence; an unexpected or missing response stops the
 * whole probe immediately with no retry. Reassembly, decoding and marker
 * verification of the resulting 210-byte parts happen in Dart, reusing the
 * existing lib/presets/p01_readback_decoder.dart and
 * lib/midi/p01_read_probe_evaluator.dart -- this class only decides,
 * per step, "did the confirmed response for this exact part arrive".
 */
internal class VerifiedPresetP01FullReadProbe(
    private val eligibility: () -> ProbeEligibility,
    private val openSendPort: () -> VerifiedPresetP01FullReadSendPort,
    private val openReceivePort: () -> ReceiveOnlyMidiPort,
    private val delay: (Long) -> Unit = Thread::sleep,
    private val clock: () -> Long = System::currentTimeMillis,
    private val stepTimeoutMillis: Long = 500,
) {
    private val inProgress = AtomicBoolean(false)
    private val lock = Any()
    private val attemptedConnections = mutableSetOf<String>()
    private var generation = 0
    private var sendPort: VerifiedPresetP01FullReadSendPort? = null
    private var receivePort: ReceiveOnlyMidiPort? = null
    private val logs = mutableListOf<String>()
    private fun log(event: String, details: String) {
        logs.add("[${clock()}] $event $details")
        if (logs.size > 400) logs.removeAt(0)
    }
    private fun hex(bytes: ByteArray) =
        bytes.joinToString(" ") { "%02X".format(it) }

    fun status(): Map<String, Any?> = synchronized(lock) {
        val current = eligibility()
        mapOf(
            "enabled" to current.enabled,
            "attempted" to (current.connection in attemptedConnections),
            "connection" to current.connection,
            "busy" to inProgress.get(),
            "ready" to runCatching { current.check() }.isSuccess,
            "logs" to logs.toList(),
        )
    }

    fun sendVerifiedPresetP01FullReadProbe(): Map<String, Any?> {
        check(inProgress.compareAndSet(false, true)) {
            "Sendevorgang laeuft bereits. Es wurde kein weiterer Versuch durchgefuehrt."
        }
        var sent: VerifiedPresetP01FullReadSendPort? = null
        var received: ReceiveOnlyMidiPort? = null
        val accumulator = SysExAccumulator()
        val windowMessages = mutableListOf<Pair<ByteArray, Long>>()
        val chunks = mutableListOf<Pair<ByteArray, Long>>()
        val stepLogs = mutableListOf<FullReadStepLog>()
        var completedParts = 0
        // `failure` reflects a genuine native-level problem (exception,
        // lost eligibility) and drives the caller's decision to close the
        // device connection. A timeout or unexpected response on one part
        // is an expected, informative diagnostic outcome -- it stops the
        // sequence (no retry) but is reported via `stopReason`/`steps`,
        // never as `failure`, so an incomplete readback never forces the
        // MIDI connection closed the way a real error does.
        var failure: String? = null
        var stopReason: String? = null
        var token = -1
        try {
            val connection: String
            synchronized(lock) {
                val current = eligibility()
                current.check()
                VerifiedPresetP01FullReadReference.validate()
                connection = requireNotNull(current.connection)
                check(connection !in attemptedConnections) {
                    "Test in dieser Verbindung bereits ausgefuehrt."
                }
                attemptedConnections.add(connection) // Consume also on failure/timeout. Never retry.
                token = generation
                log("MANUAL_CONFIRMATION", "Sonicake Matribox 1 84EF:0054 P01-Full-Read; zehn feste Requests, kein Schreiben")
            }

            // Attach the receiver before the first send so a fast response is never missed.
            val openedReceive = openReceivePort()
            received = openedReceive
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                receivePort = openedReceive
            }
            openedReceive.connect { bytes, timestamp ->
                synchronized(lock) {
                    if (receivePort !== openedReceive || token != generation) return@connect
                    for (complete in accumulator.feed(bytes)) {
                        windowMessages.add(complete to timestamp)
                    }
                }
            }

            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                val current = eligibility()
                current.check()
                check(current.connection == connection) { "Geraeteverbindung geaendert." }
            }
            val openedSend = openSendPort()
            sent = openedSend
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                sendPort = openedSend
            }

            partLoop@ for (partIndex in VerifiedPresetP01FullReadReference.requests.indices) {
                synchronized(lock) { check(token == generation) { "Lifecycle-Abbruch." } }
                val requestBytes = VerifiedPresetP01FullReadReference.requests[partIndex]
                synchronized(lock) { windowMessages.clear() }
                openedSend.sendPartRequest(partIndex)
                log("REQUEST_PART_$partIndex", "len=${requestBytes.size} hex=${hex(requestBytes)}")

                delay(stepTimeoutMillis)

                val windowSnapshot = synchronized(lock) { windowMessages.toList() }
                val match = windowSnapshot.firstOrNull { (bytes, _) ->
                    VerifiedPresetP01FullReadReference.isValidResponseForPart(bytes, partIndex)
                }
                if (match == null) {
                    val unexpected = windowSnapshot.map { hex(it.first) }
                    val timedOut = windowSnapshot.isEmpty()
                    stepLogs.add(
                        FullReadStepLog(
                            partIndex = partIndex,
                            requestHex = hex(requestBytes),
                            responseHex = null,
                            responseTimestampNanos = null,
                            unexpectedHex = unexpected,
                            timedOut = timedOut,
                        ),
                    )
                    stopReason = if (timedOut) {
                        log("TIMEOUT_PART_$partIndex", "keine vollstaendige Antwort innerhalb ${stepTimeoutMillis} ms")
                        "Teil $partIndex: Timeout nach ${stepTimeoutMillis} ms."
                    } else {
                        log("UNEXPECTED_SYSEX_PART_$partIndex", "erhalten aber nicht passend: ${unexpected.joinToString(" | ")}")
                        "Teil $partIndex: unerwartete Antwort, kein struktureller Treffer."
                    }
                    break@partLoop
                }
                val (responseBytes, responseTimestamp) = match
                chunks.add(responseBytes to responseTimestamp)
                stepLogs.add(
                    FullReadStepLog(
                        partIndex = partIndex,
                        requestHex = hex(requestBytes),
                        responseHex = hex(responseBytes),
                        responseTimestampNanos = responseTimestamp,
                        unexpectedHex = windowSnapshot.filter { it != match }.map { hex(it.first) },
                        timedOut = false,
                    ),
                )
                log("RESPONSE_PART_$partIndex", "len=${responseBytes.size} hex=${hex(responseBytes)}")
                completedParts = partIndex + 1
            }
        } catch (error: Exception) {
            failure = "${error.message} Es wurde kein weiterer Sendeversuch durchgefuehrt."
            synchronized(lock) { log("SEND_FAILED", "$failure") }
        } finally {
            synchronized(lock) {
                if (token == generation) {
                    if (sent != null) {
                        val closed = runCatching { sent.close() }
                        log("SEND_PORT_CLOSED", "geschlossen=${closed.isSuccess}")
                    }
                    sendPort = null
                    if (received != null) {
                        runCatching { received.disconnect() }
                        val closed = runCatching { received.close() }
                        log("RECEIVE_PORT_CLOSED", "Teile abgeschlossen=$completedParts geschlossen=${closed.isSuccess}")
                    }
                    receivePort = null
                }
            }
            inProgress.set(false)
        }
        return status() + mapOf(
            "success" to (failure == null),
            "error" to failure,
            "completedParts" to completedParts,
            "stopReason" to stopReason,
            "fullyComplete" to (completedParts == VerifiedPresetP01FullReadReference.requests.size),
            "steps" to stepLogs.map {
                mapOf(
                    "part" to it.partIndex,
                    "requestHex" to it.requestHex,
                    "responseHex" to it.responseHex,
                    "responseTimestampNanos" to it.responseTimestampNanos,
                    "unexpectedHex" to it.unexpectedHex,
                    "timedOut" to it.timedOut,
                )
            },
            "chunks" to chunks.map { mapOf("bytes" to it.first, "timestampNanos" to it.second) },
        )
    }

    fun cancel() = synchronized(lock) {
        ++generation
        sendPort?.let { runCatching { it.close() } }
        sendPort = null
        receivePort?.let {
            runCatching { it.disconnect() }
            runCatching { it.close() }
        }
        receivePort = null
    }

    fun detached(connection: String?) = synchronized(lock) {
        cancel()
        if (connection != null) attemptedConnections.remove(connection)
    }
}
