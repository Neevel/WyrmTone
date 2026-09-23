package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/**
 * This interface cannot accept bytes, a slot number, an algorithm id or a
 * parameter index: only an operation of the fixed [MatriboxFullLivePlan],
 * which the port itself re-checks against that plan.
 */
internal interface MatriboxFullLiveSendPort {
    fun sendOperation(operation: FullLiveOperation)
    fun close()
}

/** Android MIDI only; the only actual send call site for the Full Live test. */
internal class MatriboxFullLiveWriterPort(private val input: MidiInputPort) : MatriboxFullLiveSendPort {
    private val closed = AtomicBoolean(false)

    override fun sendOperation(operation: FullLiveOperation) {
        check(!closed.get()) { "Input-Port geschlossen." }
        val fullLive = BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_FULL_LIVE_CERTIFICATION
        val angels = BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_ANGELS_PRODUCT_CERTIFICATION
        val familyExpansion = BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_FAMILY_EXPANSION_P01_V1
        check(fullLive || angels || familyExpansion) { "Native Freigabe für die Certification fehlt." }
        check(operation in MatriboxCertificationPlans.permitted(fullLive, angels, familyExpansion)) {
            "Operation gehört nicht zum festen, freigegebenen Plan."
        }
        val message = MatriboxFullLiveCodec.encode(operation)
        MatriboxFullLiveCodec.validate(message)
        input.send(message, 0, message.size)
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) input.close()
    }
}
