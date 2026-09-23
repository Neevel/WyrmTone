package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/**
 * This interface cannot accept an algorithm, a parameter index or raw
 * bytes. [sendGainWrite] only ever encodes and sends the one confirmed
 * Sol-100-OD Gain message shape ([MatriboxConfirmedGainWriter]) for a
 * value already independently validated by this port itself.
 */
internal interface MatriboxConfirmedGainWriteSendPort {
    fun sendGainWrite(value: Float)
    fun close()
}

/** Android MIDI only; the only actual send call site for this write. */
internal class MatriboxConfirmedGainWriterPort(private val input: MidiInputPort) :
    MatriboxConfirmedGainWriteSendPort {
    private val closed = AtomicBoolean(false)

    override fun sendGainWrite(value: Float) {
        check(!closed.get()) { "Input-Port geschlossen." }
        check(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_GAIN_WRITE) {
            "Native Freigabe für den Gain-Write fehlt."
        }
        val message = MatriboxConfirmedGainWriter.encode(value)
        MatriboxConfirmedGainWriter.validate(message)
        input.send(message, 0, message.size)
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) input.close()
    }
}
