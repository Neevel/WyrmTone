package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android MIDI only; the native call site owns the ten immutable fixed
 * requests. [partIndex] only ever selects among the ten hardcoded byte
 * arrays in [VerifiedPresetP01FullReadReference] -- no bytes, bank or slot
 * ever originate from Flutter or from a caller-supplied value.
 */
internal class VerifiedPresetP01FullReadProbePort(private val input: MidiInputPort) : VerifiedPresetP01FullReadSendPort {
    private val closed = AtomicBoolean(false)

    override fun sendPartRequest(partIndex: Int) {
        check(!closed.get()) { "Input-Port geschlossen." }
        check(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_FULL_READ_PROBE) {
            "Native Full-Read-Freigabe fehlt."
        }
        VerifiedPresetP01FullReadReference.validate()
        val reference = VerifiedPresetP01FullReadReference.requests[partIndex]
        input.send(reference, 0, reference.size)
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) input.close()
    }
}
