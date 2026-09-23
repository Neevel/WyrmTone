package de.neevel.wyrmtone

import java.util.concurrent.atomic.AtomicBoolean

/**
 * The exactly-one-supported production write operation: Sol-100-OD Gain
 * on User/P01. Mirrors [VerifiedMatriboxProbe]'s one-shot-per-connection,
 * no-retry, fail-closed design exactly, generalised from a single fixed
 * historical value to any independently-validated value in
 * [MatriboxConfirmedGainWriter.MIN_VALUE, MatriboxConfirmedGainWriter.MAX_VALUE].
 *
 * A write is only ever attempted once per USB connection -- exactly like
 * the historical write probe -- even though the *read* side
 * ([MatriboxPresetReader]) is deliberately repeatable. A write is a far
 * more consequential action than a read, so this class keeps the more
 * conservative one-shot latch rather than relaxing it.
 */
enum class MatriboxGainWriteOutcome {
    SUCCESS,
    DEVICE_NOT_CONNECTED,
    MIDI_NOT_AVAILABLE,
    INVALID_VALUE,
    SEND_FAILED,
    SAFETY_REJECTED,
}

private class MatriboxGainWriteRejection(
    val outcome: MatriboxGainWriteOutcome,
    message: String,
) : Exception(message)

internal class MatriboxConfirmedGainWriteSession(
    private val eligibility: () -> ProbeEligibility,
    private val openSendPort: () -> MatriboxConfirmedGainWriteSendPort,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val inProgress = AtomicBoolean(false)
    private val lock = Any()
    private val attemptedConnections = mutableSetOf<String>()
    private var generation = 0
    private var port: MatriboxConfirmedGainWriteSendPort? = null
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

    private fun classifyAndCheck(current: ProbeEligibility) {
        if (!current.enabled) {
            throw MatriboxGainWriteRejection(
                MatriboxGainWriteOutcome.SAFETY_REJECTED,
                "Native Freigabe fehlt.",
            )
        }
        if (current.connection == null || current.vendor != 0x84ef || current.product != 0x0054) {
            throw MatriboxGainWriteRejection(
                MatriboxGainWriteOutcome.DEVICE_NOT_CONNECTED,
                "Matribox nicht eindeutig verbunden.",
            )
        }
        if (!current.uniqueUsb || !current.uniqueMidi || !current.directlyMapped ||
            !current.deviceOpen || !current.expectedInput || current.monitoring
        ) {
            throw MatriboxGainWriteRejection(
                MatriboxGainWriteOutcome.MIDI_NOT_AVAILABLE,
                "MIDI-Zugriff nicht eindeutig verfügbar.",
            )
        }
    }

    /**
     * Sends exactly one Sol-100-OD Gain write for [targetGain], once per
     * connection, if and only if every safety check passes. No automatic
     * retry at any step; a rejected/failed attempt still consumes the
     * one-shot latch once a connection was identified as eligible (never
     * silently retried, even manually, without a real reconnect).
     */
    fun writeConfirmedSol100OdGain(targetGain: Double): Map<String, Any?> {
        check(inProgress.compareAndSet(false, true)) {
            "Schreibvorgang läuft bereits. Es wurde kein weiterer Sendeversuch durchgeführt."
        }
        var opened: MatriboxConfirmedGainWriteSendPort? = null
        var outcome: MatriboxGainWriteOutcome
        var error: String?
        try {
            val value = targetGain.toFloat()
            if (!value.isFinite() ||
                value < MatriboxConfirmedGainWriter.MIN_VALUE ||
                value > MatriboxConfirmedGainWriter.MAX_VALUE
            ) {
                throw MatriboxGainWriteRejection(
                    MatriboxGainWriteOutcome.INVALID_VALUE,
                    "Gain-Wert außerhalb des bestätigten Bereichs " +
                        "[${MatriboxConfirmedGainWriter.MIN_VALUE}, " +
                        "${MatriboxConfirmedGainWriter.MAX_VALUE}]: $targetGain.",
                )
            }
            val token: Int
            val connection: String
            synchronized(lock) {
                val current = eligibility()
                classifyAndCheck(current)
                connection = requireNotNull(current.connection)
                check(connection !in attemptedConnections) {
                    "Schreibversuch in dieser Verbindung bereits ausgeführt."
                }
                attemptedConnections.add(connection) // Consume also on failure. Never retry.
                token = generation
                log(
                    "MANUAL_CONFIRMATION",
                    "Sonicake Matribox 1 84EF:0054 Sol 100 OD Gain-Index 0 Zielwert $value",
                )
            }
            val openedPort = openSendPort()
            opened = openedPort
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                port = openedPort
                val current = eligibility()
                classifyAndCheck(current)
                check(current.connection == connection) { "Geräteverbindung geändert." }
                val message = MatriboxConfirmedGainWriter.encode(value)
                MatriboxConfirmedGainWriter.validate(message)
                log("SEND_ATTEMPT", "Zielwert $value Länge ${message.size}")
                openedPort.sendGainWrite(value)
                log(
                    "SEND_SUCCESS",
                    "Gain-Write gesendet, Zielwert $value. Noch kein Store, noch kein Readback.",
                )
            }
            outcome = MatriboxGainWriteOutcome.SUCCESS
            error = null
        } catch (thrown: MatriboxGainWriteRejection) {
            outcome = thrown.outcome
            error = thrown.message
            synchronized(lock) { log("WRITE_REJECTED", "$error") }
        } catch (thrown: Exception) {
            outcome = MatriboxGainWriteOutcome.SEND_FAILED
            error = "${thrown.message} Es wurde kein weiterer Sendeversuch durchgeführt."
            synchronized(lock) { log("SEND_FAILED", "$error") }
        } finally {
            synchronized(lock) {
                val toClose = opened
                if (toClose != null) {
                    val closed = runCatching { toClose.close() }
                    log("PORT_CLOSED", "geschlossen=${closed.isSuccess}")
                }
                port = null
            }
            inProgress.set(false)
        }
        return status() + mapOf(
            "outcome" to outcome.name,
            "error" to error,
            "value" to targetGain,
        )
    }

    fun cancel() = synchronized(lock) {
        ++generation
        port?.let { runCatching { it.close() } }
        port = null
    }

    fun detached(connection: String?) = synchronized(lock) {
        cancel()
        if (connection != null) attemptedConnections.remove(connection)
    }
}
