package de.neevel.wyrmtone

import android.media.midi.MidiInputPort
import java.util.concurrent.atomic.AtomicBoolean

/**
 * V5B.1: the narrowest possible send primitive for the offline-validated
 * WyrmTone NAM Clone-5 transfer (`tool/matribox_nam_analysis/v5_*.dart`).
 * Unlike [MatriboxToneTransferSendPort] (which knows presets, live edits
 * and Store) this port knows NOTHING about the NAM transfer PROTOCOL --
 * which frame, what order, whether the last block repeats is decided
 * entirely upstream, offline, by `v5_transfer_plan.dart`. But like every
 * other sender in this file tree, it never accepts a raw `ByteArray`
 * directly: the only value it can send is a [NamCloneTransferFrame],
 * which can only be constructed via
 * [MatriboxNamCloneTransferReference.parseValidated] -- so an invalid, a
 * wrong-slot, or a checksum-mismatched frame structurally cannot reach
 * [MidiInputPort.send].
 */
internal interface MatriboxNamCloneSendPort {
    fun sendFrame(frame: NamCloneTransferFrame)
    fun close()
}

/**
 * Android MIDI only; the single send call site for the NAM Clone transfer.
 * Gated by [BuildConfig.REAL_MATRIBOX_WRITE] alone (unlike
 * [MatriboxToneTransferWriterPort], which stays debug-only): release
 * hardcodes this field `true` (see `android/app/build.gradle.kts`), since
 * this is now the hardware-confirmed product feature -- the real safety
 * boundary is the explicit per-transfer UI confirmation (preparation ->
 * connect -> Clone-slot pick -> overwrite confirmation) plus this port's
 * own structural validation, not a build-time kill switch. A debug build
 * still defaults this field `false` unless an explicit dart-define sets
 * it, so a developer build never writes by accident.
 */
internal class MatriboxNamCloneSendPortImpl(private val input: MidiInputPort) : MatriboxNamCloneSendPort {
    private val closed = AtomicBoolean(false)

    override fun sendFrame(frame: NamCloneTransferFrame) {
        check(!closed.get()) { "Input-Port geschlossen." }
        check(BuildConfig.REAL_MATRIBOX_WRITE) {
            "Native Freigabe für den NAM-Clone-Transfer fehlt (REAL_MATRIBOX_WRITE)."
        }
        // Belt-and-suspenders: [frame] can only exist already-validated (see
        // its constructor), but this re-validates its bytes right at the
        // send call site anyway -- the same defense-in-depth every other
        // sender in this file tree has at its own single send call site.
        val revalidated = MatriboxNamCloneTransferReference.parseValidated(frame.bytes)
        input.send(revalidated.bytes, 0, revalidated.bytes.size)
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) input.close()
    }
}
