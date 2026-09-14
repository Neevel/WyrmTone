package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/** Android MIDI only; the native call site owns the immutable P01 payload. */
internal class VerifiedPresetP01ProbePort(private val input: MidiInputPort) : VerifiedPresetP01Port {
    private val closed = AtomicBoolean(false)

    override fun sendVerifiedPresetP01() {
        check(!closed.get()) { "Input-Port geschlossen." }
        check(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_PRESET_P01_PROBE) {
            "Native P01-Freigabe fehlt."
        }
        val reference = VerifiedPresetP01Reference.bytes()
        VerifiedPresetP01Reference.validate(reference)
        input.send(reference, 0, reference.size)
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) input.close()
    }
}
