package de.neevel.wyrmtone

import java.util.concurrent.atomic.AtomicBoolean

/**
 * Runs the fixed Full Live plan once per USB connection. The first failure
 * stops the run immediately: the remaining operations are NOT sent, there is
 * no retry and no rollback. A transport error is never reported as success.
 * No Store / commit is part of this session.
 */
enum class MatriboxFullLiveOutcome {
    SUCCESS,
    DEVICE_NOT_CONNECTED,
    MIDI_NOT_AVAILABLE,
    SAFETY_REJECTED,
    SEND_FAILED,
}

private class MatriboxFullLiveRejection(
    val outcome: MatriboxFullLiveOutcome,
    message: String,
) : Exception(message)

internal class MatriboxFullLiveCertificationSession(
    private val eligibility: () -> ProbeEligibility,
    private val openSendPort: () -> MatriboxFullLiveSendPort,
    private val clock: () -> Long = System::currentTimeMillis,
    private val pause: (Long) -> Unit = { Thread.sleep(it) },
    /**
     * Whole-plan preflight BEFORE the port is opened or a run is consumed: returns a
     * rejection message (zero sends) or null. Plans without one pass through.
     */
    private val preflight: (String, List<FullLiveOperation>, CertificationTarget?) -> String? = { _, _, _ -> null },
    /** Resolves a plan id to its fixed constant operation list (or null). */
    private val planResolver: (String) -> List<FullLiveOperation>? = { id ->
        if (id == MatriboxFullLivePlan.PLAN_ID) MatriboxFullLivePlan.operations else null
    },
) {
    private val inProgress = AtomicBoolean(false)
    private val lock = Any()
    private val attemptedConnections = mutableSetOf<String>()
    private var generation = 0
    private var port: MatriboxFullLiveSendPort? = null
    private val logs = mutableListOf<String>()
    private fun log(event: String, details: String) {
        logs.add("[${clock()}] $event $details")
        if (logs.size > 200) logs.removeAt(0)
    }

    fun status(): Map<String, Any?> = synchronized(lock) {
        val current = eligibility()
        mapOf(
            "enabled" to current.enabled,
            "attempted" to (current.connection in attemptedConnections),
            "connection" to current.connection,
            "busy" to inProgress.get(),
            "ready" to runCatching { current.check() }.isSuccess,
            "planId" to MatriboxFullLivePlan.PLAN_ID,
            "logs" to logs.toList(),
        )
    }

    private fun classifyAndCheck(current: ProbeEligibility) {
        if (!current.enabled) {
            throw MatriboxFullLiveRejection(MatriboxFullLiveOutcome.SAFETY_REJECTED, "Native Freigabe fehlt.")
        }
        if (current.connection == null || current.vendor != 0x84ef || current.product != 0x0054) {
            throw MatriboxFullLiveRejection(
                MatriboxFullLiveOutcome.DEVICE_NOT_CONNECTED,
                "Matribox nicht eindeutig verbunden.",
            )
        }
        if (!current.uniqueUsb || !current.uniqueMidi || !current.directlyMapped ||
            !current.deviceOpen || !current.expectedInput || current.monitoring
        ) {
            throw MatriboxFullLiveRejection(
                MatriboxFullLiveOutcome.MIDI_NOT_AVAILABLE,
                "MIDI-Zugriff nicht eindeutig verfügbar.",
            )
        }
    }

    fun run(planId: String, target: CertificationTarget? = null): Map<String, Any?> {
        check(inProgress.compareAndSet(false, true)) {
            "Lauf läuft bereits. Es wurde kein weiterer Sendeversuch durchgeführt."
        }
        val resolvedPlan = planResolver(planId)
        val operations = resolvedPlan ?: emptyList()
        val statuses = MutableList(operations.size) { "NOT_SENT" }
        var opened: MatriboxFullLiveSendPort? = null
        var outcome: MatriboxFullLiveOutcome
        var error: String?
        var failedIndex: Int? = null
        try {
            if (resolvedPlan == null) {
                throw MatriboxFullLiveRejection(
                    MatriboxFullLiveOutcome.SAFETY_REJECTED,
                    "Unbekannte Plan-ID: $planId.",
                )
            }
            // WHOLE-PLAN PREFLIGHT: no side effect, nothing opened, no run consumed, nothing sent.
            preflight(planId, resolvedPlan, target)?.let { message ->
                synchronized(lock) { log("PREFLIGHT_REJECTED", message) }
                throw MatriboxFullLiveRejection(MatriboxFullLiveOutcome.SAFETY_REJECTED, "Preflight abgelehnt: $message")
            }
            val token: Int
            val connection: String
            synchronized(lock) {
                val current = eligibility()
                classifyAndCheck(current)
                connection = requireNotNull(current.connection)
                check(connection !in attemptedConnections) {
                    "Full-Live-Lauf in dieser Verbindung bereits ausgeführt."
                }
                attemptedConnections.add(connection) // consumed also on failure: never retried
                token = generation
                log(
                    "MANUAL_CONFIRMATION",
                    "Sonicake Matribox 1 84EF:0054 User P01 Plan $planId ${operations.size} Operationen, " +
                        "${target?.let { "Backup ${it.backupHash.take(12)}, " } ?: ""}kein Store",
                )
            }
            val openedPort = openSendPort()
            opened = openedPort
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                port = openedPort
            }
            for ((index, operation) in operations.withIndex()) {
                synchronized(lock) {
                    check(token == generation) { "Lifecycle-Abbruch." }
                    val current = eligibility()
                    classifyAndCheck(current)
                    check(current.connection == connection) { "Geräteverbindung geändert." }
                    val message = MatriboxFullLiveCodec.encode(operation)
                    MatriboxFullLiveCodec.validate(message)
                    log("SEND_ATTEMPT", "#$index ${operation.label} ${message.joinToString(" ") { "%02x".format(it) }}")
                    try {
                        openedPort.sendOperation(operation)
                    } catch (thrown: Exception) {
                        failedIndex = index
                        statuses[index] = "FAILED"
                        throw thrown
                    }
                    statuses[index] = "SENT"
                    log("SEND_SUCCESS", "#$index gesendet")
                }
                pause(MatriboxFullLivePlan.pauseAfterMillis(operation))
            }
            outcome = MatriboxFullLiveOutcome.SUCCESS
            error = null
        } catch (thrown: MatriboxFullLiveRejection) {
            outcome = thrown.outcome
            error = thrown.message
            synchronized(lock) { log("RUN_REJECTED", "$error") }
        } catch (thrown: Exception) {
            outcome = MatriboxFullLiveOutcome.SEND_FAILED
            error = "${thrown.message} Restliche Operationen wurden nicht gesendet, kein Retry, kein Rollback."
            synchronized(lock) { log("RUN_STOPPED", "$error") }
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
            "total" to operations.size,
            "completed" to statuses.count { it == "SENT" },
            "failedIndex" to failedIndex,
            "operations" to operations.mapIndexed { i, op ->
                mapOf("index" to i, "label" to op.label, "status" to statuses[i])
            },
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
