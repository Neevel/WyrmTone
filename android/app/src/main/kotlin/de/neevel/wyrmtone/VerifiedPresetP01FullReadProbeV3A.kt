package de.neevel.wyrmtone

import java.util.concurrent.atomic.AtomicBoolean

/**
 * The single confirmed "Phase D" announce/acknowledge pair for User-Bank
 * Slot 0 (P01), observed byte-identically in both Sonicake-editor
 * connect/sync captures immediately before every Part-0 trigger of every
 * one of the 199 observed slot transitions -- see
 * docs/MATRIBOX_OFFLINE_ANALYSIS.md, "Präambel-Analyse: die fehlende
 * Phase D vor Part 0". This tests exactly one hypothesis: that Phase D
 * alone (without the session-global Ping/Capability/Enumeration phases)
 * establishes the context needed for an isolated multi-part P01 read.
 */
object VerifiedPresetP01PhaseDReference {
    /** Host->Device announce for Bank=User(0x00)/Slot=0(0x00). */
    val announce: ByteArray = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x11, 0x13, 0x01, 0x00, 0x00, 0x00, 0x00, 0xf7.toByte(),
    )

    /** Device->Host acknowledgement for Bank=User(0x00)/Slot=0(0x00). */
    val acknowledgement: ByteArray = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x12, 0x13, 0x01, 0x00, 0x01, 0x00, 0x00, 0x0c, 0x1c, 0x01, 0x40, 0xf7.toByte(),
    )

    internal fun validateAnnounce() {
        require(announce.size == 16) { "Phase-D-Announce-Länge falsch." }
        require(announce.first() == 0xf0.toByte() && announce.last() == 0xf7.toByte()) {
            "Phase-D-Announce-Grenzen falsch."
        }
        require(acknowledgement.size == 20) { "Phase-D-Ack-Länge falsch." }
        require(
            acknowledgement.first() == 0xf0.toByte() &&
                acknowledgement.last() == 0xf7.toByte(),
        ) { "Phase-D-Ack-Grenzen falsch." }
    }

    /**
     * True only for the complete byte-identical acknowledgement observed
     * for User-P01 in both reference captures. V3A deliberately does not
     * generalise any field of this single confirmed response.
     */
    fun isValidAck(bytes: ByteArray): Boolean = bytes.contentEquals(acknowledgement)
}

/**
 * This interface cannot accept bytes, a bank, a slot or an arbitrary part
 * number. [sendPhaseDAnnounce] only ever sends the one fixed Phase-D
 * announce; [sendPartRequest] only ever selects among the ten fixed
 * requests already confirmed for V2 ([VerifiedPresetP01FullReadReference]).
 */
internal interface VerifiedPresetP01FullReadV3ASendPort {
    fun sendPhaseDAnnounce()
    fun sendPartRequest(partIndex: Int)
    fun close()
}

/**
 * V3A: tests exactly one hypothesis -- that the confirmed Phase-D
 * announce/ack pair alone (no Ping, no Capability query, no metadata
 * enumeration) establishes the context an isolated ten-part P01 read
 * needs. Strictly sequential: Phase D must complete with a structurally
 * matching acknowledgement before Part 0 is ever sent; from there the
 * state machine is identical to V2 ([VerifiedPresetP01FullReadProbe]),
 * reusing its confirmed reference requests unchanged. No retry, no
 * fallback to a larger preamble, no reconnect -- a single failure at any
 * step stops the whole probe.
 */
internal class VerifiedPresetP01FullReadProbeV3A(
    private val eligibility: () -> ProbeEligibility,
    private val openSendPort: () -> VerifiedPresetP01FullReadV3ASendPort,
    private val openReceivePort: () -> ReceiveOnlyMidiPort,
    private val delay: (Long) -> Unit = Thread::sleep,
    private val clock: () -> Long = System::currentTimeMillis,
    private val stepTimeoutMillis: Long = 500,
) {
    private val inProgress = AtomicBoolean(false)
    private val lock = Any()
    private val attemptedConnections = mutableSetOf<String>()
    private var generation = 0
    private var sendPort: VerifiedPresetP01FullReadV3ASendPort? = null
    private var receivePort: ReceiveOnlyMidiPort? = null
    private val logs = mutableListOf<String>()
    private fun log(event: String, details: String) {
        logs.add("[${clock()}] $event $details")
        if (logs.size > 400) logs.removeAt(0)
    }
    private fun hex(bytes: ByteArray) = bytes.joinToString(" ") { "%02X".format(it) }

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

    fun sendVerifiedPresetP01FullReadProbeV3A(): Map<String, Any?> {
        check(inProgress.compareAndSet(false, true)) {
            "Sendevorgang läuft bereits. Es wurde kein weiterer Versuch durchgeführt."
        }
        var sent: VerifiedPresetP01FullReadV3ASendPort? = null
        var received: ReceiveOnlyMidiPort? = null
        val accumulator = SysExAccumulator()
        val windowMessages = mutableListOf<Pair<ByteArray, Long>>()
        val chunks = mutableListOf<Pair<ByteArray, Long>>()
        val stepLogs = mutableListOf<FullReadStepLog>()
        var completedParts = 0
        var phaseDConfirmed = false
        // See VerifiedPresetP01FullReadProbe.kt for why `failure` and
        // `stopReason` are kept separate: a stalled/unexpected Phase D or
        // part response is an expected diagnostic outcome, not a native
        // error, and must never force the MIDI connection closed.
        var failure: String? = null
        var stopReason: String? = null
        var token = -1
        try {
            val connection: String
            synchronized(lock) {
                val current = eligibility()
                current.check()
                VerifiedPresetP01PhaseDReference.validateAnnounce()
                VerifiedPresetP01FullReadReference.validate()
                connection = requireNotNull(current.connection)
                check(connection !in attemptedConnections) {
                    "Test in dieser Verbindung bereits ausgeführt."
                }
                attemptedConnections.add(connection) // Consume also on failure/timeout. Never retry.
                token = generation
                log(
                    "MANUAL_CONFIRMATION",
                    "Sonicake Matribox 1 84EF:0054 P01-Full-Read V3A; Phase D + zehn feste Requests, kein Schreiben",
                )
            }

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
                check(current.connection == connection) { "Geräteverbindung geändert." }
            }
            val openedSend = openSendPort()
            sent = openedSend
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                sendPort = openedSend
            }

            // Phase D: must complete before Part 0 is ever considered.
            synchronized(lock) { windowMessages.clear() }
            openedSend.sendPhaseDAnnounce()
            log("PHASE_D_REQUEST", "len=${VerifiedPresetP01PhaseDReference.announce.size} hex=${hex(VerifiedPresetP01PhaseDReference.announce)}")

            delay(stepTimeoutMillis)

            val ackSnapshot = synchronized(lock) { windowMessages.toList() }
            // Fail closed: exactly one complete SysEx is expected. A matching
            // ack accompanied by any other complete message is still an
            // unexpected Phase-D response and must not unlock Part 0.
            val ackMatch = ackSnapshot.singleOrNull()?.takeIf { (bytes, _) ->
                VerifiedPresetP01PhaseDReference.isValidAck(bytes)
            }
            if (ackMatch == null) {
                val unexpected = ackSnapshot.map { hex(it.first) }
                val timedOut = ackSnapshot.isEmpty()
                stopReason = if (timedOut) {
                    log("TIMEOUT_PHASE_D", "keine vollständige Antwort innerhalb ${stepTimeoutMillis} ms")
                    "Phase D: Timeout nach ${stepTimeoutMillis} ms."
                } else {
                    log("UNEXPECTED_PHASE_D_RESPONSE", "erhalten aber nicht passend: ${unexpected.joinToString(" | ")}")
                    "Phase D: unerwartete Antwort, kein struktureller Treffer."
                }
            } else {
                phaseDConfirmed = true
                val ackBytes = ackMatch.first
                log("PHASE_D_RESPONSE", "len=${ackBytes.size} hex=${hex(ackBytes)}")

                partLoop@ for (partIndex in VerifiedPresetP01FullReadReference.requests.indices) {
                    synchronized(lock) { check(token == generation) { "Lifecycle-Abbruch." } }
                    val requestBytes = VerifiedPresetP01FullReadReference.requests[partIndex]
                    synchronized(lock) { windowMessages.clear() }
                    openedSend.sendPartRequest(partIndex)
                    log("REQUEST_PART_$partIndex", "len=${requestBytes.size} hex=${hex(requestBytes)}")

                    delay(stepTimeoutMillis)

                    val windowSnapshot = synchronized(lock) { windowMessages.toList() }
                    // One response window may contain exactly the response
                    // for the requested part and no additional complete SysEx.
                    val match = windowSnapshot.singleOrNull()?.takeIf { (bytes, _) ->
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
                            log("TIMEOUT_PART_$partIndex", "keine vollständige Antwort innerhalb ${stepTimeoutMillis} ms")
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
            }
        } catch (error: Exception) {
            failure = "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt."
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
                        log("RECEIVE_PORT_CLOSED", "Phase D bestätigt=$phaseDConfirmed Teile abgeschlossen=$completedParts geschlossen=${closed.isSuccess}")
                    }
                    receivePort = null
                }
            }
            inProgress.set(false)
        }
        return status() + mapOf(
            "success" to (failure == null),
            "error" to failure,
            "phaseDConfirmed" to phaseDConfirmed,
            "completedParts" to completedParts,
            "stopReason" to stopReason,
            "fullyComplete" to (phaseDConfirmed && completedParts == VerifiedPresetP01FullReadReference.requests.size),
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
