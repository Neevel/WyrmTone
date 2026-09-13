package de.neevel.wyrmtone

import org.junit.Assert.*
import org.junit.Test

class PassiveMidiMonitorTest {
    private class FakeOutput : ReceiveOnlyMidiPort {
        var connected = 0; var disconnected = 0; var closed = 0
        var receiving: ((ByteArray, Long) -> Unit)? = null
        override fun connect(receive: (ByteArray, Long) -> Unit) { connected++; receiving = receive }
        override fun disconnect() { disconnected++ }
        override fun close() { closed++ }
    }
    @Test fun opensOnlyOutputPortAndConnectsExactlyOnce() {
        val port = FakeOutput(); var opens = 0; var rx = 0; var openedNumber = -1
        val monitor = PassiveMidiMonitor({ number -> opens++; openedNumber = number; port }, { _, _ -> rx++ })
        monitor.start(0); monitor.start(0)
        assertEquals(0, openedNumber); assertEquals(1, opens); assertEquals(1, port.connected)
        port.receiving?.invoke(byteArrayOf(1), 0); assertEquals(1, rx)
        monitor.stop(); monitor.stop()
        assertEquals(1, port.disconnected); assertEquals(1, port.closed); assertFalse(monitor.monitoring)
        port.receiving?.invoke(byteArrayOf(2), 0); assertEquals(1, rx)
    }
    @Test fun stopWithoutStartAndLatePreviousReceiverSafe() {
        val ports = mutableListOf<FakeOutput>(); var rx = 0
        val monitor = PassiveMidiMonitor({ FakeOutput().also { ports.add(it) } }, { _, _ -> rx++ })
        monitor.stop(); monitor.start(0); val old = ports.single().receiving
        monitor.stop(); monitor.start(0); old?.invoke(byteArrayOf(1), 0)
        assertEquals(0, rx); monitor.stop()
    }
    @Test fun connectFailureClosesResources() {
        var closed = false
        val broken = object : ReceiveOnlyMidiPort {
            override fun connect(receive: (ByteArray, Long) -> Unit) { error("fake failure") }
            override fun disconnect() {}
            override fun close() { closed = true }
        }
        val monitor = PassiveMidiMonitor({ broken }, { _, _ -> })
        runCatching { monitor.start(0) }; assertTrue(closed); assertFalse(monitor.monitoring)
    }
    @Test fun boundsPendingChunksBytesAndPreservesOrder() {
        val buffer = MidiCaptureBatchBuffer(maxChunks = 2, maxBytes = 4)
        buffer.add(byteArrayOf(1, 2), 0, 2, 10, 20)
        buffer.add(byteArrayOf(3, 4), 0, 2, 11, 21)
        val (chunks, lost) = buffer.drain()
        assertEquals(0, lost); assertEquals(listOf(1.toByte(), 3.toByte()), chunks.map { it.bytes[0] })
        repeat(3) { buffer.add(byteArrayOf(it.toByte(), 0), 0, 2, 0, 0) }
        val (bounded, dropped) = buffer.drain(); assertEquals(1, bounded.size); assertEquals(2, dropped)
    }
    @Test fun oversizedCallbackIsRejectedWithoutAllocationAndClearsGapPrefix() {
        val buffer = MidiCaptureBatchBuffer(maxChunkBytes = 2)
        buffer.add(byteArrayOf(1), 0, 1, 0, 0)
        buffer.add(byteArrayOf(1, 2, 3), 0, 3, 0, 0)
        val (chunks, lost) = buffer.drain(); assertTrue(chunks.isEmpty()); assertEquals(2, lost)
    }
}
