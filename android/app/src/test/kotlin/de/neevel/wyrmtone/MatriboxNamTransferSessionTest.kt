package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class MatriboxNamTransferSessionTest {
    private val prefix = byteArrayOf(
        0xf0.toByte(), 0x21, 0x25, 0x7f, 0x51, 0x4d, 0x45, 0x32,
        0x12, 0x12, 0x00, 0x10, 0x13,
    )

    private fun rawFrame(block: Int, slot: Int = MatriboxNamCloneTransferReference.CLONE5_SLOT): ByteArray {
        val nibbles = IntArray(28) { 0 }
        val sum = nibbles.sum() and 0xff
        val bytes = mutableListOf<Byte>()
        bytes.addAll(prefix.toList())
        bytes.add(slot.toByte())
        bytes.add((block ushr 7).toByte())
        bytes.add((block and 0x7f).toByte())
        nibbles.forEach { bytes.add(it.toByte()) }
        bytes.add(((sum shr 4) and 0x0f).toByte())
        bytes.add((sum and 0x0f).toByte())
        bytes.add(0xf7.toByte())
        return bytes.toByteArray()
    }

    private fun frame(block: Int) = MatriboxNamCloneTransferReference.parseValidated(rawFrame(block))

    private fun ackBytes(block: Int, slot: Int = MatriboxNamCloneTransferReference.CLONE5_SLOT, status: Int = 0x01): ByteArray {
        val bytes = mutableListOf<Byte>()
        bytes.addAll(prefix.toList())
        bytes.add(slot.toByte())
        bytes.add((block ushr 7).toByte())
        bytes.add((block and 0x7f).toByte())
        bytes.add(status.toByte())
        bytes.add(0xf7.toByte())
        return bytes.toByteArray()
    }

    private fun eligible(monitoring: Boolean = false) = ProbeEligibility(
        enabled = true, connection = "usb-1", vendor = 0x84ef, product = 0x0054,
        uniqueUsb = true, uniqueMidi = true, directlyMapped = true,
        deviceOpen = true, expectedInput = true, monitoring = monitoring,
    )

    /** Records every sent frame's block, in order; replies come from [replyFor]. */
    private class FakeSendPort(val onSend: (NamCloneTransferFrame) -> Unit) : MatriboxNamCloneSendPort {
        val sent = mutableListOf<Int>()
        var closed = false
        override fun sendFrame(frame: NamCloneTransferFrame) {
            sent.add(frame.block)
            onSend(frame)
        }
        override fun close() { closed = true }
    }

    private class FakeReceivePort : ReceiveOnlyMidiPort {
        var receiver: ((ByteArray, Long) -> Unit)? = null
        var connected = false
        var disconnected = false
        var closed = false
        override fun connect(receive: (ByteArray, Long) -> Unit) { receiver = receive; connected = true }
        override fun disconnect() { disconnected = true; receiver = null }
        override fun close() { closed = true }
        fun emit(bytes: ByteArray) = receiver?.invoke(bytes, 0L)
    }

    @Test
    fun `happy path- all-ok replies complete every frame, strict stop-and-wait, no leaks`() {
        val order = mutableListOf<String>()
        lateinit var receivePort: FakeReceivePort
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                order.add("openSend")
                FakeSendPort { frame ->
                    order.add("send:${frame.block}")
                    // Reply synchronously, on the same thread, exactly matching the frame.
                    receivePort.emit(ackBytes(frame.block))
                    order.add("ackDelivered:${frame.block}")
                }
            },
            openReceivePort = {
                order.add("openReceive")
                receivePort = FakeReceivePort()
                receivePort
            },
            ackTimeoutMillis = 200,
            quietPeriodMillis = 5,
        )
        val frames = (0..9).map { frame(it) }
        val result = session.execute(frames)

        assertEquals(NamTransferOutcome.SUCCESS.name, result["outcome"])
        assertEquals(10, result["framesSent"])
        assertEquals(9, result["lastConfirmedBlock"])
        assertTrue(receivePort.closed)
        assertTrue(receivePort.disconnected)
        // Strict ordering: openReceive before openSend, and each ackDelivered
        // immediately follows its own send -- never two sends without an ACK
        // between them.
        assertEquals("openReceive", order[0])
        assertEquals("openSend", order[1])
        for (i in 0..9) {
            val sendIdx = order.indexOf("send:$i")
            val ackIdx = order.indexOf("ackDelivered:$i")
            assertTrue(sendIdx in 0 until ackIdx)
            if (i < 9) assertTrue(ackIdx < order.indexOf("send:${i + 1}"))
        }
    }

    @Test
    fun `590-frame fake transfer completes, one send per ACK, no pipelining`() {
        val sendOrder = mutableListOf<Int>()
        lateinit var receivePort: FakeReceivePort
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame ->
                    sendOrder.add(frame.block)
                    // At the moment of THIS send, no frame after it should already be recorded.
                    assertTrue(sendOrder.all { it <= frame.block })
                    receivePort.emit(ackBytes(frame.block))
                }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 100,
            quietPeriodMillis = 2,
        )
        val frames = (0..587).map { frame(it) }
        val result = session.execute(frames)
        assertEquals(NamTransferOutcome.SUCCESS.name, result["outcome"])
        assertEquals(588, result["framesSent"])
        assertEquals(587, result["lastConfirmedBlock"])
        assertEquals((0..587).toList(), sendOrder)
    }

    // Product NAM transfer V1: onProgress fires once per CONFIRMED ACK (never per
    // send), with the running confirmed count, the ACK's own block number, and the
    // total frame count -- exactly what a "347 von 590" UI needs, and nothing a
    // send alone (which could still time out) would justify reporting as confirmed.
    @Test
    fun `onProgress fires once per confirmed ACK with confirmedCount, lastConfirmedBlock and totalFrames`() {
        lateinit var receivePort: FakeReceivePort
        val progressCalls = mutableListOf<Triple<Int, Int, Int>>()
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame -> receivePort.emit(ackBytes(frame.block)) }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 200,
            quietPeriodMillis = 5,
            onProgress = { confirmedCount, lastConfirmedBlock, totalFrames ->
                progressCalls.add(Triple(confirmedCount, lastConfirmedBlock, totalFrames))
            },
        )
        val frames = (0..9).map { frame(it) }
        val result = session.execute(frames)
        assertEquals(NamTransferOutcome.SUCCESS.name, result["outcome"])
        assertEquals(10, progressCalls.size)
        assertEquals((1..10).toList(), progressCalls.map { it.first })
        assertEquals((0..9).toList(), progressCalls.map { it.second })
        assertTrue(progressCalls.all { it.third == 10 })
    }

    // An onProgress that itself throws must never affect the transfer -- it is
    // observability only.
    @Test
    fun `an exception thrown by onProgress does not abort or otherwise affect the transfer`() {
        lateinit var receivePort: FakeReceivePort
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame -> receivePort.emit(ackBytes(frame.block)) }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 200,
            quietPeriodMillis = 5,
            onProgress = { _, _, _ -> throw IllegalStateException("boom") },
        )
        val result = session.execute((0..4).map { frame(it) })
        assertEquals(NamTransferOutcome.SUCCESS.name, result["outcome"])
        assertEquals(4, result["lastConfirmedBlock"])
    }

    // V5B.2c: a single ACK split across two MIDI callbacks must NOT be
    // mistaken for an extra/unexpected message (this is the regression the
    // real block-409 abort motivated -- see NamAckStreamAssembler).
    @Test
    fun `a single ACK fragmented across two receive callbacks still completes the transfer, not UNEXPECTED_MESSAGE`() {
        lateinit var receivePort: FakeReceivePort
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame ->
                    val bytes = ackBytes(frame.block)
                    receivePort.emit(bytes.copyOfRange(0, 10))
                    receivePort.emit(bytes.copyOfRange(10, bytes.size))
                }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 200,
            quietPeriodMillis = 20,
        )
        val result = session.execute(listOf(frame(0)))
        assertEquals(NamTransferOutcome.SUCCESS.name, result["outcome"])
        assertEquals(0, result["lastConfirmedBlock"])
    }

    // V5B.2c section 8: the full 590-frame transfer must still succeed when EVERY ACK arrives
    // fragmented in a rotating, deterministic pattern (18B whole / 9+9 / 1+17 / 5+7+6).
    @Test
    fun `590-frame fake transfer succeeds even when every ACK arrives deterministically fragmented`() {
        lateinit var receivePort: FakeReceivePort
        val splitPatterns = listOf(
            listOf(18), // whole
            listOf(9, 9),
            listOf(1, 17),
            listOf(5, 7, 6),
        )
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame ->
                    val bytes = ackBytes(frame.block)
                    val pattern = splitPatterns[frame.block % splitPatterns.size]
                    var offset = 0
                    for (chunkSize in pattern) {
                        receivePort.emit(bytes.copyOfRange(offset, offset + chunkSize))
                        offset += chunkSize
                    }
                }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 200,
            quietPeriodMillis = 5,
        )
        val frames = (0..587).map { frame(it) }
        val result = session.execute(frames)
        assertEquals(NamTransferOutcome.SUCCESS.name, result["outcome"])
        assertEquals(588, result["framesSent"])
        assertEquals(587, result["lastConfirmedBlock"])
    }

    // V5B.2c: two GENUINELY complete ACKs (not a fragmented one) must still be treated as an
    // extra/unexpected message -- the fix must not swallow real anomalies.
    @Test
    fun `two genuinely complete ACKs for the same frame still abort as UNEXPECTED_MESSAGE`() {
        lateinit var receivePort: FakeReceivePort
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame ->
                    receivePort.emit(ackBytes(frame.block))
                    receivePort.emit(ackBytes(frame.block)) // stray genuine duplicate
                }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 200,
            quietPeriodMillis = 20,
        )
        val result = session.execute(listOf(frame(0)))
        assertEquals(NamTransferOutcome.UNEXPECTED_MESSAGE.name, result["outcome"])
    }

    // V5C: the session must generalize to any Clone slot the frames target (not just Clone 5) --
    // a Clone-1 (0x00) transfer must succeed the same way a Clone-5 one does.
    @Test
    fun `a full transfer targeting Clone 1 (0x00) succeeds the same way Clone 5 does`() {
        lateinit var receivePort: FakeReceivePort
        val slot = MatriboxNamCloneTransferReference.CLONE1_SLOT
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame -> receivePort.emit(ackBytes(frame.block, slot = slot)) }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 200,
            quietPeriodMillis = 5,
        )
        val frames = (0..9).map { MatriboxNamCloneTransferReference.parseValidated(rawFrame(it, slot = slot)) }
        val result = session.execute(frames)
        assertEquals(NamTransferOutcome.SUCCESS.name, result["outcome"])
        assertEquals(9, result["lastConfirmedBlock"])
    }

    // Frames that disagree on the target slot must never be sent at all -- a session writes to
    // exactly one Clone slot, never a mix.
    @Test
    fun `frames targeting different Clone slots are refused before any send`() {
        var sendCalls = 0
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = { FakeSendPort { sendCalls++ } },
            openReceivePort = { FakeReceivePort() },
        )
        val mixed = listOf(
            MatriboxNamCloneTransferReference.parseValidated(rawFrame(0, slot = MatriboxNamCloneTransferReference.CLONE1_SLOT)),
            MatriboxNamCloneTransferReference.parseValidated(rawFrame(1, slot = MatriboxNamCloneTransferReference.CLONE5_SLOT)),
        )
        val result = session.execute(mixed)
        assertEquals(NamTransferOutcome.NOT_ELIGIBLE.name, result["outcome"])
        assertEquals(0, sendCalls)
    }

    @Test
    fun `second execute on the same session is refused, no send happens`() {
        lateinit var receivePort: FakeReceivePort
        var sendCalls = 0
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame -> sendCalls++; receivePort.emit(ackBytes(frame.block)) }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 100,
        )
        session.execute(listOf(frame(0)))
        val second = session.execute(listOf(frame(1)))
        assertEquals(NamTransferOutcome.ALREADY_USED.name, second["outcome"])
        assertEquals(1, sendCalls) // only the first execute's frame was ever sent
    }

    // -- failure injection: every case must stop before the next frame --

    private fun runWithFailureAtFrame(
        failAt: Int,
        totalFrames: Int,
        reply: (frame: NamCloneTransferFrame, receivePort: FakeReceivePort, ordinal: Int) -> Unit,
    ): Triple<Map<String, Any?>, List<Int>, FakeReceivePort> {
        val sentBlocks = mutableListOf<Int>()
        lateinit var receivePort: FakeReceivePort
        val ordinal = AtomicInteger(0)
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame ->
                    sentBlocks.add(frame.block)
                    reply(frame, receivePort, ordinal.getAndIncrement())
                }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 60,
            quietPeriodMillis = 10,
        )
        val frames = (0 until totalFrames).map { frame(it) }
        val result = session.execute(frames)
        return Triple(result, sentBlocks, receivePort)
    }

    @Test
    fun `timeout at an early frame aborts before any later frame`() {
        val (result, sent, receivePort) = runWithFailureAtFrame(failAt = 1, totalFrames = 5) { f, rp, ord ->
            if (ord != 1) rp.emit(ackBytes(f.block)) // no reply for frame #1
        }
        assertEquals(NamTransferOutcome.TIMEOUT.name, result["outcome"])
        assertEquals(listOf(0, 1), sent)
        assertTrue(receivePort.closed)
    }

    @Test
    fun `timeout mid-transfer aborts before any later frame`() {
        val (result, sent, _) = runWithFailureAtFrame(failAt = 3, totalFrames = 10) { f, rp, ord ->
            if (ord != 3) rp.emit(ackBytes(f.block))
        }
        assertEquals(NamTransferOutcome.TIMEOUT.name, result["outcome"])
        assertEquals(listOf(0, 1, 2, 3), sent)
    }

    @Test
    fun `malformed ACK aborts before any later frame`() {
        // A genuinely framed (F0..F7) but structurally-invalid message --
        // NOT unframed garbage (which the V5B.2c stream assembler now
        // correctly never turns into a "message" at all, see the
        // NamAckStreamAssembler tests: unframed bytes -> no message ->
        // TIMEOUT, not MALFORMED_ACK).
        fun brokenPrefixAck(block: Int): ByteArray {
            val bytes = ackBytes(block)
            bytes[4] = 0x00 // corrupt one confirmed prefix byte, keep F0..F7 framing intact
            return bytes
        }
        val (result, sent, _) = runWithFailureAtFrame(failAt = 2, totalFrames = 5) { f, rp, ord ->
            if (ord == 2) rp.emit(brokenPrefixAck(f.block)) else rp.emit(ackBytes(f.block))
        }
        assertEquals(NamTransferOutcome.MALFORMED_ACK.name, result["outcome"])
        assertEquals(listOf(0, 1, 2), sent)
    }

    @Test
    fun `wrong slot in the ACK aborts before any later frame`() {
        val (result, sent, _) = runWithFailureAtFrame(failAt = 2, totalFrames = 5) { f, rp, ord ->
            rp.emit(if (ord == 2) ackBytes(f.block, slot = 0x00) else ackBytes(f.block))
        }
        assertEquals(NamTransferOutcome.WRONG_SLOT.name, result["outcome"])
        assertEquals(listOf(0, 1, 2), sent)
    }

    @Test
    fun `wrong block in the ACK aborts before any later frame`() {
        val (result, sent, _) = runWithFailureAtFrame(failAt = 2, totalFrames = 5) { f, rp, ord ->
            rp.emit(if (ord == 2) ackBytes(f.block + 1) else ackBytes(f.block))
        }
        assertEquals(NamTransferOutcome.WRONG_BLOCK.name, result["outcome"])
        assertEquals(listOf(0, 1, 2), sent)
    }

    @Test
    fun `non-success status in the ACK aborts before any later frame`() {
        val (result, sent, _) = runWithFailureAtFrame(failAt = 2, totalFrames = 5) { f, rp, ord ->
            rp.emit(if (ord == 2) ackBytes(f.block, status = 0x00) else ackBytes(f.block))
        }
        assertEquals(NamTransferOutcome.UNEXPECTED_STATUS.name, result["outcome"])
        assertEquals(listOf(0, 1, 2), sent)
    }

    @Test
    fun `an unexpected extra message aborts before any later frame`() {
        val (result, sent, _) = runWithFailureAtFrame(failAt = 2, totalFrames = 5) { f, rp, ord ->
            rp.emit(ackBytes(f.block))
            if (ord == 2) rp.emit(ackBytes(f.block)) // stray duplicate
        }
        assertEquals(NamTransferOutcome.UNEXPECTED_MESSAGE.name, result["outcome"])
        assertEquals(listOf(0, 1, 2), sent)
    }

    @Test
    fun `a send exception aborts before any later frame`() {
        var sendCalls = 0
        lateinit var receivePort: FakeReceivePort
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame ->
                    sendCalls++
                    if (frame.block == 2) throw IllegalStateException("Transport-Fehler")
                    receivePort.emit(ackBytes(frame.block))
                }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 60,
        )
        val result = session.execute((0..4).map { frame(it) })
        assertEquals(NamTransferOutcome.SEND_FAILED.name, result["outcome"])
        assertEquals(3, sendCalls) // frames 0, 1, 2 attempted; 2 threw; nothing after
    }

    @Test
    fun `a receive-port open exception aborts before any send`() {
        var sendCalls = 0
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = { FakeSendPort { sendCalls++ } },
            openReceivePort = { throw IllegalStateException("Output-Port nicht verfügbar") },
        )
        val result = session.execute((0..4).map { frame(it) })
        assertEquals(NamTransferOutcome.OPEN_FAILED.name, result["outcome"])
        assertEquals(0, sendCalls)
    }

    @Test
    fun `not eligible (monitoring active) refuses before any send or port open`() {
        var opened = false
        var sendCalls = 0
        val session = MatriboxNamTransferSession(
            eligibility = { eligible(monitoring = true) },
            openSendPort = { opened = true; FakeSendPort { sendCalls++ } },
            openReceivePort = { opened = true; FakeReceivePort() },
        )
        val result = session.execute((0..2).map { frame(it) })
        assertEquals(NamTransferOutcome.NOT_ELIGIBLE.name, result["outcome"])
        assertFalse(opened)
        assertEquals(0, sendCalls)
    }

    // -- cleanup / lifecycle --

    @Test
    fun `cancel before the first send makes execute refuse without opening anything`() {
        var opened = false
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = { opened = true; FakeSendPort {} },
            openReceivePort = { opened = true; FakeReceivePort() },
        )
        session.cancel()
        val result = session.execute((0..2).map { frame(it) })
        assertFalse(opened)
        assertEquals(NamTransferOutcome.NOT_ELIGIBLE.name, result["outcome"])
    }

    @Test
    fun `cancel while a send is blocked waiting for an ACK closes both ports promptly`() {
        lateinit var receivePort: FakeReceivePort
        lateinit var sendPort: FakeSendPort
        val startedWaiting = CountDownLatch(1)
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                sendPort = FakeSendPort { startedWaiting.countDown() } // never replies -> would time out
                sendPort
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 5000, // long enough that cancel(), not the timeout, ends the run
        )
        val done = AtomicBoolean(false)
        val thread = Thread {
            session.execute(listOf(frame(0)))
            done.set(true)
        }
        thread.start()
        assertTrue(startedWaiting.await(2, TimeUnit.SECONDS))
        session.cancel()
        thread.join(3000)
        assertTrue(done.get())
        assertTrue(sendPort.closed)
        assertTrue(receivePort.closed)
    }

    // Product NAM transfer V1, hardware-certification pre-review: the existing cancel test proves
    // both ports close promptly, but does not check the RETURNED OUTCOME or that onProgress stops
    // firing -- a cancelled run must never be reportable as SUCCESS, and no progress callback may
    // fire for a frame whose ACK never arrived because cancel() interrupted the wait.
    @Test
    fun `cancelling mid-wait never reports SUCCESS and stops further onProgress calls`() {
        lateinit var receivePort: FakeReceivePort
        lateinit var sendPort: FakeSendPort
        val startedWaiting = CountDownLatch(1)
        val progressCalls = mutableListOf<Int>()
        val session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                sendPort = FakeSendPort { frame ->
                    if (frame.block == 0) {
                        receivePort.emit(ackBytes(0)) // block 0 confirms normally
                    } else {
                        startedWaiting.countDown() // block 1 never replies -> cancel() ends the wait
                    }
                }
                sendPort
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
            ackTimeoutMillis = 5000,
            onProgress = { confirmedCount, _, _ -> progressCalls.add(confirmedCount) },
        )
        val result = AtomicReference<Map<String, Any?>>()
        val thread = Thread { result.set(session.execute((0..2).map { frame(it) })) }
        thread.start()
        assertTrue(startedWaiting.await(2, TimeUnit.SECONDS))
        session.cancel()
        thread.join(3000)

        assertNotEquals(NamTransferOutcome.SUCCESS.name, result.get()!!["outcome"])
        assertTrue(sendPort.closed)
        assertTrue(receivePort.closed)
        // Only block 0's confirmed ACK produced a progress call; block 1 (the one cancel()
        // interrupted) and block 2 (never sent) must never appear.
        assertEquals(listOf(1), progressCalls)

        // No automatic retry: a second execute() on the SAME (now-used, now-cancelled) session
        // is refused, exactly like the existing one-shot guarantee for a completed session.
        val second = session.execute((0..2).map { frame(it) })
        assertEquals(NamTransferOutcome.ALREADY_USED.name, second["outcome"])
    }

    @Test
    fun `isActive is true only during execute`() {
        lateinit var receivePort: FakeReceivePort
        var observedDuring = false
        lateinit var session: MatriboxNamTransferSession
        session = MatriboxNamTransferSession(
            eligibility = { eligible() },
            openSendPort = {
                FakeSendPort { frame ->
                    observedDuring = session.isActive
                    receivePort.emit(ackBytes(frame.block))
                }
            },
            openReceivePort = { FakeReceivePort().also { receivePort = it } },
        )
        assertFalse(session.isActive)
        session.execute(listOf(frame(0)))
        assertTrue(observedDuring)
        assertFalse(session.isActive)
    }
}
