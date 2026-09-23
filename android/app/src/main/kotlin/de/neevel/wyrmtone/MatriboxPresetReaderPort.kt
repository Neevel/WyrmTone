package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android MIDI only; the native call site owns the Phase-D announce and the
 * ten fixed part requests of [VerifiedPresetP01PhaseDReference] /
 * [VerifiedPresetP01FullReadReference] -- the same references already
 * confirmed and reproduced by the V3A experimental probe -- addressed at a
 * validated [MatriboxUserPreset] through [MatriboxUserSlotReadReference]
 * (only the confirmed slot byte differs). [partIndex] only ever selects
 * among the ten requests; no bytes or bank ever originate from Flutter.
 */
internal class MatriboxPresetReaderPort(private val input: MidiInputPort) :
    MatriboxPresetReaderSendPort {
    private val closed = AtomicBoolean(false)

    private fun sendReference(reference: ByteArray) {
        check(!closed.get()) { "Input-Port geschlossen." }
        check(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_P01_RAW_BACKUP) {
            "Native Freigabe für den Raw-Backup-Reader fehlt."
        }
        input.send(reference, 0, reference.size)
    }

    override fun sendPhaseDAnnounce(slot: MatriboxUserPreset) {
        MatriboxUserSlotReadReference.validate()
        sendReference(MatriboxUserSlotReadReference.announce(slot))
    }

    override fun sendPartRequest(slot: MatriboxUserPreset, partIndex: Int) {
        MatriboxUserSlotReadReference.validate()
        sendReference(MatriboxUserSlotReadReference.partRequest(slot, partIndex))
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) input.close()
    }
}
