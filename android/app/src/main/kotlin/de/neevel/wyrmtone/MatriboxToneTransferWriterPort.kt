package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The productive port accepts only an already validated [FullLiveOperation]
 * (never bytes, a slot number, an algorithm id or a parameter index) and
 * re-checks it against the native evidence table. The preset select only
 * takes a [MatriboxWritableUserPreset], which cannot exist for P01..P10.
 */
internal interface MatriboxToneTransferSendPort {
    fun selectUserPreset(target: MatriboxWritableUserPreset)
    fun sendValidated(operation: FullLiveOperation)
    fun close()
}

/** Android MIDI only; the single productive send call site. */
internal class MatriboxToneTransferWriterPort(private val input: MidiInputPort) : MatriboxToneTransferSendPort {
    private val closed = AtomicBoolean(false)

    override fun selectUserPreset(target: MatriboxWritableUserPreset) = transmit(Outgoing.PresetSelect(target))

    override fun sendValidated(operation: FullLiveOperation) = transmit(Outgoing.Edit(operation))

    /** What the port may send: closed, typed; the bytes are only ever built and validated here. */
    private sealed interface Outgoing {
        class PresetSelect(val target: MatriboxWritableUserPreset) : Outgoing
        class Edit(val operation: FullLiveOperation) : Outgoing
    }

    /** The one gated send call site of the productive transfer. */
    private fun transmit(outgoing: Outgoing) {
        check(!closed.get()) { "Input-Port geschlossen." }
        check(BuildConfig.DEBUG && BuildConfig.ENABLE_MATRIBOX_TONE_TRANSFER) {
            "Native Freigabe für den Tone Transfer fehlt."
        }
        val message = when (outgoing) {
            is Outgoing.PresetSelect -> {
                val target = outgoing.target
                check(MatriboxSlotPolicy.isProductWritable(target.presetNumber)) { "Geschützter Speicherplatz." }
                MatriboxPresetSelectReference.message(target).also { MatriboxPresetSelectReference.validate(it, target) }
            }
            // live edits only: the codec admits the 12 10 family alone (never 12 11 / 12 12, and not the
            // 12 00 preset select, which is checked against its own reference above)
            is Outgoing.Edit -> {
                val operation = outgoing.operation
                check(MatriboxToneTransferCatalog.isConfirmed(operation)) { "Operation ist nicht FAMILY/EXACT-bestätigt." }
                val message = MatriboxFullLiveCodec.encode(operation)
                MatriboxFullLiveCodec.validate(message)
                message
            }
        }
        input.send(message, 0, message.size)
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) input.close()
    }
}
