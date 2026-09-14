package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/** Only actual Android send site; no caller-supplied payload is accepted. */
internal class VerifiedMatriboxProbePort(private val input: MidiInputPort) : VerifiedProbePort {
    private val closed = AtomicBoolean(false)
    override fun sendVerifiedGain41() {
        check(!closed.get()) { "Input-Port geschlossen." }
        check(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_WRITE_PROBE) { "Native Freigabe fehlt." }
        val reference = VerifiedGain41Reference.bytes()
        VerifiedGain41Reference.validate(reference)
        input.send(reference, 0, reference.size)
    }
    override fun close() { if (closed.compareAndSet(false, true)) input.close() }
}
