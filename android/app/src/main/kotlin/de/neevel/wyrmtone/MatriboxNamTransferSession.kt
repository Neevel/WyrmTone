package de.neevel.wyrmtone

import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

enum class NamTransferOutcome {
    SUCCESS,
    ALREADY_USED,
    NOT_ELIGIBLE,
    OPEN_FAILED,
    SEND_FAILED,
    TIMEOUT,
    MALFORMED_ACK,
    WRONG_SLOT,
    WRONG_BLOCK,
    UNEXPECTED_STATUS,
    UNEXPECTED_MESSAGE,
}

private class NamTransferGuard(val outcome: NamTransferOutcome, message: String) : Exception(message)

/**
 * V5B.2c: bounded, experimental-only diagnostics -- no personal or
 * device-identifying data, just protocol-level bytes/timestamps for THIS
 * transfer session. One entry per raw `MidiReceiver.onSend` callback,
 * already offset/count-sliced by the caller.
 */
internal class NamRawCallbackLog(val timestampNanos: Long, val byteCount: Int, val hex: String)

/** One entry per COMPLETE SysEx message [NamAckStreamAssembler] emitted. */
internal class NamAssembledMessageLog(val sequence: Int, val length: Int, val hex: String, val classification: String)

private fun ByteArray.toHex(): String = joinToString(" ") { "%02x".format(it) }

/**
 * V5B.2a: the ONLY place in this repository that owns a send
 * ([MatriboxNamCloneSendPort]) AND a receive ([ReceiveOnlyMidiPort]) port
 * for the Matribox at the same time. Deliberately narrow -- it knows
 * nothing but the confirmed NAM Clone-transfer protocol: send one
 * [NamCloneTransferFrame], wait for its ACK, validate slot/block/status,
 * advance; never two outbound frames without an accepted ACK between
 * them, never a retry, never a second [execute] on the same instance
 * (mirrors `V5WriteBudget`'s one-shot semantics natively). Does not touch
 * [PassiveMidiMonitor] and is not reachable while it is active --
 * [eligibility] is the SAME [ProbeEligibility] shape the other two
 * senders already use, whose `check()` already requires `!monitoring`.
 */
internal class MatriboxNamTransferSession(
    private val eligibility: () -> ProbeEligibility,
    private val openSendPort: () -> MatriboxNamCloneSendPort,
    private val openReceivePort: () -> ReceiveOnlyMidiPort,
    private val ackTimeoutMillis: Long = 2000L,
    /** After the expected ACK, how long to wait for a stray extra message. */
    private val quietPeriodMillis: Long = 50L,
    /**
     * Product NAM transfer V1: an observability-only hook, called once per
     * CONFIRMED ACK (never per send) with (confirmedCount, lastConfirmedBlock,
     * totalFrames) -- lets the UI show real "347 von 590" progress instead of
     * a fake timer. Never influences protocol behaviour: the strict
     * stop-and-wait loop below is unchanged whether or not this is set, and
     * an exception thrown by it is never allowed to affect the transfer (see
     * its call site).
     */
    private val onProgress: ((confirmedCount: Int, lastConfirmedBlock: Int, totalFrames: Int) -> Unit)? = null,
) {
    private val used = AtomicBoolean(false)
    private val activeFlag = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)

    /** True only while [execute] is running -- gates the passive monitor. */
    val isActive: Boolean get() = activeFlag.get()

    // V5B.2c: bounded (see MAX_DIAGNOSTIC_ENTRIES), experimental-only, cleared per execute().
    private val rawCallbacks = mutableListOf<NamRawCallbackLog>()
    private val assembledMessages = mutableListOf<NamAssembledMessageLog>()
    private var assembledSequence = 0

    @Volatile private var executingThread: Thread? = null

    /**
     * Aborts an in-progress [execute] from another thread (device
     * lifecycle interruption: USB detach, app pause closing the device).
     * Interrupts the thread blocked in the ACK-receive-queue poll (closing
     * the ports alone does NOT wake that poll -- a fake test port proved
     * this: it just sits blocked until its own timeout, so cancel() would
     * silently do nothing for up to [ackTimeoutMillis]) and closes both
     * ports; [execute] still runs its own `finally` cleanup exactly as on
     * any other abort path (the resulting `InterruptedException` is caught
     * by the same generic handler every other native-layer failure is). A
     * no-op if [execute] never ran, has already finished, or was already
     * cancelled.
     */
    fun cancel() {
        if (!cancelled.compareAndSet(false, true)) return
        executingThread?.interrupt()
        volatileReceivePort?.let { runCatching { it.disconnect() }; runCatching { it.close() } }
        volatileSendPort?.let { runCatching { it.close() } }
    }

    @Volatile private var volatileSendPort: MatriboxNamCloneSendPort? = null
    @Volatile private var volatileReceivePort: ReceiveOnlyMidiPort? = null

    fun execute(frames: List<NamCloneTransferFrame>): Map<String, Any?> {
        if (!used.compareAndSet(false, true)) {
            return result(NamTransferOutcome.ALREADY_USED, "Sitzung wurde bereits verwendet, kein Retry.", 0, null)
        }
        if (cancelled.get()) {
            return result(NamTransferOutcome.NOT_ELIGIBLE, "Sitzung wurde vor dem ersten Senden abgebrochen.", 0, null)
        }
        // Every frame in one session must target the SAME Clone slot -- each frame's own slot
        // byte was already range-checked by parseValidated, but nothing upstream guarantees they
        // all agree with each other; a session must never silently write to more than one slot.
        val targetSlot = frames.firstOrNull()?.slot
        if (targetSlot == null || frames.any { it.slot != targetSlot }) {
            return result(NamTransferOutcome.NOT_ELIGIBLE, "Frames adressieren nicht alle denselben Clone-Slot.", 0, null)
        }
        activeFlag.set(true)
        executingThread = Thread.currentThread()
        val queue = LinkedBlockingQueue<ByteArray>()
        val assembler = NamAckStreamAssembler()
        rawCallbacks.clear()
        assembledMessages.clear()
        assembledSequence = 0
        var sendPort: MatriboxNamCloneSendPort? = null
        var receivePort: ReceiveOnlyMidiPort? = null
        var sentCount = 0
        var lastConfirmedBlock: Int? = null
        var outcome: NamTransferOutcome
        var error: String
        try {
            val current = eligibility()
            try {
                current.check()
            } catch (rejection: IllegalArgumentException) {
                throw NamTransferGuard(NamTransferOutcome.NOT_ELIGIBLE, rejection.message ?: "Nicht bereit.")
            }
            receivePort = try {
                openReceivePort().also {
                    it.connect { bytes, timestamp ->
                        if (rawCallbacks.size < MAX_DIAGNOSTIC_ENTRIES) {
                            rawCallbacks.add(NamRawCallbackLog(timestamp, bytes.size, bytes.toHex()))
                        }
                        // NEVER treat one callback as one message: fragmented or
                        // multi-message callbacks are reassembled/split here
                        // BEFORE anything reaches the ACK-validation queue.
                        for (message in assembler.feed(bytes)) {
                            val classification = classifyAssembledMessage(message)
                            if (assembledMessages.size < MAX_DIAGNOSTIC_ENTRIES) {
                                assembledMessages.add(
                                    NamAssembledMessageLog(assembledSequence, message.size, message.toHex(), classification),
                                )
                            }
                            assembledSequence++
                            queue.offer(message)
                        }
                    }
                }
            } catch (thrown: Exception) {
                throw NamTransferGuard(NamTransferOutcome.OPEN_FAILED, "Empfangs-Port: ${thrown.message}")
            }
            volatileReceivePort = receivePort
            if (cancelled.get()) throw NamTransferGuard(NamTransferOutcome.NOT_ELIGIBLE, "Während des Öffnens abgebrochen.")
            sendPort = try {
                openSendPort()
            } catch (thrown: Exception) {
                throw NamTransferGuard(NamTransferOutcome.OPEN_FAILED, "Sende-Port: ${thrown.message}")
            }
            volatileSendPort = sendPort
            if (cancelled.get()) throw NamTransferGuard(NamTransferOutcome.NOT_ELIGIBLE, "Während des Öffnens abgebrochen.")

            for (frame in frames) {
                try {
                    sendPort.sendFrame(frame)
                } catch (thrown: Exception) {
                    throw NamTransferGuard(NamTransferOutcome.SEND_FAILED, "Frame ${frame.block}: ${thrown.message}")
                }
                sentCount++

                val first = queue.poll(ackTimeoutMillis, TimeUnit.MILLISECONDS)
                    ?: throw NamTransferGuard(NamTransferOutcome.TIMEOUT, "Keine Antwort auf Block ${frame.block}.")
                // A stray SECOND message before the quiet period elapses is an
                // anomaly: never silently take "the first" and move on.
                val second = queue.poll(quietPeriodMillis, TimeUnit.MILLISECONDS)
                if (second != null) {
                    throw NamTransferGuard(NamTransferOutcome.UNEXPECTED_MESSAGE, "Zusätzliche Nachricht nach Block ${frame.block}.")
                }
                val ack = try {
                    MatriboxNamCloneTransferReference.parseValidatedAck(first)
                } catch (rejection: IllegalArgumentException) {
                    throw NamTransferGuard(NamTransferOutcome.MALFORMED_ACK, rejection.message ?: "Fehlformatiertes ACK.")
                }
                if (ack.slot != targetSlot) {
                    throw NamTransferGuard(NamTransferOutcome.WRONG_SLOT, "ACK-Slot 0x${ack.slot.toString(16)} statt 0x${targetSlot.toString(16)}.")
                }
                if (ack.block != frame.block) {
                    throw NamTransferGuard(NamTransferOutcome.WRONG_BLOCK, "ACK-Block ${ack.block} statt ${frame.block}.")
                }
                if (!ack.isSuccess) {
                    throw NamTransferGuard(NamTransferOutcome.UNEXPECTED_STATUS, "ACK-Status ${ack.status} statt Erfolg.")
                }
                lastConfirmedBlock = ack.block
                // Observability only -- never allowed to affect the transfer itself.
                runCatching { onProgress?.invoke(sentCount, ack.block, frames.size) }
            }
            outcome = NamTransferOutcome.SUCCESS
            error = ""
        } catch (guard: NamTransferGuard) {
            outcome = guard.outcome
            error = guard.message ?: ""
        } catch (thrown: Exception) {
            outcome = NamTransferOutcome.SEND_FAILED
            error = "${thrown.message} Keine weiteren Frames gesendet, kein Retry."
        } finally {
            activeFlag.set(false)
            executingThread = null
            Thread.interrupted() // clear any interrupt cancel() raised, so the (possibly pooled) thread is clean for its next task
            receivePort?.let { runCatching { it.disconnect() }; runCatching { it.close() } }
            sendPort?.let { runCatching { it.close() } }
            volatileReceivePort = null
            volatileSendPort = null
        }
        return result(outcome, error, sentCount, lastConfirmedBlock)
    }

    private fun result(
        outcome: NamTransferOutcome,
        error: String,
        sentCount: Int,
        lastConfirmedBlock: Int?,
    ): Map<String, Any?> = mapOf(
        "outcome" to outcome.name,
        "error" to error.ifEmpty { null },
        "framesSent" to sentCount,
        "lastConfirmedBlock" to lastConfirmedBlock,
        "rawCallbacks" to rawCallbacks.map {
            mapOf("timestampNanos" to it.timestampNanos, "byteCount" to it.byteCount, "hex" to it.hex)
        },
        "assembledMessages" to assembledMessages.map {
            mapOf("sequence" to it.sequence, "length" to it.length, "hex" to it.hex, "classification" to it.classification)
        },
    )

    /** Structural classification only, for diagnostics -- never used to decide the outcome. */
    private fun classifyAssembledMessage(message: ByteArray): String =
        runCatching { MatriboxNamCloneTransferReference.parseValidatedAck(message) }
            .fold(
                onSuccess = { "ACK slot=0x${it.slot.toString(16)} block=${it.block} status=${it.status}" },
                onFailure = { "unrecognized: ${it.message}" },
            )

    private companion object {
        const val MAX_DIAGNOSTIC_ENTRIES = 200
    }
}
