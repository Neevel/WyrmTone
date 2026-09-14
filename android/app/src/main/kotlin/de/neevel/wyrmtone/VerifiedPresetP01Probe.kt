package de.neevel.wyrmtone

import java.util.concurrent.atomic.AtomicBoolean

object VerifiedPresetP01Reference {
    fun bytes(): ByteArray = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x12, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0xf7.toByte(),
    )

    internal fun validate(data: ByteArray) {
        require(data.size == 22) { "P01-Referenzlänge falsch." }
        require(data.contentEquals(bytes())) { "Keine bytegleiche P01-Editor-Referenz." }
    }
}

/** This interface cannot accept bytes, a preset number, timing or a repeat count. */
internal interface VerifiedPresetP01Port {
    fun sendVerifiedPresetP01()
    fun close()
}

internal class VerifiedPresetP01Probe(
    private val eligibility: () -> ProbeEligibility,
    private val openPort: () -> VerifiedPresetP01Port,
    private val delay: (Long) -> Unit = Thread::sleep,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val inProgress = AtomicBoolean(false)
    private val lock = Any()
    private val attemptedConnections = mutableSetOf<String>()
    private var generation = 0
    private var port: VerifiedPresetP01Port? = null
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

    fun sendVerifiedPresetP01SelectionProbe(): Map<String, Any?> {
        check(inProgress.compareAndSet(false, true)) {
            "Sendevorgang läuft bereits. Es wurde kein weiterer Sendeversuch durchgeführt."
        }
        var calls = 0
        var opened: VerifiedPresetP01Port? = null
        var success = false
        var failure: String? = null
        try {
            val token: Int
            val connection: String
            synchronized(lock) {
                val current = eligibility()
                current.check()
                VerifiedPresetP01Reference.validate(VerifiedPresetP01Reference.bytes())
                connection = requireNotNull(current.connection)
                check(connection !in attemptedConnections) {
                    "Test in dieser Verbindung bereits ausgeführt."
                }
                attemptedConnections.add(connection)
                token = generation
                log("MANUAL_CONFIRMATION", "Sonicake Matribox 1 84EF:0054 P01; kein Speichern")
            }
            opened = openPort()
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                port = opened
                val current = eligibility()
                current.check()
                check(current.connection == connection) { "Geräteverbindung geändert." }
                log("SEND_ATTEMPT", "sendVerifiedPresetP01SelectionProbe Länge 22 Sendecalls 2 Abstand 3 ms")
            }

            calls = 1
            opened.sendVerifiedPresetP01()
            delay(3)
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch nach erstem Sendecall." }
                val current = eligibility()
                current.check()
                check(current.connection == connection) { "Geräteverbindung geändert." }
            }
            calls = 2
            opened.sendVerifiedPresetP01()
            success = true
            synchronized(lock) {
                log("SEND_SUCCESS", "Sendecalls 2; Android hat beide P01-Nachrichten angenommen; Display manuell prüfen.")
            }
        } catch (error: Exception) {
            failure = "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt."
            synchronized(lock) { log("SEND_FAILED", "$failure Sendecalls $calls") }
        } finally {
            synchronized(lock) {
                if (opened != null) {
                    val closed = runCatching { opened.close() }
                    log("PORT_CLOSED", "Sendecalls $calls geschlossen=${closed.isSuccess}")
                    if (closed.isFailure) {
                        success = false
                        failure = "Portschluss fehlgeschlagen. Es wurde kein weiterer Sendeversuch durchgeführt."
                        log("SEND_FAILED", requireNotNull(failure))
                    }
                }
                port = null
            }
            inProgress.set(false)
        }
        return status() + mapOf("success" to success, "error" to failure, "sendCalls" to calls)
    }

    fun cancel() = synchronized(lock) {
        ++generation
        port?.let {
            log("PORT_CLOSED", "Lifecycle-Abbruch geschlossen=${runCatching { it.close() }.isSuccess}")
        }
        port = null
    }

    fun detached(connection: String?) = synchronized(lock) {
        cancel()
        if (connection != null) attemptedConnections.remove(connection)
    }
}
