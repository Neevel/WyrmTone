package de.neevel.wyrmtone

import java.util.concurrent.atomic.AtomicBoolean

/**
 * Production, read-only User preset reader. Sends nothing new: it is
 * the exact same sequence already CONFIRMED and REPRODUCED (byte-identical
 * across two independent hardware connections, see
 * docs/MATRIBOX_OFFLINE_ANALYSIS.md, "V3A Reproduktion") by the
 * experimental [VerifiedPresetP01FullReadProbeV3A] probe -- Phase-D
 * announce/ack for Bank=User Slot=0 ([VerifiedPresetP01PhaseDReference]),
 * followed by the ten fixed part requests already confirmed for V2
 * ([VerifiedPresetP01FullReadReference]). Neither reference is duplicated
 * here; both are reused unchanged. [VerifiedPresetP01FullReadProbeV3A]
 * itself is untouched by this file and remains the historical,
 * independently verifiable diagnostic path.
 *
 * Deliberately UI-independent: this class knows nothing about Flutter, the
 * diagnostics panel, or any compile-gated probe's status map.
 * [readVerifiedUserP01] performs the one confirmed User/P01 sequence;
 * [readVerifiedUserSlot] performs the same sequence for another User slot,
 * with only the confirmed slot byte replaced ([MatriboxUserSlotReadReference];
 * for P01 byte-identical to the references). Every response must name
 * exactly the requested Bank=User/slot, so a read of P11 can never return
 * another slot's data.
 */
enum class MatriboxPresetReadOutcome {
    SUCCESS,
    PHASE_D_TIMEOUT,
    PHASE_D_INVALID,
    PART_TIMEOUT,
    PART_INVALID,
    INCOMPLETE,
    TRANSPORT_ERROR,
}

/**
 * Immutable read result. [phaseDResponse] and [parts] are only non-null/
 * non-empty when [outcome] is SUCCESS -- a partial result is never
 * returned as if it were a valid snapshot. [parts] has exactly 10 entries
 * on SUCCESS, each the raw framed SysEx response bytes (F0..F7 inclusive)
 * for that part index, in order.
 */
data class MatriboxPresetReadResult(
    val outcome: MatriboxPresetReadOutcome,
    val phaseDResponse: ByteArray?,
    val parts: List<ByteArray>,
    val error: String?,
)

/**
 * This interface cannot accept bytes, a bank or an arbitrary part number.
 * [sendPhaseDAnnounce] only ever sends the confirmed Phase-D announce and
 * [sendPartRequest] only ever one of the ten confirmed requests
 * ([VerifiedPresetP01FullReadReference]), each addressed at a validated
 * User preset through [MatriboxUserSlotReadReference].
 */
internal interface MatriboxPresetReaderSendPort {
    fun sendPhaseDAnnounce(slot: MatriboxUserPreset)
    fun sendPartRequest(slot: MatriboxUserPreset, partIndex: Int)
    fun close()
}

internal class MatriboxPresetReader(
    private val eligibility: () -> ProbeEligibility,
    private val openSendPort: () -> MatriboxPresetReaderSendPort,
    private val openReceivePort: () -> ReceiveOnlyMidiPort,
    private val delay: (Long) -> Unit = Thread::sleep,
    private val stepTimeoutMillis: Long = 500,
) {
    private val inProgress = AtomicBoolean(false)
    private val lock = Any()
    private var generation = 0
    private var sendPort: MatriboxPresetReaderSendPort? = null
    private var receivePort: ReceiveOnlyMidiPort? = null

    fun status(): Map<String, Any?> = synchronized(lock) {
        val current = eligibility()
        mapOf(
            "enabled" to current.enabled,
            "connection" to current.connection,
            "busy" to inProgress.get(),
            "ready" to runCatching { current.check() }.isSuccess,
        )
    }

    /**
     * Performs exactly one User/P01 read attempt: Phase-D announce, wait
     * for a structurally matching ack, then the ten part requests in
     * order, each only sent after the previous step's response validated.
     * No retry at any step -- a stalled or unexpected response stops the
     * whole read immediately and returns the corresponding outcome. Unlike
     * the experimental probes, this is not one-shot-per-connection: it may
     * be called again (e.g. to create another backup later), but never
     * runs two reads concurrently.
     */
    fun readVerifiedUserP01(): MatriboxPresetReadResult = readVerifiedUserSlot(MatriboxUserPreset.P01)

    /** The same single read attempt for exactly [slot]; see [readVerifiedUserP01]. */
    fun readVerifiedUserSlot(slot: MatriboxUserPreset): MatriboxPresetReadResult {
        check(inProgress.compareAndSet(false, true)) {
            "Lesevorgang läuft bereits."
        }
        var sent: MatriboxPresetReaderSendPort? = null
        var received: ReceiveOnlyMidiPort? = null
        val accumulator = SysExAccumulator()
        val windowMessages = mutableListOf<ByteArray>()
        val parts = mutableListOf<ByteArray>()
        var phaseDResponse: ByteArray? = null
        var outcome: MatriboxPresetReadOutcome = MatriboxPresetReadOutcome.TRANSPORT_ERROR
        var error: String? = null
        var token = -1
        try {
            synchronized(lock) {
                eligibility().check()
                MatriboxUserSlotReadReference.validate()
                token = generation
            }
            val openedReceive = openReceivePort()
            received = openedReceive
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                receivePort = openedReceive
            }
            openedReceive.connect { bytes, _ ->
                synchronized(lock) {
                    if (receivePort !== openedReceive || token != generation) return@connect
                    windowMessages.addAll(accumulator.feed(bytes))
                }
            }
            synchronized(lock) { check(token == generation) { "Lifecycle-Abbruch." } }
            val openedSend = openSendPort()
            sent = openedSend
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                sendPort = openedSend
            }

            synchronized(lock) { windowMessages.clear() }
            openedSend.sendPhaseDAnnounce(slot)
            delay(stepTimeoutMillis)
            val ackSnapshot = synchronized(lock) { windowMessages.toList() }
            // Fail closed: exactly one complete SysEx is expected.
            val ack = ackSnapshot.singleOrNull()
                ?.takeIf { MatriboxUserSlotReadReference.isValidAck(it, slot) }
            if (ack == null) {
                outcome = if (ackSnapshot.isEmpty()) {
                    MatriboxPresetReadOutcome.PHASE_D_TIMEOUT
                } else {
                    MatriboxPresetReadOutcome.PHASE_D_INVALID
                }
                error = "Phase D wurde nicht bestätigt."
            } else {
                phaseDResponse = ack
                outcome = MatriboxPresetReadOutcome.SUCCESS
                partLoop@ for (partIndex in VerifiedPresetP01FullReadReference.requests.indices) {
                    synchronized(lock) { check(token == generation) { "Lifecycle-Abbruch." } }
                    synchronized(lock) { windowMessages.clear() }
                    openedSend.sendPartRequest(slot, partIndex)
                    delay(stepTimeoutMillis)
                    val snapshot = synchronized(lock) { windowMessages.toList() }
                    val match = snapshot.singleOrNull()?.takeIf {
                        MatriboxUserSlotReadReference.isValidResponse(it, slot, partIndex)
                    }
                    if (match == null) {
                        outcome = if (snapshot.isEmpty()) {
                            MatriboxPresetReadOutcome.PART_TIMEOUT
                        } else {
                            MatriboxPresetReadOutcome.PART_INVALID
                        }
                        error = "Teil $partIndex wurde nicht bestätigt."
                        break@partLoop
                    }
                    parts.add(match)
                }
                if (outcome == MatriboxPresetReadOutcome.SUCCESS &&
                    parts.size != VerifiedPresetP01FullReadReference.requests.size
                ) {
                    // Unreachable given the loop above already breaks on any
                    // non-matching step; kept as a fail-closed invariant guard.
                    outcome = MatriboxPresetReadOutcome.INCOMPLETE
                    error = "Nicht alle zehn Teile wurden empfangen."
                }
            }
        } catch (thrown: Exception) {
            outcome = MatriboxPresetReadOutcome.TRANSPORT_ERROR
            error = thrown.message
        } finally {
            synchronized(lock) {
                if (token == generation) {
                    sent?.let { runCatching { it.close() } }
                    sendPort = null
                    received?.let {
                        runCatching { it.disconnect() }
                        runCatching { it.close() }
                    }
                    receivePort = null
                }
            }
            inProgress.set(false)
        }
        return if (outcome == MatriboxPresetReadOutcome.SUCCESS) {
            MatriboxPresetReadResult(outcome, phaseDResponse, parts.toList(), null)
        } else {
            // A partial result is never returned as if it were valid.
            MatriboxPresetReadResult(outcome, null, emptyList(), error)
        }
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
}
