package de.neevel.wyrmtone

import java.util.concurrent.atomic.AtomicBoolean

/**
 * The single confirmed connect-sync trigger for User-Bank Slot 0 (P01),
 * observed byte-identically in two independent Sonicake-editor connect
 * sessions (see docs/MATRIBOX_OFFLINE_ANALYSIS.md,
 * "Minimaler Read-Request-Kandidat"). This is a READ-ONLY experimental
 * probe: it asks the device to (re-)send its own already-stored preset
 * data, exactly the way the official editor's connect/sync does. It never
 * selects, changes or stores a preset, and never accepts a bank, a slot or
 * a byte array from Flutter.
 */
object VerifiedPresetP01ReadRequestReference {
    fun bytes(): ByteArray = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x12, 0x13, 0x01, 0x00, 0x02, 0x00, 0x00, 0x01, 0xf7.toByte(),
    )

    internal fun validate(data: ByteArray) {
        require(data.size == 17) { "Read-Request-Länge falsch." }
        require(data.contentEquals(bytes())) { "Keine bytegleiche P01-Read-Referenz." }
    }
}

/** This interface cannot accept bytes, a bank, a slot or a repeat count. */
internal interface VerifiedPresetP01ReadSendPort {
    fun sendVerifiedPresetP01ReadRequest()
    fun close()
}

/**
 * Sends the one hardcoded read request exactly once per connection and
 * reports the raw device->host bytes collected during a fixed listening
 * window. Segment reassembly, decoding and marker verification happen in
 * Dart (lib/presets/p01_readback_decoder.dart,
 * lib/midi/p01_read_probe_evaluator.dart), reusing the existing offline
 * decoder; this probe only enforces eligibility, the exact fixed request
 * and the one-shot/no-retry rule. It never loops, retries or accepts a
 * target slot/bank.
 */
internal class VerifiedPresetP01ReadProbe(
    private val eligibility: () -> ProbeEligibility,
    private val openSendPort: () -> VerifiedPresetP01ReadSendPort,
    private val openReceivePort: () -> ReceiveOnlyMidiPort,
    private val delay: (Long) -> Unit = Thread::sleep,
    private val clock: () -> Long = System::currentTimeMillis,
    private val listenWindowMillis: Long = 3000,
) {
    private val inProgress = AtomicBoolean(false)
    private val lock = Any()
    private val attemptedConnections = mutableSetOf<String>()
    private var generation = 0
    private var sendPort: VerifiedPresetP01ReadSendPort? = null
    private var receivePort: ReceiveOnlyMidiPort? = null
    private val logs = mutableListOf<String>()

    private fun log(event: String, details: String) {
        logs.add("[${clock()}] $event $details")
        if (logs.size > 100) logs.removeAt(0)
    }

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

    fun sendVerifiedPresetP01ReadProbe(): Map<String, Any?> {
        check(inProgress.compareAndSet(false, true)) {
            "Sendevorgang läuft bereits. Es wurde kein weiterer Versuch durchgeführt."
        }
        var sent: VerifiedPresetP01ReadSendPort? = null
        var received: ReceiveOnlyMidiPort? = null
        val chunks = mutableListOf<Pair<ByteArray, Long>>()
        var success = false
        var failure: String? = null
        var finalChunks: List<Pair<ByteArray, Long>> = emptyList()
        // Sentinel: never equals a real generation, so a concurrent cancel()
        // detected via `token == generation` is never true before the first
        // synchronized block below actually assigns a real token.
        var token = -1
        try {
            val connection: String
            synchronized(lock) {
                val current = eligibility()
                current.check()
                VerifiedPresetP01ReadRequestReference.validate(VerifiedPresetP01ReadRequestReference.bytes())
                connection = requireNotNull(current.connection)
                check(connection !in attemptedConnections) {
                    "Test in dieser Verbindung bereits ausgeführt."
                }
                attemptedConnections.add(connection) // Consume also on failure/timeout. Never retry.
                token = generation
                log("MANUAL_CONFIRMATION", "Sonicake Matribox 1 84EF:0054 P01-Read; kein Schreiben, kein Auswählen")
            }

            // Attach the receiver before sending so a fast device response can never be missed.
            val opened = openReceivePort()
            received = opened
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                receivePort = opened
            }
            opened.connect { bytes, timestamp ->
                synchronized(lock) {
                    if (receivePort !== opened || token != generation) return@connect
                    val total = chunks.sumOf { it.first.size }
                    if (chunks.size < 256 && total + bytes.size <= 8192) {
                        chunks.add(bytes to timestamp)
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
                log("SEND_ATTEMPT", "sendVerifiedPresetP01ReadRequest Länge 17, ein Sendecall, kein Retry")
            }
            openedSend.sendVerifiedPresetP01ReadRequest()
            success = true
            synchronized(lock) {
                log("SEND_SUCCESS", "Ein Sendecall angenommen; sammle bis zu $listenWindowMillis ms Geräteantwort.")
            }

            delay(listenWindowMillis)
        } catch (error: Exception) {
            failure = "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt."
            synchronized(lock) { log("SEND_FAILED", "$failure") }
        } finally {
            synchronized(lock) {
                finalChunks = chunks.toList()
                // A concurrent cancel() (pause/detach while this call was
                // sleeping in `delay`) already closed both ports and bumped
                // `generation`; skip closing them a second time here.
                if (token == generation) {
                    if (sent != null) {
                        val closed = runCatching { sent.close() }
                        log("SEND_PORT_CLOSED", "geschlossen=${closed.isSuccess}")
                    }
                    sendPort = null
                    if (received != null) {
                        runCatching { received.disconnect() }
                        val closed = runCatching { received.close() }
                        log("RECEIVE_PORT_CLOSED", "Chunks ${finalChunks.size} geschlossen=${closed.isSuccess}")
                    }
                    receivePort = null
                }
            }
            inProgress.set(false)
        }
        return status() + mapOf(
            "success" to success,
            "error" to failure,
            "chunks" to finalChunks.map { mapOf("bytes" to it.first, "timestampNanos" to it.second) },
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
