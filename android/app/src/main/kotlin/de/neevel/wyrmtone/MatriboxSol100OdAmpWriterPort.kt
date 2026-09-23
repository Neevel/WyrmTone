package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/**
 * This interface cannot accept an algorithm, a parameter index or raw
 * bytes: only a closed [Sol100OdAmpField] and a value, both re-validated
 * by the port itself before anything is sent.
 */
internal interface MatriboxSol100OdCertificationSendPort {
    fun sendCertificationWrite(field: Sol100OdAmpField, value: Float)
    fun close()
}

/** Android MIDI only; the only actual send call site for certification writes. */
internal class MatriboxSol100OdAmpWriterPort(private val input: MidiInputPort) :
    MatriboxSol100OdCertificationSendPort {
    private val closed = AtomicBoolean(false)

    override fun sendCertificationWrite(field: Sol100OdAmpField, value: Float) {
        check(!closed.get()) { "Input-Port geschlossen." }
        check(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_SOL100OD_AMP_CERTIFICATION) {
            "Native Freigabe für die AMP-Certification fehlt."
        }
        check(field in Sol100OdAmpField.CERTIFICATION_FIELDS) {
            "Feld ist nicht für die Certification freigegeben."
        }
        val message = MatriboxSol100OdAmpWriter.encode(field, value)
        MatriboxSol100OdAmpWriter.validate(field, message)
        input.send(message, 0, message.size)
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) input.close()
    }
}
