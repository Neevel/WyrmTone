package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android MIDI only; the native call site owns the immutable Phase-D
 * announce and the ten immutable fixed part requests. [partIndex] only
 * ever selects among the ten hardcoded byte arrays already confirmed for
 * V2 -- no bytes, bank or slot ever originate from Flutter or from a
 * caller-supplied value.
 */
internal class VerifiedPresetP01FullReadProbeV3APort(private val input: MidiInputPort) :
    VerifiedPresetP01FullReadV3ASendPort {
    private val closed = AtomicBoolean(false)

    private fun sendReference(reference: ByteArray) {
        check(!closed.get()) { "Input-Port geschlossen." }
        check(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_FULL_READ_PROBE_V3A) {
            "Native V3A-Freigabe fehlt."
        }
        input.send(reference, 0, reference.size)
    }

    override fun sendPhaseDAnnounce() {
        VerifiedPresetP01PhaseDReference.validateAnnounce()
        sendReference(VerifiedPresetP01PhaseDReference.announce)
    }

    override fun sendPartRequest(partIndex: Int) {
        VerifiedPresetP01FullReadReference.validate()
        sendReference(VerifiedPresetP01FullReadReference.requests[partIndex])
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) input.close()
    }
}
