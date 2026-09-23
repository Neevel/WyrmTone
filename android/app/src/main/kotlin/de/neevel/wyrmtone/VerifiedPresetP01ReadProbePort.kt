package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/** Android MIDI only; the native call site owns the immutable fixed read-request payload. */
internal class VerifiedPresetP01ReadProbePort(private val input: MidiInputPort) : VerifiedPresetP01ReadSendPort {
    private val closed = AtomicBoolean(false)

    override fun sendVerifiedPresetP01ReadRequest() {
        check(!closed.get()) { "Input-Port geschlossen." }
        check(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_READ_PROBE) {
            "Native Read-Freigabe fehlt."
        }
        val reference = VerifiedPresetP01ReadRequestReference.bytes()
        VerifiedPresetP01ReadRequestReference.validate(reference)
        input.send(reference, 0, reference.size)
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) input.close()
    }
}
