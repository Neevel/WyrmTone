package de.neevel.wyrmtone

/**
 * V5B.2c: a small, dedicated SysEx stream assembler for the NAM
 * Clone-transfer ACK receive path. Built after the first real hardware
 * transfer aborted with UNEXPECTED_MESSAGE at block 409, whose actual raw
 * bytes were never logged (no diagnostics existed yet) -- so the exact
 * cause of that abort remains UNKNOWN, not confirmed. This assembler
 * exists because [MatriboxNamTransferSession] previously treated every
 * single `MidiReceiver.onSend` callback as a complete message on its own,
 * which is wrong whenever Android's MIDI transport splits one logical
 * SysEx (F0..F7) across multiple callbacks, or delivers more than one
 * complete SysEx in a single callback -- both are normal, expected
 * behaviors of that API that the previous code never accounted for.
 *
 * State (an in-progress F0..F7) persists across [feed] calls, on purpose:
 * that's what lets a message fragmented across callbacks be reassembled.
 * A callback boundary is NEVER treated as a message boundary.
 */
class NamAckStreamAssembler(private val maxBytes: Int = 256) {
    private val buffer = mutableListOf<Byte>()
    private var accumulating = false

    /**
     * Feeds one raw receive callback's bytes (already offset/count-sliced
     * by the caller -- this class never reads raw offset/count itself).
     * Returns zero or more COMPLETE SysEx messages (F0..F7, inclusive)
     * found while processing [bytes], in the order their closing F7
     * arrived. Anything before the first F0 this instance has ever seen,
     * or between a message's F7 and the next F0, is silently discarded
     * (garbage/inter-message bytes) -- deterministically, never crashing,
     * never growing [buffer] past [maxBytes].
     */
    fun feed(bytes: ByteArray): List<ByteArray> {
        val messages = mutableListOf<ByteArray>()
        for (raw in bytes) {
            val value = raw.toInt() and 0xff
            if (value == 0xf0) {
                // A new F0 always starts fresh -- including the case where
                // a previous F0..(no F7 yet) was already in progress
                // (malformed/interrupted stream): that incomplete data is
                // deterministically discarded, never silently merged into
                // the new message.
                buffer.clear()
                buffer.add(raw)
                accumulating = true
                continue
            }
            if (!accumulating) {
                continue // garbage before any F0 this instance has seen
            }
            buffer.add(raw)
            if (buffer.size > maxBytes) {
                // Oversized: reset, bounded memory, no message emitted for it.
                buffer.clear()
                accumulating = false
                continue
            }
            if (value == 0xf7) {
                messages.add(buffer.toByteArray())
                buffer.clear()
                accumulating = false
            }
        }
        return messages
    }

    /** True while an F0 has been seen without its closing F7 yet. */
    val hasIncompleteMessage: Boolean get() = accumulating
}
