package de.neevel.wyrmtone

import java.util.concurrent.atomic.AtomicBoolean

enum class ToneTransferOutcome {
    SUCCESS,
    VALIDATION_REJECTED,
    DEVICE_NOT_CONNECTED,
    MIDI_NOT_AVAILABLE,
    SAFETY_REJECTED,
    SEND_FAILED,
}

private class ToneTransferGuard(val outcome: ToneTransferOutcome, message: String) : Exception(message)

/**
 * Productive Tone Transfer, native side: VALIDATE WHOLE PLAN (including the
 * target: User P11..P99 only), then SELECT the target preset (the confirmed
 * editor message, sent twice like the editor), then EXECUTE in plan order.
 * One run per plan id, slot and connection, no retry, no dynamic plan
 * change, first transport failure stops (completed / failed / notSent), no
 * rollback, no Store. Nothing -- not even the preset select -- is sent when
 * the target or any single operation is invalid.
 */
internal class MatriboxToneTransferSession(
    private val eligibility: () -> ProbeEligibility,
    private val openSendPort: () -> MatriboxToneTransferSendPort,
    private val clock: () -> Long = System::currentTimeMillis,
    private val pause: (Long) -> Unit = { Thread.sleep(it) },
) {
    private val inProgress = AtomicBoolean(false)
    private val lock = Any()
    private val attempted = mutableSetOf<String>()
    private var generation = 0
    private var port: MatriboxToneTransferSendPort? = null
    private val logs = mutableListOf<String>()

    private fun log(event: String, details: String) {
        logs.add("[${clock()}] $event $details")
        if (logs.size > 200) logs.removeAt(0)
    }

    fun status(): Map<String, Any?> = synchronized(lock) {
        val current = eligibility()
        mapOf(
            "enabled" to current.enabled,
            "connection" to current.connection,
            "busy" to inProgress.get(),
            "ready" to runCatching { current.check() }.isSuccess,
            "logs" to logs.toList(),
        )
    }

    private fun result(
        outcome: ToneTransferOutcome,
        error: String?,
        code: String?,
        operations: List<FullLiveOperation>,
        statuses: List<String>,
        failedIndex: Int?,
        target: MatriboxWritableUserPreset?,
        presetSelect: String,
    ): Map<String, Any?> = status() + mapOf(
        "outcome" to outcome.name,
        "targetSlot" to target?.presetNumber,
        "presetSelect" to presetSelect,
        "error" to error,
        "errorCode" to code,
        "total" to operations.size,
        "completed" to statuses.count { it == "SENT" },
        "failedIndex" to failedIndex,
        "operations" to operations.mapIndexed { i, op ->
            mapOf("index" to i, "label" to op.label, "status" to statuses[i])
        },
    )

    fun execute(request: Any?): Map<String, Any?> {
        // 1. VALIDATE WHOLE PLAN: no side effect, nothing opened, nothing sent.
        val plan = try {
            MatriboxToneTransferPlanValidator.validate(request)
        } catch (rejection: ToneTransferRejection) {
            synchronized(lock) { log("PLAN_REJECTED", "${rejection.code} ${rejection.message}") }
            return result(
                ToneTransferOutcome.VALIDATION_REJECTED,
                rejection.message,
                rejection.code,
                emptyList(),
                emptyList(),
                null,
                null,
                "NOT_SENT",
            )
        }
        val operations = plan.operations
        val target = plan.target
        val statuses = MutableList(operations.size) { "NOT_SENT" }
        var presetSelect = "NOT_SENT"
        check(inProgress.compareAndSet(false, true)) {
            "Übertragung läuft bereits. Es wurde kein weiterer Sendeversuch durchgeführt."
        }
        var opened: MatriboxToneTransferSendPort? = null
        var outcome: ToneTransferOutcome
        var error: String? = null
        var failedIndex: Int? = null
        try {
            val token: Int
            val connection: String
            synchronized(lock) {
                val current = eligibility()
                if (!current.enabled) throw ToneTransferGuard(ToneTransferOutcome.SAFETY_REJECTED, "Native Freigabe fehlt.")
                val name = current.connection
                if (name == null || current.vendor != 0x84ef || current.product != 0x0054) {
                    throw ToneTransferGuard(ToneTransferOutcome.DEVICE_NOT_CONNECTED, "Matribox nicht eindeutig verbunden.")
                }
                if (!current.uniqueUsb || !current.uniqueMidi || !current.directlyMapped ||
                    !current.deviceOpen || !current.expectedInput || current.monitoring
                ) {
                    throw ToneTransferGuard(ToneTransferOutcome.MIDI_NOT_AVAILABLE, "MIDI-Zugriff nicht eindeutig verfügbar.")
                }
                connection = name
                val key = "$connection|${target.presetNumber}|${plan.planId}"
                if (key in attempted) {
                    throw ToneTransferGuard(
                        ToneTransferOutcome.SAFETY_REJECTED,
                        "Dieser Plan wurde in dieser Verbindung bereits ausgeführt (kein Retry).",
                    )
                }
                attempted.add(key) // consumed also on failure: never retried
                token = generation
                log(
                    "EXECUTE",
                    "Plan ${plan.planId} ${operations.size} Operationen, Backup ${plan.backupHash.take(12)}, " +
                        "User ${target.label} (Index ${target.deviceIndex}), kein Store",
                )
            }
            val openedPort = openSendPort()
            opened = openedPort
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                port = openedPort
            }
            // The live edits land on the ACTIVE preset: select the target first. Like the editor
            // capture (and the hardware-confirmed P01 probe) the message goes out twice.
            for (repeat in 0 until PRESET_SELECT_TRANSMISSIONS) {
                synchronized(lock) {
                    check(token == generation) { "Lifecycle-Abbruch." }
                    val current = eligibility()
                    check(current.connection == connection && !current.monitoring) { "Geräteverbindung geändert." }
                    val message = MatriboxPresetSelectReference.message(target)
                    MatriboxPresetSelectReference.validate(message, target)
                    log("PRESET_SELECT_ATTEMPT", "${target.label} #$repeat ${message.joinToString(" ") { "%02x".format(it) }}")
                    try {
                        openedPort.selectUserPreset(target)
                    } catch (thrown: Exception) {
                        presetSelect = "FAILED"
                        throw thrown
                    }
                    // one transmission is out: from here an abort is FAILED, never NOT_SENT
                    presetSelect = if (repeat + 1 < PRESET_SELECT_TRANSMISSIONS) "FAILED" else "SENT"
                }
                pause(if (repeat + 1 < PRESET_SELECT_TRANSMISSIONS) PRESET_SELECT_REPEAT_MILLIS else PRESET_SELECT_SETTLE_MILLIS)
            }
            synchronized(lock) { log("PRESET_SELECT_SUCCESS", "${target.label} ausgewählt") }
            for ((index, operation) in operations.withIndex()) {
                synchronized(lock) {
                    check(token == generation) { "Lifecycle-Abbruch." }
                    val current = eligibility()
                    check(current.connection == connection && !current.monitoring) { "Geräteverbindung geändert." }
                    val message = MatriboxFullLiveCodec.encode(operation)
                    MatriboxFullLiveCodec.validate(message)
                    log("SEND_ATTEMPT", "#$index ${operation.label} ${message.joinToString(" ") { "%02x".format(it) }}")
                    try {
                        openedPort.sendValidated(operation)
                    } catch (thrown: Exception) {
                        failedIndex = index
                        statuses[index] = "FAILED"
                        throw thrown
                    }
                    statuses[index] = "SENT"
                    log("SEND_SUCCESS", "#$index gesendet")
                }
                pause(pauseAfterMillis(operation))
            }
            outcome = ToneTransferOutcome.SUCCESS
        } catch (guard: ToneTransferGuard) {
            outcome = guard.outcome
            error = guard.message
            synchronized(lock) { log("RUN_REJECTED", "$error") }
        } catch (thrown: Exception) {
            outcome = ToneTransferOutcome.SEND_FAILED
            error = "${thrown.message} Restliche Operationen wurden nicht gesendet, kein Retry, kein Rollback."
            synchronized(lock) { log("RUN_STOPPED", "$error") }
        } finally {
            synchronized(lock) {
                opened?.let {
                    val closed = runCatching { it.close() }
                    log("PORT_CLOSED", "geschlossen=${closed.isSuccess}")
                }
                port = null
            }
            inProgress.set(false)
        }
        return result(outcome, error, null, operations, statuses, failedIndex, target, presetSelect)
    }

    fun cancel() = synchronized(lock) {
        ++generation
        port?.let { runCatching { it.close() } }
        port = null
    }

    fun detached(connection: String?) = synchronized(lock) {
        cancel()
        if (connection != null) attempted.removeAll { it.startsWith("$connection|") }
    }

    private companion object {
        const val PRESET_SELECT_TRANSMISSIONS = 2
        const val PRESET_SELECT_REPEAT_MILLIS = 3L

        /** Time for the device to load the selected preset before the first live edit. */
        const val PRESET_SELECT_SETTLE_MILLIS = 500L

        /** Pacing of the confirmed live-edit messages: a model select needs longer to settle. */
        fun pauseAfterMillis(operation: FullLiveOperation): Long =
            if (operation is FullLiveOperation.ModelSelect) 200L else 60L
    }
}
