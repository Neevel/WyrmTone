package de.neevel.wyrmtone

/** Only device-output reception is available here; no device-input/write API. */
interface ReceiveOnlyMidiPort {
    fun connect(receive: (ByteArray, Long) -> Unit)
    fun disconnect()
    fun close()
}

class PassiveMidiMonitor(
    private val openOutput: (Int) -> ReceiveOnlyMidiPort,
    private val receive: (ByteArray, Long) -> Unit,
) {
    private var port: ReceiveOnlyMidiPort? = null
    private var generation = 0
    var outputPortNumber: Int? = null
        private set
    val monitoring: Boolean
        @Synchronized get() = port != null

    @Synchronized
    fun start(outputPort: Int) {
        if (port != null) return
        val token = ++generation
        val opened = openOutput(outputPort)
        port = opened
        outputPortNumber = outputPort
        try {
            opened.connect { bytes, timestamp ->
                synchronized(this) {
                    if (port === opened && token == generation) receive(bytes, timestamp)
                }
            }
        } catch (error: Throwable) {
            stop()
            throw error
        }
    }

    @Synchronized
    fun stop() {
        ++generation
        val current = port
        port = null
        outputPortNumber = null
        runCatching { current?.disconnect() }
        runCatching { current?.close() }
    }
}

data class CapturedMidiChunk(val bytes: ByteArray, val timestampNanos: Long, val receivedAtMillis: Long)

/** Bounds pending main-thread delivery as well as per-chunk allocation. */
class MidiCaptureBatchBuffer(
    private val maxChunks: Int = 256,
    private val maxBytes: Int = 262144,
    private val maxChunkBytes: Int = 4096,
) {
    private val chunks = java.util.ArrayDeque<CapturedMidiChunk>()
    private var bytes = 0
    private var dropped = 0

    @Synchronized
    fun add(data: ByteArray, offset: Int, count: Int, timestamp: Long, at: Long) {
        // Reject oversized callbacks rather than allocate unbounded fragments.
        if (count > maxChunkBytes || count < 0 || offset < 0 || offset > data.size - count) {
            dropped += chunks.size + 1
            chunks.clear(); bytes = 0
            return
        }
        if (count == 0) return
        if (chunks.size >= maxChunks || bytes + count > maxBytes) {
            // Drop the whole pending prefix: the loss event precedes all later
            // bytes, so the Dart assembler can never splice across a gap.
            dropped += chunks.size
            chunks.clear()
            bytes = 0
        }
        if (count > maxBytes) { dropped++; return }
        chunks.add(CapturedMidiChunk(data.copyOfRange(offset, offset + count), timestamp, at))
        bytes += count
    }

    @Synchronized
    fun drain(): Pair<List<CapturedMidiChunk>, Int> {
        val result = Pair(chunks.toList(), dropped)
        chunks.clear(); bytes = 0; dropped = 0
        return result
    }

    @Synchronized
    fun clear() { chunks.clear(); bytes = 0; dropped = 0 }
}
