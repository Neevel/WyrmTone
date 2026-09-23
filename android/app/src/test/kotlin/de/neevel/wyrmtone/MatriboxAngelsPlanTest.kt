package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MatriboxAngelsPlanTest {
    private fun hex(bytes: ByteArray) = bytes.joinToString(" ") { "%02x".format(it) }

    @Test fun `the plan is the exact fixed operation list, 2 model 5 parameter 4 block`() {
        val ops = MatriboxAngelsPlan.operations
        assertEquals(11, ops.size)
        assertEquals(2, ops.count { it is FullLiveOperation.ModelSelect })
        assertEquals(5, ops.count { it is FullLiveOperation.Parameter })
        assertEquals(4, ops.count { it is FullLiveOperation.BlockToggle })
        assertEquals(
            listOf(
                "FX1 BLOCK OFF", "FX2 MODEL Boost", "FX2 BLOCK ON",
                "AMP PARAM Gain = 67.0", "AMP PARAM PRES = 59.0", "AMP PARAM Bass = 41.0",
                "AMP PARAM Middle = 59.0", "AMP PARAM Treble = 61.0",
                "CAB MODEL Sol 4x12", "CAB BLOCK ON", "EQ BLOCK OFF",
            ),
            ops.map { it.label },
        )
    }

    @Test fun `every message equals the golden hex generated from the Dart plan`() {
        assertEquals(MatriboxAngelsGolden.messages, MatriboxAngelsPlan.operations.map { hex(MatriboxFullLiveCodec.encode(it)) })
    }

    @Test fun `no store, metadata, name, NR or RVB write exists in the plan`() {
        for (op in MatriboxAngelsPlan.operations) {
            val bytes = MatriboxFullLiveCodec.encode(op)
            MatriboxFullLiveCodec.validate(bytes)
            if (bytes.size > 3) {
                assertEquals(0x12, bytes[8].toInt())
                assertEquals(0x10, bytes[9].toInt()) // 12 10 only: never 12 11 / 12 12
            }
        }
        val slots = MatriboxAngelsPlan.operations.map { it.slot() }.toSet()
        assertTrue(slots.intersect(setOf(ChainSlot.NR, ChainSlot.MOD, ChainSlot.DLY, ChainSlot.RVB)).isEmpty())
    }

    @Test fun `plans resolve only through their own gate`() {
        assertNull(MatriboxCertificationPlans.operations(MatriboxAngelsPlan.PLAN_ID, fullLiveEnabled = true, angelsEnabled = false))
        assertNull(MatriboxCertificationPlans.operations(MatriboxFullLivePlan.PLAN_ID, fullLiveEnabled = false, angelsEnabled = true))
        assertNotNull(MatriboxCertificationPlans.operations(MatriboxAngelsPlan.PLAN_ID, fullLiveEnabled = false, angelsEnabled = true))
        assertNull(MatriboxCertificationPlans.operations("ANGELS_DONT_KILL_P01_V2", true, true))
        assertTrue(MatriboxCertificationPlans.permitted(false, false).isEmpty())
        // a gate exposes only its own plan to the port
        assertEquals(MatriboxAngelsPlan.operations, MatriboxCertificationPlans.permitted(false, true))
    }

    @Test fun `the session runs the Angels plan once, in order, first failure stops, no retry`() {
        val sent = mutableListOf<FullLiveOperation>()
        var failAt: Int? = null
        val port = object : MatriboxFullLiveSendPort {
            override fun sendOperation(operation: FullLiveOperation) {
                if (failAt == sent.size) throw IllegalStateException("Transport-Fehler.")
                sent.add(operation)
            }
            override fun close() {}
        }
        val eligibility = {
            ProbeEligibility(
                enabled = true, connection = "usb/box", vendor = 0x84ef, product = 0x0054, uniqueUsb = true,
                uniqueMidi = true, directlyMapped = true, deviceOpen = true, expectedInput = true, monitoring = false,
            )
        }
        val resolver = { id: String -> MatriboxCertificationPlans.operations(id, false, true) }
        val session = MatriboxFullLiveCertificationSession(eligibility, { port }, pause = {}, planResolver = resolver)
        val ok = session.run(MatriboxAngelsPlan.PLAN_ID)
        assertEquals("SUCCESS", ok["outcome"])
        assertEquals(MatriboxAngelsPlan.operations, sent)
        assertEquals(11, ok["completed"])
        assertEquals("SAFETY_REJECTED", session.run(MatriboxFullLivePlan.PLAN_ID)["outcome"]) // other plan: not resolvable here
        assertEquals("SEND_FAILED", session.run(MatriboxAngelsPlan.PLAN_ID)["outcome"]) // second run in the same connection

        sent.clear()
        failAt = 3
        val fresh = MatriboxFullLiveCertificationSession(eligibility, { port }, pause = {}, planResolver = resolver)
        val failed = fresh.run(MatriboxAngelsPlan.PLAN_ID)
        assertEquals("SEND_FAILED", failed["outcome"])
        assertEquals(3, failed["completed"])
        assertEquals(MatriboxAngelsPlan.operations.take(3), sent)
    }

    private fun FullLiveOperation.slot(): ChainSlot = when (this) {
        is FullLiveOperation.ModelSelect -> slot
        is FullLiveOperation.Parameter -> slot
        is FullLiveOperation.BlockToggle -> slot
    }
}
