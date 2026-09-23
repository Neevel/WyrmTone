package de.neevel.wyrmtone

import java.util.concurrent.atomic.AtomicBoolean

/**
 * Certification write session: sends at most one Sol-100-OD AMP write for
 * a whitelisted certification field on User/P01 per USB connection. Same
 * one-shot, no-retry, fail-closed design as
 * [MatriboxConfirmedGainWriteSession]; a transport error is never mapped
 * to SUCCESS. Gain is rejected (already certified through its own path).
 */
enum class MatriboxCertificationWriteOutcome {
    SUCCESS,
    DEVICE_NOT_CONNECTED,
    MIDI_NOT_AVAILABLE,
    INVALID_VALUE,
    SEND_FAILED,
    SAFETY_REJECTED,
}

private class MatriboxCertificationWriteRejection(
    val outcome: MatriboxCertificationWriteOutcome,
    message: String,
) : Exception(message)

internal class MatriboxSol100OdCertificationSession(
    private val eligibility: () -> ProbeEligibility,
    private val openSendPort: () -> MatriboxSol100OdCertificationSendPort,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val inProgress = AtomicBoolean(false)
    private val lock = Any()
    private val attemptedConnections = mutableSetOf<String>()
    private var generation = 0
    private var port: MatriboxSol100OdCertificationSendPort? = null
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
            throw MatriboxCertificationWriteRejection(
                MatriboxCertificationWriteOutcome.SAFETY_REJECTED,
                "Native Freigabe fehlt.",
            )
        }
        if (current.connection == null || current.vendor != 0x84ef || current.product != 0x0054) {
            throw MatriboxCertificationWriteRejection(
                MatriboxCertificationWriteOutcome.DEVICE_NOT_CONNECTED,
                "Matribox nicht eindeutig verbunden.",
            )
        }
        if (!current.uniqueUsb || !current.uniqueMidi || !current.directlyMapped ||
            !current.deviceOpen || !current.expectedInput || current.monitoring
        ) {
            throw MatriboxCertificationWriteRejection(
                MatriboxCertificationWriteOutcome.MIDI_NOT_AVAILABLE,
                "MIDI-Zugriff nicht eindeutig verfügbar.",
            )
        }
    }

    /**
     * Sends exactly one certification write for the whitelisted field, once
     * per connection, if and only if every safety check passes. No
     * automatic retry; a failed attempt still consumes the one-shot latch
     * once the connection was identified as eligible.
     */
    fun writeCertificationAmpField(fieldName: String, targetValue: Double): Map<String, Any?> {
        check(inProgress.compareAndSet(false, true)) {
            "Schreibvorgang läuft bereits. Es wurde kein weiterer Sendeversuch durchgeführt."
        }
        var opened: MatriboxSol100OdCertificationSendPort? = null
        var outcome: MatriboxCertificationWriteOutcome
        var error: String?
        try {
            val field = Sol100OdAmpField.fromWireName(fieldName)
            if (field == null || field !in Sol100OdAmpField.CERTIFICATION_FIELDS) {
                throw MatriboxCertificationWriteRejection(
                    MatriboxCertificationWriteOutcome.SAFETY_REJECTED,
                    "Feld ist nicht für die Certification freigegeben: $fieldName.",
                )
            }
            val value = targetValue.toFloat()
            if (!value.isFinite() ||
                value < MatriboxSol100OdAmpWriter.MIN_VALUE ||
                value > MatriboxSol100OdAmpWriter.MAX_VALUE
            ) {
                throw MatriboxCertificationWriteRejection(
                    MatriboxCertificationWriteOutcome.INVALID_VALUE,
                    "Wert außerhalb des bestätigten Bereichs " +
                        "[${MatriboxSol100OdAmpWriter.MIN_VALUE}, " +
                        "${MatriboxSol100OdAmpWriter.MAX_VALUE}]: $targetValue.",
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
                    "Sonicake Matribox 1 84EF:0054 Sol 100 OD ${field.wireName} " +
                        "Index ${field.parameterIndex} Zielwert $value",
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
                val message = MatriboxSol100OdAmpWriter.encode(field, value)
                MatriboxSol100OdAmpWriter.validate(field, message)
                log("SEND_ATTEMPT", "${field.wireName} Zielwert $value Länge ${message.size}")
                openedPort.sendCertificationWrite(field, value)
                log(
                    "SEND_SUCCESS",
                    "${field.wireName}-Write gesendet, Zielwert $value. " +
                        "Noch kein Store, noch kein Readback.",
                )
            }
            outcome = MatriboxCertificationWriteOutcome.SUCCESS
            error = null
        } catch (thrown: MatriboxCertificationWriteRejection) {
            outcome = thrown.outcome
            error = thrown.message
            synchronized(lock) { log("WRITE_REJECTED", "$error") }
        } catch (thrown: Exception) {
            outcome = MatriboxCertificationWriteOutcome.SEND_FAILED
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
            "field" to fieldName,
            "value" to targetValue,
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
